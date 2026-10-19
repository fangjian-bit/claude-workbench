#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/spec-find.sh: the finder that picks a task
# issue's one approved spec comment (#662, part 1).
#
# Two parts, because the stub `gh` cannot run `--jq`.
#
#   1. Projection fixtures. The listing's --jq program is pulled out of the script, from its one
#      listing line, and run with `jq -r` over a JSON array of comment fixtures. A failed pull is
#      a test failure, never a skip. These prove jq's behaviour ONLY. That `gh`'s own gojq agrees
#      rests on the manual run recorded in the issue's spec, so ANY LATER EDIT TO THE PROGRAM
#      MUST BE RE-RUN UNDER `gh` (for example `gh api --jq` over a posted comment) and checked
#      against the same cases.
#   2. Script fixtures. Each case copies spec-find.sh into its own fixture bin/ directory and
#      runs it by path, beside the real spec-reaction.sh and either the real gh-identity.sh or a
#      logging stub. A stub `gh`, first on PATH and keyed on the shape of the call, serves a
#      canned listing TSV, canned reactions and a second-read value, and logs its argv.
#
# No case's stdout or stderr may contain the sentinel the stub plants on its failure paths.
# Needs yq (mikefarah v4) and jq; skips, loudly, without either.
# Permitted toolset: POSIX sh, plus jq, yq, awk, sed, cut and grep as the cases need.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
bindir="$root_dir/plugins/way-of-working/bin"
script="$bindir/spec-find.sh"

for tool in yq jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "SKIP - $tool not on PATH; spec-find.test.sh needs it" >&2
    exit 0
  fi
done

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

SENTINEL="SENTINEL-4b1f9e07"
SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

# --- part 1: the projection ---------------------------------------------------------------
listing_line="$(grep -E 'issues/\$issue/comments' "$script" | grep -v '^[[:space:]]*#' || true)"
if [ "$(printf '%s\n' "$listing_line" | grep -c .)" -ne 1 ]; then
  echo "FAIL - the script does not have exactly one listing line" >&2
  exit 1
fi
prog="$(printf '%s\n' "$listing_line" | sed -n "s/^.*--jq '\\(.*\\)' >\"\$tmp\\/list.tsv\".*\$/\\1/p")"
if [ -z "$prog" ]; then
  echo "FAIL - could not pull the --jq program from the listing line" >&2
  exit 1
fi

proj() { # <body-or-@null> -> the projected rows for one comment, tab-separated
  if [ "$1" = "@null" ]; then
    jq -n '[{id: 11, updated_at: "2026-09-21T09:00:00Z", issue_url: "u", user: {login: "l", id: 5}, body: null}]' >"$tmp/proj.json"
  elif [ "$1" = "@missing" ]; then
    jq -n '[{id: 11, updated_at: "2026-09-21T09:00:00Z", issue_url: "u", user: {login: "l", id: 5}}]' >"$tmp/proj.json"
  else
    jq -n --arg b "$1" '[{id: 11, updated_at: "2026-09-21T09:00:00Z", issue_url: "u", user: {login: "l", id: 5}, body: $b}]' >"$tmp/proj.json"
  fi
  jq -r "$prog" "$tmp/proj.json"
}

M="spec-task: issue=7 base=main sha=$SHA"
want_row="$(printf '11\t2026-09-21T09:00:00Z\tu\tl\t5\t7\tmain')"

assert_eq "projection: a marker first line matches" "$want_row" "$(proj "$M
the rest of the spec")"
assert_eq "projection: a marker alone matches" "$want_row" "$(proj "$M")"
assert_eq "projection: a first line ending in CR matches" "$want_row" "$(proj "$M$(printf '\r')
the rest")"
assert_eq "projection: a CR-only body does not match" "" "$(proj "$M$(printf '\r')the rest")"
assert_eq "projection: trailing text does not match" "" "$(proj "$M extra")"
assert_eq "projection: a marker on the second line does not match" "" "$(proj "intro
$M")"
assert_eq "projection: a 39-character sha does not match" "" "$(proj "spec-task: issue=7 base=main sha=$(printf '%s' "$SHA" | cut -c2-)")"
assert_eq "projection: an upper-case sha does not match" "" "$(proj "spec-task: issue=7 base=main sha=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")"
assert_eq "projection: an empty body produces no row" "" "$(proj "")"
assert_eq "projection: a null body produces no row" "" "$(proj "@null")"
assert_eq "projection: a missing body produces no row" "" "$(proj "@missing")"
case "$(proj "$M
$SENTINEL")" in
  *"$SENTINEL"*) echo "FAIL - projection: a sentinel in the second line reached the output" >&2; fail=1 ;;
  *) echo "ok - projection: a sentinel in the second line never appears in the output" ;;
esac
row="$(proj "spec-task: issue=7 base=feat/x-y.z sha=$SHA")"
assert_eq "projection: a base with / and - matches and column 7 reads back whole" "feat/x-y.z" "$(printf '%s\n' "$row" | awk -F '\t' '{print $7}')"

# --- part 2: the script -------------------------------------------------------------------
fakebin="$tmp/fakebin"
mkdir -p "$fakebin"

cat >"$fakebin/gh" <<'FAKE_GH'
#!/bin/sh
printf '%s\n' "$*" >>"$FX_DIR/gh.log"
[ ! -f "$FX_DIR/flags" ] || . "$FX_DIR/flags"
[ -z "${FX_DRAIN:-}" ] || cat >/dev/null
leak() {
  echo "$FX_MARK gh failure text"
  echo "$FX_MARK gh failure text" >&2
}
case "$*" in
  "api --paginate repos/"*"/issues/"*"/comments --jq "*)
    if [ -n "${FX_LIST_FAIL:-}" ]; then
      [ -z "${FX_PARTIAL:-}" ] || cat "$FX_DIR/list.tsv"
      leak
      exit 1
    fi
    cat "$FX_DIR/list.tsv"
    ;;
  "api repos/"*"/issues/comments/"*"/reactions --paginate --jq "*)
    id="${2##*/issues/comments/}"
    id="${id%%/*}"
    if [ -n "${FX_RX_FAIL:-}" ]; then
      [ -z "${FX_PARTIAL:-}" ] || { [ ! -f "$FX_DIR/rx/$id.tsv" ] || cat "$FX_DIR/rx/$id.tsv"; }
      leak
      exit 1
    fi
    [ ! -f "$FX_DIR/rx/$id.tsv" ] || cat "$FX_DIR/rx/$id.tsv"
    ;;
  "api repos/"*"/issues/comments/"*" --jq .updated_at")
    id="${2##*/issues/comments/}"
    if [ -n "${FX_UPD_FAIL:-}" ]; then
      leak
      exit 1
    fi
    cat "$FX_DIR/upd/$id"
    ;;
  *)
    leak
    exit 1
    ;;
esac
FAKE_GH
chmod +x "$fakebin/gh"

cat >"$tmp/gi-stub.sh" <<'FAKE_GI'
#!/bin/sh
d="$(dirname "$0")"
printf '%s\n' "$*" >>"$d/../gi.log"
w="$(cat "$d/gi.word")"
[ "$w" != EXIT2 ] || exit 2
printf '%s\n' "$w"
FAKE_GI

T1="2026-09-21T09:00:00Z" # a comment's last edit
T2="2026-09-21T09:05:00Z" # a reaction after it
ISSUE=7
cn=0

# Defaults for the project file; a case reassigns them and calls writeyml again.
reset_yml() {
  Y_PRBASE="main"
  Y_BACKLOG="null"
  Y_IDENT='  maintainer:
    - {login: maint1, id: 101}
    - {login: maint2, id: 102}
  dev_app: {login: "dev-app[bot]", id: 201}
  reviewer_app: {login: "rev-app[bot]", id: 202}
  loop_app: {login: "loop-app[bot]", id: 203}'
}
writeyml() {
  {
    printf 'repo: acme/app\n'
    printf 'pr_base: %s\n' "$Y_PRBASE"
    printf 'backlog:\n  repo: %s\n' "$Y_BACKLOG"
    printf 'identities:\n%s\n' "$Y_IDENT"
  } >"$cd_/project.yml"
}

# A fresh fixture directory with the real siblings beside the script copy.
nc() {
  cn=$((cn + 1))
  cd_="$tmp/c$cn"
  mkdir -p "$cd_/bin" "$cd_/rx" "$cd_/upd"
  cp "$script" "$cd_/bin/spec-find.sh"
  cp "$bindir/spec-reaction.sh" "$bindir/gh-identity.sh" "$cd_/bin/"
  : >"$cd_/list.tsv"
  : >"$cd_/gh.log"
  : >"$cd_/gi.log"
  BACKLOG="acme/app"
  ISSUE=7
  reset_yml
  writeyml
}

use_gi_stub() { # <word>: swap in the logging gh-identity.sh
  cp "$tmp/gi-stub.sh" "$cd_/bin/gh-identity.sh"
  printf '%s\n' "$1" >"$cd_/bin/gi.word"
}

# addrow <id> <login> <uid> [updated] [issue-in-marker] [base] [issue_url]
addrow() {
  r_updated="${4:-$T1}"
  r_issue="${5:-$ISSUE}"
  r_base="${6:-$Y_PRBASE}"
  r_url="${7:-https://api.github.com/repos/$BACKLOG/issues/$ISSUE}"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$r_updated" "$r_url" "$2" "$3" "$r_issue" "$r_base" >>"$cd_/list.tsv"
  printf '%s' "$r_updated" >"$cd_/upd/$1"
}
# addrx <id> <user-id> <content> <created_at>
addrx() { printf '%s\t%s\t%s\n' "$2" "$3" "$4" >>"$cd_/rx/$1.tsv"; }
# a maintainer-authored (or dev-App) row with a maintainer's fresh approving reaction
approved() { addrow "$1" "$2" "$3"; addrx "$1" 101 +1 "$T2"; }
flag() { printf '%s\n' "$1" >>"$cd_/flags"; }

run() {
  rc=0
  out="$(PATH="$fakebin:$PATH" FX_DIR="$cd_" FX_MARK="$SENTINEL" sh "$cd_/bin/spec-find.sh" find "$ISSUE" "$cd_/project.yml" 2>"$cd_/err" </dev/null)" || rc=$?
  err="$(cat "$cd_/err")"
}

# expect <desc> <want-stdout> [want-rc]
expect() {
  want_rc="${3:-0}"
  assert_eq "$1" "$2|$want_rc" "$out|$rc"
  case "$out$err" in
    *"$SENTINEL"*) echo "FAIL - $1: the sentinel reached an output stream" >&2; fail=1 ;;
  esac
}

# --- found ---
nc; approved 1001 maint1 101; run
expect "found: a maintainer-authored reacted spec" "found 1001 $T1"

nc; approved 1001 "dev-app[bot]" 201; run
expect "found: a dev-App-authored reacted spec" "found 1001 $T1"

nc; approved 1001 maint1 101; addrow 1002 maint1 101; run
expect "found: one approved row beside one unreacted row" "found 1001 $T1"

nc; approved 1001 maint1 101; addrow 1001 maint1 101; run
expect "found: a repeated row is de-duplicated" "found 1001 $T1"

nc; Y_BACKLOG="other/backlog"; BACKLOG="other/backlog"; writeyml; approved 1001 maint1 101; run
expect "found: a non-null backlog.repo" "found 1001 $T1"
if grep -q 'repos/other/backlog/issues/7/comments' "$cd_/gh.log" &&
  grep -q 'repos/other/backlog/issues/comments/1001/reactions' "$cd_/gh.log" &&
  grep -q 'repos/other/backlog/issues/comments/1001 --jq' "$cd_/gh.log" &&
  ! grep -q 'repos/acme/app/' "$cd_/gh.log"; then
  echo "ok - found: the listing and the reaction reads go to backlog.repo"
else
  echo "FAIL - found: the calls did not all go to backlog.repo" >&2
  fail=1
fi

nc; Y_PRBASE="release/1.x"; writeyml; approved 1001 maint1 101; run
expect "found: a pr_base other than the default" "found 1001 $T1"

nc; Y_IDENT='  maintainer:
    - {login: maint1, id: 101}
  dev_app: null'; writeyml; approved 1001 maint1 101; run
expect "found: a null dev_app is the closed direction, a maintainer still found" "found 1001 $T1"

nc; Y_IDENT='  maintainer:
    - {login: maint1, id: 101}'; writeyml; approved 1001 maint1 101; run
expect "found: an absent dev_app is the closed direction, a maintainer still found" "found 1001 $T1"

nc; Y_IDENT='  maintainer:
    - {login: maint1, id: 101}'; writeyml; addrow 1001 "dev-app[bot]" 201; addrx 1001 101 +1 "$T2"; run
expect "none: with no dev_app declared a dev-App-looking author is dropped" "none"

# --- unreacted ---
nc; addrow 1001 maint1 101; addrx 1001 201 +1 "$T2"; run
expect "unreacted: only the dev App reacted" "unreacted 1001"

nc; addrow 1001 maint1 101; addrx 1001 999 +1 "$T2"; run
expect "unreacted: only a non-maintainer reacted" "unreacted 1001"

nc; addrow 1001 maint1 101; addrx 1001 101 +1 "2026-09-21T08:59:59Z"; run
expect "unreacted: a maintainer reacted before the last edit" "unreacted 1001"

nc; addrow 1001 maint1 101; addrx 1001 101 +1 "$T1"; run
expect "unreacted: a maintainer reacted in the same second as the edit" "unreacted 1001"

nc; addrow 1001 maint1 101; addrx 1001 101 -1 "$T2"; addrx 1001 102 eyes "$T2"; run
expect "unreacted: a -1 and an eyes reaction" "unreacted 1001"

nc; addrow 1001 maint1 101; addrow 1002 "dev-app[bot]" 201; run
expect "unreacted: several rows past the role check are listed in order" "unreacted 1001,1002"

# --- none ---
nc; run
expect "none: no marker rows" "none"

nc; addrow 1002 maint1 101 "$T1" 8; addrx 1002 101 +1 "$T2"; run
expect "none: an issue= mismatch" "none"

nc; addrow 1001 maint1 101 "$T1" 7 main "https://api.github.com/repos/acme/app/issues/8"; run
expect "none: an issue_url mismatch" "none"

nc; addrow 1001 maint1 101 "$T1" 7 other-branch; addrx 1001 101 +1 "$T2"; run
expect "none: a base= mismatch" "none"

nc; use_gi_stub maintainer; addrow 1001 outsider 555; addrx 1001 101 +1 "$T2"; run
expect "none: an undeclared author with a maintainer reaction" "none"
assert_eq "none: the role lookup is never called for an undeclared author" "" "$(cat "$cd_/gi.log")"
if grep -q 'issues/comments/1001' "$cd_/gh.log"; then
  echo "FAIL - none: an undeclared author's reactions were fetched" >&2
  fail=1
else
  echo "ok - none: an undeclared author's reactions are never fetched"
fi

nc; addrow 1001 "rev-app[bot]" 202; addrx 1001 101 +1 "$T2"; addrow 1002 "loop-app[bot]" 203; addrx 1002 101 +1 "$T2"; run
expect "none: a declared reviewer-App or loop-App author" "none"


# String, not numeric, comparison of the marker's base against pr_base (security-critic round 1).
nc; Y_PRBASE='"1000"'; writeyml; addrow 1001 maint1 101 "$T1" 7 1e3; addrx 1001 101 +1 "$T2"; run
expect "none: base=1e3 is not pr_base 1000" "none"

nc; Y_PRBASE='"1000"'; writeyml; addrow 1001 maint1 101 "$T1" 7 1000; addrx 1001 101 +1 "$T2"; run
expect "found: base=1000 is pr_base 1000" "found 1001 $T1"

# The in-loop calls must not read the loop's rows: a gh that drains stdin still sees every row.
nc; approved 1001 maint1 101; approved 1002 maint2 102; flag "FX_DRAIN=1"; run
expect "ambiguous: a gh that reads stdin does not swallow the remaining rows" "ambiguous 1001,1002"

# --- ambiguous ---
nc; approved 1001 maint1 101; approved 1002 maint2 102; run
expect "ambiguous: two approved rows" "ambiguous 1001,1002"

# --- moved ---
nc; approved 1001 maint1 101; printf '%s' "2026-09-21T09:06:00Z" >"$cd_/upd/1001"; run
expect "moved: updated_at changes between the listing and the second read" "moved 1001"

# --- precedence ---
nc; approved 1001 maint1 101; approved 1002 maint1 101; approved 1003 maint1 101; printf '%s' "2026-09-21T09:06:00Z" >"$cd_/upd/1001"; run
expect "precedence: a moved row beside two candidates gives moved" "moved 1001"

nc; approved 1001 maint1 101; addrow 1002 maint1 101 "2026-09-21 09:00:00"; run
expect "precedence: an unreadable row after a candidate gives unreadable" "unreadable"

nc; addrow 1002 maint1 101 "2026-09-21 09:00:00"; approved 1001 maint1 101; run
expect "precedence: an unreadable row before a candidate gives unreadable" "unreadable"

nc; approved 1001 maint1 101; addrow 1002 maint1 101; printf '%s' "2026-09-21T09:06:00Z" >"$cd_/upd/1002"; addrow 1003 maint1 101 "2026-09-21 09:00:00"; run
expect "precedence: unreadable beats moved" "unreadable"

# --- unreadable ---
nc; approved 1001 maint1 101; flag "FX_LIST_FAIL=1"; run
expect "unreadable: the listing fails" "unreadable"

nc; approved 1001 maint1 101; flag "FX_LIST_FAIL=1"; flag "FX_PARTIAL=1"; run
expect "unreadable: the listing writes a page and then fails" "unreadable"

nc; approved 1001 maint1 101; flag "FX_RX_FAIL=1"; run
expect "unreadable: the reactions fetch fails" "unreadable"

nc; approved 1001 maint1 101; flag "FX_RX_FAIL=1"; flag "FX_PARTIAL=1"; run
expect "unreadable: the reactions fetch writes a page and then fails" "unreadable"

nc; approved 1001 maint1 101; flag "FX_UPD_FAIL=1"; run
expect "unreadable: the second read fails" "unreadable"

nc; addrow 1001 maint1 101 "2026-09-21 09:00:00"; addrx 1001 101 +1 "$T2"; run
expect "unreadable: spec-reaction.sh exits 2 on a malformed updated_at" "unreadable"

nc; use_gi_stub EXIT2; approved 1001 maint1 101; run
expect "unreadable: role exits 2" "unreadable"

nc; use_gi_stub dev_app; approved 1001 maint1 101; run
expect "unreadable: role prints the wrong role for a maintainer id" "unreadable"

nc; use_gi_stub maintainer; approved 1001 "dev-app[bot]" 201; run
expect "unreadable: role prints the wrong role for the dev-App id" "unreadable"

nc; use_gi_stub undeclared; approved 1001 maint1 101; run
expect "unreadable: role prints undeclared for a declared id" "unreadable"

nc; Y_IDENT=" null"; writeyml; approved 1001 maint1 101; run
expect "unreadable: identities: null" "unreadable"

nc; Y_IDENT='  maintainer: []
  dev_app: null'; writeyml; approved 1001 maint1 101; run
expect "unreadable: an empty maintainer list" "unreadable"

nc; Y_IDENT='  maintainer:
    - {login: maint1, id: "101"}'; writeyml; approved 1001 maint1 101; run
expect "unreadable: a string maintainer id" "unreadable"

nc; Y_IDENT='  maintainer:
    - {login: maint1, id: 101}
    - {login: maint2}'; writeyml; approved 1001 maint1 101; run
expect "unreadable: one malformed maintainer entry" "unreadable"

nc; Y_IDENT='  maintainer:
    - {login: maint1, id: 101}
  dev_app: {login: "dev-app[bot]", id: "201"}'; writeyml; approved 1001 maint1 101; run
expect "unreadable: a malformed dev_app" "unreadable"

nc; Y_IDENT='  maintainer:
    - {login: maint1, id: 101}
  dev_app: just-a-string'; writeyml; approved 1001 maint1 101; run
expect "unreadable: a dev_app that is not a map" "unreadable"

nc; Y_IDENT='  maintainer:
    - {login: maint1, id: 101}
    - {login: "dev-app[bot]", id: 201}
  dev_app: {login: "dev-app[bot]", id: 201}'; writeyml; approved 1001 maint1 101; run
expect "unreadable: a dev-App id on the maintainer list" "unreadable"

nc; Y_IDENT='  maintainer:
    - {login: maint1, id: 101}
    - {login: "dev-app[bot]", id: 2001}
  dev_app: {login: "dev-app[bot]", id: +2001}'; writeyml; approved 1001 maint1 101; run
expect "unreadable: a dev-App id spelled +2001 beside 2001 on the maintainer list" "unreadable"

nc; Y_IDENT='  maintainer:
    - {login: maint1, id: 101}
    - {login: "dev-app[bot]", id: 2001}
  dev_app: {login: "dev-app[bot]", id: 0x7D1}'; writeyml; approved 1001 maint1 101; run
expect "unreadable: a dev-App id spelled 0x7D1 beside 2001 on the maintainer list" "unreadable"

nc; Y_IDENT='  maintainer:
    - {login: maint1, id: 101}
    - {login: "dev-app[bot]", id: 2001}
  dev_app: {login: "dev-app[bot]", id: 02001}'; writeyml; approved 1001 maint1 101; run
expect "unreadable: a dev-App id spelled 02001 beside 2001 on the maintainer list" "unreadable"

nc; Y_IDENT='  maintainer:
    - {login: maint1, id: 101}
  dev_app: {login: "dev-app[bot]", id: 0x7D1}'; writeyml; approved 1001 maint1 101; run
expect "unreadable: a non-canonical dev-App id with no collision" "unreadable"

nc; Y_PRBASE="-x"; writeyml; approved 1001 maint1 101; run
expect "unreadable: a pr_base that begins with a dash" "unreadable"

nc; Y_PRBASE='"a b"'; writeyml; approved 1001 maint1 101; run
expect "unreadable: a pr_base with a space" "unreadable"

nc; Y_PRBASE='""'; writeyml; approved 1001 maint1 101; run
expect "unreadable: an empty pr_base" "unreadable"

nc; Y_BACKLOG="not-a-repo"; writeyml; approved 1001 maint1 101; run
expect "unreadable: a backlog repo without a slash" "unreadable"

nc; Y_BACKLOG="a/b/c"; writeyml; approved 1001 maint1 101; run
expect "unreadable: a backlog repo with two slashes" "unreadable"

nc; Y_BACKLOG="../x"; writeyml; approved 1001 maint1 101; run
expect "unreadable: a backlog repo starting with .." "unreadable"

nc; Y_BACKLOG="owner/.."; writeyml; approved 1001 maint1 101; run
expect "unreadable: a backlog repo ending in /.." "unreadable"

# --- every declared App off the maintainer list (#708) ---
# Each of reviewer_app and loop_app, in turn: refused under find and, below, under pending.
for app in reviewer_app loop_app; do
  case "$app" in reviewer_app) alogin="rev-app[bot]" ;; *) alogin="loop-app[bot]" ;; esac
  nc; Y_IDENT="  maintainer:
    - {login: maint1, id: 101}
    - {login: \"$alogin\", id: 2002}
  $app: {login: \"$alogin\", id: 2002}"; writeyml; approved 1001 maint1 101; run
  expect "unreadable: the $app id on the maintainer list" "unreadable"
  for sp in +2002 0x7D2 02002 2_002; do
    nc; Y_IDENT="  maintainer:
    - {login: maint1, id: 101}
    - {login: \"$alogin\", id: 2002}
  $app: {login: \"$alogin\", id: $sp}"; writeyml; approved 1001 maint1 101; run
    expect "unreadable: the $app id spelled $sp beside 2002 on the maintainer list" "unreadable"
  done
  nc; Y_IDENT="  maintainer:
    - {login: maint1, id: 101}
  $app: {login: \"$alogin\", id: \"2002\"}"; writeyml; approved 1001 maint1 101; run
  expect "unreadable: a $app entry with a string id" "unreadable"
  nc; Y_IDENT="  maintainer:
    - {login: maint1, id: 101}
  $app: just-a-string"; writeyml; approved 1001 maint1 101; run
  expect "unreadable: a $app entry that is a bare string" "unreadable"
  nc; Y_IDENT="  maintainer:
    - {login: maint1, id: 101}
  $app: {login: \"$alogin\", id: 2002}"; writeyml; approved 1001 maint1 101; run
  expect "found: a well-formed $app off the maintainer list" "found 1001 $T1"
done

nc; Y_IDENT='  maintainer:
    - {login: maint1, id: 101}
  reviewer_app: null
  loop_app: null'; writeyml; approved 1001 maint1 101; run
expect "found: reviewer_app and loop_app both null" "found 1001 $T1"

nc; Y_IDENT='  maintainer:
    - {login: maint1, id: 101}
  dev_app: null'; writeyml; approved 1001 maint1 101; run
expect "found: reviewer_app and loop_app keys missing" "found 1001 $T1"

# --- pending (#663) ---
runp() { # <after-id>
  rc=0
  out="$(PATH="$fakebin:$PATH" FX_DIR="$cd_" FX_MARK="$SENTINEL" sh "$cd_/bin/spec-find.sh" pending "$ISSUE" "$cd_/project.yml" "$1" 2>"$cd_/err" </dev/null)" || rc=$?
  err="$(cat "$cd_/err")"
}

for app in reviewer_app loop_app; do
  case "$app" in reviewer_app) alogin="rev-app[bot]" ;; *) alogin="loop-app[bot]" ;; esac
  nc; Y_IDENT="  maintainer:
    - {login: maint1, id: 101}
    - {login: \"$alogin\", id: 2002}
  $app: {login: \"$alogin\", id: 2002}"; writeyml; approved 1001 maint1 101; runp 1001
  expect "pending: the $app id on the maintainer list" "unreadable"
  nc; Y_IDENT="  maintainer:
    - {login: maint1, id: 101}
    - {login: \"$alogin\", id: 2002}
  $app: {login: \"$alogin\", id: +2002}"; writeyml; approved 1001 maint1 101; runp 1001
  expect "pending: the $app id spelled +2002 beside 2002 on the maintainer list" "unreadable"
  nc; Y_IDENT="  maintainer:
    - {login: maint1, id: 101}
  $app: just-a-string"; writeyml; approved 1001 maint1 101; runp 1001
  expect "pending: a $app entry that is a bare string" "unreadable"
  for sp in 0x7D2 02002 2_002; do
    nc; Y_IDENT="  maintainer:
    - {login: maint1, id: 101}
    - {login: \"$alogin\", id: 2002}
  $app: {login: \"$alogin\", id: $sp}"; writeyml; approved 1001 maint1 101; runp 1001
    expect "pending: the $app id spelled $sp beside 2002 on the maintainer list" "unreadable"
  done
  nc; Y_IDENT="  maintainer:
    - {login: maint1, id: 101}
  $app: {login: \"$alogin\", id: \"2002\"}"; writeyml; approved 1001 maint1 101; runp 1001
  expect "pending: a $app entry with a string id" "unreadable"
done

nc; approved 1001 maint1 101; addrow 1002 "dev-app[bot]" 201; runp 1001
expect "pending: one unreacted dev-App comment newer than the found one" "pending 1002"

nc; addrow 1000 "dev-app[bot]" 201; approved 1001 maint1 101; runp 1001
expect "pending: an older unreacted comment and no newer one" "pending none"

nc; addrow 1000 "dev-app[bot]" 201; approved 1001 maint1 101; addrow 1002 "dev-app[bot]" 201; runp 1001
expect "pending: an older and a newer unreacted comment list only the newer" "pending 1002"

nc; approved 1001 maint1 101; addrow 10002 "dev-app[bot]" 201; runp 1001
expect "pending: an id with more digits than after-id is greater" "pending 10002"

nc; addrow 999 "dev-app[bot]" 201; approved 1001 maint1 101; runp 1001
expect "pending: an id with fewer digits than after-id is not greater" "pending none"

nc; approved 1001 maint1 101; approved 1002 maint2 102; runp 1001
expect "pending: all role-passed rows approved" "pending none"

nc; runp 1001
expect "pending: no marker comments" "pending none"

nc; approved 1001 maint1 101; addrow 1002 "dev-app[bot]" 201; printf '%s' "2026-09-21T09:06:00Z" >"$cd_/upd/1002"; runp 1001
expect "pending: a row that moves between the reads" "moved 1002"

nc; approved 1001 maint1 101; flag "FX_LIST_FAIL=1"; runp 1001
expect "pending: a failed listing" "unreadable"

nc; approved 1001 maint1 101; addrow 1002 "dev-app[bot]" 201; runp 0
expect "exit 2: pending with an after-id of zero" "" 2
runp 01
expect "exit 2: pending with a leading-zero after-id" "" 2
runp abc
expect "exit 2: pending with a non-digit after-id" "" 2
rc=0; out="$(PATH="$fakebin:$PATH" FX_DIR="$cd_" sh "$cd_/bin/spec-find.sh" pending 7 "$cd_/project.yml" 2>/dev/null)" || rc=$?
expect "exit 2: pending without an after-id" "" 2

# --- exit 2, nothing on stdout ---
nc; approved 1001 maint1 101
ISSUE=abc; run
expect "exit 2: a non-digit issue" "" 2
ISSUE=07; run
expect "exit 2: an issue with a leading zero" "" 2
ISSUE=0; run
expect "exit 2: an issue of zero" "" 2

nc; approved 1001 maint1 101
rc=0; out="$(PATH="$fakebin:$PATH" FX_DIR="$cd_" sh "$cd_/bin/spec-find.sh" find 7 2>/dev/null)" || rc=$?
expect "exit 2: a wrong argument count" "" 2
rc=0; out="$(PATH="$fakebin:$PATH" FX_DIR="$cd_" sh "$cd_/bin/spec-find.sh" show 7 "$cd_/project.yml" 2>/dev/null)" || rc=$?
expect "exit 2: an unknown mode" "" 2
rc=0; out="$(PATH="$fakebin:$PATH" FX_DIR="$cd_" sh "$cd_/bin/spec-find.sh" find 7 "$cd_/no-such.yml" 2>/dev/null)" || rc=$?
expect "exit 2: a missing project file" "" 2
rc=0; out="$(cd "$cd_/bin" && PATH="$fakebin:$PATH" FX_DIR="$cd_" sh spec-find.sh find 7 ../project.yml 2>/dev/null)" || rc=$?
expect "exit 2: a slash-less \$0" "" 2

nc; approved 1001 maint1 101; rm "$cd_/bin/gh-identity.sh"; run
expect "exit 2: a missing gh-identity.sh" "" 2

nc; approved 1001 maint1 101; rm "$cd_/bin/spec-reaction.sh"; run
expect "exit 2: a missing spec-reaction.sh" "" 2

[ "$fail" -eq 0 ]
