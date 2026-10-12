# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17). Status: **implementing**.

**Just done (2026-10-12):**
- **#360 merged** (#507, `a76e615`). `resume` now runs `plan-anchor.sh verify` on every cursor with an anchor and prints `Plan anchor: <word>` (`--plan` for a null-task anchor). `handoff`'s baseline no longer depends on resume's word: it is the previous anchor, non-null and for the same milestone, checked by handoff's own `verify --plan`. Scope narrowed from the issue text (comment on #360).
  - Critic pass: `architect`, `security-critic`, `docs-consistency`; 4 fix-and-re-run rounds, cap reached; the last round's wording-only fixes were not re-run, by the maintainer's call. On the critics' default models; no second-opinion round.
  - Follow-up filed: #506 (unpark-sprint overwrites an open `hitl_gate`, so an unapproved anchor can become the baseline). Unmilestoned; place it.

**Next:** task #313 — name `/reload-plugins` beside "restart" in the pin-bump procedure, and optionally have `resume` report a loaded-vs-pinned version mismatch in one line, per the [issue body](https://github.com/glunk-works/claude-workbench/issues/313). Next in the milestone's build order. Sync main first. Build on **sonnet** (coder); green gate (slow suites in WSL), `/way-of-working:critic-gate` (architect and security-critic, per the milestone), `/way-of-working:ship`.

**HITL Gate: NONE OPEN** — milestone 17's anchor verified (match) before re-anchoring to #313. The next gate is the human's merge of the task PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
