# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **implementing**. No lanes are running. Work is paused for the maintainer's live run of the host launchers.

**Just done (2026-10-20, driver session in the container, opus):**
- **#757** merged as #784 and **#728** merged as #783. #783 carries the maintainer's CI step for `tests/identity-launchers.test.sh`.
- **#732:** spec posted as `6292588902` after 2 critic rounds plus a final fix checked by the driver. Built and merged as #786.
- **#762:** built before the live run because it changes the same launcher surface. Spec posted as `6293743604` after 2 critic rounds (security converged in round 2) plus a final fix checked by the driver. Built and merged as #787.
- The 757, 728, 732 and 762 lanes were cleaned up with `lane.sh done`.
- Every drafter and critic ran on opus, confirmed by `spawn-model.sh`.
- **#729:** the maintainer said to hold it. A draft was written but never reviewed or posted, and it is not kept. The maintainer's reaction on #729 is fresh.

**Next:** on **opus** (driver), as the cursor's `next_action` says.
1. Wait for the maintainer's live run. `wow-driver.ps1` recreates the container; `docker inspect` should show exactly the five mounts `devcontainer.json` declares; a lane should start through `wow-lane.ps1`.
2. Once it passes: redraft #729 against the then-current main, then #629, then #770, each critic-gated and posted with `spec-post.sh`.

**HITL Gate: OPEN** — the maintainer runs wow-driver and wow-lane live on the Windows host (the container is recreated, which ends this session and every lane) and reports the result before any spec or lane work starts

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [docs/identity/DEV-CONTAINER.md](../docs/identity/DEV-CONTAINER.md) · [.ai/parked/](parked/)
