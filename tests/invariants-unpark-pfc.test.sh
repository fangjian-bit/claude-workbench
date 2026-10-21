#!/bin/sh
# Fixture tests for scripts/invariants-check.sh's check 13: unpark-sprint validates the
# snapshot's parked_from_commit as hex before it reaches `git log` or `git merge-base` (#539).
#
# Each case mutates a COPY of the real tree and asserts the check fires (or stays silent), so
# a check that only passes on the real tree cannot hide. Only check 13's own message is
# asserted, never the script's overall exit.
#
# Every case but the first control runs just check 13 (`--only 13`); that control runs the full checker.
#
# Permitted toolset: POSIX sh. No jq, no yq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/scripts/invariants-check.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
MSG="unpark-sprint no longer validates parked_from_commit"

tree() {
  d="$tmp/$1"
  mkdir -p "$d"
  cp -R "$root_dir/plugins" "$d/plugins"
  echo "$d"
}

sel="--only 13"

run() { ( cd "$1" || exit 1; rc=0; bash "$script" $sel 2>&1 >/dev/null || rc=$?; [ "$rc" -ne 2 ] || : >"$tmp/usage-exit" ) || true; }

assert_fires() { # <desc> <dir>
  if run "$2" | grep -qF -- "$MSG"; then
    echo "ok - $1"
  else
    echo "FAIL - $1: expected check 13 to fire" >&2
    fail=1
  fi
}

assert_silent() { # <desc> <dir>
  if run "$2" | grep -qF -- "$MSG"; then
    echo "FAIL - $1: check 13 fired" >&2
    fail=1
  else
    echo "ok - $1"
  fi
}

# Control: the real tree is clean.
sel=
d="$(tree control)"
assert_silent "real tree passes" "$d"
sel="--only 13"

# The guard line removed fires.
d="$(tree noguard)"
f="$(ls "$d"/plugins/*/skills/unpark-sprint/SKILL.md)"
grep -vF '[!0-9a-f]' "$f" >"$f.new" && mv "$f.new" "$f"
assert_fires "unpark-sprint without the hex guard fires" "$d"

# A hex pattern for some other variable does not satisfy it.
d="$(tree othervar)"
f="$(ls "$d"/plugins/*/skills/unpark-sprint/SKILL.md)"
sed 's/PFC/OTHER/g' "$f" >"$f.new" && mv "$f.new" "$f"
assert_fires "a guard on another variable does not satisfy it" "$d"

# A guard whose value is not read with jq does not satisfy it.
d="$(tree nojq)"
f="$(ls "$d"/plugins/*/skills/unpark-sprint/SKILL.md)"
sed "s/jq -r '.parked_from_commit/echo '.parked_from_commit/" "$f" >"$f.new" && mv "$f.new" "$f"
assert_fires "a guard with no jq read of the field fires" "$d"

# A tree with no unpark-sprint skill fails, never passes.
d="$(tree nofile)"
rm -rf "$d"/plugins/*/skills/unpark-sprint
assert_fires "a missing unpark-sprint skill fires" "$d"

[ ! -e "$tmp/usage-exit" ] || { echo "FAIL - the checker exited 2 (usage) in at least one case" >&2; fail=1; }

[ "$fail" -eq 0 ]
