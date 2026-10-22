#!/bin/sh
# Fixture tests for scripts/invariants-check.sh's check 23: park-sprint and unpark-sprint write
# `"lanes": null`, never the derived lanes array (#797).
#
# Each case mutates a COPY of the real tree and asserts the check fires (or stays silent), so
# a check that only passes on the real tree cannot hide. Only check 23's own message is
# asserted, never the script's overall exit.
#
# Every case but the first control runs just check 23 (`--only 23`); that control runs the full checker.
#
# Permitted toolset: POSIX sh. No jq, no yq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/scripts/invariants-check.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# One read of the checkout per run: every fixture copies from this, never from the root.
pristine="$tmp/.pristine"
mkdir -p "$pristine"
cp -R "$root_dir/plugins" "$pristine/plugins"

fail=0
MSG='no longer writes "lanes": null'

tree() {
  d="$tmp/$1"
  mkdir -p "$d"
  cp -R "$pristine/plugins" "$d/plugins"
  echo "$d"
}

sel="--only 23"

run() { ( cd "$1" || exit 1; rc=0; bash "$script" $sel 2>&1 >/dev/null || rc=$?; [ "$rc" -ne 2 ] || : >"$tmp/usage-exit" ) || true; }

assert_fires() { # <desc> <dir>
  if run "$2" | grep -qF -- "$MSG"; then
    echo "ok - $1"
  else
    echo "FAIL - $1: expected check 23 to fire" >&2
    fail=1
  fi
}

assert_silent() { # <desc> <dir>
  if run "$2" | grep -qF -- "$MSG"; then
    echo "FAIL - $1: check 23 fired" >&2
    fail=1
  else
    echo "ok - $1"
  fi
}

# Drop the literal from a skill file (every line that holds it).
strip() { # <file>
  grep -vF '"lanes": null' "$1" >"$1.new" && mv "$1.new" "$1"
}

# Control: the real tree is clean, under the full checker.
sel=
d="$(tree control)"
assert_silent "real tree passes" "$d"
sel="--only 23"

# park-sprint without the literal fires.
d="$(tree nopark)"
strip "$(ls "$d"/plugins/*/skills/park-sprint/SKILL.md)"
assert_fires "park-sprint without the literal fires" "$d"

# unpark-sprint without the literal fires.
d="$(tree nounpark)"
strip "$(ls "$d"/plugins/*/skills/unpark-sprint/SKILL.md)"
assert_fires "unpark-sprint without the literal fires" "$d"

# A tree with no park-sprint skill fails, never passes.
d="$(tree nofilepark)"
rm -rf "$d"/plugins/*/skills/park-sprint
assert_fires "a missing park-sprint skill fires" "$d"

# A tree with no unpark-sprint skill fails, never passes.
d="$(tree nofileunpark)"
rm -rf "$d"/plugins/*/skills/unpark-sprint
assert_fires "a missing unpark-sprint skill fires" "$d"

# The literal in some other skill does not stand in for park and unpark.
d="$(tree elsewhere)"
strip "$(ls "$d"/plugins/*/skills/park-sprint/SKILL.md)"
strip "$(ls "$d"/plugins/*/skills/unpark-sprint/SKILL.md)"
other="$(ls "$d"/plugins/*/skills/handoff/SKILL.md)"
printf '%s\n' '"lanes": null' >>"$other"
assert_fires "the literal only in another skill fires" "$d"

[ ! -e "$tmp/usage-exit" ] || { echo "FAIL - the checker exited 2 (usage) in at least one case" >&2; fail=1; }

[ "$fail" -eq 0 ]
