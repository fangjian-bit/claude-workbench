#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/auto-merge-arm.sh (#386).
#
# Permitted toolset: POSIX sh. No jq, no yq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/plugins/way-of-working/bin/auto-merge-arm.sh"

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

# arms: an approval is required and the PR is waiting on something
for s in BLOCKED BEHIND UNKNOWN; do
  assert_eq "allowed + 1 approval + $s arms" "arm" "$(sh "$script" true 1 "$s")"
done
assert_eq "allowed + 2 approvals + BLOCKED arms" "arm" "$(sh "$script" true 2 BLOCKED)"
assert_eq "allowed + 10 approvals + BLOCKED arms" "arm" "$(sh "$script" true 10 BLOCKED)"

# no approval required: arming would be an agent-run merge on green checks
for a in 0 00 000; do
  assert_eq "allowed + approvals=$a + BLOCKED is not armed (no-approval)" "not-armed no-approval" "$(sh "$script" true "$a" BLOCKED)"
done
assert_eq "no approval wins over a mergeable state" "not-armed no-approval" "$(sh "$script" true 0 CLEAN)"

# already mergeable: arming would merge now; ship never merges
for s in CLEAN HAS_HOOKS UNSTABLE; do
  assert_eq "allowed + approval + $s is not armed (mergeable)" "not-armed mergeable" "$(sh "$script" true 1 "$s")"
done

assert_eq "allowed + approval + DRAFT is not armed" "not-armed draft" "$(sh "$script" true 1 DRAFT)"
assert_eq "allowed + approval + DIRTY is not armed" "not-armed conflicts" "$(sh "$script" true 1 DIRTY)"

# disallowed wins over everything, including unreadable approvals and states
for a in 0 1 bogus ""; do
  for s in BLOCKED CLEAN DRAFT bogus ""; do
    assert_eq "disallowed + [$a] + [$s] is not armed (disallowed)" "not-armed disallowed" "$(sh "$script" false "$a" "$s")"
  done
done

# unreadable: never arm on a value nobody has read
assert_eq "unknown state is unreadable" "unreadable" "$(sh "$script" true 1 MERGED)"
assert_eq "lowercase state is unreadable" "unreadable" "$(sh "$script" true 1 blocked)"
assert_eq "padded state is unreadable" "unreadable" "$(sh "$script" true 1 "BLOCKED ")"
assert_eq "empty state is unreadable" "unreadable" "$(sh "$script" true 1 "")"
assert_eq "allow=null is unreadable" "unreadable" "$(sh "$script" null 1 BLOCKED)"
assert_eq "allow=TRUE is unreadable" "unreadable" "$(sh "$script" TRUE 1 BLOCKED)"
assert_eq "empty allow is unreadable" "unreadable" "$(sh "$script" "" 1 BLOCKED)"
assert_eq "empty approvals is unreadable" "unreadable" "$(sh "$script" true "" BLOCKED)"
assert_eq "null approvals is unreadable" "unreadable" "$(sh "$script" true null BLOCKED)"
assert_eq "negative approvals is unreadable" "unreadable" "$(sh "$script" true -1 BLOCKED)"
assert_eq "fractional approvals is unreadable" "unreadable" "$(sh "$script" true 1.5 BLOCKED)"
assert_eq "padded approvals is unreadable" "unreadable" "$(sh "$script" true "1 " BLOCKED)"
assert_eq "no arguments is unreadable" "unreadable" "$(sh "$script")"
assert_eq "two arguments is unreadable" "unreadable" "$(sh "$script" true BLOCKED)"
assert_eq "four arguments is unreadable" "unreadable" "$(sh "$script" true 1 BLOCKED extra)"

# exit status is always 0
if sh "$script" true 1 bogus >/dev/null; then
  assert_eq "unreadable exits 0" 0 0
else
  assert_eq "unreadable exits 0" 0 1
fi

exit "$fail"
