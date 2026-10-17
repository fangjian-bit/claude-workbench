# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**. No lane is building. The next step is the guided #397 cutover into the dev container.

**Just done (2026-10-17, driver session):**
- **All three lanes merged:** #689 (#712), #664 (#716) and #699 (#718). Their worktrees and branches are removed, so no host lane is mid-build. #627 is still open; with its last child merged, it is ready to close.
- **`/way-of-working:plan-sprint`, two passes** (#713, #717).
  - #707–#710 went on milestone 19, ahead of the v0.20.0 release (#686).
  - #714 (container lane procedure) is milestone 19 step 8, after #397. #715 (`lanes` skill) is milestone 20 step 7.
  - #686 still waits only for #627, #629 and #689.
- **The driver edited milestones 19 and 20 outside the skill,** through `milestone-desc.sh`, each write read back by hash. All lane starts are now in the container after #397, and #707 is held as #714's trial task.
- **Maintainer's decisions:**
  - #397 is not gated on the #636 live run, as recorded on #397 on 2026-10-16.
  - A handoff runs before the cutover, and the driver guides it step by step.
- No code diff this session, so no critic pass.

**Next:** as the driver session (the only session that writes `.ai/`), on **opus**, on the host:
1. Guide the maintainer through #397 one step at a time, waiting for their confirmation after each.
   - Steps, in order: the host prerequisites in `docs/identity/DEV-CONTAINER.md`, then open a separate full clone in the dev container (never the install, review or this host clone, never a worktree), then check the container session acts as the dev App, then delete the SessionStart `GH_TOKEN` hook from `.claude/settings.local.json`.
   - The maintainer does each step. The driver runs read-only checks only.
2. Once the container session works, the next driver session runs inside the container. It writes `.ai/state.json` there, and starts #714 with #707 as the first container lane.
3. Queued in the container after #397: #696 (lane A), #629 once #627 closes (lane B), #708–#710 after the #707 trial (lane C), and #715 in milestone 20.
4. After the maintainer's second #636 live-run pass on scratch #27, record it as session 9 in `docs/proposals/IDENTITY-SCRATCH-RESULTS.md`.
   - #458 starts once its `BLOCKING` line holds. #398 and the v0.20.0 release (#686) come last.

**Lane rules that carry into the container** (#714 replaces the host-only ones):
- Lane sessions never run `/resume`, `/handoff`, `/plan-sprint` or `/archive-sprint`.
- The lane prompt names the spec pin (`PIN_ID`, `PIN_UP`) from `spec-find.sh find`, the mode (`map`) and the critics.
- A session that drafted a spec has read that issue's body, so it never builds that issue: a lane does.
- `main`'s `spec-task` is ahead of v0.19.0, so a spec is drafted with `main`'s skill text and `main`'s `plugins/way-of-working/bin/`.
- Every PR needs a code-owner approval from JaredGroves-603. Approving one with auto-merge armed merges it.

**HITL Gate: NONE OPEN** — next gate: the maintainer carries out the 397 cutover steps, then approves each container lane PR and runs the second 636 live-run pass

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
