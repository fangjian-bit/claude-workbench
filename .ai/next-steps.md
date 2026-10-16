# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**. Two lanes are building.

**Just done (2026-10-15, driver session at 7298792; no code):**
- The maintainer approved both spec comments with a reaction: [#636](https://github.com/glunk-works/claude-workbench/issues/636#issuecomment-6204782932) and [#640](https://github.com/glunk-works/claude-workbench/issues/640#issuecomment-6204758940). `spec-comment.sh check` returned `ok` on each.
- Started lane B (#636, worktree `../claude-workbench-636`, branch `feat/architect-review-cutover-636`) and lane C (#640, worktree `../claude-workbench-640`, branch `feat/blocking-criteria-640`), on sonnet, each from its maintainer-reacted spec comment. #636's PR says `Part of #636`; #640's closes #640.
- The plan anchor on milestone 19 re-verified `match`; the milestone description is unchanged.

**Next:** as the driver session (the only session that writes `.ai/`), on **opus**:
1. When a lane opens its PR, run `/way-of-working:pr-checks` on it and report whether it is ready for the maintainer's merge. Never merge.
2. After each merges, remove its worktree and branch. Then hand off.

After #636, lane B moves to #626. #636 itself closes after the maintainer's live run (`docs/identity/REVIEW-LIVE-RUN.md`, added by its PR). Lane C, after #640, moves to #627, split into one child issue per PR, each with its own spec.

Lane sessions never run `/resume`, `/handoff`, `/plan-sprint` or `/archive-sprint`.

**HITL Gate: NONE OPEN** — next gate: the maintainer merges each lane PR

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
