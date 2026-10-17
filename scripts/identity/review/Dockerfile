# The App-mode review image (#623, child b; #634): the shared dev-container base plus the
# `claude` CLI and a root-owned managed-settings file. `gh` and git act only through a mounted
# session token, read on every call. The host launcher `wow-review` (#635) starts it.
#
# Maintenance, stated so nobody assumes more than holds:
#   - Dependabot opens a separate PR for this directory, so nothing keeps the FROM pin equal
#     to the dev container's.
#   - The base image's signed provenance is not verified here, so a digest bump gets human
#     review only. .devcontainer/Dockerfile's header names a `gh attestation verify` command
#     for a check by hand.
#   - The `claude` pin below is bumped by hand, together with scripts/loop/Dockerfile's: a
#     test holds the two equal.
#   - The copied dev-token, gh shim, inject.py and proxy.py are reused unedited apart from
#     dev-token's two rewritten lines, so their own comments still describe the dev container
#     or the loop. In this image they act as the reviewer App.
#   - token-check.sh and gh-identity.sh come from plugins/way-of-working/bin/, which
#     orchestration.human_only_paths does not list, so loop-written code (merged under human
#     approval) becomes a root-owned identity check here.
#   - The root-owned files here protect against uid 1000 only while the launcher (#635) keeps the
#     dev container's run flags: a read-only root filesystem, --cap-drop=ALL and no-new-privileges.
#   - The image's own /home/app is not empty, so the entrypoint's empty-home check passes
#     only under #635's tmpfs.
#
# The build context is bin/review/ as scripts/identity/install-host-tools.ps1 exports it:
# this file plus exactly the files copied below.
FROM ghcr.io/603-identity/devcontainer-base:4.499@sha256:17089403374228a67bbe9cc0546b71ef47be180a4399a4218b977d9f47689c73

# `claude` goes in /usr/local/bin, root-owned, not the native installer's per-user location:
# that is writable state, where the session could replace the binary. Pinned by version and
# sha256, the same two values as scripts/loop/Dockerfile.
ARG CLAUDE_VERSION=2.1.289
ARG CLAUDE_SHA256=a186b99e4a9c88366cd49df2f7dad56c61fc306ef0140b19ee64b7c42a8d1348

USER 0
RUN set -eu; \
    curl -fsSL --retry 3 -o /usr/local/bin/claude \
      "https://downloads.claude.ai/claude-code-releases/${CLAUDE_VERSION}/linux-x64/claude"; \
    echo "${CLAUDE_SHA256}  /usr/local/bin/claude" | sha256sum -c -; \
    chown root:root /usr/local/bin/claude; \
    chmod 0755 /usr/local/bin/claude; \
    mkdir -p /etc/claude-code /etc/way-of-working /opt/review; \
    chmod 0755 /etc/claude-code /etc/way-of-working /opt/review

# Auto-update off, and no traffic the session does not need.
ENV DISABLE_AUTOUPDATER=1 \
    DISABLE_TELEMETRY=1 \
    DISABLE_ERROR_REPORTING=1 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

COPY --chown=root:root --chmod=0444 managed-settings.json /etc/claude-code/managed-settings.json

# Identity: the real gh moves to gh-real and a shim takes its place; git's credential helper
# for https://github.com becomes the token reader (as .devcontainer/Dockerfile does). The
# reader is the dev container's dev-token with its two fixed lines pointed at the review
# session's token; the grep fails the build unless both rewrites took.
COPY --chown=root:root --chmod=0555 dev-token /usr/local/libexec/dev-token
COPY --chown=root:root --chmod=0555 gh /usr/local/libexec/gh-shim
RUN set -eu; \
    sed -i \
      -e 's|^dir=/run/glunk-identity/dev$|dir=/run/glunk-identity/review|' \
      -e 's|^file=$dir/dev-token$|file=$dir/session-token|' \
      /usr/local/libexec/dev-token; \
    grep -q '^dir=/run/glunk-identity/review$' /usr/local/libexec/dev-token; \
    grep -q '^file=$dir/session-token$' /usr/local/libexec/dev-token; \
    mv /usr/local/bin/gh /usr/local/libexec/gh-real; \
    mv /usr/local/libexec/gh-shim /usr/local/bin/gh; \
    git config --system --unset-all credential."https://github.com".helper; \
    git config --system credential."https://github.com".helper ""; \
    git config --system --add credential."https://github.com".helper "!/usr/local/libexec/dev-token git-credential"; \
    git config --system url."https://github.com/".insteadOf "git@github.com:"; \
    git config --system --add url."https://github.com/".insteadOf "ssh://git@github.com/"

# Root-owned helpers, and the sidecar scripts #635 runs from this image.
COPY --chown=root:root --chmod=0555 token-check.sh gh-identity.sh entrypoint.sh outbox-read /usr/local/libexec/
COPY --chown=root:root --chmod=0555 inject.py proxy.py /opt/review/

# The review-container marker: review-sandbox.sh make and run refuse where it exists.
RUN touch /etc/way-of-working/review-container \
    && chown root:root /etc/way-of-working/review-container \
    && chmod 0444 /etc/way-of-working/review-container

# The image does not create /review-out; the launcher mounts it.
RUN set -eu; \
    PATH=/usr/local/bin:/usr/bin:/bin; export PATH; \
    /usr/local/libexec/gh-real --version >/dev/null; \
    jq --version >/dev/null; \
    yq --version >/dev/null; \
    python3 --version >/dev/null; \
    claude --version >/dev/null; \
    /bin/bash --version >/dev/null; \
    command -v timeout >/dev/null; \
    [ "$(stat -c %u:%a /etc/way-of-working/review-container)" = 0:444 ]; \
    [ "$(stat -c %u:%a /etc/claude-code/managed-settings.json)" = 0:444 ] \
      && jq -e '.strictPluginOnlyCustomization == true and .allowManagedHooksOnly == true' /etc/claude-code/managed-settings.json >/dev/null

USER 1000:1000
WORKDIR /work
ENTRYPOINT ["/usr/local/libexec/entrypoint.sh"]
