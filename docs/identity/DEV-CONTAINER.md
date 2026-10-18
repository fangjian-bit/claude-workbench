# The claude-workbench dev container

WB-D24, issue #393. The container is `.devcontainer/`, from the 603-Identity/devcontainers
template. A session in it is meant to reach GitHub only as the dev App, and is expected to when
the container is entered through the Dev Containers CLI (`devcontainer up`, then
`devcontainer exec`); the maintainer's live run after merge is to confirm that, and until
then it is unconfirmed; the other hazards below remain regardless. VS Code attach is
unsupported (#720, `WB-D33`): even with the host setting
`dev.containers.gitCredentialHelperConfigLocation` at `none`, an attach opens an IPC channel
that serves the host's git credential (see Hazards that remain).

## How it gets its token

- The host broker (`scripts/identity/broker.ps1`) keeps `~/.config/glunk-identity/tokens/claude-workbench/dev-token`
  current: the token on line 1, its `expires_at` on line 2.
- `devcontainer.json` bind-mounts that **directory**, read-only, at `/run/glunk-identity/dev`. A
  single-file mount would keep showing the file the broker replaced by atomic rename. Nothing else
  under the host's `glunk-identity` directory is mounted. The mount source names the GitHub repo
  (`claude-workbench`), not the checkout folder, so a clone folder with another name still mounts
  the right directory; it must exist, which `install-host-tools.ps1` ensures for each repo in `broker.json`.
- `/usr/local/libexec/dev-token` reads the file **on every call** and refuses (in plain mode: exit 2, no stdout)
  unless it holds a `ghs_` installation token with 5 minutes or more left on the container's
  clock. The broker refreshes at 30 minutes left, so a failed mint has about 25 minutes of slack.
- `/usr/local/bin/gh` is a shim that sets `GH_TOKEN` from it for that one call and runs the real
  `gh` (`/usr/local/libexec/gh-real`). git's `https://github.com` credential helper is the same
  reader. The token is never exported into a long-lived environment variable. When the token is
  refused, the helper answers `quit=1`, so git stops instead of trying another helper; the
  container also sets `GIT_TERMINAL_PROMPT=0` and turns off VS Code's `github.gitAuthentication`
  and `git.terminalAuthentication`. For the host side, `dev.containers.gitCredentialHelperConfigLocation`
  set to `none` keeps Dev Containers' helper out of git's config. It does not stop the channel
  behind that helper from answering once VS Code attaches (#720), so the container is not
  attached to.
- The container holds no `gh` login. The template's GitHub VS Code extensions are left out, as
  they sign in with the human's account.

## Opening it

- Open a **full clone** that is not the one `install-host-tools.ps1` installs from, runs git in,
  or runs host-side reviews in (a host session still runs git in its review clone, under a map
  too), and not a worktree of any of those (a worktree shares that clone's `.git`, hooks and
  config, and its `.git` file points at a host path git cannot follow in the container). A
  container-writable source clone is host code execution beside the App keys.
- Enter it with the Dev Containers CLI, from PowerShell or cmd on the host (not Git Bash, whose
  `HOME` doubles the mount path):
  ```sh
  devcontainer up --skip-post-attach --workspace-folder <clone>
  devcontainer exec --workspace-folder <clone> bash
  ```
  Replace `bash` with `claude` to start Claude Code directly. `--skip-post-attach` keeps `up` from
  running `postAttachCommand`, whose warning is meant for a VS Code attach. After a change to
  `.devcontainer/`, recreate with `devcontainer up --skip-post-attach --workspace-folder <clone>
  --remove-existing-container`. If `up` does not find a container VS Code made earlier, it makes a
  new one on the same named volumes. Before the first `up` from the CLI, stop any container VS Code
  made for the clone: find it with `docker ps -a --filter volume=<checkout folder>-tmp`, then
  `docker stop` and `docker rm` it. A running one keeps its relay, `up` does not restart it, and
  its socket would sit on the shared `-tmp` volume where the check below, which sees only its own
  container's processes, cannot see the relay. Make that `docker ps` part of the standing check:
  it should list only the CLI's container (the `containerId` `up` prints), and VS Code's
  "Reopen in Container" can make a second one later. Run the channel check below after the first `up`.
- **Do not attach VS Code** (Reopen in Container, Attach to Running Container) (#720, `WB-D33`).
  Attach is what opens the host credential channel. There is no VS Code window inside the
  container: edit files from the container shell, and do not use the Claude Code VS Code panel
  there.
- Reviewer tokens never enter this container. App-mode review runs on the host through
  `wow-review`, run from `$WOW_HOME/bin` and never from a checkout. The review session clones from
  GitHub into its own tmpfs volume. Neither the session token nor the post token ever enters a
  dev container, and `/way-of-working:architect-review` run here, under an `identities` map,
  posts nothing and prints the launcher command.

## Hazards that remain

- **`/workspace` is read-write**, so a session can edit `.devcontainer/` (an `initializeCommand`,
  wider mounts) and the host runs it at the next `devcontainer up`, Reopen or Rebuild. Compare
  `.devcontainer/` with the committed blob, from a different clone, before every `up` and every
  `devcontainer exec`. The order is: run `docker ps -a --filter volume=<checkout folder>-tmp` and
  `docker stop` every container it lists, compare, `up`, `exec`. The compare only holds while no
  container that mounts the clone is running, since any of them can write the file, so a running session could
  change it between the compare and the CLI's read; that also means no second `exec` shell beside
  a running session. The reasons: the CLI runs `initializeCommand` on the host on each `up`, even
  against a container that already exists, and `exec` re-reads `.devcontainer/devcontainer.json`
  from the host each call (its `remoteUser` and `remoteEnv`, with `${localEnv:*}` resolved from the
  host's environment), so a session's edit could copy a host environment variable into the
  container. A container created before this change keeps its old lifecycle commands until it is
  recreated, so it has no backstop.
- **VS Code's forwarded git credential channel (#720, `WB-D33`).** A VS Code attach opens it, and
  the fix is not to attach. Tested on 2026-10-17 with the VS Code user setting
  `dev.containers.gitCredentialHelperConfigLocation` at `none`: every attach still creates the
  helper client (`/tmp/vscode-remote-containers-<uuid>.js`), its socket and
  `REMOTE_CONTAINERS_IPC`, and calling the client directly returned the host's GitHub credential,
  so a process in the container could act on GitHub as the human. Keep the setting at `none`
  anyway, in every VS Code profile that keeps its own settings, as defense in depth for an
  accidental attach. The container's `postStartCommand` and `postAttachCommand` remove the
  channel's `/tmp/vscode-remote-containers-*` files (the latter also warns), as a backstop only:
  the relay VS Code starts keeps running inside the container after its socket path is removed,
  and VS Code may recreate the files at a later attach or reconnect, so an accidental attach is
  narrowed, not closed. The check, from a `devcontainer exec` shell, starts with the no-channel
  test: `echo "${REMOTE_CONTAINERS_IPC:-unset}"` prints `unset`,
  `ls /tmp/vscode-remote-containers-* 2>/dev/null` prints nothing, and
  `grep -la '[v]scode-remote-containers-server\|[v]scode-server' /proc/[0-9]*/cmdline 2>/dev/null`
  prints nothing. Anything but `unset` from the first, or any output from the second or third,
  fails the check. The first cannot see a live channel at all (the variable exists only in VS Code's own
  processes), and the second cannot see a relay left running after the backstop removed its files;
  the third can, within this container.
  After an accidental attach, close the VS Code window (or it will offer to reconnect) and stop
  the container at once (`docker stop`), which ends the relay;
  the exposure runs from the attach until that stop. A running Claude session, or code from a PR it
  builds, counts as untrusted, so in normal use treat every credential the host's git helpers can
  return (each GitHub account, each host) as exposed and rotate it. The backstop also
  loses a race against a process already watching `/tmp`, which can read the new client and
  connect before the removal runs, or move the socket out of the glob's reach.
  On the CLI path the test is the second and third checks plus the host-side `docker ps`. Do not
  run the masked credential test below there: when the `ls` check printed nothing no client file
  exists, so it has nothing to call and its lack of a `password=`
  line proves nothing. It is the diagnostic that established #720, kept for a maintainer
  investigating an attach, run from the VS Code-attached terminal of that attach (the client finds
  its socket through `REMOTE_CONTAINERS_IPC`, set only there), only while a client file is still
  there (when the `ls` check printed one), and only if the maintainer chooses to delay the stop:
  running it pulls the host credential into the container. It hides any secret it gets on screen.
  A pass is a well-formed helper reply with no `password=` line and no sign-in prompt on the host;
  an error or empty output is not a pass:
  ```sh
  N=$(ls -d ~/.vscode-server/bin/*/node | head -n 1)
  H=$(ls /tmp/vscode-remote-containers-[0-9a-f]*.js | head -n 1)
  printf 'protocol=https\nhost=github.com\n\n' | timeout 30 "$N" "$H" git-credential-helper get 2>&1 \
    | sed -E 's/^(password|oauth_refresh_token)=.*/\1=<present, hidden>/'
  ```
- **A forwarded host ssh-agent** is not blocked: git's SSH remotes are rewritten to https, but
  `ssh git@github.com` would authenticate with a GitHub key loaded in the host agent. Keep no
  GitHub key in the agent that VS Code forwards, and no key that is registered on GitHub as a
  signing key: `git -c gpg.format=ssh -c user.signingkey=... commit -S` (or `tag -s`) would sign as the human through
  it, and the commit would show Verified.
- **A forwarded GPG agent socket** was not found by the live check on 2026-10-17, which ran from
  a VS Code-attached terminal and says nothing yet about the CLI path; run the check in "What it
  still carries from the template" after the first `up`, and again after a Dev Containers CLI update
  (`WB-D25`, #574).
- **A reused home volume** can hold a human `gh auth login` PAT from an earlier container; the
  shim overrides it, but `/usr/local/libexec/gh-real` does not. `docker volume rm <checkout folder>-home`
  before first use.

## What it still carries from the template

The host's `~/.gitconfig.d` is mounted read-only, and `git-identity.sh` copies the author name
and email from it, so commits carry the human's author identity and are pushed by the App.

It carries **no commit signing** (`WB-D25`, #574). Container commits and tags are unsigned:
`devcontainer.json` forces `commit.gpgsign` and `tag.gpgsign` off through `containerEnv`
(above the identity file's `gpgsign = true`), the Dockerfile deletes `gpg`, `gpg-agent`,
`gpgconf`, `gpg-connect-agent` and `gpgsm`, and the template's `gpg-check.sh` no longer runs at start.
`main` stays signed because every merge is a squash merge, which GitHub signs.

Deleting the tools does not by itself prove VS Code stops forwarding the agent socket, and if an
agent is still forwarded, any process in the container can sign as the human by talking to the
socket directly. The live check came back empty on 2026-10-17, during the #397 cutover attempt,
from a VS Code-attached terminal: that says nothing yet about the CLI path.
Run it from a `devcontainer exec` shell:

```sh
find /home/app /tmp /run /var/tmp /dev/shm -type s -name 'S.gpg-agent*'
```

Those are the writable mounts where an agent socket can land, which `find -xdev` from `/`
would skip. Output means a socket is forwarded; no output is the pass. A "Permission denied"
line is not a pass: rerun it with `docker exec -u root`.
A socket file that predates the container's start and refuses a connection is a dead file left on the
home volume by an earlier container, not a forwarded socket (python `socket.connect` shows `ConnectionRefusedError`);
`docker volume rm <checkout folder>-home` clears it.

## Claude login

`claude /login` once inside the container, from a `devcontainer exec` shell. The credential lives in the per-checkout home volume
`<checkout folder>-home`, and `docker volume rm <checkout folder>-home`
removes it.

## Not adopted here yet

The template's `.github/workflows` (`devcontainer-image.yml`, `architect-review-gate.yml`,
`secret-scan.yml`) are not copied: adding required checks is a ruleset decision for the
maintainer. The Dockerfile header lists what `verify / verify` would enforce, and the
attestation command to check the pinned digest by hand.
