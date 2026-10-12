# syntax=docker/dockerfile:1.27@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
#
# This repo's devcontainer: the shared base image, pinned by tag AND digest, plus the two
# scripts that make `gh` and git act only as the dev App (WB-D24, #393). Dependabot's docker
# ecosystem bumps the FROM line (.github/dependabot.yml).
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
USER 1000:1000
