# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17), anchored at `06656e9`. Status: **implementing**.

**Just done (2026-10-10/11):**
- **#464 PR 1 merged** (#471, ship's App-mode preflight). The merge closed #464 by mistake, so it was **reopened**: its PR 2, the human-attended end-to-end skill runs under a dev-App token, has not happened.
- **#467 built** as [PR #472](https://github.com/glunk-works/claude-workbench/pull/472) (`Closes #467`): `pr-checks` block (c) prints `actor app -` under an App token instead of failing on `gh api user`; fixtures for it in `tests/blocked-state-block.test.sh`. Critic pass: architect, security-critic and docs-consistency, 3 rounds, converged, all on default models. Not merged.
- **Run sheet for #464 PR 2** drafted as [PR #473](https://github.com/glunk-works/claude-workbench/pull/473) (`docs/identity/APP-MODE-RUN-SHEET.md`, `Refs #464`). Docs only, no critic pass. The expectations for archive-sprint, plan-sprint and retro in it are guesses and marked so.

**Next:** task #384 — build the ruleset verdicts for the code-owner gate per the [issue body](https://github.com/glunk-works/claude-workbench/issues/384). Start only after the human has merged #472 (same `pr-checks` block (c) and `blocked-state.sh`); sync main first. Build on **sonnet** (coder); green gate, `/way-of-working:critic-gate`, `/way-of-working:ship` with `Closes #384`.

**HITL Gate: OPEN — the human merges #472 and #473 first. #464's PR 2 (the six interactive runs under a dev-App token, per the run sheet) is the human's and still outstanding; #464 stays open until it is recorded.**

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
