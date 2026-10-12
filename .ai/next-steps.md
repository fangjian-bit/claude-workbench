# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17). Status: **implementing**.

**Just done (2026-10-12):**
- **#383 merged** (#495, `2140863`). `plan-anchor.sh verify --maintainer-ids` and a new `unreacted` verdict: under a cut-over repo (`identities` a map), `resume` auto-starts only on a declared maintainer's approving reaction on the exact anchored spec comment, created after its last edit; no anchored spec comment also waits. `identities: null` repos are unchanged.
  - Critic pass: `architect` and `security-critic`, 3 rounds, converged; on the critics' default models; no second-opinion round.
  - Accepted gaps, filed: #496 (reaction does not cover `#N`'s body), #497 (script does not check the spec comment's author), #498 (reaction vs comment `updated_at` unmeasured; check before the first cutover).

**Next:** task #389 — post architect reviews with a reviewer token minted after sandbox destroy, per the [issue body](https://github.com/glunk-works/claude-workbench/issues/389) (plan task 2.13; depends on #436 and #374, both closed). Sync main first. The issue's "one review posted on scratch" live run is the human's: report it as hermetically verified, live run deferred. Build on **sonnet** (coder); green gate (slow suites in WSL), `/way-of-working:critic-gate` (architect and security-critic, per the milestone), `/way-of-working:ship`.

**HITL Gate: NONE OPEN** — milestone 17's anchor re-verified (match) before re-anchoring to #389. The next gate is the human's merge of the task PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
