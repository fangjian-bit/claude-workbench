# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17). Status: **implementing**.

**Just done (2026-10-12):**
- **#390 merged** (#504, `947591f`). The SessionStart banner now ends with `Acting as:` and `Admin mode:` lines. The admin token is read from the fixed mount `/run/wow/admin-token` (always checked, never filtered); `WOW_ADMIN_TOKEN_FILE` only adds a fixture candidate. Tests: `tests/ai-cursor-banner.test.sh`.
  - Critic pass: `architect` and `security-critic`, 4 fix-and-re-run rounds, converged; on the critics' default models; the `fable` second-opinion round was offered and declined.
  - Stated residuals: a repo that controls the session's settings (`BASH_ENV`, `PATH`, `disableAllHooks`, a hook of its own) can suppress any hook, this one included; a well-shaped token file outside the checkout reads `ADMIN MODE` (the shape check is local); under an App token the banner cannot say which App. Worth recording against WB-D24.

**Next:** task #360 — make `resume` run `plan-anchor.sh verify` even when it waits on an open gate, per the [issue body](https://github.com/glunk-works/claude-workbench/issues/360); check `handoff`'s baseline wording against it; add a `tests/` case if a predicate changes. Next in the milestone's build order. Sync main first. Build on **sonnet** (coder); green gate (slow suites in WSL), `/way-of-working:critic-gate` (architect and security-critic, per the milestone), `/way-of-working:ship`.

**HITL Gate: NONE OPEN** — milestone 17's anchor verified (match) before re-anchoring to #360. The next gate is the human's merge of the task PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
