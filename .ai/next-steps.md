# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17). Status: **implementing**.

**Just done (2026-10-12):**
- **#389 merged** (#500, `61bc94e`). `architect-review` in App mode (`identities` a map) requests a reviewer token via the new `bin/review-token.sh` only after no review sandbox exists, posts the pinned COMMENT review as `reviewer_app`, checks the response's actor, and discards the token on every exit (EXIT trap). `identities: null` repos are unchanged.
  - Critic pass: `security-critic`, `architect` and `docs-consistency`, 4 rounds, converged; on the critics' default models; no second-opinion round.
  - Verified against stubs only (`tests/review-token.test.sh`). **Live run (one review posted on scratch) deferred to the human.**
  - Stated residual: the order is not a credential boundary (same-user sandbox; real fix is #158).

**Next:** task #346 — post every `architect-review` run through the REST reviews call with `commit_id` set to the reviewed SHA, dropping the `gh pr review` path, per the [issue body](https://github.com/glunk-works/claude-workbench/issues/346). #389 already did this for App mode; unify the rest and update the fixtures. Sync main first. Build on **sonnet** (coder); green gate (slow suites in WSL), `/way-of-working:critic-gate` (architect and security-critic, per the milestone), `/way-of-working:ship`.

**HITL Gate: NONE OPEN** — milestone 17's anchor re-verified (match) before re-anchoring to #346. The next gate is the human's merge of the task PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
