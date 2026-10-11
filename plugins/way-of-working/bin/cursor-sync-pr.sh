#!/bin/sh
# Is there exactly one open /way-of-working:handoff cursor-sync PR that
# /way-of-working:resume may offer the human to merge -- and if there is none, is
# this checkout standing on a sync branch nobody merged?
#
# Issue #215: handoff opens the `.ai/next-steps.md` sync as its own docs-only PR and
# never merges it -- the human's merge is the approval of the cursor the next session
# may run unattended (of the `next_action` itself only through resume's display, which
# shows it beside the ledger -- WB-D20). In practice that PR was regularly forgotten, so resume
# now finds it at session start and offers the merge on one explicit confirmation.
# Deciding WHICH PR is safe to offer is a deterministic predicate, so it lives here,
# tested, rather than in skill prose -- the same shape as cursor-drift.sh and
# milestone-close-line.sh. The display, the confirmation, and the merge itself stay
# in the skill; this script never merges.
#
# Usage: cursor-sync-pr.sh <repo> <pr_base> [<required_checks>]   (run from inside the checkout)
#   <required_checks> is a comma-separated list of check names (the caller passes
#   `{ruleset.required_checks}`, so this shared script names no repo value), matched
#   literally against CheckRun `name` and StatusContext `context`; a name containing a
#   comma, a backslash or a control character cannot be listed (it is never matched, so
#   it refuses). Omitted or empty is no evidence: a BLOCKED PR is then never
#   offered (#245).
# Prints exactly one line, to stdout, and always exits 0 (the caller decides policy):
#   none                    -- no open PR against <pr_base> whose head branch starts
#                              with `docs/sync-cursor-` (the name handoff's own step
#                              cuts), and HEAD is not on an unmerged sync branch
#   offer <N> <oid> <branch> -- exactly one such PR, passing every check below; <oid>
#                              is its head commit, which the caller must both display
#                              from and merge with `gh pr merge --match-head-commit`
#   refuse <N> <reason>     -- exactly one such PR, failing a check; <reason> is one of
#                              cross-repository | files | not-local | bypass-never |
#                              awaiting-approval |
#                              state-<mergeStateStatus, lowercased>
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
#     otherwise). This is the binding that makes the offer mean something. Same-repo
#     alone is not enough on a public repo: anyone with read access can open a PR from
#     an existing branch, and a repo that keeps merged branches holds dozens of stale
#     `docs/sync-cursor-*` heads (49 beside one live sync, on this plugin's own repo
#     when this was written), and the newest of them can pass every other check. And `.ai/state.json` -- where auto-start reads
#     the `next_action` it runs -- is git-ignored and machine-local, so only a sync PR
#     THIS machine's handoff produced describes it. A sync opened from another machine
#     is refused here; the human merges that one on GitHub. The binding does not catch a
#     sync PR the human closed unmerged and an outsider reopens as a new PR while the
#     local branch survives -- the display then shows the human the same text they
#     rejected, and the merge needs the human's pinned confirmation. The PR AUTHOR is
#     deliberately not checked: `author_association` is viewer-relative, and read by a
#     `gh` account other than the PR's author it reports `CONTRIBUTOR` for the repo's
#     own maintainer (observed live on PR #210).
#   - `mergeStateStatus` is CLEAN, or BLOCKED with every PRESENT check green, every name in
#     <required_checks> among them, and no blocking review (#229, #245; a REVIEW_REQUIRED one is refused as awaiting-approval, #384). Everything else -- BEHIND, DIRTY (conflicts, the usual
#     shape of a stale sync), DRAFT, UNSTABLE, UNKNOWN (GitHub still computing), and a
#     BLOCKED that fails that test -- is refused with its name, for the human.
#     Why BLOCKED is admitted at all: under a restrict-updates ruleset whose only bypass
#     actor is the repository admin role, GitHub reports BLOCKED to the admin on a PR
#     whose ONLY unmet rule is that restriction, so a CLEAN-only predicate never offers
#     anything on such a repo. But BLOCKED is also what a red or pending required check,
#     or a missing required review, looks like -- and resume's merge carries --admin,
#     which switches off gh's own client-side refusal. So this script tries to establish
#     "nothing but the restriction is unmet" itself, fail-closed: `statusCheckRollup`
#     non-empty with every entry green (CheckRun COMPLETED with SUCCESS, NEUTRAL or
#     SKIPPED; StatusContext SUCCESS -- an empty rollup is no evidence, so it is not
#     green), and `reviewDecision` not CHANGES_REQUESTED (REVIEW_REQUIRED is column 2, below). All
#     present checks, not only the required ones: stricter is the safe direction. And
#     every name in <required_checks> must itself be present as a green entry (#245): a
#     required check that never REPORTED (a workflow `paths:` filter that excludes `.ai/`,
#     a job not yet registered) is absent from the rollup and so could not turn the
#     all-green test to 0 on its own. An empty or missing list fails closed. A BLOCKED PR
#     on that evidence is offered like a CLEAN one, once the bypass check below passes too.
#     A BLOCKED PR whose checks are all green and present but whose `reviewDecision` is
#     REVIEW_REQUIRED is a different shape (#384, WB-D24): the code-owner approval is what
#     holds it, and no bypass is the answer. It is `refuse <N> awaiting-approval`, never
#     `state-blocked`, so resume can say a human's approval is awaited and never offers a
#     merge for it. (The jq below marks it `2` in the green column: checks green, review
#     pending.) A rule list that carries several rulesets needs no change here: the
#     bypass check below already reads every ruleset that has an `update` rule.
#     Residuals, stated so the confirmation is not mistaken for more than it is:
#       - <required_checks> is what the caller's working-tree `.ai/project.yml` says is
#         required (a branch that edited it changes it), not what the ruleset on <base>
#         currently requires: a context added to the ruleset and not to the file is not
#         looked for. Where the admin's bypass also covers the required-checks rule that
#         is the exposure; where the server enforces that rule (as on this plugin's own
#         repo) the merge is refused there.
#       - A name is matched by name only, with no binding to the app that posted it, so a
#         check of the same name from another workflow, or a commit status with that
#         context, satisfies it. It needs write access to produce.
#       - Any other rule the admin role can bypass and this script cannot see --
#         unresolved conversations, required deployments, code-scanning or merge-queue
#         rules -- is bypassed with it.
#       - Check or review state can change between the offer and the human's "yes";
#         --match-head-commit pins the commit, not its checks. Because the merge carries
#         --admin, this applies to a CLEAN offer too (gh's own re-check is switched off).
#       - `statusCheckRollup` may be capped by gh (believed 100 entries; unverified).
#     The human's confirmation, shown the ledger text, is what stands for all of these.
#   - A BLOCKED PR is offered only if the ACTIVE `gh` identity can bypass the
#     restrict-updates ruleset(s) (#250) -- not proof it can perform the whole merge: a
#     rule of another kind that the identity cannot bypass is not read here. `--admin` only switches off gh's client-side refusal; the server
#     applies the bypass per viewer. So for a BLOCKED PR this reads the rulesets with an
#     `update` rule on <base> (`gh api repos/<repo>/rules/branches/<base>`) and each
#     one's `current_user_can_bypass` (`gh api repos/<repo>/rulesets/<id>`):
#     `never` on any of them -> `refuse <N> bypass-never` (the caller names the identity
#     and sends the human to the web UI or a bypass-capable account); `always`,
#     `pull_requests_only` or `exempt` on all -> offered; no `update` rule at all -> the
#     restriction does not explain the BLOCKED, so `refuse <N> state-blocked`; a failed
#     call or any other value -> `unreadable`. A CLEAN PR needs no bypass and skips this.
#
# The branch prefix selects candidates; it is not a trust signal.
#
# Permitted toolset: POSIX sh and its standard utilities (cat, rm, tr, mktemp), git,
# `gh` (using only its own embedded --jq). No jq, no yq, no python, no awk.
set -u

tab="$(printf '\t')"
limit=200
prefix=docs/sync-cursor-

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ] || [ -z "$1" ] || [ -z "$2" ]; then
  echo "cursor-sync-pr.sh: usage: cursor-sync-pr.sh <repo> <pr_base> [<required_checks>]" >&2
  echo unreadable
  exit 0
fi
repo="$1"; base="$2"; required="${3:-}"
us="$(printf '\037')"

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
     --json number,headRefName,headRefOid,isCrossRepository,mergeStateStatus,files,statusCheckRollup,reviewDecision \
     --jq 'def green: (.__typename == "CheckRun" and .status == "COMPLETED"
                        and (.conclusion == "SUCCESS" or .conclusion == "NEUTRAL"
                             or .conclusion == "SKIPPED"))
                       or (.__typename == "StatusContext" and .state == "SUCCESS");
           length, (.[] | select(.headRefName | startswith("docs/sync-cursor-")) |
           [.number, .headRefName, .headRefOid, .isCrossRepository, .mergeStateStatus,
            (.files | length),
            (if (((.statusCheckRollup // []) | length) > 0
                 and all((.statusCheckRollup // [])[]; green)
                 and ((.reviewDecision // "") != "CHANGES_REQUESTED"))
             then (if (.reviewDecision // "") == "REVIEW_REQUIRED" then "2" else "1" end)
             else "0" end),
            ("\u001f" + ([(.statusCheckRollup // [])[] | select(green)
                          | (.name // .context) | select(type == "string" and (explode | all(. > 31)))]
                         | join("\u001f")) + "\u001f"),
            (.files[0].path // "")] | @tsv)' \
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
while IFS="$tab" read -r number branch oid cross state nfiles green names path rest || [ -n "$number" ]; do
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
  case "$green" in 0 | 1 | 2) ;; *) echo unreadable; exit 0 ;; esac
  case "$names" in "$us"*"$us") ;; *) echo unreadable; exit 0 ;; esac
  [ -z "${rest:-}" ] || { echo unreadable; exit 0; }
  count=$((count + 1))
  numbers="$numbers $number"
  c_number="$number"; c_branch="$branch"; c_oid="$oid"; c_cross="$cross"
  c_state="$state"; c_nfiles="$nfiles"; c_path="$path"
  c_green="$green"; c_names="$names"
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
  # Every required check must be present in the rollup as a green entry (#245). An
  # empty or missing list is no evidence, the same reading as an empty rollup. Only
  # BLOCKED reaches the green column's result, so this never changes a CLEAN offer.
  if [ "$c_green" != 0 ]; then
    was="$c_green"
    c_green=0
    if [ -n "$required" ]; then
      c_green="$was"; nwant=0
      oldifs="$IFS"; IFS=,; set -f
      for want in $required; do
        nwant=$((nwant + 1))
        case "$want" in '' | *"$us"*) c_green=0 ;; esac
        case "$c_names" in *"$us$want$us"*) ;; *) c_green=0 ;; esac
      done
      set +f; IFS="$oldifs"
      # Fail closed even if a non-empty list ever split into no fields.
      [ "$nwant" -ge 1 ] || c_green=0
    fi
  fi
  # Every check green and every required name present, but a review still required: the
  # approval rule (WB-D24) is what holds it, and only a human code owner can give that.
  # This is not a bypass question, so it never reaches the check below.
  if [ "$c_state" = BLOCKED ] && [ "$c_green" = 2 ]; then
    echo "refuse $c_number awaiting-approval"
    exit 0
  fi
  if [ "$c_state" != CLEAN ] && { [ "$c_state" != BLOCKED ] || [ "$c_green" != 1 ]; }; then
    lower="$(printf '%s' "$c_state" | tr 'A-Z' 'a-z')"
    echo "refuse $c_number state-$lower"
    exit 0
  fi
  if [ "$c_state" = BLOCKED ]; then
    # A BLOCKED offer rests on "only the restriction is unmet", and resume's merge
    # carries --admin, which gets past gh's client-side refusal only -- the server
    # still needs the ACTIVE identity to be a bypass actor (#250). So read the rules
    # applying to <base>: no `update` rule means the restriction does not explain the
    # BLOCKED; one whose ruleset reports current_user_can_bypass `never` means the
    # merge would be refused. `current_user_can_bypass` is viewer-relative, which is
    # the point: it answers for whichever account `gh` is active as.
    if ! gh api --paginate "repos/$repo/rules/branches/$base" \
         --jq '.[] | select(.type == "update") | .ruleset_id' \
         >"$tmp/ids" 2>"$tmp/err"; then
      echo "cursor-sync-pr.sh: gh api rules/branches/$base failed for $repo:" >&2
      cat "$tmp/err" >&2
      echo unreadable
      exit 0
    fi
    nids=0
    while IFS= read -r rid || [ -n "$rid" ]; do
      is_digits "$rid" || { echo unreadable; exit 0; }
      nids=$((nids + 1))
      # </dev/null: the loop's stdin is the ids file; nothing here may consume it.
      if ! bypass="$(gh api "repos/$repo/rulesets/$rid" \
           --jq '.current_user_can_bypass // ""' 2>"$tmp/err" </dev/null)"; then
        echo "cursor-sync-pr.sh: gh api rulesets/$rid failed for $repo:" >&2
        cat "$tmp/err" >&2
        echo unreadable
        exit 0
      fi
      case "$bypass" in
        always | pull_requests_only | exempt) ;;
        never) echo "refuse $c_number bypass-never"; exit 0 ;;
        *) echo unreadable; exit 0 ;;
      esac
    done <"$tmp/ids"
    if [ "$nids" -eq 0 ]; then
      echo "refuse $c_number state-blocked"
      exit 0
    fi
  fi
  echo "offer $c_number $c_oid $c_branch"
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
