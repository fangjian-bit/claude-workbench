# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **implementing**. All specs for the next lanes are approved. The next work is building them, one lane at a time.

**Just done (2026-10-19, driver session in the container, opus):**
- **Eight specs drafted by architect drafter subagents** (each model confirmed with `spawn-model.sh`), critic-gated to convergence, posted as the dev App, and approved by the maintainer:
  - fresh specs replacing stale ones: #744, #756, #729, #728;
  - first specs: #761, #746, #759, #755.
  
  `spec-find.sh` finds exactly one approved spec on each, and #754's spec is still approved. Critics were architect, security-critic and docs-consistency.
- **Filed** #770: keep draft and critic text out of the driver's context. Drafters would return a path, and critics a verdict line.

**Lessons:**
- **Eight specs in one session overflowed the context.** The session was compacted partway through the second batch, so draft at most 3 specs per session and hand off between batches (#770).
- **`spec-issue.sh` needs a reaction newer than the issue's last update,** and a spec comment counts as an update. Ask for re-reactions before resuming drafters.
- **`spec-post.sh`'s leak screen refuses home-directory paths,** which #728 tripped. Grep the draft before posting.

**Next:** on **opus** (driver), as the cursor's `next_action` says. Prepare one lane at a time, and only when the maintainer says it is up, starting with #759. Then #754, #744, #756, #755 (needs a quiet container), #761 (after #755, because both edit `tests/identity-review.test.sh`), #746, #729 and #728. #762 waits on #728. Check freshness before each prep.

**HITL Gate: NONE OPEN** — next gate: the maintainer says when each lane is up and merges its PR

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [docs/identity/DEV-CONTAINER.md](../docs/identity/DEV-CONTAINER.md) · [.ai/parked/](parked/)
