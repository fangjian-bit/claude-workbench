# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**. #697 and #698 have merged. Milestone 19's build order and lanes were re-planned. No lane is building.

**Just done (2026-10-17, driver session, after the cursor sync in #701):**
- **The #698 and #697 lanes merged.** #702 (`7d65a88`) closed #698 and #703 (`e9fdf87`) closed #697. Both specs were found approved before the lanes started.
- **`/way-of-working:plan-sprint` pass.**
  - Placed #689 (step 11) and #696 (step 6) on milestone 19.
  - Left #223 and #334 unmilestoned. Their earlier triage comments still hold, so none was re-posted.
  - Rewrote milestone 19's description: finished items moved to *Done*, #697, #699, #696 and #689 added, `depends_on` markers refreshed, and a new **Lanes** section. The `BLOCKING` line is unchanged.
  - Added #601 and #589 (after #601) to milestone 22's build order, with a lanes line.
  - Both description writes went through `milestone-desc.sh` and read back `live ok`. The records are on #689, #696 and #399.
  - Milestones 13 and 14 are stale (closed items listed, open ones missing) and were left alone on purpose: milestone 13 is parked sprint-12's, and #404 re-plans it when it resumes.

**Earlier (2026-10-17, driver session):**
- **v0.19.0 is released and pinned.** The release went out (#693, tagged `fe42df4`) and this repo's pin was bumped (#694). #394 is closed. The scratch repo was pinned (603-Identity/identity-ruleset-scratch#25).
  - Release-prep critic pass: `docs-consistency`, 2 rounds, converged. Round 2's wording fix was applied and not re-run.
- **Scratch repo set up for the live run.** It got the `architect-review` gate (scratch #26, opened by the admin App, because the dev App has no Workflows permission) and the matching required check in `wb-checks`.
- **First #636 live-run pass done.**
  - #695 fixed `wow-review`'s `docker start` failure (`compress=false`). Critic pass: `security-critic`, 1 round, converged.
  - Item 10 passed: the review was posted on scratch #27 and the gate went green. Item 9 passed. Results are in session 8 of `docs/proposals/IDENTITY-SCRATCH-RESULTS.md` (#700).
  - The run's findings were filed as #696, #697, #698 and #699.
- **The #663 and #682 lanes merged** (#691, #692). Their worktrees and branches are removed.
- **The #698 spec is drafted against `main` `e34ba33` and held.** It covers the exempt-check `jq` fix plus invariants check 20. Critic pass: 3 rounds, converged.
  - `architect` and `security-critic` ran rounds 1 and 2; `architect` alone ran round 3, which was clean.
  - Round 1 found a fail-open: a filter that names the wrong field passed a shape-only rule. The spec now compares the exact output.
- **The #697 spec is drafted against `e34ba33` and held.** It covers `/home/app` mounted with `exec` (the maintainer chose option 1), a start-time executable check, and `allowManagedHooksOnly` in the review image (the maintainer's call, after the critic found the SessionStart hook would start running).
  - Critic pass: 3 rounds, converged. Rounds 1 and 2 had both critics; round 3 had `architect` alone, and was clean.
  - `security-critic` tested `allowManagedHooksOnly` live in the review image.
  - One later edit was applied and not re-run. It rewords the literal home path as `$HOME`, because `spec-post.sh`'s leak filter refuses it.

**Next:** as the driver session (the only session that writes `.ai/`), on **opus**, following milestone 19's **Lanes** section:
1. Remove the merged lanes' worktrees and branches (`../claude-workbench-697`, `../claude-workbench-698`).
2. The maintainer reinstalls the host tools into the 603 `WOW_HOME` from `main`, then runs the second #636 live-run pass on scratch #27 (items 1-8, 11 and 12 of `docs/identity/REVIEW-LIVE-RUN.md`). This session records it as session 9.
3. Draft the specs from `main` (`spec-task`, critic-gate to convergence, held for the maintainer), then give one lane per approved spec:
   - Lane A: #699, then #696. Both edit `scripts/identity/wow-review`, so one at a time.
   - Lane B: #664, then #629 once #627 closes.
   - Lane C: #689, any time.
4. Lane D, #458, starts once the `BLOCKING` line holds (the #636 live run passed). #397 is the maintainer's, when the container cutover is ready. #398 and the v0.20.0 release (#686) come last.
   - #223 and #334 stay unmilestoned by choice.

**Lane rules.**
- Lane sessions never run `/resume`, `/handoff`, `/plan-sprint` or `/archive-sprint`.
- A lane starts with Seuss27's token passed per process, because a new worktree lacks the untracked `settings.local.json` hook.
- Every PR here needs a code-owner approval. Seuss27-authored PRs are approved by JaredGroves-603, and approving one with auto-merge armed merges it.
- `main`'s `spec-task` is ahead of v0.19.0 (#663 added `spec-fresh.sh shape`), so a spec is drafted with `main`'s skill text and `main`'s `plugins/way-of-working/bin/`.
- `scripts/` is a human-only path for the loop, so #697 and #698 are built in interactive lanes, not by loop dispatch.
- A session that drafted a spec has read that issue's body, so it never builds that issue: a lane does.

**HITL Gate: NONE OPEN** — next gate: the maintainer runs the second 636 live-run pass, and posts and reacts to each held spec comment

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
