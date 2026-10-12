# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17). Status: **implementing**.

**Just done (2026-10-12):**
- **#529 merged** (#550, `c4e80ad`): `architect-review` proves the reviewer App via GraphQL `viewer` and `token-check.sh verify reviewer_app` before it posts; the post-response check stays as a backstop. The "unproven" wording in `project-schema.md`, `review-step.sh` and `resume` now says the derivation does not prove the App; App mode still never reaches `auto`.
- Critic pass on #529: `security-critic`, `architect` and `docs-consistency`, 2 rounds, converged; critics on their frontmatter defaults. The second-opinion round on `fable` was offered and declined. Subagent critics only; no fresh-session review gate is configured.
- Not covered: the App-mode post block has no automated test; its live run on the scratch repo is the human's.

**Next:** task #530 — `coupling-check.sh` catches hardcoded App logins like `glunk-dev[bot]`, with a fixture in `tests/coupling-check.test.sh`; then the green gate, `/way-of-working:critic-gate` (`architect`, `security-critic`), then `/way-of-working:ship`. Run on **sonnet** (coder). Build order step 35; no dependency. Build-order step 33 (#496) is still skipped: its issue says the human picks between two options first.

**HITL Gate: NONE OPEN** — next gate: the human's merge of #530's PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
