# Cursor — claude-workbench

**Now:** **Sprint 17** (cursor id `sprint-17`) on [milestone 24, *Green gate in parallel*](https://github.com/glunk-works/claude-workbench/milestone/24). Status: **implementing**. Live lanes: `lane-state.sh list`.

**Just done (2026-10-23, driver session in the container, opus):**
- **Test-speed push.** The launcher suite runs its sections at once (#937, PR #954, `eca1308`): its CI step went from 154–201 s to 96 s. The review launcher suite did the same (#955, PR #967, `8db2202`): 131–155 s to 46 s, 26 s locally. `tests (2)` is now the slowest CI job.
- **Wave 2.**
  - test-all: the held-out fixture witnesses start order (#878, PR #951, `8e83746`), and the runner reads its job table without a pipeline subshell (#879, PR #966, `dbc89e7`).
  - Area taxonomy in `CLAUDE.md` with every open issue labelled (#835, PR #950, `a8d2516`). A `pr-title` check runs it against each PR title, workflow pushed host-side (#839, PR #962, `99516c4`).
  - Retro screens the transcript reader's report (#914 with #916, PR #956, `2e58d01`), the reader writes no absolute path or secret (#961 with #957, PR #976), its parity and byte fixtures are pinned (#959 with #960, PR #975), and the screen is on the loop's protected list (#958, PR #971).
- **wow-lane `-Spec` guard and `-SpecSweep`** (#891, PR #977, `16feb30`). Reinstalled into both glunk-identity and 603id-identity from `16feb30`, and the sweep was run.
- Filed and placed the review follow-ups on M24 (#978 to #982, with #970 and #965 folded into #972, #980 into #979, #982 into #981). #964 was closed as intended and #969 as resolved.
- Critic passes ran in each spec and lane session. Their outcomes are in each PR body.

**Next:** on **opus** (driver). Start no build here; `next_action` holds the steps. Start the next wave as lanes: #978 (the CI `pwsh` guard) first, then #934, #968, #972, #981 and #894, then #952 and #979.

**HITL Gate: NONE OPEN** — next gate: the maintainer reacts to each spec comment before its lane is prepped

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 24](https://github.com/glunk-works/claude-workbench/milestone/24) · [.ai/parked/](parked/)
