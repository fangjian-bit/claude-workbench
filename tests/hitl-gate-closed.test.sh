#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/hitl-gate-closed.sh (#557).
#
# One predicate decides whether a hitl_gate value is closed; resume, unpark-sprint and
# plan-sprint call it instead of each restating the test.
#
# Permitted toolset: POSIX sh.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/plugins/way-of-working/bin/hitl-gate-closed.sh"

fail=0

assert_eq() {
  desc="$1"
  expected="$2"
  actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "ok - $desc"
  else
    echo "FAIL - $desc: expected [$expected], got [$actual]" >&2
    fail=1
  fi
}

check() {
  desc="$1"
  expected="$2"
  value="$3"
  assert_eq "$desc" "$expected" "$("$script" "$value")"
}

check "canonical closed form" closed 'NONE OPEN — next gate: the human merges the #557 PR.'
check "canonical form, one word of prose" closed 'NONE OPEN — next gate: merge'
check "HITL Gate label left in is not the value" open '**HITL Gate: NONE OPEN** — next gate: x'
check "text after HITL Gate: with markers" closed ' NONE OPEN** — next gate: the merge'
check "surrounding blanks trimmed" closed '  NONE OPEN — next gate: merge  '

check "bare NONE OPEN (existing cursors wait)" open 'NONE OPEN'
check "NONE OPEN with a different dash" open 'NONE OPEN - next gate: merge'
check "NONE OPEN, prose not naming the next gate" open "NONE OPEN — milestone 13's anchor re-verified. Next gate: merge"
check "next gate with no prose" open 'NONE OPEN — next gate:'
check "next gate with only blanks" open 'NONE OPEN — next gate:    '
check "no blank after the colon" open 'NONE OPEN — next gate:merge'
check "OPEN" open 'OPEN — first anchor for milestone 17'
check "parked" open 'parked 2026-10-01 at abc123; re-verify next_action'
check "lower case" open 'none open — next gate: merge'
check "prefix not at the start" open 'OPEN — NONE OPEN — next gate: merge'
check "appended parked clause" open 'NONE OPEN — next gate: merge; parked with gate open: OPEN — x'
check "appended prior-cursor clause" open 'NONE OPEN — next gate: merge; prior cursor sprint-3 (done) with gate open: OPEN'
check "semicolon inside the prose" open 'NONE OPEN — next gate: merge; then release'
check "open note after the dash" open 'NONE OPEN — next gate: x — milestone description edited, approve re-anchor'
check "OPEN after a full stop" open 'NONE OPEN — next gate: x. OPEN: approve merge'
check "lower-case open in the prose" open 'NONE OPEN — next gate: reopen the milestone'
check "fullwidth semicolon" open "NONE OPEN — next gate: x$(printf '；') y"
check "Greek question mark" open "NONE OPEN — next gate: x$(printf ';') y"
check "line separator U+2028" open "NONE OPEN — next gate: x$(printf ' ')y"
check "NEL U+0085" open "NONE OPEN — next gate: x$(printf '')y"
check "prose only a no-break space" open "NONE OPEN — next gate: $(printf ' ')"
check "prose only a zero-width space" open "NONE OPEN — next gate: $(printf '​')"
check "empty value" open ''
check "blank value" open '   '
check "newline in the value" open 'NONE OPEN — next gate: merge
OPEN — second gate'
check "trailing newline-only second line" open 'NONE OPEN — next gate: merge

'
check "tab in the value" open "NONE OPEN — next gate: merge	x"
check "control character" open "NONE OPEN — next gate: merge$(printf '\033')"
check "value starting with a dash" open '-n'

if "$script" >/dev/null 2>&1; then
  assert_eq "no argument exits non-zero" nonzero zero
else
  assert_eq "no argument exits non-zero" nonzero nonzero
fi
if "$script" a b >/dev/null 2>&1; then
  assert_eq "two arguments exit non-zero" nonzero zero
else
  assert_eq "two arguments exit non-zero" nonzero nonzero
fi

[ "$fail" -eq 0 ] || exit 1
echo "All hitl-gate-closed fixtures passed."
