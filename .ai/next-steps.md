# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**. Two lanes are building.

**Just done (2026-10-15, driver session at a7817d8; no code):**
- The maintainer confirmed milestone 19's live description is the plan, which closed the gate. The anchor re-verifies `match`.
- Split #623 into #633 (`mint.sh --strict`, read and filing token shapes), #634 (review image, entrypoint, `outbox-read`, sandbox marker, host export, broker sweep), #635 (`wow-review` launcher) and #636 (`architect-review` cutover, live run). Split #628 into #637 (retire the description hash), #638 (description-write script and allow rule) and #639 (plan-sprint writes build orders live). All seven are in milestone 19, ordered in their parent's checklist.
- Posted spec comments on #633 and #637, each approved by the maintainer's reaction.
  - #633: 5 rounds (architect, security-critic, docs-consistency), converged. Then +1 on `fable` (second_opinion), confirmed; it found the grant condition must be keyed to the App key, not an installation. Its fixes were re-run once on `fable`. Three later wording edits had no critic pass.
  - #637: 5 rounds (architect, security-critic, docs-consistency), converged.
- Filed #640, unmilestoned: project ship's and archive-sprint's `BLOCKING:` reads to the criteria (the residual #637's `WB-D27` records).
- Started lane B (#633, worktree `../claude-workbench-633`, branch `feat/mint-strict-633`) and lane C (#637, worktree `../claude-workbench-637`, branch `feat/retire-desc-hash-637`), on sonnet.
- Drafted the #634 spec. It has not been through the critic gate. It is saved at `C:/Users/SR116/AppData/Local/Temp/claude/c--Users-SR116-projects-glunk-works-claude-workbench/bcf983bb-aeaa-4e79-88d5-f2091d40ef8d/scratchpad/spec-634.md`.

**Next:** as the driver session (the only session that writes `.ai/`), on **opus**:
1. Run `/way-of-working:critic-gate` (architect, security-critic, docs-consistency, per milestone 19) on the #634 draft to convergence, then post it on #634 for the maintainer's reaction.
2. Draft the #638 spec by following `plugins/way-of-working/skills/spec-task/SKILL.md` from `main` (the pinned v0.18.0 plugin predates spec-task), critic-gate it, and post it on #638.
3. Track the lane B (#633) and lane C (#637) PRs.
4. Place #640 with `/way-of-working:plan-sprint`.

Lane sessions never run `/resume`, `/handoff`, `/plan-sprint` or `/archive-sprint`.

**HITL Gate: NONE OPEN** — next gate: the maintainer reacts to each posted child spec before its lane builds it

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
