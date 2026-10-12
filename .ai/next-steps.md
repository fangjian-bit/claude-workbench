# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17). Status: **implementing**.

**Just done (2026-10-12):**
- **#347 merged** (#516, `651539c`). The pin-bump section of `reference/conventions.md` gains a fail-closed mirror step for the other drive-letter casing of the `installed_plugins.json` record, verify-by-commit now requires every record for the project path to carry the sha, and the `ls-remote` listing also asks for the peeled `<ref>^{}` line. The CHANGELOG header points at it.
  - Critic pass: `architect`, `security-critic`, `docs-consistency`; 2 fix-and-re-run rounds plus a final docs pass, converged. On the critics' default models; no second-opinion round. No review CI gate here, so this pass and the merge were the only checks.
- **Backlog triage** (`/way-of-working:plan-sprint`, the human accepted the recommendation whole). Every write applied and read back; nothing staged.
  - Milestone 17's build order gains steps 23–33 before the release (now step 34): #478, #476, #479, #506, #510, #517, #451, #452, #498, #497, #496. The human authorized writing this anchored description; the anchor now reads `drift` until re-anchored.
  - #515 → milestone 18 (step 3); #514 → milestone 19 (step 1, and #397 now also waits on it); #489, #488, #490 → milestone 23 (steps 4–6, before #404).
  - #223 and #334 left unmilestoned (unchanged decisions, already recorded on each).

**Next:** `/way-of-working:handoff` re-anchors milestone 17 on its new description, with task #478 as the first one. Run on **opus** (architect) for the handoff; the build items are `sonnet`. Starts nothing until the gate closes.

**HITL Gate: OPEN** — the human decides that placement. A build-order edit changes the milestone description, so a `/way-of-working:handoff` re-anchor follows it. Placement decided 2026-10-12 (milestone 17 steps 23–34); the description changed, so the re-anchor is still pending.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
