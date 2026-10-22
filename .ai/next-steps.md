# Cursor — claude-workbench

**Now:** **Sprint 17** (cursor id `sprint-17`) on [milestone 24, *Green gate in parallel*](https://github.com/glunk-works/claude-workbench/milestone/24). Status: **implementing**. Live lanes: `lane-state.sh list`.

**Just done (2026-10-22, driver session in the container, opus):**
- **Wave 1 of M24 ran as lanes and merged** (the milestone's Lanes section lists each issue and PR):
  - CI's tests job is split into three parallel jobs and runs every suite through `scripts/test-all.sh -x` (#808 with #821, #836, #866, #877 and #881 folded in, PR #913, `90aa472`). The required `invariants` job also runs `tests/review-verdict.test.sh`.
  - spec-task judges an App issue's reaction by its content time (#890, PR #919, `08584c4`). A spec post, label or milestone change no longer stales the reaction.
  - Retro's transcript reader is confined by its tool list (#899, PR #911, `3f9b59c`). Check 24 stops reading quoted hashes as comments (#882, PR #917, `971f318`; spec posted by the maintainer after a critic-cap escalation).
  - Follow-ups #892, #912, #918, #903, #915 and #923 merged too (PRs #910, #921, #926, #924, #928 and #929). #922 was closed as a duplicate of #881.
- **Triage:** #914 (with #916 folded in), #915 and #923 were placed on M24. #920 was left unmilestoned for the next plan-sprint pass. #894's body gained the lane-tab-title note.
- Critic passes ran in each spec and lane session; their outcomes are in each PR body.

**Next:** on **opus** (driver). Start no build here; `next_action` holds the test-speed push. Tests now run every suite on every push, so the push looks for where local and CI test time goes and cuts it, as lanes. #900's spec comment awaits the maintainer's reaction, and the rest of wave 2 is in M24's Lanes section.

**HITL Gate: NONE OPEN** — next gate: the maintainer reacts to each spec comment before its lane is prepped

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 24](https://github.com/glunk-works/claude-workbench/milestone/24) · [.ai/parked/](parked/)
