---
name: pr-checks
description: >-
  Report the status of a PR's required checks and give an explicit merge-ready verdict
  WITHOUT merging. Run when asked whether a PR is green / ready to merge, or to poll a PR
  whose checks are still running. Reports ALL required checks (never a subset), decodes the
  skipped/BLOCKED/conflict traps, and never merges — a human's approval is the gate (the merge click, or the required approval an armed auto-merge waits on). It also reports an armed auto-merge that has stalled on an approved, clean PR.
---

# /way-of-working:pr-checks — report required-check status and merge-readiness (never merge)

Goal: answer "is PR #N ready to merge?" with a trustworthy, complete verdict — every
required check named and classified — and stop there. **Never** merge, `--approve`, or
force-push. A human's approval is the gate (the merge, or the approval an armed auto-merge waits on). This is a read-only status skill.

Argument: a PR number (e.g. `/way-of-working:pr-checks 94`). If none is given, resolve it from the
current branch with `gh pr view --json number,url` — and stop with "could not tell" unless
that `url` is under `{repo}`: a checkout whose remote is a fork or mirror would otherwise
resolve a different PR than the one every later call reads (`gh pr view --repo` cannot
resolve a PR without a number).

## The required checks

**Read `.ai/project.yml` first.** The required checks are the **union** of every declared
ruleset's `required_checks` — `{rulesets}` when that list is present (a checks ruleset and a
separate code-owner approval ruleset after a cutover, `WB-D24`), else the legacy
`{ruleset.required_checks}` (`reference/project-schema.md` § `rulesets`). Below,
`{ruleset.required_checks}` means that union:
```bash
yq -r '((.rulesets // [{"required_checks": .ruleset.required_checks}]) | [.[].required_checks // [] | .[]]) | unique | .[]' .ai/project.yml
```
It is the authoritative list — the checks the declared rulesets require on `{pr_base}`.

Report **every** name in that list, every time. A partial "looks green" is exactly the trap
that causes early merges. If a required check is *absent* from the results, that is a
finding, not a pass — a required check that never got created still blocks the merge.

Report **only** those names as required — plus, where the *Classify each required check*
step's `BLOCKED` bullet fetches them, any context the branch's own `required_status_checks`
rule names, reported as *also required by the branch's rule*. Other checks may run on the
PR; they are informational and must not be presented as gating, or the verdict overstates
what is actually enforced.

> **Without `.ai/project.yml`, this skill cannot give a verdict.** Say
> `no .ai/project.yml — cannot determine the required-check set` and report the raw
> `gh pr checks` output as *unclassified*. Never infer the required list from what happens
> to have run: a check can run without being required, and a required check can be absent
> entirely — which is the exact case worth catching.

## Steps

1. **Pull status in one shot.** Run:

   ```bash
   gh pr view <N> --repo {repo} --json number,title,mergeable,mergeStateStatus,reviewDecision,isDraft,headRefName,headRefOid,baseRefName,autoMergeRequest,url
   gh pr checks <N> --repo {repo}         # per-check state (pass/fail/pending/skipping)
   ```

   Every `gh pr` call in this skill that takes the PR number names `--repo {repo}` (the
   argument-resolution call above checks the repo instead), so the PR state and the rules
   read below come from the same repository. The view comes **first** on purpose: a push
   or a retarget between the two calls then shows up when `headRefOid` and `baseRefName`
   are re-read before a verdict that depends on them (see *AWAITING APPROVAL*),
   rather than being absorbed into the checks.

   `gh pr checks` exits non-zero when any check is failing/pending — that is expected, not
   an error; read its output regardless.

2. **Classify each required check.** Report `green` / `red` / `pending` / `absent` for
   every name in `{ruleset.required_checks}` — the same word the *Read the review gate on
   both surfaces it can post to* step's predicate uses for the identical fact on the
   review-gate check, so a reviewer never sees two words for one state. Then decode the ambiguous states — this is where the value is:

   - **`skipped` ≠ `failure`, but also ≠ a free pass.** A job can report `skipped` two ways:
     (a) a *deliberate condition* — e.g. on a PR touching none of `{code_paths}`, a test
     job's steps may short-circuit, and a review gate may be exempt. Those skips are
     legitimately green-equivalent. (b) a `needs:` dependency **failed** — the downstream
     job then reports `skipped` too. That is a *red*, masquerading. Confirm which by
     checking whether any upstream job actually failed before you call a skip benign.
   - **`mergeStateStatus: BLOCKED` with nothing red or pending** has three readings, and
     the branch's rules and the PR's `reviewDecision` decide which. Under the code-owner
     approval gate (`WB-D24`) a green PR reads `BLOCKED` until a code owner approves it, to
     every viewer — waiting never clears that. Once approved it is usually GitHub
     re-evaluation lag, though a rule that holds a PR at `BLOCKED` the same way (an
     unresolved conversation, a required deployment, an `update` rule) can be the cause.
     Let the tested predicate say which (`#224`, `#384`); it reads the approval from
     `reviewDecision`, and it refuses to answer when a rule it cannot evaluate applies
     (`#248`). There is no admin-merge reading: nothing here advises bypassing a rule.

     The branch to read the rules for is the PR's own base (`baseRefName`), never
     `{pr_base}` — a PR into another branch is judged by that branch's rules. **A branch
     name is untrusted text** (git allows `$`, `(`, `;`, `&` and `|` in one), so it is
     read **inside** each block, validated, and used only as `"$B"` — never typed into a
     command by hand, which is how an attacker's branch name would run on this machine
     (`bin/review-base-anchor.sh` reads its branch inside the script too, though it
     validates with `git check-ref-format` rather than a character set). Two blocks, each one
     chain, for the same reason the review-gate block below is one — a failed call must
     never reach what follows it:

     ```bash
     # (a) the contexts the branch's own required_status_checks rule names
     B=$(gh pr view <N> --repo {repo} --json baseRefName -q .baseRefName) &&
     case "$B" in '' | *[!A-Za-z0-9._/-]*) false ;; esac &&
     gh api --paginate "repos/{repo}/rules/branches/$B" \
       --jq '.[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context'
     ```

     If (a) fails, the verdict is COULD NOT TELL and (b) is not run — never compute
     `<green>` from `{ruleset.required_checks}` alone, which is the stale-list failure this
     call exists to close.

     A context the rule **pins to an app** (`integration_id`) is met only by a run that app
     posted: a same-named check from another workflow, or a commit status, does not count.
     The rollup the checks above are read from cannot say which app posted a run, so block
     (a2) reads the head commit's check-runs, which carry `app.id`:

     ```bash
     # (a2) every context the branch's rule pins to an app has a passing run from that app
     B=$(gh pr view <N> --repo {repo} --json baseRefName -q .baseRefName) &&
     case "$B" in '' | *[!A-Za-z0-9._/-]*) false ;; esac &&
     P=$(gh api --paginate "repos/{repo}/rules/branches/$B" --jq '.[] | select(.type=="required_status_checks") | .parameters.required_status_checks[]? | select(.integration_id != null) | "\(.integration_id) \(.context)"') &&
     S=$(gh pr view <N> --repo {repo} --json headRefOid -q .headRefOid) &&
     R=$(gh api --paginate "repos/{repo}/commits/$S/check-runs" --jq '.check_runs[] | select((.name | test("\n") | not) and .status=="completed" and (.conclusion=="success" or .conclusion=="neutral" or .conclusion=="skipped")) | "\(.app.id) \(.name)"') &&
     U=$(printf '%s\n' "$P" | while IFS= read -r pin; do
           [ -n "$pin" ] || continue
           printf '%s\n' "$R" | grep -Fxq -- "$pin" || printf 'unmet %s\n' "$pin"
         done) &&
     { [ -n "$U" ] && printf '%s\n' "$U" || echo pins-ok; }
     ```

     `pins-ok` (also what a rule with no pinned context prints) leaves `<green>` as the
     checks above decide; any `unmet` line makes `<green>` `0` and is named in the report as
     a check that only counts from its pinned app. A failed call is COULD NOT TELL, as for (a).

     ```bash
     # (b) ask the predicate
     B=$(gh pr view <N> --repo {repo} --json baseRefName -q .baseRefName) &&
     case "$B" in '' | *[!A-Za-z0-9._/-]*) false ;; esac &&
     T=$(gh api --paginate "repos/{repo}/rules/branches/$B" --jq '.[] | .type + (if .type=="pull_request" then " approvals=\(.parameters.required_approving_review_count // 0) threads=\(.parameters.required_review_thread_resolution // false) codeowner=\(.parameters.require_code_owner_review // false) reviewers=\([.parameters.required_reviewers[]?] | length)" elif .type=="required_status_checks" then " app_pinned=\([.parameters.required_status_checks[]? | select(.integration_id != null)] | length)" else "" end)') &&
     { [ -z "$T" ] || printf '%s\n' "$T"; } | blocked-state.sh BLOCKED <green> <decision> 2>&1
     ```

     `<decision>` is the `reviewDecision` the first step read, with the empty string (no
     review rule applies) written `NONE` — one of `APPROVED`, `REVIEW_REQUIRED`,
     `CHANGES_REQUESTED`, `NONE`; the predicate refuses anything else.

     The rule list is captured first (`T=$(…) &&`), so a failed `gh api` stops the chain
     before the predicate — a pipe straight from `gh` would hide that failure — and the
     pipeline's status is the predicate's own. An empty `T` (no rules apply) sends nothing,
     which the predicate reads as "no rule applies". The list is every ruleset's rules on
     the branch, so a checks ruleset and a separate approval ruleset arrive together. Each line is a rule type, plus
     `key=value` words for the two types whose parameters matter (`pull_request`,
     `required_status_checks`), so the predicate can see an approval count, thread
     resolution, code-owner review, required reviewers, or a check pinned to an app (`#248`). `2>&1` is so that
     when the predicate refuses (exit 2, nothing on stdout) its one stderr line, which
     names the rules it cannot evaluate, reaches this session to be quoted in the verdict.

     `<green>` is `1` only when **all** of these hold, otherwise `0`: every check in the
     union of `{ruleset.required_checks}` **and** the contexts (a) printed is green (or
     legitimately skipped), with none pending, red, or missing a run; `{ruleset.required_checks}`
     is not empty (an empty list is no evidence, not a vacuous pass); and block (a2) printed
     no `unmet` line. The review is **not** part of `<green>` — `<decision>` carries it. A
     context (a) names that is not in `{ruleset.required_checks}` is reported as *also
     required by the branch's rule* — it gates the merge, so it is not "informational". The
     script's header carries the rest.
     This block runs only for a `BLOCKED` PR, so the script's fourth word, `not-blocked`,
     never comes from it. Read what it prints strictly: **exactly one** of these three
     words is an answer, and
     anything else — no output, a different word, a non-zero status — is "could not tell":
     - **`lag`** — every check is green, no approval is outstanding, and no rule the
       predicate cannot evaluate applies. Usually GitHub is still re-evaluating: say so
       and wait — do **not** intervene, re-run, or push. The predicate has already
       ruled out the rules it can evaluate; if it persists, a rule type it ignores
       (`workflows`, say) may be holding the PR. The verdict is PENDING, below.
     - **`awaiting-approval`** — every check is green and the approval rule is what holds
       the PR: `reviewDecision` is `REVIEW_REQUIRED`. Not lag; do not say wait. Only a
       human reviewer can give it (a code owner, where the rule requires one). The verdict is AWAITING APPROVAL, below.
     - **`blocked`** — the checks, the review, or the check list are not in order
       (including an empty `{ruleset.required_checks}`, a context (a) named that has no
       run, a pinned context (a2) that only a different app posted, or a `reviewDecision` of
       `CHANGES_REQUESTED`); report those, not the rule. The verdict is NOT READY or
       PENDING by what is actually wrong.
     - **Could not tell** (exit 2, a failed call, or any other output) — never lag and
       never ready. The verdict is COULD NOT TELL, below. When the output is the
       predicate's `cannot judge a green BLOCKED PR past rules it cannot evaluate: <rules>`
       line, the rules it names (an `update` rule, thread resolution, a required
       deployment …) are the reason; quote them in the verdict instead of a generic
       caveat. A line saying `reviewDecision` contradicts the rules it was given is also
       this verdict: the rule list or the decision is wrong, and neither is guessed at.
   - **`mergeable: CONFLICTING`** = the PR is out of date / has conflicts and may be
     running **zero** CI silently. GitHub cannot build the merge ref when a PR is not
     mergeable, so `pull_request` workflows never start — and zero checks looks almost
     identical to checks still queuing. A "green" here proves nothing. Flag it and note the
     branch needs refreshing (merge `{pr_base}` *into* the branch — never force-push).
   - **`isDraft: true`** — checks may be intentionally incomplete; surface it.

3. **Read the review gate on both surfaces it can post to** — only when `{review.ci_gate}`
   is set. Skip this step entirely when it is `null`; there is no review check to go stale.

   A review gate reaches a commit as a **check-run** (the implicit one a workflow job
   creates, named after the job) or as a **commit status** (posted explicitly against the
   resolved head SHA by a job that may be named anything — invisible to a check-runs
   query, which is how this step used to miss it). Read both and let the tested predicate
   resolve them; its header carries the rule — any success on either surface is `success`,
   because a posted review cannot be un-posted; `pending` beats `failure`; `absent` means
   neither surface carries the name:

   ```bash
   SHA=$(gh pr view <N> --repo {repo} --json headRefOid -q .headRefOid) && T=$(mktemp -d) &&
   gh api --paginate "repos/{repo}/commits/$SHA/status" \
     --jq '.statuses[] | ["status", .context, .state] | @tsv' > "$T/s.tsv" &&
   gh api --paginate "repos/{repo}/commits/$SHA/check-runs" \
     --jq '.check_runs[] | ["check-run", .name, .status, (.conclusion // "")] | @tsv' > "$T/c.tsv" &&
   cat "$T/s.tsv" "$T/c.tsv" > "$T/gate.tsv" &&
   review-gate-state.sh "{review.ci_gate.check}" < "$T/gate.tsv"
   ```

   Run it as **one** block: the `&&` chain is load-bearing, because a `gh api` call or a
   file read that failed must never reach the predicate — a document that never arrived
   reads as `absent` — and shell state does not survive between tool calls. On exit 0 its
   stderr line says what each surface carried: **say which shape the gate took** in the
   report. Exit 2 (nothing on stdout) means it could not answer — treat that as not green.

   **The superseded-run trap.** A repo whose gate fires on both `pull_request` and
   `pull_request_review` gets *two* `{review.ci_gate.check}` check-runs on one commit: the
   first fails correctly (no review posted yet), the second passes once the review is
   posted — and **the failed one never self-clears**. The signature is the predicate
   reading `success` while `mergeStateStatus` is `BLOCKED` with a failing rollup, a
   `failure` of the gate's name still on the SHA beside the `success`:

   ```bash
   SHA=$(gh pr view <N> --repo {repo} --json headRefOid -q .headRefOid) &&
   gh api --paginate "repos/{repo}/commits/$SHA/check-runs" \
     --jq '.check_runs[] | select(.name=="{review.ci_gate.check}") | {id, conclusion, url: .html_url}'
   ```

   A status-shaped gate wears the same trap in a different coat: the job that posted the
   green status keeps its own red check-run, under its *job* name, until re-run. Where that
   job's name is not in `{ruleset.required_checks}` it blocks nothing and the verdict is
   READY with a note;
   where it is, treat it exactly as above. Either way the fix is to
   **re-run the stale failed run** — `gh run rerun <old_failed_run_id>` (the run id is in
   the failed check-run's URL) — and **never a new push**: a push changes the SHA and
   re-arms the trap. Re-running a stale CI check is not merging, approving, or
   force-pushing; it is the one sanctioned write this skill makes, only on this exact,
   confirmed signature, and only a run id reached from a check-run whose name is
   `{review.ci_gate.check}` or in `{ruleset.required_checks}` — a rerun re-executes that
   whole workflow run, so the name pins which run you may pick, not what runs.

4. **State a single explicit verdict.** One of:
   - **READY** — every check in `{ruleset.required_checks}` is green (or legitimately
     skipped per the *Classify each required check* step's (a)) **and** `mergeable` is not
     `CONFLICTING` **and** `mergeStateStatus` is not `BLOCKED` — a `BLOCKED` PR is never
     plain READY: it is AWAITING APPROVAL, PENDING, NOT READY or COULD NOT TELL by what
     `blocked-state.sh` printed (the *Classify each required check* step's bullet maps each
     word). Tell the user "PR #N is
     ready to merge — merge it yourself; I will not." List every required check with its
     state so the readiness is auditable.
   - **AWAITING APPROVAL** — `blocked-state.sh` printed `awaiting-approval`: every required
     check is green and the approval rule is what holds the PR (`reviewDecision` is
     `REVIEW_REQUIRED`). Tell the user "PR #N into `<baseRefName>` has every required check
     green and is waiting for an approval — a human gives it, never me; once
     given, and if nothing else is unmet, it merges (auto-merge, if armed) or you merge it."
     Under the WB-D24 approval ruleset the approval must come from a code owner other than the account that pushed the PR's
     last commit, so a PR whose author is the only code owner cannot approve itself:
     the human then has to go through the dev App or the org owner's break-glass step
     (`WB-D24`), which is theirs to do. Re-read `headRefOid` **and** `baseRefName`
     (`gh pr view <N> --repo {repo} --json headRefOid,baseRefName`) just before stating this
     verdict: if either differs from what the *Pull status in one shot* step read, a push or
     a retarget landed since, the checks describe something else, and any approval already
     given may have been dismissed — start over from that step. List every required check
     with its state. This verdict names no merge command: nothing in it advises a bypass,
     and `blocked-state.sh` reads no bypass actor.
   - **STALE-RED (auto-clearable)** — only possible when `{review.ci_gate}` is set. The
     *Read the review gate on both surfaces it can post to* step's predicate reads
     `success` and the *only* red is a superseded run of the gate's name (or, on a
     status-shaped gate, its required runner job) on the head SHA — that step's signature.
     This is not a real failure.
     Offer to `gh run rerun <old_failed_run_id>` (or, in a `/loop`/scheduled context, do it
     and re-poll); it clears to READY (or AWAITING APPROVAL, once the checks are green) with no
     push. Say clearly this is the stale-run
     workaround, not a merge.
   - **NOT READY (red)** — a *genuine* failure (any red that is not the stale-red above).
     Name every failing check and, for each, the one-line reason from its job log
     (`gh run view <run-id> --job <job-id> --log` grep'd to the failure). Also the verdict
     when `blocked-state.sh` printed `blocked` with every present check green: say the
     review is blocking (`reviewDecision`), that a context the rule pins to an app has no passing run from that app (block (a2), also true of one posted only as a commit status), that `{ruleset.required_checks}` is empty, or
     name the branch-rule context with no run (*also required by the branch's rule*) when
     it is not merely queued — a run that has not started yet is PENDING, not red.
   - **PENDING** — name which checks are still running; or, when `blocked-state.sh`
     printed `lag` and nothing is running, say GitHub is still re-evaluating the merge
     state — or that a rule type the predicate ignores is holding it.
     If invoked from a `/loop` or a scheduled run, reschedule
     another poll, but **bound it**: after a few polls with nothing changing, say so and
     stop rescheduling rather than waiting on a state that will not clear. Otherwise tell
     the user it's still running and offer to re-check.
   - **COULD NOT TELL** — a call this verdict depends on failed, or `blocked-state.sh`
     printed anything but one of the three words the *Classify each required check* step's
     bullet lists (including `not-blocked`, which that block should never produce). Say
     which — when it is the predicate's `cannot judge … rules it cannot evaluate: <rules>`
     line, name those rules, so the human knows what to check by hand — and give no
     merge-ready verdict.

5. **Report a stalled auto-merge (`WB-D24`, `#432`).** Only when the first step's
   `autoMergeRequest` is non-null (auto-merge is armed); otherwise skip it and say nothing.
   GitHub's auto-merge sometimes does not fire under rulesets: an approved, `CLEAN` PR with
   auto-merge armed can sit unmerged with nothing pointing at it. This step points at it. It
   **only reports**: which App holds the token is not established here (`resume` says the same,
   `reference/conventions.md` § *Acting identity and reach*), so no agent merges. The tested
   predicate (`stall-merge.sh`, bare name on `PATH`) decides from facts GitHub reports; never
   judge them by eye and never pipe `gh` output into it. The mode argument is always the
   literal `user`: `app` is reserved for the follow-up that proves the dev App from the token.
   **Run the whole block in one Bash call** — each call is a fresh shell, and the head read
   here is the one the command is pinned to:
   ```bash
   PRV=$(gh pr view <N> --repo {repo} --json headRefOid,baseRefName,reviewDecision,mergeStateStatus,autoMergeRequest \
           --jq '[.headRefOid, .baseRefName, (.reviewDecision | if . == "" then "NONE" else . end), .mergeStateStatus, (.autoMergeRequest != null), (.autoMergeRequest.mergeMethod // "-")] | @tsv') &&
   HEAD=$(printf '%s' "$PRV" | cut -f1) && B=$(printf '%s' "$PRV" | cut -f2) &&
   DEC=$(printf '%s' "$PRV" | cut -f3) && STATE=$(printf '%s' "$PRV" | cut -f4) &&
   ARMED=$(printf '%s' "$PRV" | cut -f5) && METHOD=$(printf '%s' "$PRV" | cut -f6) &&
   case "$B" in '' | *[!A-Za-z0-9._/-]*) false ;; esac &&
   RULES=$(gh api --paginate "repos/{repo}/rules/branches/$B") &&
   APPR=$(printf '%s' "$RULES" | jq -s '[.[][] | select(.type == "pull_request" and .parameters.require_code_owner_review == true)
            | .parameters.required_approving_review_count] | max // 0') &&
   REVS=$(gh api --paginate "repos/{repo}/pulls/<N>/reviews") &&
   REV=$(printf '%s' "$REVS" | jq -s -r '[.[][] | select(.state == "APPROVED")] | last
            | if . == null then "0000000000000000000000000000000000000000 0"
              else "\(.commit_id) \(now - (.submitted_at | fromdateiso8601) | floor | if . < 0 then 0 else . end)" end') &&
   AOID=${REV% *} && AGE=${REV#* } &&
   V=$(stall-merge.sh user "$ARMED" "$APPR" "$DEC" "$STATE" "$HEAD" "$AOID" "$AGE") || V=unreadable
   echo "Stall check: $V"
   case "$METHOD" in SQUASH) F=--squash ;; MERGE) F=--merge ;; REBASE) F=--rebase ;; *) F= ;; esac
   if [ "$V" = stalled ]; then
     if [ -n "$F" ]; then echo "Command: gh pr merge <N> --repo {repo} $F --match-head-commit $HEAD"
     else echo "Command: not printed (the armed merge method could not be read)"; fi
   fi
   ```
   The head is pinned in the command so a push after this read makes it refuse; it is the
   human's to run (or not), and it is never `--admin`. Report the printed line:
   - **`stalled`** — GitHub reports the PR approved, clean and armed, and auto-merge has not fired. Give the printed command **only when the verdict above is READY**; if it is anything else (the declared checks disagree with the live ruleset, or a read failed), report the disagreement and give no command. Say
     so, give the printed command, and add that re-approving is the cheaper remedy if the
     approver is at hand (not a proven cause). Name no bypass. Where no command is printed,
     the armed merge method could not be read: say so rather than guessing one.
   - **`merge`** — impossible while the mode argument is `user`; if it ever prints, treat it as
     COULD NOT TELL for this step and report that the predicate disagrees with the skill.
   - **`no-merge <reason>`** — there is no stall to report. `not-armed`, `no-approval` and
     `not-approved` mean nothing is waiting to fire; `not-clean` is whatever the *Classify
     each required check* step already reports; `head-moved` means the approval is not on this
     head; `too-soon` means auto-merge is likely still about to fire, so say wait and re-check, and that the human need not merge it yet even though the verdict reads READY.
   - **`unreadable`**, or a failed read — report it. It changes no other verdict.

6. **Never act on the PR.** No `gh pr merge`, no `gh pr review --approve`, no
   `git push --force`, ever. If the user asks you to merge, confirm the verdict is READY and
   hand it back — the merge is theirs, or auto-merge's once it is approved; and approving is
   a human reviewer's, never this skill's. This skill never names a bypass in any verdict.
   The **only** sanctioned write is `gh run rerun <old_failed_run_id>` on a **confirmed** stale review
   run (the *Read the review gate on both surfaces it can post to* step).

## Report shape

List every required check by name with its state, then the merge state, then one verdict
line. The example below is shaped for an 8-check repo with a review gate; the names and the
count come from `{ruleset.required_checks}`, so a repo with four checks prints four. A
required check with no run on the head SHA prints as `absent` — never omitted — the same
word the *Classify each required check* and *Read the review gate on both surfaces it can
post to* steps use for the identical fact.

```
PR #94 — "test(core): land the mutation-audit fix verdicts" (sprint/38-t3 → main)

  lint             ✅ pass        secrets-scan       ✅ pass
  format-check     ✅ pass        dependency-audit   ✅ pass
  test             ✅ pass        sbom               ✅ pass
  pr-title         ✅ pass        <review gate>      ✅ pass (docs-only, exempt)

  mergeable: MERGEABLE   state: CLEAN

Verdict: READY — all 8 required checks green. Merge it yourself when you're ready; I won't.
```

On a repo whose branch requires a code-owner approval the state line reads `state: BLOCKED`
until one is given, and the verdict line is `Verdict: AWAITING APPROVAL into main — all 8
required checks green (plus any contexts the branch rule names, listed); the code-owner
approval is why it reads BLOCKED. A human gives it; I won't.`

When the PR has auto-merge armed, a `Stall check:` line follows the verdict (the *Report a
stalled auto-merge* step). A `stalled` result is a READY PR the armed auto-merge has not
merged: print the pinned command under the verdict and leave the merge to the human.
