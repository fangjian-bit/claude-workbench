# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **implementing**.

**Just done (2026-10-14):**
- Sprint 15 closed: done entry in `docs/decisions.md` (#603, #605), milestone 18 closed, archived (#606). #604 filed for #578's deferred live check.
- Backlog triaged: #604 → milestone 19, #589 → milestone 22; #223, #334 left unmilestoned.
- Milestone 19's build order rewritten (description sha `3f604c71e46e…`): #567, #566, #514 (human decision), #433, #395, #396, #458, #397, #398, with #601 as a parallel track. #394 is already done (pin `v0.18.0` since #568) and awaits the maintainer's close.
- Spec comment posted on #567 and anchored. Under the declared `identities` map every Claude-built item needs a maintainer-reacted spec comment before it is built; #601's spec must also settle its schema key, the WB-D25 amendment and its release timing.
- No critic pass: no code diff this session.

**Next:** task #567 — [spec comment](https://github.com/glunk-works/claude-workbench/issues/567#issuecomment-6171619339) — reword the stale no-spec-comment comment in `plugins/way-of-working/bin/plan-anchor.sh` exactly as the spec comment says (comment text only), run the green gate and the `architect` critic pass, then ship it with `/way-of-working:ship`. On **sonnet** (coder).

**HITL Gate: OPEN** — first anchor for milestone 19 (no prior baseline), description sha `3f604c71e46e…`; merging this cursor-sync PR confirms that description, and a maintainer reaction (👍, ❤️, 🎉 or 🚀) on the #567 spec comment approves the spec.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
