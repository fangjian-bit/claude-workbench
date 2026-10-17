# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**. Three lanes are building in parallel from approved specs: A #699, B #664, C #689.

**Just done (2026-10-17, driver session):**
- **`/way-of-working:plan-sprint` placed the four follow-ups on milestone 19,** as build-order steps 13–16, ahead of the v0.20.0 release (#686, now step 17). The maintainer accepted the recommendation whole.
  - #707: waits for nothing. #708: waits for #689 and #707. #709 and #710: wait for #664.
  - The build-order write went through `milestone-desc.sh` (`live ok`, read back by hash). Each of the four issues got a triage comment.
  - #223 and #334 stay unmilestoned. They already carried the same `[plan-sprint]` decision, so no new comment was posted.
  - #686's own waits-for list still names only #627, #629 and #689. The release does not formally wait for #707–#710.
- **Milestone 19's Lanes line corrected by the driver,** outside the skill, through the same `milestone-desc.sh` write (read back by hash). #697 is merged and listed as done. A, B and C are marked building. Lane C now queues #707 and #708, then #709 and #710 once #664 merges.

**Next:** as the driver session (the only session that writes `.ai/`), on **opus**:
1. When a lane opens its PR, run `/way-of-working:pr-checks` on it and report. Never merge or approve.
   - Lane A: #699 in `../claude-workbench-699`.
   - Lane B: #664 in `../claude-workbench-664`.
   - Lane C: #689 in `../claude-workbench-689`.
   - #664 and #689 both append to `CHANGELOG.md`; whichever merges second rebases and keeps both lines.
2. After #699 merges, remove its worktree and branch, then draft #696's spec from `main` for lane A (`spec-task`, critic-gate to convergence with `architect` and `security-critic`) and give its lane command. #629 follows #664 in lane B once #627 closes.
3. After #689 merges, do the same for lane C: draft #707's spec, then #708's. #709 and #710 follow once #664 merges.
4. After the maintainer's second #636 live-run pass on scratch #27, record it as session 9 in `docs/proposals/IDENTITY-SCRATCH-RESULTS.md`.
   - #458 starts once its `BLOCKING` line holds. #397 is the maintainer's. #398 and the v0.20.0 release (#686) come last.

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
