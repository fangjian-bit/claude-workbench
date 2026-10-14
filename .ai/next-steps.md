# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **implementing**.

**Just done (2026-10-14):**
- The maintainer confirmed milestone 19's edited build order (#613, #614, #611), closing the gate the last handoff opened.
- Posted #613's spec comment ([issuecomment-6173681015](https://github.com/glunk-works/claude-workbench/issues/613#issuecomment-6173681015)). It adds a shared `bin/spec-reaction.sh` predicate that both `plan-anchor.sh` and architect-review's Map branch call. The maintainer reacted to it.
- Anchored task #613 with that spec comment. `verify --plan` read `match` against the prior anchor, and a full `verify` with the maintainer ids read `match`.
- Planning session only, no code diff, so no critic pass.

**Next:** task #613 — build it per its anchored spec comment https://github.com/glunk-works/claude-workbench/issues/613#issuecomment-6173681015 (the comment is the whole spec; the issue body is not read), run the local green gate, then `/way-of-working:critic-gate` and `/way-of-working:ship`. On **sonnet** (coder).

**HITL Gate: NONE OPEN** — next gate: code-owner approval of the #613 build PR

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
