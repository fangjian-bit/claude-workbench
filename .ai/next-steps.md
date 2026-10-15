# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**. No lane is building.

**Just done (2026-10-15, driver session at eac7d8d; no code):**
- Ran lane B on #634 and lane C on #638, on sonnet, each from its maintainer-reacted spec comment. Both merged: #646 (the App-mode review image and host plumbing, closes #634) and #645 (`milestone-desc.sh`, closes #638, `WB-D28`). #646 merged `main` in once to resolve a `CLAUDE.md` conflict with #645. Their worktrees and branches are removed.
  - The installed plugin (0.18.0) does not ship `bin/spec-comment.sh`, and the script must be run by path anyway. Lane prompts read the spec with `sh plugins/way-of-working/bin/spec-comment.sh body …` from the worktree.
- Edited #628's and #639's texts for the deferred allow rule (`WB-D28`): the staged script stays as the fallback when a live description write is refused, #639 reports what auto mode does on its first live run, and letting the write through unattended is the maintainer's decision afterwards.

**Next:** as the driver session (the only session that writes `.ai/`), on **opus**:
1. Draft the #635 spec with `plugins/way-of-working/skills/spec-task/SKILL.md` from `main`, drawing on the hand-off note on #635. Run `/way-of-working:critic-gate` on it to convergence (`architect` and `security-critic`, per milestone 19) and post it for the maintainer's reaction.
2. Draft, gate and post the #639 spec the same way, from #639's text as edited for `WB-D28`.
3. Once a spec has the maintainer's reaction, give the maintainer the worktree and start prompt for its lane (lane B: #635; lane C: #639), reading the spec by path as above.

Lane sessions never run `/resume`, `/handoff`, `/plan-sprint` or `/archive-sprint`.

**HITL Gate: NONE OPEN** — next gate: the maintainer reacts to each posted spec, then merges each lane PR

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
