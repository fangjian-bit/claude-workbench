#!/bin/sh
# Fixture tests for scripts/cursor-only-paths.sh, the predicate ci.yml's `changed-paths` job uses to
# skip the test jobs for a cursor-sync-only PR (#989). `true` for the ledger, a file under
# .ai/parked/, or both; `false` for empty input, any other path alone or mixed in, a near-miss of
# either name, a double-quoted path, and a mixed list with no final newline.
#
# Permitted toolset: POSIX sh and its standard utilities.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/scripts/cursor-only-paths.sh"

fail=0
ok() { echo "ok   - $1"; }
bad() { echo "FAIL - $1"; fail=1; }
# check <want> <label> <printf format> [args]: the input is printf's output
check() {
  want=$1; label=$2; shift 2
  got="$(printf "$@" | sh "$script")"
  if [ "$got" = "$want" ]; then ok "$label"; else bad "$label (want $want, got '$got')"; fi
}

check true "only the ledger" '.ai/next-steps.md\n'
check true "only a parked file" '.ai/parked/sprint-1/state.json\n'
check true "both together" '.ai/next-steps.md\n.ai/parked/a.md\n'
check true "ledger with no final newline" '.ai/next-steps.md'
check false "empty input" ''
check false "state.json" '.ai/state.json\n'
check false "ledger with another path" '.ai/next-steps.md\nscripts/lint.sh\n'
check false "ledger backup name" '.ai/next-steps.md.bak\n'
check false ".ai/parked with no slash" '.ai/parked\n'
check false ".ai/parked/ alone" '.ai/parked/\n'
check false "nested ledger name" 'x/.ai/next-steps.md\n'
check false "double-quoted path" '".ai/parked/caf\\303\\251.md"\n'
check false "mixed, no final newline" '.ai/next-steps.md\nscripts/lint.sh'
check false "blank line" '.ai/next-steps.md\n\n'

exit "$fail"
