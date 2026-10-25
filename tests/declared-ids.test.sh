#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/declared-ids.sh: the one read of a project.yml's `identities`
# map that spec-find.sh, spec-comment.sh, spec-answer.sh, spec-issue.sh and spec-post.sh share (#1079).
#
# Each case writes a project.yml and asserts both the helper's stdout and its exit code.
# It also holds the five caller suites' `for stub in` lines byte-identical (#1106).
# Needs yq (mikefarah v4); skips, loudly, without it.
# Permitted toolset: POSIX sh, plus yq.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/plugins/way-of-working/bin/declared-ids.sh"

if ! command -v yq >/dev/null 2>&1; then
  echo "SKIP - yq not on PATH; declared-ids.test.sh needs it" >&2
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
assert_eq() { # <desc> <want> <got>
  if [ "$2" = "$3" ]; then
    echo "ok - $1"
  else
    echo "FAIL - $1: expected [$2], got [$3]" >&2
    fail=1
  fi
}

n=0
# case_ <desc> <want-stdout> <identities-yaml, indented under `identities:`>
case_() {
  n=$((n + 1))
  printf 'repo: acme/app\npr_base: main\nidentities:\n%s\n' "$3" >"$tmp/p$n.yml"
  rc=0
  out="$(sh "$script" "$tmp/p$n.yml" 2>/dev/null)" || rc=$?
  assert_eq "$1 (stdout)" "$2" "$out"
  assert_eq "$1 (exit)" 0 "$rc"
}

M1='  maintainer:
    - { login: maint1, id: 101 }'
M2='  maintainer:
    - { login: maint1, id: 101 }
    - { login: maint2, id: 102 }'
DEV='  dev_app: { login: "dev-app[bot]", id: 201 }'
REV='  reviewer_app: { login: "rev-app[bot]", id: 202 }'
LOOP='  loop_app: { login: "loop-app[bot]", id: 203 }'

# --- ok -----------------------------------------------------------------------------------
case_ "ok: a full map" "ok 101 201" "$M1
$DEV
$REV
$LOOP"
case_ "ok: dev_app null" "ok 101 -" "$M1
  dev_app: null
$REV"
case_ "ok: dev_app missing" "ok 101 -" "$M1"
case_ "ok: two maintainers, in list order" "ok 101,102 201" "$M2
$DEV"
case_ "ok: only a reviewer App" "ok 101 -" "$M1
$REV"
case_ "ok: aliases are expanded" "ok 101,101 201" "  maintainer:
    - &m { login: maint1, id: 101 }
    - *m
$DEV"

# --- unreadable ---------------------------------------------------------------------------
n=$((n + 1))
printf 'repo: acme/app\nidentities: null\n' >"$tmp/p$n.yml"
rc=0; out="$(sh "$script" "$tmp/p$n.yml" 2>/dev/null)" || rc=$?
assert_eq "unreadable: identities null (stdout)" unreadable "$out"
assert_eq "unreadable: identities null (exit)" 0 "$rc"
n=$((n + 1))
printf 'repo: acme/app\n' >"$tmp/p$n.yml"
rc=0; out="$(sh "$script" "$tmp/p$n.yml" 2>/dev/null)" || rc=$?
assert_eq "unreadable: identities missing (stdout)" unreadable "$out"
assert_eq "unreadable: identities missing (exit)" 0 "$rc"
n=$((n + 1))
printf 'repo: acme/app\nidentities:\n  - maintainer\n' >"$tmp/p$n.yml"
rc=0; out="$(sh "$script" "$tmp/p$n.yml" 2>/dev/null)" || rc=$?
assert_eq "unreadable: identities a sequence (stdout)" unreadable "$out"
assert_eq "unreadable: identities a sequence (exit)" 0 "$rc"

case_ "unreadable: maintainer missing" unreadable "$DEV"
case_ "unreadable: maintainer empty" unreadable "  maintainer: []
$DEV"
case_ "unreadable: maintainer a map" unreadable "  maintainer: { login: maint1, id: 101 }"
case_ "unreadable: a maintainer entry that is a string" unreadable "  maintainer:
    - maint1"
case_ "unreadable: a maintainer id of 0" unreadable "  maintainer:
    - { login: maint1, id: 0 }"
case_ "unreadable: a maintainer id that is a string" unreadable "  maintainer:
    - { login: maint1, id: \"101\" }"
case_ "unreadable: a maintainer with no login" unreadable "  maintainer:
    - { id: 101 }"
case_ "unreadable: one good and one bad maintainer entry" unreadable "  maintainer:
    - { login: maint1, id: 101 }
    - { login: maint2, id: 0 }"
case_ "unreadable: a maintainer id written 0x3E9" unreadable "  maintainer:
    - { login: maint1, id: 0x3E9 }"
case_ "unreadable: a maintainer id written 1_001" unreadable "  maintainer:
    - { login: maint1, id: 1_001 }"
case_ "unreadable: a maintainer id written 10_001" unreadable "  maintainer:
    - { login: maint1, id: 10_001 }"
case_ "unreadable: a maintainer id written 01001" unreadable "  maintainer:
    - { login: maint1, id: 01001 }"
case_ "unreadable: a maintainer id written +101" unreadable "  maintainer:
    - { login: maint1, id: +101 }"
case_ "unreadable: a maintainer id written 0o1751" unreadable "  maintainer:
    - { login: maint1, id: 0o1751 }"
case_ "unreadable: a good maintainer id then one written 0x3E9" unreadable "  maintainer:
    - { login: maint1, id: 101 }
    - { login: maint2, id: 0x3E9 }"
case_ "unreadable: the dev App on the maintainer list" unreadable "$M1
  dev_app: { login: \"dev-app[bot]\", id: 101 }"
case_ "unreadable: the reviewer App on the maintainer list" unreadable "$M1
  reviewer_app: { login: \"rev-app[bot]\", id: 101 }"
case_ "unreadable: the loop App on the maintainer list" unreadable "$M1
  loop_app: { login: \"loop-app[bot]\", id: 101 }"
case_ "unreadable: a dev App entry that is a string" unreadable "$M1
  dev_app: dev"
case_ "unreadable: a reviewer App entry that is a string" unreadable "$M1
  reviewer_app: rev"
case_ "unreadable: a loop App with no login" unreadable "$M1
  loop_app: { id: 203 }"
case_ "unreadable: a dev App id of +2001" unreadable "$M1
  dev_app: { login: \"dev-app[bot]\", id: +2001 }"
case_ "unreadable: a reviewer App id of 0x7D1" unreadable "$M1
  reviewer_app: { login: \"rev-app[bot]\", id: 0x7D1 }"
case_ "unreadable: a loop App id of 02001" unreadable "$M1
  loop_app: { login: \"loop-app[bot]\", id: 02001 }"

# --- exit 2 -------------------------------------------------------------------------------
rc=0; out="$(sh "$script" 2>/dev/null)" || rc=$?
assert_eq "exit 2: no argument (stdout)" "" "$out"
assert_eq "exit 2: no argument (exit)" 2 "$rc"
rc=0; out="$(sh "$script" "$tmp/p1.yml" "$tmp/p2.yml" 2>/dev/null)" || rc=$?
assert_eq "exit 2: two arguments (stdout)" "" "$out"
assert_eq "exit 2: two arguments (exit)" 2 "$rc"
rc=0; out="$(sh "$script" "$tmp/no-such.yml" 2>/dev/null)" || rc=$?
assert_eq "exit 2: a missing file (stdout)" "" "$out"
assert_eq "exit 2: a missing file (exit)" 2 "$rc"
printf 'a: [unclosed\n  - : :\n' >"$tmp/bad.yml"
rc=0; out="$(sh "$script" "$tmp/bad.yml" 2>/dev/null)" || rc=$?
assert_eq "exit 2: a non-YAML file (stdout)" "" "$out"
assert_eq "exit 2: a non-YAML file (exit)" 2 "$rc"

# --- the five caller suites feed the same malformed-line stubs (#1106) ----------------------
stub_line() { # <suite file>: prints the one `for stub in ` line, or "none" / "many"
  sl_n=0 sl_line=
  while IFS= read -r l; do
    case "$l" in 'for stub in '*) sl_n=$((sl_n + 1)); sl_line="$l" ;; esac
  done <"$1"
  case "$sl_n" in 0) echo none ;; 1) printf '%s\n' "$sl_line" ;; *) echo many ;; esac
}
ref="$(stub_line "$root_dir/tests/spec-find.test.sh")"
for suite in spec-find spec-answer spec-comment spec-issue spec-post; do
  got="$(stub_line "$root_dir/tests/$suite.test.sh")"
  case "$got" in
    none | many) assert_eq "stubs: $suite.test.sh has exactly one for-stub line" one "$got" ;;
    *) assert_eq "stubs: $suite.test.sh matches spec-find.test.sh" "$ref" "$got" ;;
  esac
done

[ "$fail" -eq 0 ]
