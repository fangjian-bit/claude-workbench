# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17). Status: **implementing**.

**Just done (2026-10-13):**
- Human picks recorded as comments: **Carry** on #540, **option B** on #496.
- **#540 merged** (#559, `c48dd7f`): `unpark-sprint` carries a `done` live cursor's open gate into the gate it writes (`; prior cursor <sprint> (done) …`), never reads an unreadable state gate as closed, and both carry paragraphs use resume's `NONE OPEN` test; `archive-sprint`'s parked-sprint path writes the closed sprint's `hitl_gate` before unparking and only confirms the carried pending-close note.
- Critic pass on #559: `architect` and `docs-consistency`, initial pass plus 2 fix-and-re-run rounds, converged (round 3 tightenings only, also applied); critics on their frontmatter defaults, no second-opinion round. Subagent critics only; no fresh-session review gate is configured.
- Milestone 17's description was edited since the last anchor: the build order now ends #557 (step 41, after #540) then #391. Re-anchored with task #496 and its pick comment as the spec comment.

**Next:** task #496 — build option B per [the pick comment](https://github.com/glunk-works/claude-workbench/issues/496#issuecomment-6135229860): under an identities map, the builder treats only the anchored spec comment as the spec and never reads the task issue body to act on it; legacy (`identities: null`) unchanged. On **sonnet** (coder); critic gate `architect` and `security-critic`; ship as its own PR. Then #557, then #391 (the v0.18.0 release).

**HITL Gate: OPEN** — milestone 17 description edited since last anchor (new description sha `a333ea30d44e…`, build order now adds #557 at step 41); the human confirms the new text, then the human merges the #496 PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
