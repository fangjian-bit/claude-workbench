# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17). Status: **implementing**.

**Just done (2026-10-11):**
- **#387 merged** (#493, `1f1dfeb`). The merge-approval prose now reads as a human code-owner approval in `workflow.md` and the `architect-review`, `archive-sprint`, `handoff` and `critic-gate` skills; the human's merge stays named where no code-owner approval is required. Status lines ("awaits the human's merge") and historical docs are unchanged.
  - Critic pass: docs-consistency, 3 rounds, converged; on the critic's default model; the second-opinion round was declined.
  - Left alone on purpose (still true while nothing arms auto-merge on handoff's PR): `workflow.md:294` and `auto-start-rationale.md` ("a merge on GitHub approves the ledger's **Next:**"), and `handoff` lines 7 and 296 ("the human merges").

**Next:** task #383 — require a maintainer reaction on the spec before unattended start, per the [issue body](https://github.com/glunk-works/claude-workbench/issues/383) (plan task 2.7; depends on #382, closed). Sync main first. Build on **sonnet** (coder); green gate (slow suites in WSL), `/way-of-working:critic-gate` (architect and security-critic, per the milestone), `/way-of-working:ship`.

**HITL Gate: NONE OPEN** — milestone 17's anchor re-verified (match) before re-anchoring to #383. The next gate is the human's merge of the task PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
