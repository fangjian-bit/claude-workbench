#!/bin/sh
# Fixture tests for .devcontainer/dev-token, the container's dev-App token reader.
#
# #393 (WB-D24): the container reads the broker's token file on every call and fails closed on
# anything but a live installation token with 5 minutes or more left. Permitted toolset:
# POSIX sh plus GNU date (the container's own).
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# The production script fixes its directory; test a copy pointing at the fixture directory.
mkdir "$tmp/d"
sed "s|^dir=/run/glunk-identity/dev\$|dir=$tmp/d|" "$root_dir/.devcontainer/dev-token" >"$tmp/script"
grep -q "^dir=$tmp/d\$" "$tmp/script" || { echo "FAIL - could not substitute dir" >&2; exit 1; }
script="$tmp/script"

if ! date -u -d '+1 min' +%s >/dev/null 2>&1; then
  echo "SKIP - GNU date -d not available" >&2
  exit 0
fi

fail=0
assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok - $1"
  else
    echo "FAIL - $1: expected [$2], got [$3]" >&2
    fail=1
  fi
}

run() {
  rc=0
  out=$(sh "$script" "$@" 2>"$tmp/err") || rc=$?
}
expect() { # expect <desc> <out> <rc>
  assert_eq "$1 (stdout)" "$2" "$out"
  assert_eq "$1 (rc)" "$3" "$rc"
}
at() { date -u -d "$1" +%Y-%m-%dT%H:%M:%SZ; }

tok=ghs_0123456789abcdefghijklmnopqrstuvwxyzABCD
mk() { printf '%s\n%s\n' "$1" "$2" >"$tmp/d/dev-token"; }

mk "$tok" "$(at '+20 minutes')"
run; expect "live token prints" "$tok" 0
run git-credential get </dev/null
expect "credential with no host prints nothing" "" 0
run git-credential get <<EOT
protocol=https
host=github.com

EOT
expect "credential for github.com" "username=x-access-token
password=$tok" 0
run git-credential get <<EOT
protocol=https
host=example.com

EOT
expect "credential for another host prints nothing" "" 0
run git-credential get <<EOT
protocol=http
host=github.com

EOT
expect "credential over http prints nothing" "" 0
run git-credential store </dev/null
expect "credential store is ignored" "" 0

# A rotated file is picked up on the next call.
tok2=ghs_ZYXWVUTSRQPONMLKJIHGFEDCBAzyxwvutsrqponm
mk "$tok2" "$(at '+30 minutes')"
run; expect "rotated token is read fresh" "$tok2" 0

mk "$tok" "$(at '+2 minutes')"
run; expect "under 5 minutes left refused" "" 2
run git-credential get <<EOT
protocol=https
host=github.com

EOT
expect "credential refusal tells git to quit" "quit=1" 0
run git-credential get <<EOT
protocol=https
host=example.com

EOT
expect "refusal stays silent for another host" "" 0
rm "$tmp/d/dev-token"
run git-credential get <<EOT
protocol=https
host=github.com

EOT
expect "missing file in credential mode tells git to quit" "quit=1" 0
mk "$tok" "$(at '-1 minute')"
run; expect "expired refused" "" 2
mk "ghp_0123456789abcdefghijklmnopqrstuvwxyzABCD" "$(at '+20 minutes')"
run; expect "user token refused" "" 2
mk "ghs_short" "$(at '+20 minutes')"
run; expect "short token refused" "" 2
mk "" "$(at '+20 minutes')"
run; expect "empty token refused" "" 2
mk "ghs_0123456789abcdefghijklmnopqrstuvwxyz\$(id)" "$(at '+20 minutes')"
run; expect "token with shell characters refused" "" 2
mk "$tok" "tomorrow"
run; expect "malformed expiry refused" "" 2
printf '%s\n%s\nextra\n' "$tok" "$(at '+20 minutes')" >"$tmp/d/dev-token"
run; expect "three lines refused" "" 2
rm -f "$tmp/d/dev-token"
run; expect "missing file refused" "" 2
mk "$tok" "$(at '+20 minutes')"
mv "$tmp/d/dev-token" "$tmp/d/real"
ln -s "$tmp/d/real" "$tmp/d/dev-token" 2>/dev/null && [ -L "$tmp/d/dev-token" ] && { run; expect "symlinked file refused" "" 2; }
rm -f "$tmp/d/dev-token"
mk "$tok" "$(at '+20 minutes')"
run bogus; expect "unknown argument refused" "" 2

[ "$fail" -eq 0 ] || exit 1
echo "all dev-token tests passed"
