#!/bin/sh
# Fixture tests for WOW_TESTS_REQUIRE_TOOLS, the switch that turns a missing-tool skip into a
# failure in tests/identity-review.test.sh, tests/identity-launchers.test.sh and
# tests/review-verdict.test.sh (#985, #986, #930). ci.yml sets it to 1.
#
# Each suite runs under a POSIX shell given by its absolute path, with PATH set to a scratch
# directory that holds only a link to `dirname` (each suite needs it before its tool check), so
# the suite's first tool is hidden. With the variable exactly 1: exit 1 and a stderr line that
# starts `FAIL - ` and names the missing tool. With it unset, and with it 0: exit 0 and today's
# `SKIP - ` line. A child suite's lines are printed only indented, so scripts/test-all.sh does not
# read a child's SKIP line as this suite's own.
#
# Permitted toolset: POSIX sh and its standard utilities.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"

sh_bin=""
for c in /bin/sh /usr/bin/sh; do
  if [ -x "$c" ]; then sh_bin=$c; break; fi
done
dirname_bin="$(command -v dirname || true)"
if [ -z "$sh_bin" ] || [ -z "$dirname_bin" ]; then
  echo "SKIP - sh or dirname not found; require-tools fixtures not run" >&2
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
ln -s "$dirname_bin" "$tmp/bin/dirname"

fail=0
ok() { echo "ok   - $1"; }
bad() { echo "FAIL - $1"; fail=1; }
show() { sed 's/^/    /' "$1"; } # a child's lines, indented

# run_case <var-mode: 1|0|unset> <suite>: sets rc, out, err
run_case() {
  rc=0
  case "$1" in
    unset) (unset WOW_TESTS_REQUIRE_TOOLS; PATH="$tmp/bin" "$sh_bin" "$root_dir/tests/$2" >"$tmp/out" 2>"$tmp/err" </dev/null) || rc=$? ;;
    *) (WOW_TESTS_REQUIRE_TOOLS="$1" PATH="$tmp/bin" "$sh_bin" "$root_dir/tests/$2" >"$tmp/out" 2>"$tmp/err" </dev/null) || rc=$? ;;
  esac
}

# suite:first missing tool
for pair in identity-review.test.sh:jq identity-launchers.test.sh:pwsh review-verdict.test.sh:jq; do
  suite=${pair%%:*}
  tool=${pair#*:}

  run_case 1 "$suite"
  if [ "$rc" -eq 1 ] && grep -q "^FAIL - $tool " "$tmp/err" && ! grep -q '^SKIP - ' "$tmp/err"; then
    ok "$suite: =1 fails naming $tool"
  else
    bad "$suite: =1 should exit 1 with a FAIL line naming $tool (rc $rc)"; show "$tmp/err"
  fi

  for mode in unset 0; do
    run_case "$mode" "$suite"
    if [ "$rc" -eq 0 ] && grep -q "^SKIP - $tool " "$tmp/err" && ! grep -q '^FAIL - ' "$tmp/err"; then
      ok "$suite: $mode skips as before"
    else
      bad "$suite: $mode should exit 0 with a SKIP line naming $tool (rc $rc)"; show "$tmp/err"
    fi
  done
done

exit "$fail"
