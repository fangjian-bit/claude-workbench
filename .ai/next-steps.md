# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17). Status: **implementing**.

**Just done (2026-10-12):**
- **#539 merged** (#554, `758fcaf`): `unpark-sprint` step 1 reads `parked_from_commit` and `parked_at` with `jq -r` before the move deletes the snapshot, keeps only a lowercase-hex commit id and a plain `YYYY-MM-DD` date, and prints one `PFC/PA/ANC` line that step 2 builds the gate from. No printed line stops the skill before the move. `invariants-check.sh` check 13 pins the read and the guard and fails when the skill file is missing; `tests/invariants-unpark-pfc.test.sh` has five fixtures.
- Critic pass on #539: `security-critic`, `architect` and `docs-consistency`, initial pass plus 3 fix-and-re-run rounds, converged (round 3 architect only); critics on their frontmatter defaults. No second-opinion round was offered. Subagent critics only; no fresh-session review gate is configured.
- Not covered, said in the PR: a hex id that is also a ref name resolves to that ref's commit (resume does the same); an ISO datetime `parked_at` falls back to the "unreadable date" gate text. The fixtures ran under Git Bash only. The fixture takes about two minutes there.

**Next:** task #541 — `resume`'s auto-start gate test says `hitl_gate` must begin `NONE OPEN`, with #542 (`plan-sprint` stops saying drift is caught at unpark) and #543 (`handoff`, `archive-sprint` and `unpark-sprint` agree on the HITL Gate line and its name) as one prose PR; then the green gate, `/way-of-working:critic-gate` (`docs-consistency`, `architect`), then `/way-of-working:ship`. Run on **sonnet** (coder). Build order steps 38–40; no dependency. #540 (step 37) and #496 (step 33) need the human to pick their option first, so each ships as its own PR after.

**HITL Gate: NONE OPEN** — next gate: the human's merge of #541's PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
