#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/stall-merge.sh (#432).
#
# Permitted toolset: POSIX sh. No jq, no yq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/plugins/way-of-working/bin/stall-merge.sh"

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

H1=1111111111111111111111111111111111111111
H2=2222222222222222222222222222222222222222

# run <mode> <armed> <approvals> <decision> <state> <head> <approved> <age>
run() { sh "$script" "$@"; }

# armed + approved + clean + on the approved head + old enough: merge (dev App) / stalled (human)
assert_eq "armed+approved+clean, app mode merges" "merge" "$(run app true 1 APPROVED CLEAN $H1 $H1 300)"
assert_eq "armed+approved+clean, user mode only reports" "stalled" "$(run user true 1 APPROVED CLEAN $H1 $H1 300)"
assert_eq "exactly 180 seconds merges" "merge" "$(run app true 1 APPROVED CLEAN $H1 $H1 180)"
assert_eq "two required approvals merge" "merge" "$(run app true 2 APPROVED CLEAN $H1 $H1 600)"
assert_eq "a very large age merges" "merge" "$(run app true 1 APPROVED CLEAN $H1 $H1 99999999999999999999)"

# head moved since the approval: never merge
assert_eq "approved head differs from the PR head" "no-merge head-moved" "$(run app true 1 APPROVED CLEAN $H2 $H1 300)"

# blocked or otherwise not clean: never merge
for s in BLOCKED BEHIND UNKNOWN HAS_HOOKS UNSTABLE DRAFT DIRTY; do
  assert_eq "approved but $s does not merge" "no-merge not-clean" "$(run app true 1 APPROVED "$s" $H1 $H1 300)"
done

# not armed: nothing was waiting to fire
assert_eq "not armed" "no-merge not-armed" "$(run app false 1 APPROVED CLEAN $H1 $H1 300)"

# no code-owner approval required on the base: an APPROVED decision proves nothing
for a in 0 00 000; do
  assert_eq "approvals required=$a" "no-merge no-approval" "$(run app true "$a" APPROVED CLEAN $H1 $H1 300)"
done

# not approved
for d in REVIEW_REQUIRED CHANGES_REQUESTED NONE; do
  assert_eq "decision $d" "no-merge not-approved" "$(run app true 1 "$d" CLEAN $H1 $H1 300)"
done

# too soon: auto-merge normally fires within seconds
assert_eq "179 seconds is too soon" "no-merge too-soon" "$(run app true 1 APPROVED CLEAN $H1 $H1 179)"
assert_eq "0 seconds is too soon" "no-merge too-soon" "$(run app true 1 APPROVED CLEAN $H1 $H1 0)"

# order: armed, then approval rule, then decision, then state, then head, then age
assert_eq "not armed beats everything" "no-merge not-armed" "$(run app false 0 NONE BLOCKED $H2 $H1 0)"
assert_eq "no-approval beats the decision" "no-merge no-approval" "$(run app true 0 NONE BLOCKED $H2 $H1 0)"
assert_eq "not-approved beats the state" "no-merge not-approved" "$(run app true 1 REVIEW_REQUIRED BLOCKED $H2 $H1 0)"
assert_eq "not-clean beats head-moved" "no-merge not-clean" "$(run app true 1 APPROVED BLOCKED $H2 $H1 0)"
assert_eq "head-moved beats too-soon" "no-merge head-moved" "$(run app true 1 APPROVED CLEAN $H2 $H1 0)"

# unreadable: wrong argument count, or a value outside the vocabulary. Never merge.
assert_eq "no arguments" "unreadable" "$(run)"
assert_eq "seven arguments" "unreadable" "$(run app true 1 APPROVED CLEAN $H1 $H1)"
assert_eq "nine arguments" "unreadable" "$(run app true 1 APPROVED CLEAN $H1 $H1 300 x)"
assert_eq "unknown mode" "unreadable" "$(run admin true 1 APPROVED CLEAN $H1 $H1 300)"
assert_eq "empty mode" "unreadable" "$(run '' true 1 APPROVED CLEAN $H1 $H1 300)"
assert_eq "armed not a boolean" "unreadable" "$(run app yes 1 APPROVED CLEAN $H1 $H1 300)"
assert_eq "armed uppercase" "unreadable" "$(run app TRUE 1 APPROVED CLEAN $H1 $H1 300)"
assert_eq "approvals empty" "unreadable" "$(run app true '' APPROVED CLEAN $H1 $H1 300)"
assert_eq "approvals negative" "unreadable" "$(run app true -1 APPROVED CLEAN $H1 $H1 300)"
assert_eq "approvals not a number" "unreadable" "$(run app true one APPROVED CLEAN $H1 $H1 300)"
assert_eq "decision empty" "unreadable" "$(run app true 1 '' CLEAN $H1 $H1 300)"
assert_eq "decision lowercase" "unreadable" "$(run app true 1 approved CLEAN $H1 $H1 300)"
assert_eq "state lowercase" "unreadable" "$(run app true 1 APPROVED clean $H1 $H1 300)"
assert_eq "state unknown word" "unreadable" "$(run app true 1 APPROVED MERGED $H1 $H1 300)"
assert_eq "state with a trailing space" "unreadable" "$(run app true 1 APPROVED 'CLEAN ' $H1 $H1 300)"
assert_eq "head too short" "unreadable" "$(run app true 1 APPROVED CLEAN abc123 $H1 300)"
assert_eq "approved oid too long" "unreadable" "$(run app true 1 APPROVED CLEAN $H1 ${H1}1 300)"
assert_eq "head uppercase hex" "unreadable" "$(run app true 1 APPROVED CLEAN AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA $H1 300)"
assert_eq "approved oid empty" "unreadable" "$(run app true 1 APPROVED CLEAN $H1 '' 300)"
assert_eq "age empty" "unreadable" "$(run app true 1 APPROVED CLEAN $H1 $H1 '')"
assert_eq "age negative" "unreadable" "$(run app true 1 APPROVED CLEAN $H1 $H1 -5)"
assert_eq "age fractional" "unreadable" "$(run app true 1 APPROVED CLEAN $H1 $H1 3.5)"
assert_eq "unreadable beats a not-armed PR" "unreadable" "$(run app false 1 APPROVED CLEAN $H1 $H1 abc)"

exit "$fail"
