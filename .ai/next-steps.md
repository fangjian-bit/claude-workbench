# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17). Status: **implementing**.

**Just done (2026-10-12):**
- **#498 merged** (#546, `3b2f2af`): a `rocket` added 6s after a comment was created left its `updated_at` unchanged (one observation, recorded in `plan-anchor.sh`'s header, comment-only). Throwaway comment on #380 deleted.
- Critic pass on #498: `architect` and `docs-consistency`, 1 round, no blocking findings, both wording suggestions applied and not re-run; critics on their frontmatter defaults, no second-opinion round. Subagent critic only; no fresh-session review gate is configured.
- Milestone description edited since the last anchor: issues #529, #530, #539–#543 were added to it after this session's resume, not by this session. Re-anchored to the new description sha below.

**Next:** task #497 — `plan-anchor.sh verify` checks the anchored spec comment's author against the maintainer ids; then the green gate, `/way-of-working:critic-gate` (`architect`, `security-critic`), then `/way-of-working:ship`. Run on **sonnet** (coder). Build order step 32; no dependency. Do not start until the gate below is cleared.

**HITL Gate: OPEN** — milestone 17's description was edited since the last anchor (see *Just done*): the human re-verifies the description and clears the gate. Next gate after that: the human's merge of #497's PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
