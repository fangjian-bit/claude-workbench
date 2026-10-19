# syntax=docker/dockerfile:1.27@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
#
# This repo's devcontainer: the shared base image, pinned by tag AND digest, plus the two
# scripts that make `gh` and git act only as the dev App (WB-D24, #393) and a pinned,
# checksum-verified `claude` (#725) with a root-owned managed settings file (#742) and GNU
# coreutils ahead of uutils on PATH (#741). Dependabot's docker ecosystem bumps the FROM line
# (.github/dependabot.yml).
#
# Every pull request is checked by `verify / verify` once the template's
# .github/workflows/devcontainer-image.yml is adopted: the FROM line must be one of the
# shared images, by tag and digest, with signed provenance and an SBOM from a first-attempt
# build.yml run on main, and this file must keep the template's shape:
#   - the `# syntax=` line above, unchanged, and no other directive;
#   - ASCII only, LF line endings, no NUL, no BOM, at most 1 MiB;
#   - one stage only: no second FROM, no ARG before FROM, no `$` in the image reference;
#   - a plain FROM: no `AS <name>` and no `--platform`;
#   - no `COPY --from`, `RUN --mount from=` or ONBUILD.
# For a first look by hand, for the digest on the FROM line:
#   gh attestation verify oci://ghcr.io/603-identity/devcontainer-base@sha256:<digest> \
#     --repo 603-Identity/devcontainers \
#     --cert-identity https://github.com/603-Identity/devcontainers/.github/workflows/build.yml@refs/heads/main \
#     --cert-oidc-issuer https://token.actions.githubusercontent.com \
#     --source-ref refs/heads/main --deny-self-hosted-runners
FROM ghcr.io/603-identity/devcontainer-base:4.499@sha256:17089403374228a67bbe9cc0546b71ef47be180a4399a4218b977d9f47689c73

# The container's root filesystem is read-only at run time (devcontainer.json runArgs), so
# everything extra is installed here, outside /home/app (the home volume copies the image's
# /home/app once, at first mount).
#
# Identity. The base image's `gh` is the stock binary with git's credential helper pointed
# at `gh auth git-credential`, which reads a stored login. This container holds no stored
# login: the dev App's token arrives as a read-only file from the host broker, and is read on
# every call. So:
#   - the real gh moves to /usr/local/libexec/gh-real and /usr/local/bin/gh becomes a shim that
#     reads the token fresh and sets it for that one call;
#   - git's credential helper for https://github.com becomes the same reader.
# SSH remotes to github.com are rewritten to https, so a forwarded host ssh-agent is not used
# for git (it steers git only; raw ssh is not blocked, see docs/identity/DEV-CONTAINER.md).
# Both live in /usr/local, which the read-only root filesystem keeps out of the app user's
# reach. ~/.local/bin leads PATH, so a user can still shadow `gh` there; that is the
# container's own session, which can read the same token anyway.
#
# Commit signing. Container commits are unsigned (WB-D25, #574), so the GPG tools the base
# image installs with gnupg are deleted here. That does not by itself close a forwarded agent
# socket (WB-D25 residual); the live container check confirms whether one is forwarded.
# devcontainer.json forces commit.gpgsign and tag.gpgsign off as well.
USER 0
COPY --chmod=0755 dev-token /usr/local/libexec/dev-token
COPY --chmod=0755 gh /usr/local/libexec/gh-shim
RUN mv /usr/local/bin/gh /usr/local/libexec/gh-real \
    && mv /usr/local/libexec/gh-shim /usr/local/bin/gh \
    && git config --system --unset-all credential."https://github.com".helper \
    && git config --system credential."https://github.com".helper "" \
    && git config --system --add credential."https://github.com".helper "!/usr/local/libexec/dev-token git-credential" \
    && git config --system url."https://github.com/".insteadOf "git@github.com:" \
    && git config --system --add url."https://github.com/".insteadOf "ssh://git@github.com/" \
    && /usr/local/libexec/gh-real --version
RUN for t in gpg gpg-agent gpgconf gpg-connect-agent gpgsm; do \
      p=$(command -v "$t") && rm -f "$p"; \
      if command -v "$t" >/dev/null; then exit 1; fi; \
    done

# Claude Code, at /usr/local/bin/claude: root-owned and on the read-only root filesystem, so no
# session can modify that file. A copy earlier on PATH can still shadow it (the native
# installer's copy in ~/.local/bin sits on the writable home volume). CLAUDE_VERSION and
# CLAUDE_SHA256 come from that version's release manifest.json (the `linux-x64` entry). Dependabot does not track a pin inside a RUN, so it is bumped by hand,
# together with scripts/loop/Dockerfile's and scripts/identity/review/Dockerfile's (tests hold
# the three equal): edit both ARG lines, then recreate with the compare-first procedure in
# docs/identity/DEV-CONTAINER.md. Auto-update is off in devcontainer.json (DISABLE_AUTOUPDATER) and
# in the managed settings file below.
ARG CLAUDE_VERSION=2.1.289
ARG CLAUDE_SHA256=a186b99e4a9c88366cd49df2f7dad56c61fc306ef0140b19ee64b7c42a8d1348
RUN set -eu; \
    curl -fsSL --retry 3 -o /usr/local/bin/claude \
      "https://downloads.claude.ai/claude-code-releases/${CLAUDE_VERSION}/linux-x64/claude"; \
    echo "${CLAUDE_SHA256}  /usr/local/bin/claude" | sha256sum -c -; \
    chown root:root /usr/local/bin/claude; \
    chmod 0755 /usr/local/bin/claude

# Managed settings: DISABLE_AUTOUPDATER pinned in a root-owned file that a settings-file `env`
# (~/.claude/settings.json on the home volume, a project .claude/settings.json) cannot override,
# and the root filesystem is read-only at run time. The guard fails the build if a later base
# image ships anything under /etc/claude-code, instead of overwriting or merging it.
RUN set -eu; test ! -e /etc/claude-code; mkdir -p /etc/claude-code; chmod 0755 /etc/claude-code
COPY --chown=root:root --chmod=0444 managed-settings.json /etc/claude-code/managed-settings.json
RUN [ "$(stat -c %u:%a /etc/claude-code/managed-settings.json)" = 0:444 ]

# GNU coreutils ahead of uutils on PATH (#741). The base image is Ubuntu 26.04, where the plain
# coreutils names (timeout, date, tail and the rest) are the Rust uutils build. Its `timeout`
# adds about 100 ms to every call, and some tools give wrong results: `date +%s%3N` ignores the
# width and prints nanoseconds. CI and Git Bash run GNU, so the container is the odd one out.
# The base image already ships GNU coreutils under gnu-prefixed names (package gnu-coreutils),
# so each /usr/bin/gnu<name> is linked as /usr/local/bin/<name>, which comes before /usr/bin on
# PATH; nothing is downloaded. Plain `ln -s`, never a force option, fails the build if a file or
# link of any of those names already exists in /usr/local/bin (the `gh` shim and `claude` live
# there). A directory (or a link to one) of that name is not refused, and that tool keeps uutils
# (for `timeout` and `date` the assertion below fails the build). `set -f` keeps the `gnu[` entry
# literal. If a later base image stops shipping gnu-coreutils the loop runs zero times and the
# assertion below fails the build; it also checks that `date` honours the millisecond width (13
# digits plus a newline).
# Not covered, so these still get uutils: callers that bypass PATH (absolute /usr/bin/... or
# /bin/... paths, /bin being the usrmerge link to /usr/bin; a PATH reset to /usr/bin:/bin; `env -i`
# with no PATH, where libc defaults to /bin:/usr/bin). A `#!/usr/bin/env` shebang runs only `env`
# itself from uutils; the script's own calls go through PATH and get GNU. Anything earlier on PATH
# also wins: the home directory's local bin leads it. Coreutils only: awk (mawk) and sh (dash)
# are unchanged.
RUN set -euf; \
for p in $(dpkg -L gnu-coreutils | grep '^/usr/bin/gnu'); do \
ln -s "$p" "/usr/local/bin/${p#/usr/bin/gnu}"; \
done
RUN [ "$(readlink -f "$(command -v timeout)")" = /usr/bin/gnutimeout ] && [ "$(date +%s%3N | wc -c)" -eq 14 ]
USER 1000:1000
