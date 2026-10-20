# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **implementing**. Lanes run when the maintainer calls them up. The #757 and #728 lanes are building now.

**Just done (2026-10-20, driver session in the container, opus):**
- **#756** merged as #779, and **#746** merged as #780. Both lanes were cleaned up with `lane.sh done`.
- **#746:** the stale spec was redrafted, posted as `6289741742` and approved. Critics ran 2 rounds plus a final fix checked by the driver. The maintainer kept `status/needs-human` as a named label exception.
- **Plan-sprint:** #764 placed at step 23 and #770 at step 24 of milestone 19 (`depends_on` #744 and #629). The description was edited live through `milestone-desc.sh`, which the auto-mode classifier allowed. #223 and #334 were left unmilestoned. Triage comments are posted. Issue bodies were read by a subagent, not the driver.
- **#764:** spec posted as `6290607011` after 2 critic rounds that converged. Built and merged as #781. The lane was cleaned up.
- **#757:** its App-filed body first stopped `hidden` because it typed the openers it is about. The maintainer edited it and reacted again. Spec posted as `6290854228` after 2 critic rounds and a final fix checked by the driver. The lane is building at `/tmp/lanes/757`.
- **#728:** spec posted as `6290983507` after 4 critic rounds and a final fix checked by the driver. The maintainer made three design calls:
  - the pwsh launcher suite runs in CI, and both pwsh suites run on the host;
  - the launcher recreates the container at start of day;
  - while a container runs, the launcher attaches to the recorded one, so a driver restart does not disturb running lanes.
  The lane is building at `/tmp/lanes/728`.
- Every drafter and critic ran on opus, confirmed by `spawn-model.sh`.

**Next:** on **opus** (driver), as the cursor's `next_action` says.
1. When a lane's PR merges and its session has exited, run `lane.sh done <N>` and give the maintainer the milestone 19 command. #728's PR is maintainer-driven: the maintainer pushes the `ci.yml` step and runs both pwsh suites on Windows.
2. Draft each spec only when its lane is next:
   - after #757 merges: #732, then #629, then #770 (all on `spec-post.sh`);
   - after #728 merges: #729 and #762.

**HITL Gate: NONE OPEN** — next gate: the maintainer merges the 757 and 728 lane PRs and reacts to each next spec

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [docs/identity/DEV-CONTAINER.md](../docs/identity/DEV-CONTAINER.md) · [.ai/parked/](parked/)
