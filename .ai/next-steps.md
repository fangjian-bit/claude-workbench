# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**. No lane is building.

**Just done (2026-10-15, driver session at 67a95b0; no code):**
- Lane B and lane C merged: #642 (`mint.sh --strict`, closes #633) and #643 (retires the description hash, closes #637). Their worktrees and branches are removed.
- Posted the #634 spec (review image, entrypoint, `outbox-read`, review-container marker, host export, broker sweep). The maintainer approved it with a reaction. Hand-off notes for the next specs are posted on #635 and #636.
  - Critic pass: 4 rounds (architect, security-critic, docs-consistency), converged. Then +1 on `fable` (second_opinion), confirmed; its fixes re-run once on `fable`, confirmed. One more `fable` architect check on the last 7-line fix, at the maintainer's choice, converged.
- Posted the #638 spec (`milestone-desc.sh write`, a checked milestone-description writer). The maintainer approved it with a reaction.
  - Critic pass: 3 rounds (architect, security-critic, docs-consistency), converged. No second-opinion round, by the maintainer's choice.
  - The maintainer deferred the issue's allow rule: a Bash allow rule approves a command name, so any file of that name earlier on `PATH` would run under it. The spec has #638's build record this as `WB-D28`.
- Placed #640 in milestone 19 with `/way-of-working:plan-sprint`. #223 and #334 stay unmilestoned. Milestone 19's description is unchanged; the anchor re-verifies `match`.

**Next:** as the driver session (the only session that writes `.ai/`), on **opus**:
1. Start lane B on #634 and lane C on #638, each in a fresh worktree off `main` and a fresh sonnet session that builds only from its maintainer-reacted spec comment ([#634](https://github.com/glunk-works/claude-workbench/issues/634#issuecomment-6196323631), [#638](https://github.com/glunk-works/claude-workbench/issues/638#issuecomment-6197132672)), never the issue body.
2. Track both lane PRs.
3. Once #634 merges, draft the #635 spec with `plugins/way-of-working/skills/spec-task/SKILL.md` from `main`, drawing on the hand-off note on #635. Critic-gate it and post it.
4. Once #638 merges and the maintainer has edited #628's and #639's texts for the deferred allow rule, draft, gate and post the #639 spec the same way.

Lane sessions never run `/resume`, `/handoff`, `/plan-sprint` or `/archive-sprint`.

**HITL Gate: NONE OPEN** — next gate: the maintainer merges each lane PR

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
