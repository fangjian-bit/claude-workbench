# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17). Status: **implementing**.

**Just done (2026-10-12):**
- **#347 merged** (#516, `651539c`). The pin-bump section of `reference/conventions.md` gains a fail-closed mirror step for the other drive-letter casing of the `installed_plugins.json` record, verify-by-commit now requires every record for the project path to carry the sha, and the `ls-remote` listing also asks for the peeled `<ref>^{}` line. The CHANGELOG header points at it.
  - Critic pass: `architect`, `security-critic`, `docs-consistency`; 2 fix-and-re-run rounds plus a final docs pass, converged. On the critics' default models; no second-opinion round. No review CI gate here, so this pass and the merge were the only checks.
  - Follow-up filed: #517 (carry the mirror step into the `release.yml` release notes and `archive-sprint` step 8). Unmilestoned; do it together with #510.

**Next:** the milestone's build order is exhausted except #391 (the release, which the human dispatches). Ask the human what follows: place #476 and #478 (in the milestone, not in the build order) and #510 and #517 (unmilestoned), or release first. Run on **opus** (architect). Starts nothing until the gate closes.

**HITL Gate: OPEN** — the human decides that placement. A build-order edit changes the milestone description, so a `/way-of-working:handoff` re-anchor follows it.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
