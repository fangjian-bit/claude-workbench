#!/bin/sh
# Fixture tests for scripts/invariants-check.sh's check 14: resume, unpark-sprint and
# plan-sprint call bin/hitl-gate-closed.sh instead of restating the closed-gate test (#557).
#
# Each case mutates a COPY of the real tree and asserts the check fires (or stays silent).
# Only check 14's own message is asserted, never the script's overall exit.
#
# Every case but the first control runs just check 14 (`--only 14`); that control runs the full checker.
#
# Permitted toolset: POSIX sh. No jq, no yq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/scripts/invariants-check.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
MSG="a hitl_gate reader no longer calls the shared closed-gate predicate"

tree() {
  d="$tmp/$1"
  mkdir -p "$d"
  cp -R "$root_dir/plugins" "$d/plugins"
  echo "$d"
}

sel="--only 14"

run() { ( cd "$1" && bash "$script" $sel 2>&1 >/dev/null ) || true; }

assert_fires() { # <desc> <dir>
  if run "$2" | grep -qF -- "$MSG"; then
    echo "ok - $1"
  else
    echo "FAIL - $1: expected check 14 to fire" >&2
    fail=1
  fi
}

assert_silent() { # <desc> <dir>
  if run "$2" | grep -qF -- "$MSG"; then
    echo "FAIL - $1: check 14 fired" >&2
    fail=1
  else
    echo "ok - $1"
  fi
}

sel=
d="$(tree control)"
assert_silent "real tree passes" "$d"
sel="--only 14"

for s in resume unpark-sprint plan-sprint; do
  d="$(tree "no-$s")"
  f="$(ls "$d"/plugins/*/skills/"$s"/SKILL.md)"
  sed 's/hitl-gate-closed\.sh/the-predicate/g' "$f" >"$f.new" && mv "$f.new" "$f"
  assert_fires "$s without a call to the predicate fires" "$d"
done

for s in resume unpark-sprint plan-sprint; do
  d="$(tree "calldel-$s")"
  f="$(ls "$d"/plugins/*/skills/"$s"/SKILL.md)"
  sed -e 's/hitl-gate-closed\.sh "\$GATE"/the-predicate/g' -e 's/hitl-gate-closed\.sh "\$G1"/the-predicate/g' "$f" >"$f.new" && mv "$f.new" "$f"
  assert_fires "$s with only its call line removed (mentions kept) fires" "$d"
done

d="$(tree restated)"
f="$(ls "$d"/plugins/*/skills/resume/SKILL.md)"
printf '\nThe gate is closed when it reads NONE OPEN with nothing open after it.\n' >>"$f"
assert_fires "a prose restatement of the test fires" "$d"

d="$(tree nofile)"
rm -rf "$d"/plugins/*/skills/plan-sprint
assert_fires "a missing reader skill fires" "$d"

d="$(tree noscript)"
rm -f "$d"/plugins/*/bin/hitl-gate-closed.sh
assert_fires "a missing predicate script fires" "$d"

[ "$fail" -eq 0 ]
