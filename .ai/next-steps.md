# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**. Three lanes are building in parallel from approved specs: A #699, B #664, C #689.

**Just done (2026-10-17, driver session):**
- **Lanes C and B merged:** #689 (PR #712) and #664 (PR #716). #627 is still open; with its last child merged, it is ready to close.
- **`/way-of-working:plan-sprint`, two passes.** The maintainer accepted each recommendation whole.
  - #707–#710 went on milestone 19 as build-order steps ahead of the v0.20.0 release (#686).
  - Two new issues were filed and placed. #714, writing down and trialling the container lane procedure, is milestone 19 step 8, after #397. #715, the `lanes` skill, is milestone 20 step 7, the one Claude lane beside the maintainer's cutover checklists.
  - Every build-order write went through `milestone-desc.sh` (`live ok`, read back by hash), and each placed issue got a triage comment.
  - #223 and #334 stay unmilestoned. They already carried the same `[plan-sprint]` decision, so no new comment was posted.
  - #686's own waits-for list still names only #627, #629 and #689.
- **Milestone descriptions updated by the driver,** outside the skill, through the same `milestone-desc.sh` write (read back by hash).
  - Milestone 19's Done list and Lanes line now show #697, #689 and #664 merged. #397 waits only for lane A's #699. Every lane start after that is in the container.
  - #707 is held as #714's trial task, the first lane built inside the container.
  - Milestone 20 gained a Lanes line and #715's model-per-phase entries.
- **Maintainer's decisions:**
  - #397 comes after #699 merges.
  - A handoff runs before the cutover, and the driver then guides the maintainer through #397 step by step.
  - The successful #636 live run is not a prerequisite for #397, as recorded on #397 on 2026-10-16.

**Next:** as the driver session (the only session that writes `.ai/`), on **opus**:
1. When lane A opens #699's PR, run `/way-of-working:pr-checks` on it and report. Never merge or approve.
2. Once #664's and #689's lane sessions have closed, remove their worktrees (`../claude-workbench-664`, `../claude-workbench-689`) and branches.
3. After #699 merges, do the same for its worktree. No new host lane starts: #696, #629, #707 (the #714 trial), #708, #709 and #710 all start in the container after #397.
4. Run `/way-of-working:handoff`. Then, in a fresh session, guide the maintainer through #397 step by step. After the move, write and trial #714's procedure with #707 as the first container lane.
5. After the maintainer's second #636 live-run pass on scratch #27, record it as session 9 in `docs/proposals/IDENTITY-SCRATCH-RESULTS.md`.
   - #458 starts once its `BLOCKING` line holds. #398 and the v0.20.0 release (#686) come last.

**Lane rules.**
- Lane sessions never run `/resume`, `/handoff`, `/plan-sprint` or `/archive-sprint`.
- A lane starts with Seuss27's token passed per process, because a new worktree lacks the untracked `settings.local.json` hook: `GH_TOKEN=$(gh auth token -u Seuss27) claude --model sonnet` in Git Bash.
- A worktree is a different project directory, so this repo's memory does not load there. The lane prompt states the rules a lane needs:
  - test suites run in WSL (`wsl.exe -d Ubuntu -- setsid -w sh tests/<name>.test.sh`);
  - a commit that hangs on GPG signing is retried under `timeout 90`, then handed back;
  - the installed v0.19.0 lacks `spec-fresh.sh`, so a lane puts its own worktree's `plugins/way-of-working/bin` first on `PATH`.
- The lane prompt names the spec pin (`PIN_ID`, `PIN_UP`) from `spec-find.sh find`, the mode (`map`) and the critics.
- Every PR here needs a code-owner approval. Seuss27-authored PRs are approved by JaredGroves-603, and approving one with auto-merge armed merges it.
- `main`'s `spec-task` is ahead of v0.19.0, so a spec is drafted with `main`'s skill text and `main`'s `plugins/way-of-working/bin/`.
- `scripts/` and the spec predicates are human-only paths for the loop, so these items are built in interactive lanes, not by loop dispatch.
- A session that drafted a spec has read that issue's body, so it never builds that issue: a lane does.

**HITL Gate: NONE OPEN** — next gate: the maintainer approves each lane PR, and runs the second 636 live-run pass

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
