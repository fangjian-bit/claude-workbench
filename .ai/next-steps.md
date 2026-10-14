# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**.

**Just done (2026-10-14):**
- Task #614 shipped: PR #619 (`3837acc`) adds `bin/spec-comment.sh`, which resume, the coder and architect-review call to check the anchored spec comment before printing it, plus invariants check 17.
  - Critic pass on #619, carried from its PR body: architect, security-critic and docs-consistency ran for 2 rounds (the initial pass plus 1 fix-and-re-run round, under the cap of 4), converged: round 2 returned tightenings only from all three. Every round ran on the critics' own frontmatter models; no second-opinion round was run. Check 17's allow-list was tightened after round 2 (with new fixtures) and that last edit was not re-run through the critics.
  - Left open on purpose: `<backlog-repo>` is a caller argument, not read from the default-branch yml (pre-existing, legacy mode only).
- The no-op handoff did not apply (the review-step derive answered `none`, and #619 had already merged), so this is the ordinary ledger PR.

**Next:** plan the next task of milestone 19 with the maintainer: pick one open issue, post its spec comment for the maintainer to react to, then `/way-of-working:handoff` to anchor it. On **opus** (architect), in a fresh session.

**HITL Gate: NONE OPEN** — next gate: maintainer reaction to the next task's spec comment

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
