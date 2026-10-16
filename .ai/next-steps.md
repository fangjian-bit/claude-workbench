# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**. Lane B's spec is approved; lane C needs its split and specs.

**Just done (2026-10-16, driver session at cbb0d0e; no code):**
- Drafted lane B's spec for [#626](https://github.com/glunk-works/claude-workbench/issues/626) (the host review poller, `wow-review-poll`, and its scheduled task) with `spec-task`, against `main` at `cbb0d0e`. Posted it as the maintainer: [spec comment](https://github.com/glunk-works/claude-workbench/issues/626#issuecomment-6215847925).
- The maintainer reacted to it. `spec-comment.sh check` returned `ok`, and a full-mode `plan-anchor.sh verify` on it printed `match`.
- The plan anchor on milestone 19 re-verified `match`; the milestone description is unchanged.

**Next:** as the driver session (the only session that writes `.ai/`), on **opus**:
1. Lane B: give the maintainer the shell command and prompt to start a lane session on #626 in a new worktree cut from `origin/main`, building only from its [spec comment](https://github.com/glunk-works/claude-workbench/issues/626#issuecomment-6215847925). This driver session has read #626's body, so it does not build #626 itself.
2. Lane C: split [#627](https://github.com/glunk-works/claude-workbench/issues/627) into one child issue per PR. Draft each child's spec with `spec-task`, post it as the maintainer on that child, and wait for the reaction. Start lane C only after `spec-comment.sh check` returns `ok`.
3. #636 stays open until the maintainer's live run (`docs/identity/REVIEW-LIVE-RUN.md`). Never merge.

Lane sessions never run `/resume`, `/handoff`, `/plan-sprint` or `/archive-sprint`.

**HITL Gate: NONE OPEN** — next gate: the maintainer reacts to each lane C child spec comment and merges each lane PR

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
