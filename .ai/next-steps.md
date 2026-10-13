# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17). Status: **implementing**.

**Just done (2026-10-13):**
- **#496 merged** (#561, `082e3f0`): under an `identities` map the builder (`resume`, the `coder` agent) takes only the anchored spec comment as the spec and `#N`'s body never enters its context; no spec comment, no other issue's body, and a mode mismatch with the spawner all stop; `identities: null` unchanged. `handoff`, `plan-sprint` and `project-schema.md` carry the matching text.
- Critic pass on #561: `architect`, `security-critic` and `docs-consistency`, initial pass plus 4 fix-and-re-run rounds, then 2 delta rounds on `security-critic` alone at the human's call (past the cap). Critics on their frontmatter defaults, no second-opinion round. The last round's fixes were not re-read by a critic. Subagent critics only; no review CI gate is configured.
- Not in #561, left as follow-ups: `architect-review` step 5 still loads `#N`'s body under a map (it first needs a way to verify the anchored comment; `project-schema.md` says so), and the comment at `bin/plan-anchor.sh:451` ("the issue body is the whole spec") is stale under a map. Neither is filed as an issue yet.
- Re-anchored on task #557 with no spec comment (the issue has none); milestone 17's description is unchanged from the text confirmed this session.

**Next:** task #557 — one tested predicate decides whether `hitl_gate` is closed: pin `NONE OPEN — next gate: <prose>` in `handoff`, add a `bin/` predicate with `tests/` fixtures, have `resume`, `unpark-sprint` and `plan-sprint` call it, and pin the three call sites in `scripts/invariants-check.sh`. On **sonnet** (coder); critic gate `architect`, `security-critic` and `docs-consistency`; ship as its own PR. Then #391 (the v0.18.0 release).

**HITL Gate: OPEN** — first anchor for milestone 17 (the handing-off session had no verified baseline); description sha `a333ea30d44e…` is the text the human confirmed, and merging this cursor-sync PR is the confirmation. Then the human merges the #557 PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
