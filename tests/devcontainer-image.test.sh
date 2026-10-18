#!/bin/sh
# Static fixtures for the dev container image (#725): .devcontainer/Dockerfile and
# .devcontainer/devcontainer.json.
#
#   Dockerfile          the template's shape (header of the Dockerfile), the claude pin against
#                       scripts/loop/Dockerfile's, the download and checksum, nothing in the app
#                       user's home directory, no npm or node
#   devcontainer.json   DISABLE_AUTOUPDATER is "1" inside containerEnv. The file has // comments,
#                       so jq cannot parse it; this checks with a line-anchored grep inside the
#                       containerEnv block (awk cuts the block out), not by stripping comments.
#
# Permitted toolset: POSIX sh and its standard utilities (awk, grep, sed). A fixture that needs a
# tool the runner lacks would skip loudly; none does beyond these.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
dc="${DEVCONTAINER_DIR:-$root_dir/.devcontainer}"
loop="${LOOP_DOCKERFILE:-$root_dir/scripts/loop/Dockerfile}"

for t in awk grep sed; do
  if ! command -v "$t" >/dev/null 2>&1; then
    echo "SKIP - $t not on PATH; devcontainer-image fixtures not run" >&2
    exit 0
  fi
done

fail=0
ok() { printf 'ok - %s\n' "$1"; }
bad() { printf 'FAIL - %s\n' "$1" >&2; fail=1; }
check() { # check <label> <command...>
  l=$1; shift
  if "$@"; then ok "$l"; else bad "$l"; fi
}
assert_eq() { # assert_eq <label> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: expected [$2], got [$3]"; fi
}

df="$dc/Dockerfile"
dj="$dc/devcontainer.json"
[ -f "$df" ] && [ -f "$dj" ] || { echo "FAIL - $df or $dj is missing" >&2; exit 1; }

# --- Dockerfile: the template's shape ----------------------------------------------------
check "Dockerfile: the first line is a # syntax= directive" sh -c 'head -1 "$1" | grep -Eq "^# syntax=docker/dockerfile:[0-9.]+@sha256:[0-9a-f]{64}$"' _ "$df"
check "Dockerfile: line 2 is not a parser directive" test -z "$(sed -n 2p "$df" | grep -Ei '^#[[:space:]]*[a-z][a-z0-9]*[[:space:]]*=' || true)"
assert_eq "Dockerfile: exactly one # syntax= line" 1 "$(grep -ci '^#[[:space:]]*syntax[[:space:]]*=' "$df" || true)"
first_instr=$(grep -n '^[A-Za-z]' "$df" | head -1)
case $first_instr in *:FROM\ *) ok "Dockerfile: FROM is the first instruction (no ARG before it)" ;; *) bad "Dockerfile: the first instruction is [$first_instr]" ;; esac
assert_eq "Dockerfile: exactly one FROM" 1 "$(grep -Eci '^[[:space:]]*FROM[[:space:]]' "$df" || true)"
from=$(grep '^FROM ' "$df" | head -1)
case $from in *'$'*|*' AS '*|*--platform*) bad "Dockerfile: the FROM line is not plain: $from" ;; *) ok "Dockerfile: the FROM line is plain" ;; esac
printf '%s\n' "$from" | grep -Eq '^FROM [a-z0-9./-]+:[A-Za-z0-9._-]+@sha256:[0-9a-f]{64}$' && ok "Dockerfile: the FROM line is tag-and-digest pinned" || bad "Dockerfile: FROM is not tag-and-digest pinned: $from"
assert_eq "Dockerfile: no ARG before FROM" 0 "$(sed -n '1,/^FROM /p' "$df" | grep -Eci '^[[:space:]]*ARG[[:space:]]' || true)"
check "Dockerfile: no COPY --from, RUN --mount from= or ONBUILD" test -z "$(grep -v '^#' "$df" | grep -Ei -e 'COPY +(--[^ ]+ +)*--from' -e '--mount[^ ]*from=' -e '^[[:space:]]*ONBUILD' || true)"
check "Dockerfile: ASCII only" test -z "$(LC_ALL=C grep -n '[^ -~	]' "$df" | grep -v '^[0-9]*:$' || true)"
check "Dockerfile: LF line endings only" test -z "$(grep -c "$(printf '\r')" "$df" | grep -v '^0$' || true)"

# --- Dockerfile: the claude install ------------------------------------------------------
# The install checks read the file with comment lines removed, so a commented-out install fails.
dfcode=$(mktemp); trap 'rm -f "$dfcode"' EXIT
grep -v '^[[:space:]]*#' "$df" >"$dfcode"
arg() { sed -n "s/^ARG $2=//p" "$1"; }
for a in CLAUDE_VERSION CLAUDE_SHA256; do
  v=$(arg "$dfcode" $a); w=$(arg "$loop" $a)
  if [ -n "$v" ] && [ "$v" = "$w" ]; then ok "Dockerfile: $a equals scripts/loop/Dockerfile's"; else bad "Dockerfile: $a [$v] differs from the loop's [$w]"; fi
done
check "Dockerfile: CLAUDE_VERSION is a plain x.y.z" sh -c 'arg=$(sed -n "s/^ARG CLAUDE_VERSION=//p" "$1"); printf "%s\n" "$arg" | grep -Eq "^[0-9]+\.[0-9]+\.[0-9]+\$"' _ "$dfcode"
check "Dockerfile: CLAUDE_SHA256 is 64 lowercase hex" sh -c 'arg=$(sed -n "s/^ARG CLAUDE_SHA256=//p" "$1"); printf "%s\n" "$arg" | grep -Eq "^[0-9a-f]{64}\$"' _ "$dfcode"
check "Dockerfile: nothing masks a failure (no || true)" test -z "$(grep -F -e '|| true' -e '; true' "$dfcode" || true)"
check "devcontainer.json: no build args override the pin" test -z "$(grep -E -e '"args"[[:space:]]*:' -e '--build-arg' "$dj" || true)"
check "Dockerfile: the download is to /usr/local/bin/claude from the \${CLAUDE_VERSION}/linux-x64/claude URL" \
  grep -qF 'https://downloads.claude.ai/claude-code-releases/${CLAUDE_VERSION}/linux-x64/claude' "$dfcode"
check "Dockerfile: the download writes /usr/local/bin/claude" grep -q 'curl .*-o /usr/local/bin/claude' "$dfcode"
check "Dockerfile: the download is checked with sha256sum -c against CLAUDE_SHA256" grep -qF '${CLAUDE_SHA256}  /usr/local/bin/claude" | sha256sum -c -' "$dfcode"
check "Dockerfile: the install RUN starts with set -eu" grep -Eq '^RUN set -eu; \\$' "$dfcode"
check "Dockerfile: sha256sum -c ends its line, nothing masks it" grep -qE 'sha256sum -c -; \\$' "$dfcode"
check "Dockerfile: the binary is root-owned" grep -qF 'chown root:root /usr/local/bin/claude' "$dfcode"
check "Dockerfile: the binary is mode 0755" grep -qF 'chmod 0755 /usr/local/bin/claude' "$dfcode"
assert_eq "Dockerfile: USER 1000:1000 is the last USER" "USER 1000:1000" "$(grep '^USER ' "$df" | tail -1)"
code=$(cat "$dfcode")
check "Dockerfile: no instruction names the app user's home directory" test -z "$(printf '%s\n' "$code" | grep -e '/home/app' -e '~/' -e '\$HOME' || true)"
check "Dockerfile: no instruction names npm or node" test -z "$(printf '%s\n' "$code" | grep -Ewi -e 'npm' -e 'node' -e 'nodejs' || true)"

# --- devcontainer.json -------------------------------------------------------------------
block=$(awk '/^[[:space:]]*"containerEnv"[[:space:]]*:/ {on=1} on {print} on && /}/ {exit}' "$dj")
check "devcontainer.json: containerEnv is found" test -n "$block"
check "devcontainer.json: DISABLE_AUTOUPDATER is \"1\" inside containerEnv" sh -c 'printf "%s\n" "$1" | grep -Eq "^[[:space:]]*\"DISABLE_AUTOUPDATER\"[[:space:]]*:[[:space:]]*\"1\"[[:space:]]*,?[[:space:]]*\$"' _ "$block"
for k in 'GIT_CONFIG_COUNT": "2"' 'GIT_CONFIG_KEY_0": "commit.gpgsign"' 'GIT_CONFIG_VALUE_0": "false"' 'GIT_CONFIG_KEY_1": "tag.gpgsign"' 'GIT_CONFIG_VALUE_1": "false"'; do
  check "devcontainer.json: containerEnv keeps $k" sh -c 'printf "%s\n" "$1" | grep -qF "$2"' _ "$block" "$k"
done

[ "$fail" -eq 0 ] || exit 1
echo "all devcontainer-image fixtures passed"
