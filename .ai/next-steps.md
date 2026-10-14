# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **implementing**.

**Just done (2026-10-14):**
- Shipped #566 as PR #612 (`23dcae1`, merged): architect-review loads only the anchored spec comment under an identities map. Filed #613 (re-read the maintainer's reaction) and #614 (print the spec comment only after its checks pass); the maintainer has since added them, with #611, to the milestone's build order.
- Critic pass on #566:
  - 4 fix-and-re-run rounds, cap reached; the last two small edits were read by an Opus architect, not a fifth critic round.
  - All rounds ran on each critic's own default model; no second-opinion round.
- Re-anchored on milestone 19 (task #613, no spec comment yet) after the description changed: `verify --plan` read `drift`, so the gate below is open.

**Milestone description edited since last anchor.** The new build order lists #613 next; every Claude-built item needs a maintainer-reacted spec comment before it is built.

**Next:** task #613 — draft and post its spec comment on #613 (architect-review re-reads the maintainer's reaction on the spec comment it loads); a maintainer reacts to it, and `/way-of-working:handoff` anchors it. The build follows on **sonnet** (coder). This planning step is on **opus** (architect).

**HITL Gate: OPEN** — milestone 19 description edited since the last anchor (build order now has #613, #614, #611); confirm it, then close this gate in a handoff

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
