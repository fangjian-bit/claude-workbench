#!/bin/sh
# Has an armed auto-merge on an approved PR stalled?
#
# WB-D24 (#432): the code-owner approval is the control and the merge is mechanical.
# GitHub auto-merge sometimes does not fire under rulesets (scratch case c, #376: armed,
# APPROVED, CLEAN for over three minutes, never merged; community discussion 162623), which
# leaves an approved PR unmerged with nothing pointing at it. This predicate decides, from
# facts GitHub reports, whether that has happened. The `gh` reads, the merge call and the
# report stay in the skill (which today only reports); this script runs no `gh` and merges nothing -- the same shape as
# auto-merge-arm.sh and blocked-state.sh.
#
# The merge it permits would complete what the approval already allowed: every required rule
# is met (CLEAN), the PR's review decision is APPROVED under a base that requires a code-owner
# approval, the latest APPROVED review is on exactly the head, and the call would be pinned to
# that head (`--match-head-commit`), never `--admin`. The "latest APPROVED review" is any
# approver's, so where stale-review dismissal is off a non-owner approving a pushed head
# satisfies it -- GitHub's own auto-merge would merge that PR too; WB-D24 turns dismissal on.
# <mode> `app` is RESERVED: pr-checks passes `user` until it can prove the dev App from the
# token itself (#432 residual), so today this predicate only ever reports a stall (`stalled`).
#
# Usage: stall-merge.sh <mode> <armed> <approvals_required> <decision> <merge_state>
#                       <head_oid> <approved_oid> <approval_age_seconds>
#   <mode>                RESERVED `app` (the acting identity is a proven dev App) or `user`
#                         for anything else. pr-checks always passes `user` today.
#   <armed>               `true` when the PR has auto-merge enabled (`gh pr view --json
#                         autoMergeRequest`, non-null), else `false`.
#   <approvals_required>  as auto-merge-arm.sh: the largest `required_approving_review_count`
#                         of any ruleset `pull_request` rule on the PR's base that sets
#                         `require_code_owner_review`, 0 when none does. Without it an
#                         APPROVED decision could come from any identity GitHub counts.
#   <decision>            the PR's `reviewDecision`, `NONE` for the empty string: one of
#                         APPROVED, REVIEW_REQUIRED, CHANGES_REQUESTED, NONE.
#   <merge_state>         the PR's `mergeStateStatus`, as GitHub spells it.
#   <head_oid>            the PR's current `headRefOid`, 40 lowercase hex.
#   <approved_oid>        the `commit_id` of the latest APPROVED review, 40 lowercase hex.
#   <approval_age_seconds> seconds since that review was submitted, a non-negative integer.
#                         It stands in for "how long the PR has been mergeable": checks that
#                         finish after the approval make the true wait shorter, and a merge
#                         then is still the one auto-merge was about to make.
# Prints exactly one line, to stdout, and always exits 0 (the caller decides policy):
#   merge                  -- every condition holds and <mode> is `app`: merge, pinned to
#                             <head_oid>
#   stalled                -- every condition holds but <mode> is not `app`: report it; the
#                             merge is the human's
#   no-merge not-armed     -- auto-merge is not enabled; nothing is waiting to fire
#   no-merge no-approval   -- the base requires no code-owner approval; arming is not even
#                             allowed there (auto-merge-arm.sh), so an unarmed-by-design PR
#                             is not a stall
#   no-merge not-approved  -- <decision> is not APPROVED
#   no-merge not-clean     -- <merge_state> is not CLEAN (BLOCKED, BEHIND, DIRTY, UNSTABLE ...
#                             something is still holding the PR; HAS_HOOKS and UNSTABLE are
#                             not CLEAN either: only CLEAN means every required rule is met)
#   no-merge head-moved    -- the approval is not on the current head
#   no-merge too-soon      -- fewer than 180 seconds since the approval; auto-merge normally
#                             fires within seconds, so give it a few minutes
#   unreadable             -- wrong arguments, or a value outside the vocabulary above.
#                             Never `merge`: a value that cannot be read is not one to
#                             merge on
#
# All values are validated first, so an unreadable one reads `unreadable` whatever the
# others say. Values are compared exactly (merge state uppercase): a stray case or space is a
# value nobody has read. The conditions are then judged in the order above.
#
# Permitted toolset: POSIX sh. No jq, no yq, no python.
set -eu

if [ "$#" -ne 8 ]; then
  echo unreadable
  exit 0
fi
mode="$1"
armed="$2"
approvals="$3"
decision="$4"
state="$5"
head="$6"
approved="$7"
age="$8"

case "$mode" in app | user) ;; *) echo unreadable; exit 0 ;; esac
case "$armed" in true | false) ;; *) echo unreadable; exit 0 ;; esac
case "$approvals" in '' | *[!0-9]*) echo unreadable; exit 0 ;; *) ;; esac
case "$decision" in
  APPROVED | REVIEW_REQUIRED | CHANGES_REQUESTED | NONE) ;;
  *) echo unreadable; exit 0 ;;
esac
case "$state" in
  BLOCKED | BEHIND | UNKNOWN | CLEAN | HAS_HOOKS | UNSTABLE | DRAFT | DIRTY) ;;
  *) echo unreadable; exit 0 ;;
esac
for oid in "$head" "$approved"; do
  case "$oid" in
    *[!0-9a-f]*) echo unreadable; exit 0 ;;
  esac
  [ "${#oid}" -eq 40 ] || { echo unreadable; exit 0; }
done
case "$age" in '' | *[!0-9]*) echo unreadable; exit 0 ;; *) ;; esac

[ "$armed" = true ] || { echo "no-merge not-armed"; exit 0; }
case "$approvals" in
  *[!0]*) ;;
  *) echo "no-merge no-approval"; exit 0 ;;
esac
[ "$decision" = APPROVED ] || { echo "no-merge not-approved"; exit 0; }
[ "$state" = CLEAN ] || { echo "no-merge not-clean"; exit 0; }
[ "$head" = "$approved" ] || { echo "no-merge head-moved"; exit 0; }
# a decimal string of 10+ digits is far past 180; avoid shell integer overflow on huge input
[ "${#age}" -gt 9 ] || [ "$age" -ge 180 ] || { echo "no-merge too-soon"; exit 0; }

if [ "$mode" = app ]; then echo merge; else echo stalled; fi
