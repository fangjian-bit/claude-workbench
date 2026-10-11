#!/bin/sh
# Read a PR's `mergeStateStatus: BLOCKED` correctly: is it GitHub re-evaluation lag, a
# required approval nobody has given yet, or a rule this script cannot judge?
#
# Issue #224: /way-of-working:pr-checks read "BLOCKED with nothing red or pending" as
# GitHub re-evaluation lag and said to wait, so a rule that holds a green PR BLOCKED for good
# made the lag reading never clear. Whether such a rule applies is a deterministic question
# with a correctness argument, so it is a tested script the skill invokes rather than a rule
# described in prose (WB-D10).
#
# Issue #384 (WB-D24): the merge gate is one human code-owner approval, not the admin role.
# The admin-merge verdict this script used to print is gone: nothing here reads a bypass
# actor, and a PR that only an `update` rule's bypass actor could merge is no longer a
# ready PR. The approval a PR waits for is now a verdict of its own, read from
# `reviewDecision` instead of folded into <green>.
#
# Usage: blocked-state.sh <mergeStateStatus> <green> <reviewDecision>      (rule lines on
#        stdin; the caller captures `gh`'s output first -- see the failed-gh warning below
#        -- and never pipes `gh` itself, whose exit status a pipe would hide)
#
#   <mergeStateStatus>  the PR's mergeStateStatus, as `gh pr view --json` prints it
#   <green>             1 only when the caller has established ALL of: every required
#                       check green (or legitimately skipped) with none pending, red or
#                       missing a run -- over the union of every declared ruleset's
#                       required checks and the contexts the branch's own
#                       required_status_checks rule names; a non-empty required-check
#                       list; and, for each context that rule pins to an app
#                       (`integration_id`), a run of that name posted BY that app. Else 0.
#                       The review is NOT part of it any more: <reviewDecision> carries it.
#                       The caller computes it; this script cannot see any of it, so a
#                       wrong 1 is a wrong verdict.
#   <reviewDecision>    the PR's reviewDecision, as `gh pr view --json` prints it, with the
#                       empty string (no review rule applies) written NONE: one of
#                       APPROVED | REVIEW_REQUIRED | CHANGES_REQUESTED | NONE
#
# stdin is the rules that apply to the PR's own base branch (its baseRefName, not the
# configured {pr_base}), one per line: the rule type, then for the two types whose
# parameters decide the answer, those parameters as `key=value` words. Issue #248: type
# names alone dropped every parameter, so a `pull_request` rule demanding approvals or
# thread resolution read the same as one demanding nothing.
#
#   gh api --paginate "repos/{repo}/rules/branches/<baseRefName>" --jq '.[] | .type +
#     (if .type=="pull_request" then " approvals=\(.parameters.required_approving_review_count // 0)
#        threads=\(.parameters.required_review_thread_resolution // false)
#        codeowner=\(.parameters.require_code_owner_review // false)
#        reviewers=\([.parameters.required_reviewers[]?] | length)"
#      elif .type=="required_status_checks"
#        then " app_pinned=\([.parameters.required_status_checks[]? | select(.integration_id != null)] | length)"
#      else "" end)'
#
# (one line per rule; the line breaks above are for reading: the pr-checks skill carries
# the exact, single-line form, and a break inside the output is a stdin line this script
# rejects.) A key may appear once, and only on the type that owns it. `gh`
# embeds jq, so neither the caller nor this script needs a separate jq. Those are the rules
# of EVERY ruleset applying to the branch -- the endpoint merges them, so a checks ruleset and a
# separate approval ruleset (WB-D24) arrive as one list. A rule this script cannot evaluate is
# never read as absent -- see "cannot evaluate" below. The caller must not let a
# failed `gh api` reach this script: a rule list that never arrived is indistinguishable
# from one with no rules, and the answer would be `lag` -- a fail-open. It
# captures the call's output first (`T=$(gh api ...) &&`) or redirects it to a file, and
# only then feeds this script, never `gh api | blocked-state.sh`, whose exit status a pipe
# discards (the same principle review-gate-state.sh states for its own input).
#
# Prints exactly one word to stdout and exits 0:
#   not-blocked        -- the state is not BLOCKED; this script has nothing to say
#   blocked            -- BLOCKED, and either `green` is 0 (a check red, pending or missing,
#                         a pinned check from the wrong app, an empty check list) or
#                         <reviewDecision> is CHANGES_REQUESTED: what the caller found
#                         wrong, not a rule, is what to report
#   awaiting-approval  -- BLOCKED, `green` is 1, <reviewDecision> is REVIEW_REQUIRED, and a
#                         `pull_request` rule that demands an approving review or a code
#                         owner's review applies: the approval is what the PR waits for, and
#                         only a human reviewer can give it. Printed before the "cannot
#                         evaluate" refusal below, because it is true whatever else is also
#                         unmet -- a later poll names that
#   lag                -- BLOCKED, `green` is 1, <reviewDecision> is APPROVED or NONE, and
#                         every rule that applies is one this script can evaluate and
#                         finds satisfied: usually GitHub is still re-evaluating. A rule
#                         type outside the list below (e.g. `workflows`) is ignored, so a
#                         `lag` that does not clear is still not proof of lag
# Exits 2, printing NOTHING to stdout, when the question cannot be answered: a wrong
# argument count, a state or a decision outside the documented vocabulary, a <green> that
# is not 0 or 1, a stdin line that is not a rule-type token optionally followed by
# key=value words, or -- the case #248 adds -- the state is BLOCKED, `green` is 1, no
# approval is awaited, and a rule this script cannot evaluate applies. The stderr line says
# why and NAMES those rules, which the pr-checks skill puts in the verdict text (it
# captures stderr). The CALLER decides policy for 2; pr-checks treats it as no verdict.
#
# Cannot evaluate (BLOCKED + green + no approval awaited only; a not-BLOCKED state, a red
# check or a pending approval says nothing about these, so `not-blocked`, `blocked` and
# `awaiting-approval` are unchanged):
#   required_deployments, code_scanning, required_signatures, merge_queue
#                         -- no state of the PR visible here says whether they are met
#   update                -- the restriction a bypass actor could get past. It is what the old
#                         admin-merge verdict was for; that verdict is gone (WB-D24), and
#                         nothing here reads bypass actors, so a green, approved PR that
#                         still reads BLOCKED under an `update` rule is not judged
#   pull_request          -- threads=true (reviewDecision cannot see an unresolved
#                         conversation) or reviewers>0 (it may not see required-reviewer
#                         teams), or a line missing any of the four words, which means the
#                         caller dropped the parameters. An approvals>0 or codeowner=true
#                         requirement IS evaluated, from <reviewDecision>: APPROVED means it
#                         is met, REVIEW_REQUIRED is `awaiting-approval`, and NONE next to
#                         such a rule contradicts it, so that is refused too
#   required_status_checks -- a line without `app_pinned=` means the caller dropped the
#                         parameters. app_pinned>0 is evaluated by the CALLER, inside
#                         <green> (a pinned context needs a run from its pinned app); the
#                         word is only validated here
# Bypass actors are deliberately not read: `current_user_can_bypass` is `never` to a
# non-admin viewer, so for the viewers who most need the answer it cannot be reached
# from here. The resume drift check reads them off the ruleset itself.
#
# What `lag` does not establish: a rule type outside the lists above (`workflows`,
# `commit_message_pattern`, ...) is ignored, not evaluated, and would read the same. So is
# the approval ruleset's "last push must be approved by someone other than its pusher", which
# no word on the line carries: an approval by the account that pushed last can leave
# reviewDecision APPROVED beside a PR GitHub still holds. The verdict is "required checks green,
# approval not outstanding, and no rule this script cannot evaluate", never "safe to merge".
# `rules/branches/<branch>` is believed to list only active rulesets; whether an
# evaluate-mode rule would also appear is unverified.
#
# Permitted toolset: POSIX sh and its standard utilities. No jq, no yq, no python.
LC_ALL=C; export LC_ALL        # the [a-z_] token class below must not depend on locale
set -u

if [ "$#" -ne 3 ]; then
  echo "blocked-state.sh: usage: blocked-state.sh <mergeStateStatus> <green> <reviewDecision>  (rule lines on stdin; see its header)" >&2
  exit 2
fi
state="$1"; green="$2"; decision="$3"

case "$state" in
  BEHIND | BLOCKED | CLEAN | DIRTY | DRAFT | HAS_HOOKS | UNKNOWN | UNSTABLE) ;;
  *) echo "blocked-state.sh: unrecognised mergeStateStatus: $state" >&2; exit 2 ;;
esac
case "$green" in
  0 | 1) ;;
  *) echo "blocked-state.sh: <green> must be 0 or 1, got: $green" >&2; exit 2 ;;
esac
case "$decision" in
  APPROVED | REVIEW_REQUIRED | CHANGES_REQUESTED | NONE) ;;
  *) echo "blocked-state.sh: <reviewDecision> must be APPROVED, REVIEW_REQUIRED, CHANGES_REQUESTED or NONE, got: $decision" >&2; exit 2 ;;
esac

wants_review=0
unseen=
# note <what>: record a rule this script cannot evaluate, once per distinct reason.
note() {
  case ", $unseen, " in *", $1, "*) ;; *) unseen="${unseen:+$unseen, }$1" ;; esac
}
set -f                                # the words below are validated, but never glob them
# `|| [ -n "$line" ]` keeps a final line that lacks a trailing newline.
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$(printf '\r')}"      # a Windows gh may end lines in CR
  case "$line" in
    '' | *[!a-z_=A-Z0-9\ ]* | ' '* | *' ' | *'  '*)
      echo "blocked-state.sh: stdin line is not a rule type plus key=value words: $line" >&2; exit 2 ;;
  esac
  rule="${line%% *}"; rest=
  case "$line" in *' '*) rest="${line#* }" ;; esac
  case "$rule" in
    '' | *[!a-z_]*) echo "blocked-state.sh: stdin line does not start with a rule-type token: $line" >&2; exit 2 ;;
  esac
  approvals= threads= codeowner= reviewers= pinned=
  for w in $rest; do
    # key=value, each key at most once and only on the type that owns it
    k="${w%%=*}"
    case "$rule:$k" in
      pull_request:approvals | pull_request:threads | pull_request:codeowner | pull_request:reviewers | required_status_checks:app_pinned) ;;
      *) echo "blocked-state.sh: a $rule line does not take the word: $w" >&2; exit 2 ;;
    esac
    case "$w" in
      approvals=[0-9]*) [ -z "$approvals" ] && approvals="${w#*=}" || approvals=dup ;;
      reviewers=[0-9]*) [ -z "$reviewers" ] && reviewers="${w#*=}" || reviewers=dup ;;
      app_pinned=[0-9]*) [ -z "$pinned" ] && pinned="${w#*=}" || pinned=dup ;;
      threads=true | threads=false) [ -z "$threads" ] && threads="${w#*=}" || threads=dup ;;
      codeowner=true | codeowner=false) [ -z "$codeowner" ] && codeowner="${w#*=}" || codeowner=dup ;;
      *) echo "blocked-state.sh: unrecognised word on a $rule line: $w" >&2; exit 2 ;;
    esac
  done
  case "$approvals$reviewers$pinned$threads$codeowner" in *dup*)
    echo "blocked-state.sh: a key is repeated on one line: $line" >&2; exit 2 ;;
  esac
  case "$approvals$reviewers$pinned" in *[!0-9]*)
    echo "blocked-state.sh: a count word is not a number: $line" >&2; exit 2 ;;
  esac
  # Counts are judged by pattern, never by `[ -gt ]`: an overlong count makes `[` error out,
  # which would skip the `note` below and read a non-zero requirement as zero.
  case "$rule" in
    update) note "update (a bypass actor's restriction; the admin-merge verdict was retired)" ;;
    required_deployments | code_scanning | required_signatures | merge_queue) note "$rule" ;;
    pull_request)
      if [ -z "$approvals" ] || [ -z "$reviewers" ] || [ -z "$threads" ] || [ -z "$codeowner" ]; then
        note "pull_request (parameters not supplied)"
      else
        # An approval or code-owner requirement is judged from reviewDecision, not noted.
        case "$approvals" in *[1-9]*) wants_review=1 ;; esac
        [ "$codeowner" = true ] && wants_review=1
        case "$reviewers" in *[1-9]*) note "pull_request names required reviewers" ;; esac
        [ "$threads" = true ] && note "pull_request requires review-thread resolution"
      fi ;;
    required_status_checks)
      [ -n "$pinned" ] || note "required_status_checks (parameters not supplied)" ;;
  esac
done

if [ "$state" != BLOCKED ]; then
  echo not-blocked
elif [ "$green" != 1 ] || [ "$decision" = CHANGES_REQUESTED ]; then
  echo blocked
elif [ "$decision" = REVIEW_REQUIRED ]; then
  if [ "$wants_review" = 1 ]; then
    echo awaiting-approval
  else
    echo "blocked-state.sh: reviewDecision is REVIEW_REQUIRED but no pull_request rule read here requires an approval or a code owner's review" >&2
    exit 2
  fi
elif [ "$decision" = NONE ] && [ "$wants_review" = 1 ]; then
  echo "blocked-state.sh: a pull_request rule requires an approval or a code owner's review, yet reviewDecision is NONE" >&2
  exit 2
elif [ -n "$unseen" ]; then
  echo "blocked-state.sh: cannot judge a green BLOCKED PR past rules it cannot evaluate: $unseen" >&2
  exit 2
else
  echo lag
fi
exit 0
