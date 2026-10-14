# Cursor — claude-workbench

**Now:** **Sprint 15** (cursor id `sprint-15`) on [milestone 18, *Identity M3: host broker and dev container*](https://github.com/glunk-works/claude-workbench/milestone/18). Status: **implementing**.

**Just done (2026-10-14):**
- Spec for #579 posted as [comment 6168580438](https://github.com/glunk-works/claude-workbench/issues/579#issuecomment-6168580438), from a scratch-clone trial: the index is already all LF, so `* text=auto eol=lf` alone fixes a fresh clone and the renormalize is a no-op; an existing clone needs a one-time re-checkout. A maintainer reacted to it.
- Anchor re-taken on #579 with that spec comment (milestone 18's description verified as `match` against the prior anchor). No code in this session, so no critic pass.

**Next:** task #579 — build the anchored spec comment https://github.com/glunk-works/claude-workbench/issues/579#issuecomment-6168580438 (one repo-wide eol=lf rule in .gitattributes, renormalize expected to be a no-op), run the local green gate, then /way-of-working:ship it; the dev-container check stays a pending item in the PR body for the maintainer. On **sonnet** (coder), in a fresh session (this one read #579's body). After it: #588 (milestone 18 step 8); then `/way-of-working:archive-sprint` for milestone 18.

**HITL Gate: NONE OPEN** — next gate: the maintainer runs the dev-container check and approves the #579 work PR

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 18](https://github.com/glunk-works/claude-workbench/milestone/18) · [.ai/parked/](parked/)
