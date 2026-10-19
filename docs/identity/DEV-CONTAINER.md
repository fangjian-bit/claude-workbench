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

## Lanes

A lane is a second Claude session building one task in parallel with the driver session. The
driver runs in `/workspace`; every lane runs in the same container, in a worktree under
`/tmp/lanes/N` (`N` the task issue number). `/tmp` is the per-repo `-tmp` volume, so it is
writable under the read-only root and the worktree's `.git` file points at a path the
container can follow. A host worktree beside the checkout cannot be used: the container sees
only `/workspace`, and its `.git` file names a host path.

- **Prepare the lane** (driver, in `/workspace`, the main worktree):
  ```sh
  scripts/lanes/lane.sh prep N M BRANCH CRITICS
  ```
  `M` is the milestone the driver expects the task to be on, `BRANCH` is `TYPE/SLUG` and
  `CRITICS` a comma list of `architect`, `security-critic` and `docs-consistency`. The script
  is in `scripts/`, not the plugin (`WB-D23`). It reads the project file and the plugin's
  `bin/` from the default branch's committed copy, finds the approved spec with `spec-find.sh`,
  checks the task is open, not a pull request and on milestone `M`, cuts the worktree from
  `origin/<pr_base>` with `--no-track` (so nothing pushes to `main` by accident), and writes
  `/tmp/lanes/N-prompt.md` outside the worktree. The prompt names the task and milestone (the
  container clone has no `.ai/state.json`, so `coder.md`'s checks need them named), the spec pin
  (`PIN_ID`, `PIN_UP`), the mode, the critics, the lane rules and a `PATH` line that puts the
  worktree's scripts first while the installed plugin is behind `main`. It never holds issue or
  comment text. It prints `worktree=`, `branch=`, `found=`, `milestone=`, `prompt=` and
  `prompt-sha256=`. If a step from the base fetch on fails it undoes what it did, as far as it
  can, and prints `failed`. Setting the PR's milestone to `M` is the driver's, since `ship` never
  sets one. It stops with one word instead: `not-main`, `unsafe-dir`, `unreadable`,
  `repo-mismatch`, `not-map`, `finder: WORD`, `bad-issue` or `exists`. To clear an `exists`
  caused by a stale name, run `git branch -dr origin/BRANCH` for a lingering remote-tracking
  ref, or `git config --remove-section branch.BRANCH` for leftover config, or pick another
  branch name. `WOW_LANES_DIR` overrides `/tmp/lanes` for the tests only.
  The `PATH` line is written by the script and its text is checked by the fixture. A Bash tool
  call does not keep exports, so the lane prefixes the line, and checks that `command -v
  spec-find.sh` finds the worktree's copy, on every call that runs a plugin script. No lane has
  run it that way yet.
- **Start the lane** from the host, in its own terminal, with `docker exec` (find the container
  id with `docker ps`):
  ```sh
  docker exec -it -u app -e GIT_TERMINAL_PROMPT=0 -w /tmp/lanes/N <container-id> bash -l
  claude --model sonnet
  ```
  Do not use a second `devcontainer exec` beside a running session: `exec` re-reads
  `devcontainer.json` from the host, and that file has to be checked first (see *Opening it*).
  `GIT_TERMINAL_PROMPT` is a `remoteEnv` value, which `docker exec` does not see, so it is passed
  by hand; the commit-signing settings are `containerEnv` and arrive without help.
  Then send the lane this first message in its terminal, with the `prompt-sha256` that `prep`
  printed in place of `HASH`:
  > In one Bash call, run: T=$(mktemp -d) && cp /tmp/lanes/N-prompt.md "$T/p.md" && sha256sum
  > "$T/p.md" && echo "$T/p.md". Stop unless the hash is HASH. If it matches, read only that
  > copy and follow it.

  The copy that was hashed is the copy that is followed.
- **Identity.** Every session, driver or lane, acts as the dev App through the container's `gh`
  shim and git credential helper. Do not prefix commands with `GH_TOKEN`. Suites run natively
  (no WSL), and commits are unsigned (`WB-D25`), so no `timeout 90` around signing.
- **Runtime of `tests/identity-review.test.sh` (#755).** Run alone on the container as built
  (GNU `timeout`), it takes 88 s. With the uutils `timeout` first on `PATH` the same run takes
  775 s, which overruns even the Bash tool's 600 s maximum (its default is 120 s). The cause is
  the `timeout` build: a run makes about 7,500 `timeout` calls across the launcher's wrapped
  docker and gh calls. An isolated `timeout 5 true` measured 62.2 ms with uutils against 0.8 ms
  with GNU, a 61.4 ms difference; that varies with load, and the suite's effective overhead is
  higher, about 90 ms per call. The other uutils tools' share was not measured. Run the suite
  alone, in its own Bash call, with the tool timeout at least 176 s (twice the 88 s). The bound
  is advice: `scripts/lanes/lane.sh` and the prompt it writes are unchanged. On a container whose
  `timeout --version` names uutils, the bound is about 1550 s: run the suite in the background, or
  stop and ask the maintainer. If `command -v timeout` prints `/usr/bin/timeout`, the container
  predates #741 and the maintainer recreates it, on the host, only after every lane and the
  driver session have exited, following the compare-first order in *Hazards that remain* and the
  `--remove-existing-container` command in *Opening it*, then runs *The check after a rebuild* in
  *GNU coreutils, not uutils*, which is also how to tell such a container. If it prints another
  path, a uutils copy in `~/.local/bin` shadows the links: the maintainer removes that copy (it
  survives a recreate, so recreating does not fix it).
  A lane never recreates the container.
- **Reviews** still run on the host through `wow-review`; in the container
  `/way-of-working:architect-review` prints the launcher command.
- **Lane rules that still apply:**
  - Lanes never run `/way-of-working:resume`, `/way-of-working:handoff`,
    `/way-of-working:plan-sprint` or `/way-of-working:archive-sprint`, and never write `.ai/`.
  - A lane never merges, approves or force-pushes. It works in its own worktree and does not
    edit `/workspace`'s working tree (the worktree's `.git` lives under `/workspace/.git`, so its
    commits and refs land there).
  - A session that drafted a spec, or read an issue's body, never builds that issue.
  - Every PR needs a code-owner approval; approving one with auto-merge armed merges it.
- **Cleanup** after the lane's PR merges (driver, in `/workspace`, and only after the lane
  session has exited): `scripts/lanes/lane.sh done N`. It removes the worktree, deletes the branch
  and removes the prompt file, but only if a same-repository PR from that branch merged into
  the base and `prune-verdict.sh` reads `delete`; the branch is deleted with `git update-ref -d`
  against the judged tip, never `git branch -D`.
  - On `kept X skip-ahead` or `kept X skip-unfetchable`, the worktree stays. Inspect it, then
    you may run `git worktree remove` and keep the branch.
  - On `missing`, run `git worktree prune --dry-run -v` first, since `git worktree prune`
    prunes every stale entry, other lanes' included.
  - `not-main`, `unsafe-dir`, `unreadable`, `repo-mismatch`, `not-map`, `no-lane`,
    `not-merged`, `ambiguous` and `kept X unreadable` remove nothing, and so does
    `kept X checked-out` unless the second checkout appears just before the worktree is removed.
    `dirty` leaves the worktree and branch. An `unreadable` after the worktree was removed (the
    re-read of the worktree list failed) leaves the branch, its config and the prompt file: finish
    by hand. `kept X moved` (the branch holds a commit the lane
    made after the verdict) and that late `kept X checked-out` leave the branch and the prompt
    file for you to look at; the worktree is already gone.
  - `failed` means the config probe or removal, or the prompt file removal, failed after the
    branch was deleted; finish by hand with `git config --remove-section branch.X` and `rm` of
    the prompt file.
- **Fallback**, untried: if lanes in one container stop working, use one full clone and one
  container per lane, as *Opening it* describes. Each clone gets its own home volume, so the
  Claude login and the plugin install happen once per clone.

**Trial record.** The first container lane (#707) was built by the hand steps this section then described, and the proposed shape
worked as written: it launched with no changes, read its spec through the finder, built, ran
the gate natively, ran `critic-gate`, and shipped as the dev App with auto-merge armed. Nothing
in the procedure changed. The trial filed follow-ups #727, #728 and #729.

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
removes it. The login lives on the volume; the binary does not.

## The `claude` binary

- **Where it comes from.** The image: `/usr/local/bin/claude`, root-owned, at the version pinned
  in `.devcontainer/Dockerfile` (`CLAUDE_VERSION`), its SHA-256 (`CLAUDE_SHA256`) checked at
  build time. Auto-update is off through both `DISABLE_AUTOUPDATER=1` in `devcontainer.json`'s
  `containerEnv` and the root-owned `/etc/claude-code/managed-settings.json` (`.devcontainer/`),
  which a settings file cannot override. The read-only root filesystem keeps the binary from being
  replaced, but not an updater writing a newer copy to `~/.local` on the home volume, so the
  `DISABLE_AUTOUPDATER` setting (from either source) is the control. It stops the automatic updater
  only: per Claude Code's environment-variable documentation, a manual `claude update` still works,
  and `DISABLE_UPDATES` blocks both; this image does not set it. After a rebuild,
  `stat -c '%U %a' /etc/claude-code/managed-settings.json` prints `root 444`. Per Claude Code's
  managed-settings documentation ("How Claude Code combines managed sources"), `env` merges per
  variable across managed sources, so server-managed settings, if this account ever receives them,
  override this pin only if they set `DISABLE_AUTOUPDATER` themselves.
- **How to bump it.** Edit `CLAUDE_VERSION` and `CLAUDE_SHA256` in all three Dockerfiles
  (`.devcontainer/`, `scripts/identity/review/` and `scripts/loop/`; Dependabot does not track
  them, and `tests/devcontainer-image.test.sh` and `tests/review-image.test.sh` hold them equal).
  Take the sha256 from that version's release `manifest.json` (the `linux-x64` entry). Then
  recreate the container with the compare-first order in *Hazards that remain*.
- **Clearing a stopgap install.** A copy from the native installer lives on the home volume, and
  `~/.local/bin` leads `PATH`, so it shadows the image's. Remove `~/.local/bin/claude` and
  `~/.local/share/claude`, then check with `command -v claude` (should print
  `/usr/local/bin/claude`) and `claude --version` (should print the pinned version).
- **What this does not close.** The binary cannot be modified, but which `claude` runs can be:
  anything earlier on `PATH` shadows it (`type -a claude` lists every match). Hooks in
  `~/.claude/settings.json` and startup code in `~/.bashrc` are still on the writable home volume, as are, for
  example, `~/.profile`, `~/.claude.json` and `~/.local/bin`, so a session can still persist code
  that runs in the next one. The VS Code extension's own `claude` is outside the pin too (VS Code
  attach is unsupported here). `docker volume rm <checkout folder>-home <checkout folder>-tmp`
  (after removing the containers that use them) resets the container's own state, not the `/workspace` checkout, whose `.claude/` and
  `.git/hooks` or `.git/config` a session can also write and which must be checked separately.

## GNU coreutils, not uutils

- **Why.** The base image is Ubuntu 26.04, where the plain coreutils names (`timeout`, `date`,
  `tail` and the rest) are the Rust uutils build. Its `timeout` adds about 100 ms to every call,
  which `scripts/identity/wow-review`, `tests/identity-review.test.sh` and other suites and plugin
  scripts pay, and some uutils tools give wrong results: `date +%s%3N` ignores the width and prints
  nanoseconds. CI and Git Bash run GNU, so the container was the odd one out (#741).
- **What it does.** Every gnu-prefixed tool in `/usr/bin` (the base image's own gnu-coreutils
  package, so nothing is downloaded) is linked under its plain name in `/usr/local/bin`, which
  comes before `/usr/bin` on `PATH`. A build-time assertion fails the build if `timeout` does not
  resolve to `/usr/bin/gnutimeout` or `date` ignores the millisecond width, and plain `ln -s`
  fails it if a file or link of that name already exists (the `gh` shim and `claude` live there). A directory (or a link to one) of that name is not
  refused, and that tool keeps uutils (for `timeout` and `date` the assertion fails the build). The
  package providing the plain names is not switched to coreutils-from-gnu: the image ships no apt lists,
  and the switch would need a network package fetch at build time that the FROM line's digest
  does not pin.
- **What it covers.** Parity with CI for coreutils only. The container's `awk` (mawk) and `sh`
  (dash) are unchanged. The links also change which `date` and `tr` the token reader
  `/usr/local/libexec/dev-token` uses, to GNU; `tests/dev-token.test.sh` assumes GNU `date`. That
  suite is not in CI, so the rebuilt container is the only place it is checked against the tools
  the reader really runs.
- **What it does not cover.** Callers that bypass `PATH` still get uutils: absolute `/usr/bin/...`
  or `/bin/...` paths (`/bin` is the usrmerge link to `/usr/bin`), a `PATH` reset to
  `/usr/bin:/bin`, and `env -i` with no `PATH` (libc's default is `/bin:/usr/bin`). A
  `#!/usr/bin/env` shebang runs only `env` itself from uutils; the script's own calls go through
  `PATH` and get GNU. Anything earlier on `PATH` wins, and `~/.local/bin` leads it. The
  uutils-only extras (for example `hashsum`) and `/usr/sbin/gnuchroot` are not linked. The review
  image and the loop image are separate (#760).
- **The check after a rebuild**, with the compare-first order in *Hazards that remain*:
  `command -v timeout` prints `/usr/local/bin/timeout`, `timeout --version` names GNU coreutils on
  its first line, `date +%s%3N` prints 13 digits, and `ls ~/.local/bin` lists no coreutils name (a
  copy there, on the home volume, would shadow the links).

## Not adopted here yet

The template's `.github/workflows` (`devcontainer-image.yml`, `architect-review-gate.yml`,
`secret-scan.yml`) are not copied: adding required checks is a ruleset decision for the
maintainer. The Dockerfile header lists what `verify / verify` would enforce, and the
attestation command to check the pinned digest by hand.
