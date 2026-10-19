# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **implementing**. Lanes A, B and C and #749 merged; the next work is drafting specs.

**Just done (2026-10-19, driver session in the container, opus):**
- **Four lanes built and merged:** #696 (#765), #708 (#768), #741 (#766), #749 (#767), with #708 merged before #749. Each was cleaned up with `lane.sh done`, and each PR was put on milestone 19.
- **Four specs drafted by the driver, critic-gated to convergence and approved:** #749 (2 rounds), #754 (2 rounds), #744 (3 rounds), #756 (3 rounds). Critics were architect, security-critic and docs-consistency, all opus at high effort. #754's spec is still fresh. The #756 and #744 specs read stale since #708 merged.
- **Lane E held.** The #728 and #729 lanes were removed unused; both specs read stale since #741 and #708 merged.
- **Filed** #764: drafting ahead relies on a freshness re-check that runs only under an `identities` map.

**Lessons:**
- **Overlapping *Files touched* lists make specs go stale.** A merge makes every other spec that lists one of its paths read `stale`, which needs a redraft and a new reaction. Check overlaps before running lanes in parallel, and set the merge order so the costly spec merges first.
- **A rejected tool call may have partly run.** A rejected two-lane prep had already prepared the first lane. Check the effect afterwards.
- **Subagent effort follows the session.** The agent definitions pin `model: opus` but no effort, so drafters and critics take the spawning session's effort.

**Next:** on **opus** (driver), as the cursor's `next_action` says:
- Draft by drafter subagents (the standing SOP, now that #749 has merged). Batch 1 is fresh specs for #728, #729, #756 and #744. Batch 2 is #746, #759, #761 and #755. #762 waits on #728.
- Maintainer: once each new spec is up, react to it and remove the reaction from the stale one. Say when the next lane is up; #754 is ready.
- Maintainer, before the next session: rebuild the container with the compare-first order (`docs/identity/DEV-CONTAINER.md`), so it carries #741's GNU coreutils.

**HITL Gate: NONE OPEN** — next gate: the maintainer reacts to each critic-gated spec comment before its lane is built

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [docs/identity/DEV-CONTAINER.md](../docs/identity/DEV-CONTAINER.md) · [.ai/parked/](parked/)
