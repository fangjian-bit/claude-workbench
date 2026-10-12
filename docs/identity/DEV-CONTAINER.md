# The claude-workbench dev container

WB-D24, issue #393. The container is `.devcontainer/`, from the 603-Identity/devcontainers
template. A session in it reaches GitHub only as the dev App, provided the host setting
`dev.containers.gitCredentialHelperConfigLocation` is `none` (see Hazards that remain).

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
  set to `none` stops Dev Containers from injecting a helper at all.
- The container holds no `gh` login. The template's GitHub VS Code extensions are left out, as
  they sign in with the human's account.

## Opening it

- Open a **full clone** that is not the one `install-host-tools.ps1` installs from, runs git in,
  or runs host-side reviews in, and not a worktree of any of those (a worktree shares that clone's `.git`, hooks and
  config, and its `.git` file points at a host path git cannot follow in the container). A
  container-writable source clone is host code execution beside the App keys.
- Start VS Code from PowerShell, cmd or the Start menu, not Git Bash.
- Reviewer tokens never enter this container. Where App-mode review runs is tracked separately.

## Hazards that remain

- **`/workspace` is read-write**, so a session can edit `.devcontainer/` (an `initializeCommand`,
  wider mounts) and the host runs it at the next Reopen or Rebuild. Compare `.devcontainer/`
  with the committed blob, from a different clone, before every Rebuild.
- **VS Code's forwarded git credential channel (required setting).** Set the VS Code user setting
  `dev.containers.gitCredentialHelperConfigLocation` to `none` **before the first open**. Otherwise
  the helper script and IPC socket Dev Containers injects stay reachable, and a session can call
  them directly for the host's GitHub credential even though git itself asks `dev-token` first.
  Whether the channel answers with the option set to `none` has not been tested; check in a live
  container (`env | grep REMOTE_CONTAINERS_IPC`).
- **A forwarded host ssh-agent** is not blocked: git's SSH remotes are rewritten to https, but
  `ssh git@github.com` would authenticate with a GitHub key loaded in the host agent. Keep no
  GitHub key in the agent that VS Code forwards.
- **A reused home volume** can hold a human `gh auth login` PAT from an earlier container; the
  shim overrides it, but `/usr/local/libexec/gh-real` does not. `docker volume rm <checkout folder>-home`
  before first use.

## What it still carries from the template

Commit signing. The template forwards VS Code's GPG agent and mounts the host's `~/.gitconfig.d`
read-only, so commits are signed as the human and pushed by the App. This is signing, not
GitHub access, and it is kept; it is the one human-held capability in the container, beyond
WB-D24's "no GPG" wording for item 4, so say so if the owner wants it dropped.

## Claude login

`claude /login` once inside the container. The credential lives in the per-checkout home volume
`<checkout folder>-home`, and `docker volume rm <checkout folder>-home`
removes it.

## Not adopted here yet

The template's `.github/workflows` (`devcontainer-image.yml`, `architect-review-gate.yml`,
`secret-scan.yml`) are not copied: adding required checks is a ruleset decision for the
maintainer. The Dockerfile header lists what `verify / verify` would enforce, and the
attestation command to check the pinned digest by hand.
