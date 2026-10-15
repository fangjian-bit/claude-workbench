# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**. No lane is building.

**Just done (2026-10-15, driver session at 46e2c39; no code):**
- Drafted the #635 spec (the `wow-review` host launcher) with `spec-task` from `main`, critic-gated it, and posted it: [spec comment](https://github.com/glunk-works/claude-workbench/issues/635#issuecomment-6199934707). The maintainer approved it with a reaction.
- Drafted, gated and posted the #639 spec (`plan-sprint` rewrites a build order live, records it in the triage comment): [spec comment](https://github.com/glunk-works/claude-workbench/issues/639#issuecomment-6199785741). The maintainer approved it with a reaction.
- Critic pass, `architect` and `security-critic` on their frontmatter models:
  - #635: 5 rounds (initial plus 4 fix-and-re-run rounds); converged at the cap, with no blocking findings in the last round.
  - #639: 5 rounds, same; converged at the cap. The maintainer declined the offered `fable` second-opinion round.
- Beyond `spec-task`'s rules:
  - It read #623's two design comments, #628's body and the hand-off note on #635, after checking each was written by the declared maintainer.
  - It posted both specs as Seuss27, as the #634 and #638 specs were.
- Each spec lists the choices it made (C1, C2, …) for the maintainer to change. #639 records an open `WB-D28` residual: its pre-write checks bind only a session that follows the skill.

**Next:** as the driver session (the only session that writes `.ai/`), on **opus**: give the maintainer the worktree and start prompt for lane B (#635) and lane C (#639). Each lane builds on **sonnet** from its maintainer-reacted spec comment, read by path with `sh plugins/way-of-working/bin/spec-comment.sh`, since the installed plugin (0.18.0) does not ship it. Then wait for the lane PRs.

Lane sessions never run `/resume`, `/handoff`, `/plan-sprint` or `/archive-sprint`.

**HITL Gate: NONE OPEN** — next gate: the maintainer merges each lane PR

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
