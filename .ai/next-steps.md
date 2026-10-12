# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17). Status: **implementing**.

**Just done (2026-10-11):**
- **#346 merged** (#502, `af6c87b`). `architect-review` now posts every run, hand-started included, through `POST …/pulls/<N>/reviews` with `commit_id` set to the reviewed SHA; the `gh pr review` path is gone. Prose only; no `bin/` or fixture change.
  - Critic pass: `architect`, `security-critic` and `docs-consistency`, 3 rounds, converged; on the critics' default models; no second-opinion round (declined).
  - Stated residuals: the unpinned verify poll still accepts `success` on a moved head (only a `--pin` poll reports it); the REST form is **not verified live** on any gated repo, an adopter's first run is the live check.

**Next:** task #390 — show the acting identity and ADMIN MODE (with expiry) in the SessionStart banner, per the [issue body](https://github.com/glunk-works/claude-workbench/issues/390); extend `tests/ai-cursor-banner.test.sh`. Next in the milestone's build order. Sync main first. Build on **sonnet** (coder); green gate (slow suites in WSL), `/way-of-working:critic-gate` (architect and security-critic, per the milestone), `/way-of-working:ship`.

**HITL Gate: NONE OPEN** — milestone 17's anchor verified (match) before re-anchoring to #390. The next gate is the human's merge of the task PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
