# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17), anchored at `06656e9`. Status: **implementing**.

**Just done (2026-10-11):**
- **#464 closed.** PR 2, the skills run as interactive sessions under a dev-App token on the scratch repo, is recorded as session 7 in [IDENTITY-SCRATCH-RESULTS.md](../docs/proposals/IDENTITY-SCRATCH-RESULTS.md) (#477, merged). Every skill on the sheet ran; the designed `mismatch` stop was seen live with a wrong `dev_app` declaration standing in for a wrong credential; pr-checks block (c) is unreachable under the approval ruleset, which is #384's territory.
- **Follow-ups filed from the runs:** #476 (ship checks the acting App before the push), #478 (handoff and archive-sprint push as the human in App mode, so the human's own approval cannot count), #479 (archive-sprint reads a null `backlog.repo` as no repo), and a note on #386 (ship arms auto-merge). #475 was a duplicate of #386 and is closed.
- #472 (#467) and #473 (the run sheet) merged earlier; #474 synced the cursor.

**Next:** task #384 — build the ruleset verdicts for the code-owner gate per the [issue body](https://github.com/glunk-works/claude-workbench/issues/384). Sync main first. Build on **sonnet** (coder); green gate, `/way-of-working:critic-gate`, `/way-of-working:ship` with `Closes #384`.

**HITL Gate: NONE OPEN** — next gate is the human's merge of the task PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
