# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**. Both first lanes have merged; the next two lanes need specs.

**Just done (2026-10-16, driver session at 9bfa64a; no code):**
- Lane B's PR [#656](https://github.com/glunk-works/claude-workbench/pull/656) (#636, architect-review cut over to the review outbox) merged at `9bfa64a`. #636 stays open until the maintainer's live run (`docs/identity/REVIEW-LIVE-RUN.md`).
- Lane C's PR [#655](https://github.com/glunk-works/claude-workbench/pull/655) (#640, ship reads blocking criteria through `blocking-criteria.sh`) merged at `ffc888f` and closed #640.
- Removed both lane worktrees (`../claude-workbench-636`, `../claude-workbench-640`) and their local branches.
- The plan anchor on milestone 19 re-verified `match`; the milestone description is unchanged.

**Next:** as the driver session (the only session that writes `.ai/`), on **opus**:
1. Lane B: draft the spec for [#626](https://github.com/glunk-works/claude-workbench/issues/626) and post it as a comment on #626.
2. Lane C: split [#627](https://github.com/glunk-works/claude-workbench/issues/627) into one child issue per PR, and post each child's spec as a comment on that child.
3. Start a lane only after the maintainer reacts to its spec comment and `spec-comment.sh check` returns `ok`. Never merge.

Lane sessions never run `/resume`, `/handoff`, `/plan-sprint` or `/archive-sprint`.

**HITL Gate: NONE OPEN** — next gate: the maintainer reacts to each new lane spec comment

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
