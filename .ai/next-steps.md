# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**. Milestone 19 is re-planned into lanes. No lane is building, and no spec is drafted yet for the next lanes.

**Just done (2026-10-17, driver session):**
- **#698 and #697 merged from their lanes.** #702 (`7d65a88`) closed #698 and #703 (`e9fdf87`) closed #697. Both specs were confirmed `found` with `spec-find.sh` before the lanes started.
- **`/way-of-working:plan-sprint` pass** (cursor sync #704, `522de10`).
  - Placed #689 and #696 on milestone 19. Left #223 and #334 unmilestoned; their earlier triage comments still hold.
  - Rewrote milestone 19's description: a fresh build order with `depends_on` markers and a **Lanes** section. The `BLOCKING` line is unchanged. Its Lanes line still says "#697 (PR open)": #697 has since merged.
  - Added #601, then #589, to milestone 22's build order.
  - Both writes went through `milestone-desc.sh`, read back `live ok`, and were not refused by the auto-mode classifier. The records are on #689, #696 and #399.
  - Milestones 13 and 14 are stale and were left alone on purpose: 13 is parked sprint-12's, and #404 re-plans it when it resumes.

**Next:** as the driver session (the only session that writes `.ai/`), on **opus**, following milestone 19's **Lanes** section:
1. Remove the merged lanes' worktrees and branches (`../claude-workbench-697`, `../claude-workbench-698`).
2. Draft the #699, #664 and #689 specs from `main` (`spec-task`, critic-gate to convergence with `architect` and `security-critic`, held for the maintainer).
   - Once the maintainer posts and reacts to each, confirm it with `spec-find.sh find <N>` and give its lane command and prompt.
   - Lane A: #699, then #696. Both edit `scripts/identity/wow-review`, so one at a time.
   - Lane B: #664, then #629 once #627 closes.
   - Lane C: #689, any time.
3. When a lane opens its PR, run `/way-of-working:pr-checks` on it and report. Never merge or approve.
4. The maintainer reinstalls the host tools into the 603 `WOW_HOME` from `main`, then runs the second #636 live-run pass on scratch #27 (items 1-8, 11 and 12 of `docs/identity/REVIEW-LIVE-RUN.md`). This session records it as session 9 in `docs/proposals/IDENTITY-SCRATCH-RESULTS.md`.
   - #458 starts once its `BLOCKING` line holds. #397 is the maintainer's. #398 and the v0.20.0 release (#686) come last.

**Lane rules.**
- Lane sessions never run `/resume`, `/handoff`, `/plan-sprint` or `/archive-sprint`.
- A lane starts with Seuss27's token passed per process, because a new worktree lacks the untracked `settings.local.json` hook.
- A worktree is a different project directory, so this repo's memory does not load there. The lane prompt states the rules a lane needs: test suites run in WSL (`wsl.exe -d Ubuntu -- setsid -w sh tests/<name>.test.sh`), and a commit that hangs on GPG signing is retried under `timeout 90`, then handed back.
- The lane prompt names the spec pin (`PIN_ID`, `PIN_UP`) from `spec-find.sh find`, the mode (`map`) and the critics.
- Every PR here needs a code-owner approval. Seuss27-authored PRs are approved by JaredGroves-603, and approving one with auto-merge armed merges it.
- `main`'s `spec-task` is ahead of v0.19.0, so a spec is drafted with `main`'s skill text and `main`'s `plugins/way-of-working/bin/`.
- `scripts/` and the spec predicates are human-only paths for the loop, so these items are built in interactive lanes, not by loop dispatch.
- A session that drafted a spec has read that issue's body, so it never builds that issue: a lane does.

**HITL Gate: NONE OPEN** — next gate: the maintainer runs the second 636 live-run pass, and posts and reacts to each held spec comment

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
