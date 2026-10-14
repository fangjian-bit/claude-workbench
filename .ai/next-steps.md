# Cursor — claude-workbench

**Now:** **Sprint 15** (cursor id `sprint-15`) on [milestone 18, *Identity M3: host broker and dev container*](https://github.com/glunk-works/claude-workbench/milestone/18). Status: **implementing**.

**Just done (2026-10-14):**
- [#595](https://github.com/glunk-works/claude-workbench/pull/595) merged (`4f098f1`): the three host scripts read `.Source` only when a tool is found, with a no-tool-on-PATH fixture group. #578 is closed.
- Critic pass on that diff (`architect`, `security-critic`): 1 round, converged, no fixes needed; every round on the critics' own default models. Not the fresh-session review (`review.ci_gate` is `null`).
- The anchor was re-taken on #579 with no spec comment (milestone 18's description verified as `match` against the prior anchor).

**Next:** task #579 — post its spec as a comment on #579 (line endings in the host scripts; out of scope of #578), then anchor it at handoff and have a maintainer react; build only after that. On **opus** (architect), in a fresh session. After it: #588 (milestone 18 step 8); then `/way-of-working:archive-sprint` for milestone 18.

**HITL Gate: OPEN** — #579 has no spec comment; the architect posts one and a maintainer reacts to it before any build

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 18](https://github.com/glunk-works/claude-workbench/milestone/18) · [.ai/parked/](parked/)
