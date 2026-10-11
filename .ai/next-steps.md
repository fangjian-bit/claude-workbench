# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17), anchored at `06656e9`. Status: **implementing**.

**Just done (2026-10-11):**
- **#384 merged** (#481, `9980401`). `blocked-state.sh` takes `reviewDecision`, prints `awaiting-approval`, and no longer prints `admin-merge-ready`. `pr-checks` gained the AWAITING APPROVAL verdict and a pinned-app check (block a2), and lost the admin-merge verdict and block (c). `cursor-sync-pr.sh` refuses a review-only block as `awaiting-approval`. `resume` reads a `rulesets` list, and an approval ruleset with any bypass actor is drift (a bypass list it cannot see is inconclusive, never zero).
  - Critic pass: architect, security-critic, docs-consistency, 2 rounds, converged; all on the critics' default models.
  - Behaviour change to expect until each repo cuts over: a green PR held only by a `restrict-updates` rule reads COULD NOT TELL, not READY (admin merge).
  - Unmeasured: whether GitHub sends `bypass_actors` as absent or `null` to a non-admin token (handled either way); org rulesets likely read inconclusive under a repo-scoped token.
- #464 closed and session 7 recorded earlier (#477, #480).

**Next:** task #385 — remove resume's agent-run `--admin` cursor-sync merge, per the [issue body](https://github.com/glunk-works/claude-workbench/issues/385); it also closes #368. Sync main first. Build on **sonnet** (coder); green gate, `/way-of-working:critic-gate`, `/way-of-working:ship`.

**HITL Gate: NONE OPEN** — next gate is the human's merge of the task PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
