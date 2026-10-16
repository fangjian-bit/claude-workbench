# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**. No lane is building.

**Just done (2026-10-15, driver session at 487ee8c; no code):**
- Drafted the #636 spec (lane B: the last part of #623, which cuts architect-review's App mode over to the `wow-review` launcher) with `spec-task` from `main`. Posted it as [a comment on #636](https://github.com/glunk-works/claude-workbench/issues/636#issuecomment-6204782932).
- Drafted the #640 spec (lane C: project ship's and archive-sprint's `BLOCKING:` reads to the criteria). Posted it as [a comment on #640](https://github.com/glunk-works/claude-workbench/issues/640#issuecomment-6204758940).
- Critic gate on each draft, with `architect` and `security-critic` on their default models: 2 rounds each, cap reached. Neither second round found anything blocking, and its should-fix items were applied without a third round.
- The #636 draft used the maintainer's hand-off note on #636, as the cursor directed, and no other comment. `spec-shape.sh` ran from `main`'s copy, because the installed plugin (0.18.0) predates it.

**Next:** as the driver session (the only session that writes `.ai/`), on **opus**, once the maintainer has reacted to both spec comments:
1. Start lane B on #636 and lane C on #640, each in its own worktree on sonnet, from its maintainer-reacted spec comment.
2. Then hand off.

After #636, lane B moves to #626. Lane C, after #640, moves to #627, split into one child issue per PR, each with its own spec. #636's PR says `Part of #636`: the issue closes after the maintainer's live run (`docs/identity/REVIEW-LIVE-RUN.md`, added by that PR).

Lane sessions never run `/resume`, `/handoff`, `/plan-sprint` or `/archive-sprint`.

**HITL Gate: NONE OPEN** — next gate: the maintainer reacts to the #636 and #640 spec comments

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
