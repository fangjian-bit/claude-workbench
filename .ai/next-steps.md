# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17). Status: **implementing**.

**Just done (2026-10-12):**
- **#517 merged** (#544, `f3cfcb7`): the release notes and archive-sprint step 8 now point at the drive-letter mirror step and the every-record sha check in `reference/conventions.md`.
- Critic pass on #517: `docs-consistency`, 2 rounds, converged; critic on its frontmatter default, second-opinion round offered and skipped. Subagent critic only; no fresh-session review gate is configured.
- Filed #539–#543 (the #506 follow-ups). Moved #479 to milestone 18: its wording fix shipped in #533, but archive-sprint has not been run live with `backlog.repo: null`. #391 (the release) carries a note to validate that before dispatch.
- Not filed: the release notes' `git ls-remote` line lacks the `^{}` form for annotated tags (pre-existing, noted in #544's body).

**Next:** task #498 — measure whether adding a reaction to an issue comment changes its `updated_at`: react to a throwaway comment, re-read `updated_at`, and cite the result in `plan-anchor.sh`'s header (as #380 is cited). Run the green gate, then `/way-of-working:critic-gate` (`architect`, `security-critic`), then `/way-of-working:ship`. Run on **sonnet** (coder). Build order step 31; no dependency.

**HITL Gate: NONE OPEN** — next gate: the human's merge of #498's PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
