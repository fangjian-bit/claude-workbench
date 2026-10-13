# Cursor — claude-workbench

**Now:** **Sprint 15** (cursor id `sprint-15`) on [milestone 18, *Identity M3: host broker and dev container*](https://github.com/glunk-works/claude-workbench/milestone/18). Status: **implementing**.

**Just done (2026-10-13):**
- #515 closed: the host token broker was verified live under its scheduled task against the real dev App, installed from a clone no container opens (`4c5f9c1`). Rotation, sleep/wake and the container mount are recorded on the issue. The Docker mount passed with no sharing violation, so the retry path stayed unexercised.
- Filed #578 (`register-broker-task.ps1` throws a null-property error when `sh` is not on PATH) and #579 (normalize line endings so the dev container and a Windows checkout agree).
- Host config set: `WOW_HOME` and the identity `bin` directory are on the Windows user environment.
- The milestone 18 description was confirmed by the human with a go at resume; the anchor re-verified as `match` and was re-taken for #522.

**Next:** task #522 — read-only prep: check the entra repo's merge settings and ruleset, and draft the `required_signatures` ruleset JSON and `gh api` commands for the two terraform repos as text in the issue, running no write against any repo. The `.devcontainer/` edits and the live container signing checks are the human's. After it: #574. On **sonnet** (coder).

**HITL Gate: NONE OPEN** — next gate: the human merges the 522 PR and runs the live container signing checks

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 18](https://github.com/glunk-works/claude-workbench/milestone/18) · [.ai/parked/](parked/)
