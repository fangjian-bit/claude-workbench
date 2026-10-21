#!/bin/sh
# Fixture tests for the review-match program the gate reads a review's verdict with (#851,
# WB-D38). The program exists twice: in .github/workflows/architect-review-gate.yml and in
# scripts/identity/wow-review's `decide_already`. This suite pulls out of each the `--jq`
# projection of the reviews read and the program (the quoted text that opens on the line carrying
# `--argjson rid` and ends before the line that begins with the closing quote), strips each line's
# leading blanks (the jq argument lines around them may differ), fails when either pair differs,
# shows that a sed-mutated copy of either file fails the comparison, and runs canned review
# lists through the program.
#
# Permitted toolset: POSIX sh and its standard utilities, awk and jq (skipped, loudly, if absent).
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
wf="$root_dir/.github/workflows/architect-review-gate.yml"
wr="$root_dir/scripts/identity/wow-review"

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP - jq not on PATH; review-verdict fixtures not run" >&2
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
ok() { printf 'ok - %s\n' "$1"; }
bad() { printf 'FAIL - %s\n' "$1" >&2; fail=1; }
check() { # check <label> <command...>
  l=$1; shift
  if "$@"; then ok "$l"; else bad "$l"; fi
}
assert_eq() { # assert_eq <label> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: expected [$2], got [$3]"; fi
}

program_of() { # program_of <file>: the program's lines, leading blanks removed
  awk '
    on && $0 ~ /^[ \t]*\047/ { exit }
    on { sub(/^[ \t]+/, ""); print }
    /--argjson rid/ { on = 1 }
  ' "$1"
}
projection_of() { # projection_of <file>: the quoted --jq text of the reviews read
  sed -n "s/^.*--jq '\\(\\.\\[\\] | {uid: [^']*\\)'.*\$/\\1/p" "$1"
}
same_pair() { # same_pair <file-a> <file-b>: both extractions equal, and not empty
  pa=$(program_of "$1"); pb=$(program_of "$2")
  ja=$(projection_of "$1"); jb=$(projection_of "$2")
  [ -n "$pa" ] && [ -n "$ja" ] && [ "$pa" = "$pb" ] && [ "$ja" = "$jb" ]
}

check "the workflow carries one program" test "$(grep -c -e '--argjson rid' "$wf")" = 1
check "wow-review carries one program" test "$(grep -c -e '--argjson rid' "$wr")" = 1
check "the workflow's program is not empty" test -n "$(program_of "$wf")"
check "the workflow's projection is not empty" test -n "$(projection_of "$wf")"
check "the workflow and decide_already carry the same program and projection" same_pair "$wf" "$wr"

# A change to the program alone, or to the projection alone, in either copy, fails the comparison.
sed 's/"blocking"/"blocking2"/' "$wf" >"$tmp/wf.prog"
sed 's/"blocking"/"blocking2"/' "$wr" >"$tmp/wr.prog"
sed 's/{uid: \.user\.id/{uid: .user.login/' "$wr" >"$tmp/wr.proj"
sed 's/{uid: \.user\.id/{uid: .user.login/' "$wf" >"$tmp/wf.proj"
check "a mutated program in the workflow differs from wow-review's" test "$(program_of "$tmp/wf.prog")" != "$(program_of "$wr")"
check "a mutated program in wow-review differs from the workflow's" test "$(program_of "$wr")" != "$(program_of "$tmp/wr.prog")"
if same_pair "$tmp/wf.prog" "$wr"; then bad "the comparison accepts a program changed in the workflow alone"; else ok "the comparison refuses a program changed in the workflow alone"; fi
if same_pair "$wf" "$tmp/wr.prog"; then bad "the comparison accepts a program changed in wow-review alone"; else ok "the comparison refuses a program changed in wow-review alone"; fi
if same_pair "$tmp/wf.proj" "$wr"; then bad "the comparison accepts a projection changed in the workflow alone"; else ok "the comparison refuses a projection changed in the workflow alone"; fi
if same_pair "$wf" "$tmp/wr.proj"; then bad "the comparison accepts a projection changed in wow-review alone"; else ok "the comparison refuses a projection changed in wow-review alone"; fi

if [ "$fail" != 0 ]; then echo "review-verdict: FAILURES" >&2; exit 1; fi

# --- canned review lists through the program ---------------------------------------------------
program_of "$wf" >"$tmp/prog.jq"
SHA=$(printf 'a%.0s' $(seq 1 40))
OTHER=$(printf 'b%.0s' $(seq 1 40))
RID=4242
H='**Opus/Architect review (automated)**'
A='*Fresh-session review: this session did not author the diff.*'

rev() { # rev <uid> <commit> <state> <submitted_at json> <body>
  jq -nc --argjson uid "$1" --arg c "$2" --arg s "$3" --argjson t "$4" --arg b "$5" \
    '{uid:$uid, commit_id:$c, state:$s, submitted_at:$t, body:$b}'
}
mk() { # mk <line 4 or "-"> : a matching body; "-" is the three-line form
  if [ "$1" = - ]; then printf '%s\n\n%s' "$H" "$A"; else printf '%s\n\n%s\n\n%s\n\nReviewed against head %s' "$H" "$A" "$1" "$SHA"; fi
}
run_prog() { # run_prog <review lines...>: prints the program's word
  printf '%s\n' "$@" | jq -r -s --argjson rid "$RID" --arg sha "$SHA" --arg h "$H" --arg a "$A" -f "$tmp/prog.jq"
}
T1='"2026-10-15T10:00:00Z"'; T2='"2026-10-15T11:00:00Z"'
PASS=$(mk 'Review verdict: pass'); CHG=$(mk 'Review verdict: changes-needed')
OLD=$(printf '%s\n\n%s\n\nReviewed against head %s\n\nother' "$H" "$A" "$SHA")

assert_eq "pass reads success" success "$(run_prog "$(rev $RID $SHA COMMENTED "$T1" "$PASS")")"
assert_eq "an old-form line 4 reads success" success "$(run_prog "$(rev $RID $SHA COMMENTED "$T1" "$OLD")")"
assert_eq "a three-line body reads success" success "$(run_prog "$(rev $RID $SHA COMMENTED "$T1" "$(mk -)")")"
assert_eq "changes-needed reads blocking" blocking "$(run_prog "$(rev $RID $SHA COMMENTED "$T1" "$CHG")")"
assert_eq "another Review verdict: line reads blocking" blocking "$(run_prog "$(rev $RID $SHA COMMENTED "$T1" "$(mk 'Review verdict: maybe')")")"
assert_eq "a Review verdict: line with no word reads blocking" blocking "$(run_prog "$(rev $RID $SHA COMMENTED "$T1" "$(mk 'Review verdict:')")")"
assert_eq "a lower-case review verdict line is the old form" success "$(run_prog "$(rev $RID $SHA COMMENTED "$T1" "$(mk 'review verdict: changes-needed')")")"
assert_eq "no review reads none" none "$(run_prog)"
assert_eq "a review by another author reads none" none "$(run_prog "$(rev 9 $SHA COMMENTED "$T1" "$PASS")")"
assert_eq "a review on another commit reads none" none "$(run_prog "$(rev $RID $OTHER COMMENTED "$T1" "$PASS")")"
assert_eq "a review that is not COMMENTED reads none" none "$(run_prog "$(rev $RID $SHA APPROVED "$T1" "$PASS")")"
assert_eq "a PENDING review reads none" none "$(run_prog "$(rev $RID $SHA PENDING null "$PASS")")"
assert_eq "an unsubmitted review reads none" none "$(run_prog "$(rev $RID $SHA COMMENTED null "$PASS")")"
assert_eq "the wrong header reads none" none "$(run_prog "$(rev $RID $SHA COMMENTED "$T1" "$(printf 'wrong\n\n%s\n\nReview verdict: pass' "$A")")")"
assert_eq "the wrong attestation reads none" none "$(run_prog "$(rev $RID $SHA COMMENTED "$T1" "$(printf '%s\n\nwrong\n\nReview verdict: pass' "$H")")")"
assert_eq "a null body reads none" none "$(run_prog "$(jq -nc --arg c "$SHA" '{uid:4242, commit_id:$c, state:"COMMENTED", submitted_at:"2026-10-15T10:00:00Z", body:null}')")"
assert_eq "the latest review decides: changes-needed after pass" blocking \
  "$(run_prog "$(rev $RID $SHA COMMENTED "$T1" "$PASS")" "$(rev $RID $SHA COMMENTED "$T2" "$CHG")")"
assert_eq "the latest review decides regardless of list order" blocking \
  "$(run_prog "$(rev $RID $SHA COMMENTED "$T2" "$CHG")" "$(rev $RID $SHA COMMENTED "$T1" "$PASS")")"
assert_eq "the latest review decides: pass after changes-needed" success \
  "$(run_prog "$(rev $RID $SHA COMMENTED "$T1" "$CHG")" "$(rev $RID $SHA COMMENTED "$T2" "$PASS")")"
assert_eq "equal submitted_at: the later in list order decides (pass)" success \
  "$(run_prog "$(rev $RID $SHA COMMENTED "$T1" "$CHG")" "$(rev $RID $SHA COMMENTED "$T1" "$PASS")")"
assert_eq "equal submitted_at: the later in list order decides (changes-needed)" blocking \
  "$(run_prog "$(rev $RID $SHA COMMENTED "$T1" "$PASS")" "$(rev $RID $SHA COMMENTED "$T1" "$CHG")")"
assert_eq "a later non-matching review does not decide" success \
  "$(run_prog "$(rev $RID $SHA COMMENTED "$T1" "$PASS")" "$(rev 9 $SHA COMMENTED "$T2" "$CHG")")"

if [ "$fail" = 0 ]; then echo "review-verdict: all fixtures passed"; else echo "review-verdict: FAILURES" >&2; fi
exit "$fail"
