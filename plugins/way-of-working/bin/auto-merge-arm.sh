#!/bin/sh
# May /way-of-working:ship arm auto-merge on the PR it just opened -- or is there nothing
# for arming to do, or nothing that would make it safe?
#
# WB-D24 (#386): "the human's merge is the approval" becomes "the human's code-owner
# approval is the approval". `ship` arms `gh pr merge --auto --squash --match-head-commit`
# so the merge itself is mechanical. That only holds where an approval is actually
# required: `gh pr merge --auto` MERGES IMMEDIATELY on a PR that is already mergeable
# (docs/proposals/IDENTITY-SCRATCH-RESULTS.md, case k), so on a base that needs no
# code-owner approval arming is an agent-run merge on green checks. Whether to arm is therefore a
# deterministic function of three facts GitHub reports, so it lives here, tested, rather
# than in skill prose -- the same shape as blocked-state.sh. The `gh` reads, the arming
# call and the report stay in the skill; this script runs no `gh` and merges nothing.
#
# Usage: auto-merge-arm.sh <allow_auto_merge> <approvals_required> <merge_state>
#   <allow_auto_merge>    the repo's `allow_auto_merge` (`gh api repos/<repo> --jq
#                         .allow_auto_merge`): `true` or `false`.
#   <approvals_required>  the largest `required_approving_review_count` of any ruleset
#                         `pull_request` rule that applies to the PR's base AND sets
#                         `require_code_owner_review` (0 when none
#                         does; classic branch protection is not read, and a count without
#                         code-owner review is not counted: any identity GitHub counts, an
#                         App's APPROVE included, could then trigger the merge), a
#                         non-negative decimal integer.
#   <merge_state>         the PR's `mergeStateStatus` (`gh pr view --json
#                         mergeStateStatus`), as GitHub spells it.
# Prints exactly one line, to stdout, and always exits 0 (the caller decides policy):
#   arm                       -- auto-merge is allowed, a code-owner approval is required, and the PR
#                                is waiting on something (BLOCKED, BEHIND or UNKNOWN). With
#                                an approval required a fresh PR cannot be mergeable yet,
#                                which is why UNKNOWN (GitHub's "not computed yet", the
#                                usual state right after `gh pr create`) may arm. Assumes the
#                                arming identity is not a bypass actor on the approval rule
#   not-armed disallowed      -- the repo does not allow auto-merge; arming would be
#                                refused, and enabling the setting is not ship's to do
#   not-armed no-approval     -- the base requires no code-owner approval, so nothing but
#                                green checks would stand between an armed PR and the merge
#   not-armed mergeable       -- the PR is already mergeable (CLEAN, HAS_HOOKS or UNSTABLE,
#                                where only non-required checks fail): arming would merge
#                                it now, and a merge is a decision, not a thing to arm
#   not-armed draft           -- a draft PR cannot be armed
#   not-armed conflicts       -- the branch conflicts with its base (DIRTY); arming
#                                would wait on a push that must come first
#   unreadable                -- wrong arguments, or a value outside the vocabulary above.
#                                Never `arm`: a value that cannot be read is not one that
#                                can be armed
#
# `disallowed` is judged first, then the approval count, then the merge state, so a repo
# that does not allow auto-merge reads the same whatever its PR looks like. Values are
# compared exactly, uppercase for the merge state: a stray case or space is a value nobody
# has read, and reads `unreadable`.
#
# Permitted toolset: POSIX sh. No jq, no yq, no python.
set -eu

if [ "$#" -ne 3 ]; then
  echo unreadable
  exit 0
fi
allow="$1"
approvals="$2"
state="$3"

case "$allow" in
  true) ;;
  false) echo "not-armed disallowed"; exit 0 ;;
  *) echo unreadable; exit 0 ;;
esac

case "$approvals" in
  '' | *[!0-9]*) echo unreadable; exit 0 ;;
  *) ;;
esac
case "$approvals" in
  *[!0]*) ;;
  *) echo "not-armed no-approval"; exit 0 ;;
esac

case "$state" in
  BLOCKED | BEHIND | UNKNOWN) echo arm ;;
  CLEAN | HAS_HOOKS | UNSTABLE) echo "not-armed mergeable" ;;
  DRAFT) echo "not-armed draft" ;;
  DIRTY) echo "not-armed conflicts" ;;
  *) echo unreadable ;;
esac
