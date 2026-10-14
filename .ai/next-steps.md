# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **implementing**.

**Just done (2026-10-14):**
- Task #613 shipped: PR #617 (`bc3a539`) adds `bin/spec-reaction.sh`, which `plan-anchor.sh` and architect-review's Map branch both call.
  - Critic pass on #617, carried from its PR body: architect, security-critic and docs-consistency ran for 3 rounds (the initial pass plus 2 fix-and-re-run rounds, under the cap of 4), converged: round 3 returned no false statements, contradictions or fail-open paths, only a wording fix that was applied afterwards. Every round ran on the critics' own frontmatter models; no second-opinion round was run. The last small edits (a usage string, header comments, one recipe default) were not re-run through the critics.
- Posted #614's spec comment ([issuecomment-6176369440](https://github.com/glunk-works/claude-workbench/issues/614#issuecomment-6176369440)). It adds a shared `bin/spec-comment.sh` that resume, coder and architect-review call to check the anchored spec comment before printing it, plus invariants check 17. The maintainer reacted to it.
- Anchored task #614 with that spec comment. `verify --plan` read `match` against the prior anchor.
- Planning session only, no code diff, so no critic pass.

**Next:** task #614 — build it per its anchored spec comment https://github.com/glunk-works/claude-workbench/issues/614#issuecomment-6176369440 (the comment is the whole spec; the issue body is not read), run the local green gate, then `/way-of-working:critic-gate` and `/way-of-working:ship`. On **sonnet** (coder), in a fresh session: this planning session read #614's issue body.

**HITL Gate: NONE OPEN** — next gate: code-owner approval of the #614 build PR

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
