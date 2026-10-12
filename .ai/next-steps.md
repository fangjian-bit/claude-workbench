# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17). Status: **implementing**.

**Just done (2026-10-12):**
- **#530 merged** (#552, `0e99fc3`): `coupling-check.sh` has a Tier 4 for App logins (`glunk-<role>`, `603id-<role>`, the `603-Identity` org and `603identity-*` repos). Tier 2, Tier 4 and the maintainer login run in a second, case-insensitive grep pass; Tier 1 and Tier 3 stay case-sensitive. Fixtures in `tests/coupling-check.test.sh`, including a grep that errors only on the `-i` pass.
- Critic pass on #530: `architect`, `security-critic` and `docs-consistency`, 3 rounds, converged; critics on their frontmatter defaults. No second-opinion round was offered. Subagent critics only; no fresh-session review gate is configured.
- Not covered, stated in the script: numeric App/client/installation ids, other user logins, separator and Unicode lookalikes. The fixtures ran under Git Bash only, not WSL.

**Next:** task #539 — `unpark-sprint` validates `parked_from_commit` before it reaches `git log` or `merge-base`, with a fixture; then the green gate, `/way-of-working:critic-gate` (`architect`, `security-critic`), then `/way-of-working:ship`. Run on **sonnet** (coder). Build order step 36; no dependency. #540 shares the step but needs the human to pick its option first, so it ships as its own PR after. #496 is still skipped for the same reason.

**HITL Gate: NONE OPEN** — next gate: the human's merge of #539's PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
