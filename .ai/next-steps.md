# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**. No lane is building.

**Just done (2026-10-15, driver session at 230b8c7; no code):**
- Started lane B on #635 and lane C on #639, each in its own worktree on sonnet, from its maintainer-reacted spec comment.
- Both merged: #651 (the `wow-review` host launcher, closes #635) and #650 (`plan-sprint` edits a build order live through `milestone-desc.sh`, closes #639). Their worktrees and branches are removed.
- Closed #628: all three of its parts are merged (#637 by #643, #638 by #645, #639 by #650).
- The plan anchor on milestone 19 re-verified `match`; the milestone description is unchanged.

**Next:** as the driver session (the only session that writes `.ai/`), on **opus**:
1. Draft the #636 spec (lane B: the last part of #623, which switches architect-review's App mode over to the `wow-review` launcher). Draw on the hand-off note on #636.
2. Draft the #640 spec (lane C: placed in this milestone to go before #627).
3. Use `plugins/way-of-working/skills/spec-task/SKILL.md` from `main` for each. Critic-gate each with `architect` and `security-critic`, and post each as a comment for the maintainer's reaction. Then hand off.

After #636, lane B moves to #626. After #640, lane C moves to #627, split into one child issue per PR, each with its own spec.

Lane sessions never run `/resume`, `/handoff`, `/plan-sprint` or `/archive-sprint`.

**HITL Gate: NONE OPEN** — next gate: the maintainer reacts to the #636 and #640 spec comments

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
