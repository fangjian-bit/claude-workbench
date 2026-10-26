# Cursor — claude-workbench

**Now:** **Sprint 18** (cursor id `sprint-18`), status **implementing**, working from milestone 20, *Identity M5: glunk-works repos cut over*. Live lanes: `lane-state.sh list`.

**Just done (2026-10-26, driver session in the container, opus):**
- **Pre-cutover Fable pass on `v0.27.0`:** four read-only lenses on `models.second_opinion` (the 0.15.0 to 0.27.0 upgrade, the identities cutover from a repo's side, several repos on one host, the `bin/` trust paths); each blocks-cutover finding re-checked by hand. The maintainer triaged them one decision at a time.
- **Filed:** #1158 (consuming-repo cutover runbook and add-a-repo host steps, milestone 20), #1159 (`cursor-drift.sh` and `token-check.sh` fail-open inputs, milestone 20), #1160 (how `review-step.sh`'s auto start proves freshness, a design question, unmilestoned), #1161 (multi-repo host hardening, unmilestoned). The someday findings are one dated comment on #1158.
- **Folded into issue bodies:** the schema completion step before the pin bump, the label rename and the pin-bump notes into #406 to #410 (repo-specific notes on #407 and #409); the multi-repo lane scope into #715.
- **Milestone 20's description** rewritten via `milestone-desc.sh` (read-back `ok`): #1158 first, #409 and #410 depend on it, #1159 added, the Lanes and Model per phase lines updated.
- Open suggestion, not yet decided: put the repo name in the first message of driver, lane and spec launches (session tab label), as a sixth item on #1161.

**Next:** task #1158 — on **opus** (driver, fresh session): draft its spec with `/way-of-working:spec-task 1158`, then wait for the maintainer's reaction; build it as a lane only when the maintainer says so. #406 to #408 can run on the maintainer's side in parallel.

**HITL Gate: OPEN** — first anchor for milestone 20: the maintainer confirms sprint 18 works from milestone 20 with #1158 first

**Critic pass:** none in this driver session (no diff: issue writes, milestone description edits and this ledger). The Fable lenses were a pre-cutover review, not a critic-gate pass.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 20](https://github.com/glunk-works/claude-workbench/milestone/20) · [.ai/parked/](parked/)
