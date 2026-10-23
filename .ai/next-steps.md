# Cursor — claude-workbench

**Now:** **Sprint 17** (cursor id `sprint-17`) on [milestone 24, *Green gate in parallel*](https://github.com/glunk-works/claude-workbench/milestone/24), with wave 4 on [milestone 25, *Review follow-ups: tests, docs and guards*](https://github.com/glunk-works/claude-workbench/milestone/25). Status: **implementing**. Live lanes: `lane-state.sh list`.

**Just done (2026-10-23, driver session in the container, opus):**
- **#1016 with #1015 merged** (PR #1027, `0495241`): the broker task's stops end the broker `pwsh`, and its trigger repeats every minute. Lane 1016 cleaned up with `lane.sh done`.
- **Two hotfixes from the host checks, built in this driver session at the maintainer's request:**
  - PR #1031 (`5450357`): `Disable-`/`Enable-ScheduledTask` take no `-Confirm`; the reinstall failed on it. A parser-based check now guards it.
  - PR #1034 (`6ed7ef9`, closes the reopened #1016): the Store app-alias `pwsh` reports the `-File` path unquoted, so the matcher accepts it quoted or bare.
  - Critic passes: #1031 architect, 3 rounds, converged; #1034 architect, 2 rounds, converged. A second-opinion round was offered for each and skipped by the maintainer.
- **Host checks passed on the glunk home** (the only home running a broker): `-Unregister` leaves no broker, a re-register leaves one, a killed broker restarts within a minute, no window opens. The 603id home gets a file refresh only (`install-host-tools.ps1`) until a broker is deployed there.
- **Milestone 24 description:** #1016 (12f) and #1018 (12g) added to the build order; Wave 3 marked done.

**Next:** on **opus** (driver). Start no build here; `next_action` holds the steps: check the ten wave 4 spec comments and their transcripts, confirm their files are disjoint with `lane-groups.sh 25`, and prep their lanes in batches on the maintainer's reactions.

**HITL Gate: NONE OPEN** — next gate: the maintainer reacts to each wave 4 spec comment before its lane is prepped, and approves each lane PR

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 24](https://github.com/glunk-works/claude-workbench/milestone/24) · [milestone 25](https://github.com/glunk-works/claude-workbench/milestone/25) · [.ai/parked/](parked/)
