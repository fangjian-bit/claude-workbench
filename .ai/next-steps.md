# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17), anchored at `d1d17ee`. Status: **implementing**.

**Just done (2026-10-11):**
- **#386 merged** (#485, `d1d17ee`). `ship` arms `gh pr merge --auto --squash --match-head-commit` through `bin/auto-merge-arm.sh`, only where the repo allows auto-merge **and** the base requires a code-owner approval; `gh --auto` merges a mergeable PR at once (`IDENTITY-SCRATCH-RESULTS.md` case k), so anything else reports `not armed`. Here it reports `disallowed` (`allow_auto_merge` is off, the rule needs 0 approvals). Bypass of the arming identity and `CODEOWNERS` coverage are recorded as WB-D24 residuals.
  - Critic pass: architect, security-critic, docs-consistency, 4 rounds, converged; all on the critics' default models; the second-opinion round was declined.
  - **#486 is open** (not merged): adds `auto-merge-arm.sh` and its fixtures to `scripts/loop/protected-paths.txt`, and bumps the entry count in `tests/driver-core.test.sh` and the loop README. `driver-core.test.sh` passes under WSL, not Git Bash.
  - Follow-ups not filed: a `next_action` vs ledger **Next:** comparison (nothing shows `next_action` beside a merged ledger), an invariants check banning `--admin` and agent-run `gh pr merge`, and WB-D24's opening sentence ("until a repo's cutover … keeps today's model"), now inexact for #384 and #385; also handoff's cursor-sync PR is still a plain `gh pr create` (nothing arms it); the older "the human's merge is the approval" lines in `handoff`, `archive-sprint`, `architect-review` and `workflow.md` are still true for unarmed PRs.

**Next:** task #432 — merge an approved PR whose armed auto-merge has stalled, per the [issue body](https://github.com/glunk-works/claude-workbench/issues/432). Sync main first. Build on **sonnet** (coder); green gate (slow suites in WSL), `/way-of-working:critic-gate`, `/way-of-working:ship`.

**HITL Gate: OPEN** — the issue leaves open where the stall check runs (resume, pr-checks, or both) and it adds an agent-run merge, so the human confirms the placement before the build. The gate after that is the human's merge of the task PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
