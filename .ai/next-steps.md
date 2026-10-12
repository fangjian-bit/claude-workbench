# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17). Status: **implementing**.

**Just done (2026-10-12):**
- **#479 merged** (#533, `df6f3c5`): every skill and agent that names `{backlog.repo}` now says on that line that `null` means `{repo}`; new `invariants-check.sh` check 12 plus `tests/invariants-null-repo.test.sh` fail a file that omits it. The PR was `Refs #479`, so **#479 is still open**: it guards the wording, and archive-sprint has not been run live on a `null` repo (the issue's "done when"). Close it, or leave it for that run, at your call.
- Critic pass on #479: architect, security-critic and docs-consistency, 2 rounds, converged; all critics ran on their frontmatter defaults (no second-opinion round). Subagent critics only; no fresh-session review gate is configured.

**Next:** task #506 — make unpark-sprint carry an open snapshot `hitl_gate` into its new gate (or have park-sprint refuse a cursor with an open gate), so a parked description-drift or first-anchor gate is not lost on unpark; add a fixture or skill text covering a parked cursor with an open gate; run the green gate, then `/way-of-working:critic-gate` (`architect`, `security-critic`), then `/way-of-working:ship`. Run on **sonnet** (coder). Build order step 26; no dependency.

**HITL Gate: NONE OPEN** — next gate: the human's merge of #506's PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
