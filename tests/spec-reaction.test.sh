#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/spec-reaction.sh (#613).
#
# The predicate is pure -- no gh, no files -- so the fixtures are plain reaction rows on stdin.
#
# Permitted toolset: POSIX sh. No jq, no yq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/plugins/way-of-working/bin/spec-reaction.sh"

fail=0
tab="$(printf '\t')"
U="2026-10-14T16:56:36Z"
AFTER="2026-10-14T17:00:00Z"

check() { # <desc> <expected-word> <rows> <updated> <ids>
  out="$(printf '%s' "$3" | "$script" "$4" "$5" 2>/dev/null)" || out="exit$?"
  if [ "$out" = "$2" ]; then
    echo "ok - $1"
  else
    echo "FAIL - $1: expected [$2], got [$out]" >&2
    fail=1
  fi
}

row() { printf '%s\t%s\t%s\n' "$1" "$2" "$3"; }

for c in '+1' heart hooray rocket; do
  check "a maintainer's $c after the edit approves" approved "$(row 22668449 "$c" "$AFTER")" "$U" 22668449
done
check "a reaction in the same second as the edit does not approve" unreacted "$(row 22668449 '+1' "$U")" "$U" 22668449
check "a reaction before the edit does not approve" unreacted "$(row 22668449 '+1' "2026-10-14T16:00:00Z")" "$U" 22668449
check "a non-maintainer's reaction does not approve" unreacted "$(row 99 '+1' "$AFTER")" "$U" 22668449
check "a user id that only contains a listed id does not approve" unreacted "$(row 226684490 '+1' "$AFTER")" "$U" 22668449
for c in eyes -1 confused laugh; do
  check "a maintainer's $c does not approve" unreacted "$(row 22668449 "$c" "$AFTER")" "$U" 22668449
done
check "an empty file is unreacted" unreacted "" "$U" 22668449
check "a malformed row next to a valid one is skipped" approved \
  "$(printf 'garbage\n%s\n' "$(row 22668449 heart "$AFTER")")" "$U" 22668449
check "a malformed timestamp row is skipped, not approved" unreacted \
  "$(row 22668449 heart "tomorrow")" "$U" 22668449
check "a short row is skipped" unreacted "$(printf '22668449\theart\n')" "$U" 22668449
check "any id on a list approves" approved "$(row 7 rocket "$AFTER")" "$U" "5,7,22668449"

# Bad arguments exit 2 with nothing on stdout.
bad() { # <desc> <args...>
  d="$1"; shift
  out="$(printf '' | "$script" "$@" 2>/dev/null)" && rc=0 || rc=$?
  if [ "$rc" -eq 2 ] && [ -z "$out" ]; then
    echo "ok - $d"
  else
    echo "FAIL - $d: expected exit 2 and no output, got rc=$rc out=[$out]" >&2
    fail=1
  fi
}
bad "no arguments"
bad "one argument" "$U"
bad "three arguments" "$U" 1 2
bad "empty id list" "$U" ""
bad "a non-digit id" "$U" "abc"
bad "a leading comma" "$U" ",1"
bad "a trailing comma" "$U" "1,"
bad "a doubled comma" "$U" "1,,2"
bad "a space in the list" "$U" "1, 2"
bad "a malformed updated_at" "2026-10-14" 1
bad "an empty updated_at" "" 1

[ "$fail" -eq 0 ]
