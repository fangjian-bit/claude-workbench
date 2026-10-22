# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **implementing**. Live lanes: `lane-state.sh list`.

**Just done (2026-10-21 to 22, driver session in the container, opus):**
- **Merged, each lane cleaned up:**
  - #861 (#851, with #852 folded in) as `0c5231a`: the review gate now reads the verdict (WB-D38). The maintainer pushed the workflow half.
  - #860 (#850), #869 (#837), #870 (#753), #872 (#858), #873 (#864, with #863 and #865 folded in), #875 (#838) and #876 (#854, with #855, #856 and #871 folded in).
- **Reviews:** no blocking findings at any merged head. The review container still runs the pinned plugin, so no review carries a `Review verdict:` line yet. That waits for the WB-D38 rollout: reinstall host tools, then bump the pin.
- **Issues:**
  - Closed #728 and #852 as done, and #867 and #868 as duplicates.
  - Filed #862 (lanes set their own milestone) and #874 (no arguments on the gate's checker call).
  - Moved #433 to M20 (this repo passed its check on 2026-10-16) and #866 to M24 (the CI track, with #808, #821, #836 and #877).
- **#874** is building in a lane (PR #880). Its spec wrongly says `scripts/invariants-check.sh` needs a maintainer push. `human_only_paths` binds only the loop, and the lane was told so.
- **Folding works through the issue body:** append the folded issues' text to the spec'd issue's body, then the maintainer reacts. #864, #854 and #842 went this way.

**Next:** task #842 — on **sonnet** (coder), built in a fresh main-checkout session, not a lane. This is #398's last open item. #842's spec comment 6329248894 (the `sh` lookup with the drive-prefix fallback) stays unreacted until the first check below:
1. New window, `/model sonnet`, `/way-of-working:resume`. It must **wait** on its `Spec approval: waiting` line, naming 6329037391 and 6329248894.
2. The maintainer reacts to **6329248894 only**. 6329037391 is the superseded draft, run from PowerShell's PATH.
3. Another new window, `/model sonnet`, `/way-of-working:resume`. It must **auto-start** the #842 build. Its PR needs `wow-review`.
4. Driver (opus): record both results for #398 in `docs/proposals/IDENTITY-SCRATCH-RESULTS.md` through a docs PR, then close #398. M19 closes once #842's PR merges.

Then: check #880 (#874) against spec 6328986998, then #878 with #879 (`test-all.sh`) and the CI track in M24.

For the maintainer:
- Kill the stray #842 spec session (pid 2049393, `/tmp/lanes/spec-wun910`).
- Remove the spec worktrees left at `/tmp/lanes/spec-6xrs7j` and `/tmp/lanes/spec-qjzq7m`.
- Delete the branch `chore/api-commit-live-811`.

**HITL Gate: NONE OPEN** — next gate: the maintainer reacts to the 842 spec comment and approves its PR

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [milestone 24](https://github.com/glunk-works/claude-workbench/milestone/24) · [docs/identity/DEV-CONTAINER.md](../docs/identity/DEV-CONTAINER.md) · [.ai/parked/](parked/)
