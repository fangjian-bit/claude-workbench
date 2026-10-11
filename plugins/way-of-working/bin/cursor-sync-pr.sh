#!/bin/sh
# Report on the /way-of-working:handoff cursor-sync PR, if there is exactly one open --
# and if there is none, say whether this checkout is standing on a sync branch nobody
# merged.
#
# Issue #215: handoff opens the `.ai/next-steps.md` sync as its own docs-only PR and
# never merges it. In practice that PR was regularly forgotten, so resume finds it at
# session start. Issue #385 (WB-D24): resume no longer offers to merge it -- a session
# holding a bypass-capable login is the exposure WB-D24 removes; the merge is the
# human's, or the code owner's approval where a repo has cut over. So this script only
# REPORTS: it never merges, never reads a check, a review or a ruleset, and a caller has
# nothing to bypass. Which PR qualifies is a deterministic
# predicate, so it lives here, tested, rather than in skill prose -- the same shape as
# cursor-drift.sh and milestone-close-line.sh.
#
# Usage: cursor-sync-pr.sh <repo> <pr_base>   (run from inside the checkout)
# Prints exactly one line, to stdout, and always exits 0 (the caller decides policy):
#   none                    -- no open PR against <pr_base> whose head branch starts
#                              with `docs/sync-cursor-` (the name handoff's own step
#                              cuts), and HEAD is not on an unmerged sync branch
#   open <N> <oid> <branch> -- exactly one such PR, passing every check below; <oid> is
#                              its head commit
#   refuse <N> <reason>     -- exactly one such PR, failing a check; <reason> is one of
#                              cross-repository | files | not-local
#   ambiguous <N> <N>...    -- more than one such PR (e.g. a forgotten earlier sync plus
#                              a newer one). Never pick one: two syncs regenerate the same
#                              file wholesale, so which is right is the human's call
#   unmerged <branch>       -- no such PR is open, but HEAD is on a `docs/sync-cursor-`
#                              branch whose tip no merged PR carries: handoff's push or
#                              PR creation failed, the human closed the PR unmerged, or
#                              it merged at a different commit (edited on GitHub, or the
#                              local branch moved on). Either way the local tip is not
#                              what was approved.
#                              Only an attached HEAD is checked: a detached HEAD reads
#                              `none`, as handoff never leaves one
#   unreadable              -- wrong arguments, not in a git checkout, a `gh` call
#                              failed, its output was not in the shape asked for, or the
#                              open-PR list hit its fetch limit (a candidate past the
#                              limit would otherwise read as `none`)
#
# The checks on a single candidate, and why each is the one it is:
#   - Same repository (`isCrossRepository` false). A fork PR is the outsider path.
#   - Changed files are exactly `.ai/next-steps.md`. Handoff keeps its PR to that one
#     file (its *Commit `.ai/next-steps.md` as its own docs-only PR* step calls that
#     load-bearing); anything wider is not a cursor sync, whatever its branch is named.
#     Park and unpark PRs share the branch prefix but also touch `.ai/parked/`, so they
#     land here too, on purpose.
#   - A LOCAL branch of the same name exists and its tip is exactly <oid> (`not-local`
#     otherwise). `.ai/state.json` -- where auto-start reads the `next_action` it runs --
#     is git-ignored and machine-local, so only a sync PR THIS machine's handoff
#     produced describes it. Same-repo alone is not enough on a public repo: anyone with
#     read access can open a PR from an existing branch, and a repo that keeps merged
#     branches holds dozens of stale `docs/sync-cursor-*` heads. A sync opened from
#     another machine is refused here; it is merged on GitHub like any other PR. The PR
#     AUTHOR is deliberately not checked: `author_association` is viewer-relative, and
#     read by a `gh` account other than the PR's author it reports `CONTRIBUTOR` for the
#     repo's own maintainer (observed live on PR #210).
#   The PR's merge state, checks and reviews are deliberately not read: nothing here acts
#   on them, so reading them would only invite a caller to.
#
# The branch prefix selects candidates; it is not a trust signal.
#
# Permitted toolset: POSIX sh and its standard utilities (cat, rm, tr, mktemp), git,
# `gh` (using only its own embedded --jq). No jq, no yq, no python, no awk.
set -u

tab="$(printf '\t')"
limit=200
prefix=docs/sync-cursor-

if [ "$#" -ne 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
  echo "cursor-sync-pr.sh: usage: cursor-sync-pr.sh <repo> <pr_base>" >&2
  echo unreadable
  exit 0
fi
repo="$1"; base="$2"

git rev-parse --git-dir >/dev/null 2>&1 || {
  echo "cursor-sync-pr.sh: not inside a git checkout" >&2
  echo unreadable
  exit 0
}

tmp="$(mktemp -d)" || { echo unreadable; exit 0; }
trap 'rm -rf "$tmp"' EXIT

# Line 1 is the total count of open PRs against <base>, so a list that hit the limit
# is detected rather than silently truncated. The prefix filter runs inside --jq so
# non-candidate titles and bodies never reach this script.
if ! gh pr list --repo "$repo" --base "$base" --state open --limit "$limit" \
     --json number,headRefName,headRefOid,isCrossRepository,files \
     --jq 'length, (.[] | select(.headRefName | startswith("docs/sync-cursor-")) |
           [.number, .headRefName, .headRefOid, .isCrossRepository,
            (.files | length), (.files[0].path // "")] | @tsv)' \
     >"$tmp/rows" 2>"$tmp/err"; then
  echo "cursor-sync-pr.sh: gh pr list failed for $repo (base $base):" >&2
  cat "$tmp/err" >&2
  echo unreadable
  exit 0
fi

is_digits() { case "$1" in '' | *[!0-9]*) return 1 ;; *) return 0 ;; esac; }
is_oid() {
  case "$1" in *[!0-9a-f]*) return 1 ;; esac
  [ "${#1}" -eq 40 ]
}

total=""
count=0
numbers=""
# `|| [ -n "$number" ]` keeps a final row that lacks a trailing newline.
while IFS="$tab" read -r number branch oid cross nfiles path rest || [ -n "$number" ]; do
  if [ -z "$total" ]; then
    is_digits "$number" && [ -z "$branch" ] || { echo unreadable; exit 0; }
    total="$number"
    continue
  fi
  [ -n "$number" ] || continue
  # Shape checks: anything not exactly what --jq was asked for is unreadable, never
  # a best-effort guess.
  is_digits "$number" || { echo unreadable; exit 0; }
  case "$branch" in "$prefix"?*) ;; *) echo unreadable; exit 0 ;; esac
  is_oid "$oid" || { echo unreadable; exit 0; }
  case "$cross" in true | false) ;; *) echo unreadable; exit 0 ;; esac
  is_digits "$nfiles" || { echo unreadable; exit 0; }
  [ -z "${rest:-}" ] || { echo unreadable; exit 0; }
  count=$((count + 1))
  numbers="$numbers $number"
  c_number="$number"; c_branch="$branch"; c_oid="$oid"; c_cross="$cross"
  c_nfiles="$nfiles"; c_path="$path"
done <"$tmp/rows"

[ -n "$total" ] && [ "$count" -le "$total" ] || { echo unreadable; exit 0; }
if [ "$total" -ge "$limit" ]; then
  echo "cursor-sync-pr.sh: $total open PRs against $base reached the fetch limit" >&2
  echo unreadable
  exit 0
fi

if [ "$count" -gt 1 ]; then
  echo "ambiguous$numbers"
  exit 0
fi

if [ "$count" -eq 1 ]; then
  if [ "$c_cross" != false ]; then
    echo "refuse $c_number cross-repository"
    exit 0
  fi
  if [ "$c_nfiles" != 1 ] || [ "$c_path" != ".ai/next-steps.md" ]; then
    echo "refuse $c_number files"
    exit 0
  fi
  local_tip="$(git rev-parse -q --verify "refs/heads/$c_branch^{commit}" 2>/dev/null)" || local_tip=""
  if [ "$local_tip" != "$c_oid" ]; then
    echo "refuse $c_number not-local"
    exit 0
  fi
  echo "open $c_number $c_oid $c_branch"
  exit 0
fi

# No open candidate. Is HEAD on a sync branch nobody merged? Read the FULL ref and
# strip `refs/heads/` ourselves: `--short` abbreviates only when the name is
# unambiguous, so a same-named tag would turn it into `heads/docs/...`, miss the
# prefix, and read as `none`.
current="$(git symbolic-ref -q HEAD 2>/dev/null)" || current=""
case "$current" in
  "refs/heads/$prefix"?*) current="${current#refs/heads/}" ;;
  *) echo none; exit 0 ;;
esac
tip="$(git rev-parse -q --verify HEAD 2>/dev/null)" || { echo unreadable; exit 0; }
if ! gh pr list --repo "$repo" --base "$base" --state merged --head "$current" \
     --limit "$limit" --json headRefOid --jq '.[].headRefOid' \
     >"$tmp/merged" 2>"$tmp/err"; then
  echo "cursor-sync-pr.sh: gh pr list (merged) failed for $current:" >&2
  cat "$tmp/err" >&2
  echo unreadable
  exit 0
fi
while IFS= read -r merged_oid || [ -n "$merged_oid" ]; do
  if [ "$merged_oid" = "$tip" ]; then
    echo none
    exit 0
  fi
done <"$tmp/merged"
echo "unmerged $current"
exit 0
