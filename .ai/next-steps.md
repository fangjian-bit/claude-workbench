# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17). Status: **implementing**.

**Just done (2026-10-13):**
- **#541, #542, #543 merged** as one prose PR (#556, `88ac6b1`): `resume`'s auto-start test needs `hitl_gate` to begin `NONE OPEN` with nothing open after it; `plan-sprint` no longer says a parked sprint's drift is caught at unpark (the next `resume` reports it, the next `handoff` opens the gate); `handoff` defines the ledger's **HITL Gate** line once and `archive-sprint`'s blank seed, `unpark-sprint` and `plan-sprint` use that name and shape.
- Critic pass on #556: `docs-consistency` and `architect`, initial pass plus 1 fix-and-re-run round, converged (round 2 tightenings only); critics on their frontmatter defaults. The `fable` second-opinion round was offered and declined. Subagent critics only; no fresh-session review gate is configured.
- Filed #557 (not in the milestone): pin one closed form for `hitl_gate` and share a predicate. Cut from the architect's pass; not part of #556.

**Next:** no task builds until the human picks an option on #540 (`unpark-sprint` over a done cursor drops its open gate; build order step 37) and on #496 (`resume` covers #N's body with the maintainer reaction; step 33) — comment the pick on each issue. Then build the picked one as its own PR on **sonnet** (coder), #540 first. #391 (the v0.18.0 release) follows the rest of the milestone.

**HITL Gate: OPEN** — the human picks an option on #540 and on #496 before either is built; then the human's merge of each PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
