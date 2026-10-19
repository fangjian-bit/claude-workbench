# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **implementing**. Next is a planning pass, not a build.

**Just done (2026-10-19, driver session in the container, opus):**
- **First parallel lane runs.** Each lane ran its own critic pass, recorded in its PR body. This session ran no critic pass on code.
  - First pair: #742 → #747 (`d3e3c5c`), #743 → #748 (`0d6ea3d`).
  - Second pair, specs posted by the dev App and approved by the maintainer: #710 → #751 (`31b92a2`), #709 → #752 (`1fadf5b`).
  - #752's lane fixed a round-2 finding (one prose sentence) without a confirming re-run.
  - #752 conflicted with #751 in `CHANGELOG.md`, because both added `## [Unreleased]`. The driver merged `main` in, keeping both sides. That push dismissed the approval, so it needed a second one.
- **What the lane runs showed (#715):**
  - No lock file in the shared `/workspace/.git` in any sample, in either run.
  - In the second run, both lanes were busy together for about 16 min, with peak load 3.56 on 28 cores.
  - The lanes sat idle most of their wall time, waiting on the maintainer's answers. Throughput is bounded by the human, not the machine.
- **Filed:**
  - #746: #629 part A, `spec-post.sh escalate` plus a spec-find `escalated` word.
  - #749: `spawn-model.sh` reads Claude Code 2.1.303's `api-request-blob` records as a model `mismatch`. Every subagent spawn reads `mismatch` until it is fixed, so the #708/#709/#710 specs carry `Model provenance: mismatch (unconfirmed)`, although every drafter ran on opus.
- **#708's spec** (comment 6257500217) is approved but not built. It is pinned to `0d6ea3d`, and #751 has since changed `project-schema.md`, which it lists. Expect `spec-fresh.sh check` to read it as stale, so redraft it before a lane.

**Lessons, for the Lanes section:**
- **Where to run `lane.sh`.** Run `lane.sh done` from `/workspace` (`!` in the driver session). From a lane's own worktree it prints `not-main`.
- **Overlapping lanes.** Two lanes that both add `## [Unreleased]` to a CHANGELOG without that heading conflict. Choose lanes with disjoint *Files touched* from their specs, and expect the second merge to need `main` merged in.
- **Pushes and approvals.** A push to an approved PR dismisses the approval. Auto-merge stays armed.

**Next:** on **opus** (driver): run `/way-of-working:plan-sprint` on milestone 19.
- It places the unmilestoned issues (#744, #749, …) and confirms the Build order and its `depends_on` markers. #746, #741 and #737 have no Build order line yet, so the depends_on reader holds them behind every earlier item.
- When the skill completes, outside the skill, rewrite milestone 19's description with the latest Build order, plus a section naming which tasks can run as parallel lanes (disjoint *Files touched*). Report it for the maintainer to confirm.
- Then: redraft #708's spec if stale; spec #746 (dev-App-filed, so the maintainer reacts to the issue first), #728 and #729.
- Clean up lane 709 with `! sh scripts/lanes/lane.sh done 709`, run from `/workspace`.

**HITL Gate: NONE OPEN** — next gate: the maintainer confirms the plan-sprint placement and the new Build order

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [docs/identity/DEV-CONTAINER.md](../docs/identity/DEV-CONTAINER.md) · [.ai/parked/](parked/)
