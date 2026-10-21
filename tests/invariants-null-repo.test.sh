#!/bin/sh
# Fixture tests for scripts/invariants-check.sh's check 12: a skill or agent that names
# {backlog.repo} says, on a line that names it, that `null` means `{repo}` (#479).
#
# The first draft of the check searched the whole file for "null" near "{repo}", so
# `>/dev/null` next to a `{repo}` argument satisfied it, and deleting the real note from
# two skills left it green. Each case here mutates a COPY of the real tree and asserts the
# check fires (or stays silent), so a check that only passes on the real tree cannot hide.
#
# Only check 12's own message is asserted, never the script's overall exit.
#
# Every case but the first control runs just check 12 (`--only 12`); that control runs the full checker.
#
# Permitted toolset: POSIX sh. No jq, no yq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/scripts/invariants-check.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
MSG="names {backlog.repo} without saying null means {repo}"

tree() {
  d="$tmp/$1"
  mkdir -p "$d"
  cp -R "$root_dir/plugins" "$d/plugins"
  echo "$d"
}

sel="--only 12"

run() { ( cd "$1" || exit 1; rc=0; bash "$script" $sel 2>&1 >/dev/null || rc=$?; [ "$rc" -ne 2 ] || : >"$tmp/usage-exit" ) || true; }

assert_fires() { # <desc> <dir> [<file-substring>]
  out="$(run "$2")"
  if printf '%s\n' "$out" | grep -qF -- "$MSG" && { [ -z "${3:-}" ] || printf '%s\n' "$out" | grep -qF -- "$3"; }; then
    echo "ok - $1"
  else
    echo "FAIL - $1: expected check 12 to fire" >&2
    fail=1
  fi
}

assert_silent() { # <desc> <dir>
  if run "$2" | grep -qF -- "$MSG"; then
    echo "FAIL - $1: check 12 fired" >&2
    fail=1
  else
    echo "ok - $1"
  fi
}

# Control: the real tree is clean.
sel=
d="$(tree control)"
assert_silent "real tree passes" "$d"
sel="--only 12"

# A skill whose only note is removed fires.
d="$(tree skill)"
f="$(ls "$d"/plugins/*/skills/park-sprint/SKILL.md)"
sed 's/ (`null` means `{repo}`)//' "$f" >"$f.new" && mv "$f.new" "$f"
assert_fires "park-sprint without its note fires" "$d" "park-sprint"

# An unrelated null/{repo} pair elsewhere in the file does not satisfy it.
d="$(tree devnull)"
f="$(ls "$d"/plugins/*/skills/park-sprint/SKILL.md)"
sed 's/ (`null` means `{repo}`)//' "$f" >"$f.new" && mv "$f.new" "$f"
printf '\nrun `tool.sh discard {repo} {backlog.repo} >/dev/null`\n' >>"$f"
assert_fires "/dev/null beside {repo} does not satisfy it" "$d" "park-sprint"

# An agent is covered too.
d="$(tree agent)"
f="$(ls "$d"/plugins/*/agents/coder.md)"
sed 's/ (a `null` `{backlog.repo}` means `{repo}`:[^)]*)//' "$f" >"$f.new" && mv "$f.new" "$f"
assert_fires "coder agent without its note fires" "$d" "coder.md"

[ ! -e "$tmp/usage-exit" ] || { echo "FAIL - the checker exited 2 (usage) in at least one case" >&2; fail=1; }

[ "$fail" -eq 0 ]
