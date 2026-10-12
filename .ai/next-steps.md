# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17). Status: **implementing**.

**Just done (2026-10-12):**
- **#478 merged** (#523, `870ce0d`): `bin/app-push.sh` is the one place the App-mode pinned push is spelled; ship, handoff, archive-sprint and the schema interview call it, and `tests/app-push.test.sh` holds each pushing skill to it per push site. The script and its test joined `scripts/loop/protected-paths.txt` (driver-core's entry count updated).
- Critic pass on #478: architect, security-critic and docs-consistency, 3 rounds, converged; all critics ran on their frontmatter defaults (no second-opinion round). The last fix, exact per-file push counts in the fixture, was confirmed by a deliberate mutation, not a fourth critic round. Subagent critics only; no fresh-session review gate is configured.

**Next:** task #476 — make ship check the acting App against `identities.dev_app` before the push, not after the PR (same push path #478 just put behind `bin/app-push.sh`); run the green gate, then `/way-of-working:critic-gate` (`architect`, `security-critic`), then `/way-of-working:ship`. Run on **sonnet** (coder). Build order step 24; its dependency #478 is merged.

**HITL Gate: NONE OPEN** — next gate: the human's merge of #476's PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
