#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/blocked-state.sh.
#
# Issue #224: /way-of-working:pr-checks must tell GitHub re-evaluation lag from a rule that
# holds a green PR BLOCKED. Issue #384 (WB-D24): the merge gate is a human code-owner
# approval, so the admin-merge verdict is gone and the approval a PR waits for is read from
# reviewDecision (`awaiting-approval`). This suite covers each verdict, the rules the script
# judges (approvals, code-owner review), the ones it refuses (#248), and the fail-closed edges.
#
# The script reads rule lines on stdin and three arguments; there is no gh to stub.
#
# Permitted toolset: POSIX sh and its standard utilities. No jq, no yq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/plugins/way-of-working/bin/blocked-state.sh"

fail=0

assert_eq() {
  desc="$1"; expected="$2"; actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "ok - $desc"
  else
    echo "FAIL - $desc: expected [$expected], got [$actual]" >&2
    fail=1
  fi
}

# run <state> <green> <decision> <stdin-text>  -> "<stdout>|<exit>"
run() {
  out="$(printf '%s' "$4" | sh "$script" "$1" "$2" "$3" 2>/dev/null)" && rc=0 || rc=$?
  printf '%s|%s' "$out" "$rc"
}

# run_raw <state> <green> <decision> <printf-format>: pipes printf's output straight in, so
# bytes a command substitution would strip (Git Bash's bash drops CR from $(...)) reach the script.
run_raw() {
  out="$(printf "$4" | sh "$script" "$1" "$2" "$3" 2>/dev/null)" && rc=0 || rc=$?
  printf '%s|%s' "$out" "$rc"
}

run_err() {   # run_err <state> <green> <decision> <stdin-text> -> stderr text
  printf '%s' "$4" | sh "$script" "$1" "$2" "$3" 2>&1 >/dev/null || true
}

pr0='pull_request approvals=0 threads=false codeowner=false reviewers=0'
pr_co='pull_request approvals=1 threads=false codeowner=true reviewers=0'
rsc0='required_status_checks app_pinned=0'
rsc_pin='required_status_checks app_pinned=2'
plain="$(printf 'deletion\nnon_fast_forward\n%s\n%s\n' "$pr0" "$rsc0")"
approval="$(printf 'deletion\nnon_fast_forward\n%s\n%s\n' "$pr_co" "$rsc_pin")"

# --- the verdicts ---------------------------------------------------------------
assert_eq "BLOCKED + green + approval rule + REVIEW_REQUIRED -> awaiting-approval" \
  "awaiting-approval|0" "$(run BLOCKED 1 REVIEW_REQUIRED "$approval
")"
assert_eq "BLOCKED + green + approval rule + APPROVED -> lag (the approval is in)" \
  "lag|0" "$(run BLOCKED 1 APPROVED "$approval
")"
assert_eq "BLOCKED + green + no review rule + NONE -> lag" \
  "lag|0" "$(run BLOCKED 1 NONE "$plain
")"
assert_eq "BLOCKED + green + no rules at all + NONE -> lag" "lag|0" "$(run BLOCKED 1 NONE "")"
assert_eq "BLOCKED + green + no rules at all + APPROVED -> lag" "lag|0" "$(run BLOCKED 1 APPROVED "")"
assert_eq "BLOCKED + not green + approval rule + REVIEW_REQUIRED -> blocked (checks come first)" \
  "blocked|0" "$(run BLOCKED 0 REVIEW_REQUIRED "$approval
")"
assert_eq "BLOCKED + not green + no review rule -> blocked" \
  "blocked|0" "$(run BLOCKED 0 NONE "$plain
")"
assert_eq "BLOCKED + green + CHANGES_REQUESTED -> blocked" \
  "blocked|0" "$(run BLOCKED 1 CHANGES_REQUESTED "$approval
")"
assert_eq "an approvals-only rule (no code owner) awaits approval too" "awaiting-approval|0" \
  "$(run BLOCKED 1 REVIEW_REQUIRED "pull_request approvals=2 threads=false codeowner=false reviewers=0
")"
assert_eq "a code-owner-only rule (no approval count) awaits approval too" "awaiting-approval|0" \
  "$(run BLOCKED 1 REVIEW_REQUIRED "pull_request approvals=0 threads=false codeowner=true reviewers=0
")"

for st in BEHIND CLEAN DIRTY DRAFT HAS_HOOKS UNKNOWN UNSTABLE; do
  assert_eq "$st -> not-blocked, whatever the rules, checks and review say" \
    "not-blocked|0" "$(run "$st" 1 REVIEW_REQUIRED "$approval
")"
done

# --- the retired admin-merge verdict --------------------------------------------
# An `update` rule used to print admin-merge-ready. It is now a rule the script cannot judge.
upd="$(printf '%s\nupdate\n' "$plain")"
assert_eq "BLOCKED + green + an update rule + NONE -> exit 2, no stdout (no admin-merge verdict)" \
  "|2" "$(run BLOCKED 1 NONE "$upd")"
case "$(run_err BLOCKED 1 NONE "$upd")" in
  *"update"*"retired"*) echo "ok - the update refusal names the rule and the retirement" ;;
  *) echo "FAIL - the update refusal does not name the rule" >&2; fail=1 ;;
esac
assert_eq "BLOCKED + green + an update rule + APPROVED -> exit 2" "|2" "$(run BLOCKED 1 APPROVED "$upd")"
assert_eq "an update rule does not mask a red check -> blocked" "blocked|0" "$(run BLOCKED 0 NONE "$upd")"
assert_eq "an update rule does not hide a missing approval -> awaiting-approval" "awaiting-approval|0" \
  "$(run BLOCKED 1 REVIEW_REQUIRED "$(printf '%s\nupdate\n' "$approval")")"
assert_eq "an update rule says nothing about a PR that is not BLOCKED" "not-blocked|0" \
  "$(run CLEAN 1 NONE "$upd")"
assert_eq "the old admin-merge-ready word is never printed" "0" \
  "$(for d in APPROVED REVIEW_REQUIRED NONE; do run BLOCKED 1 $d "$upd"; done | grep -c admin-merge-ready || true)"

# --- #248: a rule this script cannot evaluate is never read as absent ------------
# Each is BLOCKED + green + APPROVED, the shape that would otherwise read lag. It must be
# exit 2, no stdout, and name the rule on stderr.
unseen_case() {   # unseen_case <desc> <extra rule lines> <expected stderr fragment>
  desc="$1"; extra="$2"; frag="$3"
  in="$(printf 'deletion\n%s\n%s\n%s\n' "$pr0" "$rsc0" "$extra")"
  assert_eq "$desc -> exit 2, no stdout" "|2" "$(run BLOCKED 1 APPROVED "$in
")"
  case "$(run_err BLOCKED 1 APPROVED "$in
")" in
    *"$frag"*) echo "ok - $desc: stderr names [$frag]" ;;
    *) echo "FAIL - $desc: stderr does not name [$frag]" >&2; fail=1 ;;
  esac
}
unseen_case "review-thread resolution on" \
  "$(printf 'pull_request approvals=0 threads=true codeowner=false reviewers=0')" "review-thread resolution"
unseen_case "a required_deployments rule" "required_deployments" "required_deployments"
unseen_case "a code_scanning rule" "code_scanning" "code_scanning"
unseen_case "a required_signatures rule" "required_signatures" "required_signatures"
unseen_case "a merge_queue rule" "merge_queue" "merge_queue"
unseen_case "required reviewers named on a pull_request rule" \
  "$(printf 'pull_request approvals=0 threads=false codeowner=false reviewers=1')" "required reviewers"
assert_eq "thread resolution beside an approval rule is still refused once approved" "|2" \
  "$(run BLOCKED 1 APPROVED "pull_request approvals=1 threads=true codeowner=true reviewers=0
")"
assert_eq "a bare pull_request line (parameters dropped) -> exit 2" "|2" \
  "$(run BLOCKED 1 APPROVED "pull_request
")"
assert_eq "a bare required_status_checks line (parameters dropped) -> exit 2" "|2" \
  "$(run BLOCKED 1 APPROVED "required_status_checks
")"
assert_eq "a pull_request line missing a word (reviewers) -> exit 2" "|2" \
  "$(run BLOCKED 1 APPROVED "pull_request approvals=0 threads=false codeowner=false
")"
assert_eq "an overlong approvals count refuses rather than reading as zero" "|2" \
  "$(run BLOCKED 1 NONE "pull_request approvals=99999999999999999999 threads=false codeowner=false reviewers=0
")"
assert_eq "a repeated key (last one would win) -> exit 2" "|2" \
  "$(run BLOCKED 1 APPROVED "pull_request approvals=5 approvals=0 threads=false codeowner=false reviewers=0
")"
assert_eq "a key on the wrong type -> exit 2" "|2" \
  "$(run BLOCKED 1 APPROVED "required_status_checks app_pinned=0 threads=true
")"
assert_eq "a key on a type that takes none -> exit 2" "|2" "$(run BLOCKED 1 APPROVED "update approvals=5
")"
assert_eq "a CRLF rule line that must refuse still refuses" "|2" \
  "$(run_raw BLOCKED 1 APPROVED 'update\r\nmerge_queue\r\n')"
assert_eq "an unseen rule is not lag either -> exit 2" "|2" \
  "$(run BLOCKED 1 NONE "$(printf '%s\nrequired_deployments' "$pr0")
")"
assert_eq "an unseen rule does not mask a red check -> blocked" "blocked|0" \
  "$(run BLOCKED 0 APPROVED "$(printf 'merge_queue')
")"
assert_eq "an unseen rule says nothing about a PR that is not BLOCKED" "not-blocked|0" \
  "$(run CLEAN 1 APPROVED "$(printf 'merge_queue')
")"
assert_eq "an unseen rule does not hide a missing approval -> awaiting-approval" "awaiting-approval|0" \
  "$(run BLOCKED 1 REVIEW_REQUIRED "$(printf '%s\nmerge_queue' "$pr_co")
")"
assert_eq "a rule type outside the lists is ignored, not unseen" "lag|0" \
  "$(run BLOCKED 1 APPROVED "$(printf 'workflows')
")"
assert_eq "an unrecognised key=value word -> exit 2" "|2" \
  "$(run BLOCKED 1 APPROVED "pull_request approvals=0 bogus=1
")"
assert_eq "a non-numeric count -> exit 2" "|2" \
  "$(run BLOCKED 1 APPROVED "pull_request approvals=x threads=false codeowner=false reviewers=0
")"
assert_eq "a doubled space between words -> exit 2" "|2" \
  "$(run BLOCKED 1 APPROVED "pull_request  approvals=0 threads=false codeowner=false reviewers=0
")"

# --- #384: pinned checks and the review decision --------------------------------
assert_eq "a check pinned to an app is the caller's to judge (inside green): green=1 -> not refused" \
  "lag|0" "$(run BLOCKED 1 APPROVED "$(printf '%s\n%s' "$pr0" "$rsc_pin")
")"
assert_eq "a pinned check whose run came from the wrong app (caller said green=0) -> blocked" \
  "blocked|0" "$(run BLOCKED 0 APPROVED "$(printf '%s\n%s' "$pr0" "$rsc_pin")
")"
assert_eq "REVIEW_REQUIRED with no approval rule to explain it -> exit 2" "|2" \
  "$(run BLOCKED 1 REVIEW_REQUIRED "$plain
")"
assert_eq "REVIEW_REQUIRED with the rules unread (empty list) -> exit 2" "|2" \
  "$(run BLOCKED 1 REVIEW_REQUIRED "")"
assert_eq "NONE next to a rule that demands an approval contradicts it -> exit 2" "|2" \
  "$(run BLOCKED 1 NONE "$approval
")"
assert_eq "an overlong approvals count with REVIEW_REQUIRED still awaits approval" "awaiting-approval|0" \
  "$(run BLOCKED 1 REVIEW_REQUIRED "pull_request approvals=99999999999999999999 threads=false codeowner=false reviewers=0
")"
assert_eq "a final rule line with no trailing newline is still read" \
  "awaiting-approval|0" "$(run BLOCKED 1 REVIEW_REQUIRED "$rsc0
$pr_co")"
assert_eq "a CRLF-terminated approval line (Windows gh) still counts" \
  "awaiting-approval|0" "$(run_raw BLOCKED 1 REVIEW_REQUIRED 'pull_request approvals=1 threads=false codeowner=true reviewers=0\r\n')"
assert_eq "only the exact type 'update' is a rule it names (not 'update_x', 'required_update')" \
  "lag|0" "$(run BLOCKED 1 APPROVED "$(printf 'update_x\nrequired_update\nupdates\n')")"

# --- fail closed: cannot answer -> no stdout, exit 2 ---------------------------
assert_eq "no arguments -> exit 2, no stdout" "|2" \
  "$(printf '' | sh "$script" 2>/dev/null && echo "|0" || printf '|%s' "$?")"
assert_eq "the old two-argument form -> exit 2, no stdout" "|2" \
  "$(printf '' | sh "$script" BLOCKED 1 2>/dev/null && echo "|0" || printf '|%s' "$?")"
assert_eq "an unrecognised state -> exit 2" "|2" "$(run MERGEABLE 1 NONE "")"
assert_eq "green other than 0/1 -> exit 2" "|2" "$(run BLOCKED yes NONE "")"
assert_eq "green empty -> exit 2" "|2" "$(run BLOCKED '' NONE "")"
assert_eq "a decision outside the vocabulary -> exit 2" "|2" "$(run BLOCKED 1 MAYBE "")"
assert_eq "an empty decision (the caller must write NONE) -> exit 2" "|2" "$(run BLOCKED 1 '' "")"
assert_eq "a lowercase decision -> exit 2" "|2" "$(run BLOCKED 1 approved "")"
assert_eq "a stdin line with a character outside the rule-line alphabet -> exit 2" "|2" \
  "$(run BLOCKED 1 NONE "pull_request
update; rm -rf /
")"
assert_eq "an uppercase UPDATE is not the rule type (and not a token) -> exit 2" "|2" \
  "$(run BLOCKED 1 NONE "UPDATE
")"
assert_eq "a CR-only line -> exit 2" "|2" "$(run_raw BLOCKED 1 NONE 'update\n\r\n')"
assert_eq "a blank line in the rule list -> exit 2" "|2" \
  "$(run BLOCKED 1 NONE "update

pull_request
")"
assert_eq "a JSON error body where rule types belong -> exit 2" "|2" \
  "$(run BLOCKED 1 NONE '{"message":"Not Found"}
')"

if [ "$fail" -ne 0 ]; then
  echo "blocked-state.test.sh: FAILED" >&2
  exit 1
fi
echo "blocked-state.test.sh: all passed"
