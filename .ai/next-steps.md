# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17). Status: **implementing**.

**Just done (2026-10-12):**
- **#313 merged** (#511, `6fecc96`). `/reload-plugins` is named beside "restart" in `archive-sprint` step 8, the CHANGELOG header, `reference/conventions.md` and the generated release notes (`.github/workflows/release.yml`), and `/clear` is stated to be neither. The optional resume loaded-vs-pinned line was not done.
  - Critic pass: `architect`, `security-critic`, `docs-consistency`; 2 fix-and-re-run rounds, converged. On the critics' default models; no second-opinion round.
  - Follow-up filed: #510 (step 8 and the CHANGELOG header still teach `claude plugin update`, a silent no-op on project-scoped installs). Unmilestoned; place it.

**Next:** task #347 — add the drive-letter mirror-and-verify step to the pin-bump procedure, per the [issue body](https://github.com/glunk-works/claude-workbench/issues/347). Next in the milestone's build order. It edits the same procedure as #510, so read #510 first. Sync main first. Build on **sonnet** (coder); green gate (slow suites in WSL), `/way-of-working:critic-gate` (architect and security-critic, per the milestone), `/way-of-working:ship`.

**HITL Gate: NONE OPEN** — milestone 17's anchor verified (match) before re-anchoring to #347. The next gate is the human's merge of the task PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
