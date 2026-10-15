# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**.

**Just done (2026-10-15):**
- Task #611 shipped: PR #622 (`025c0e9`) adds the `/way-of-working:spec-task` skill.
  - Critic pass on #622, carried from its PR body (not re-verified here): 7 rounds, past the cap of 4 at the maintainer's request, stopped because the human called it, not formally converged. Round 7: the architect found no real defects, and the security-critic found one (check 18 allowed flags before `gh issue`/`gh pr` but not `gh label`/`gh api`), fixed with no further re-run. Every critic ran on its own frontmatter model. Its fetch-and-check shell block has only run against stubs, never a live issue.
- #514 decided and closed: PR #624 (`1e33fce`) adds WB-D24 item 7 (reviewer tokens never enter a dev container, App-mode review runs on a fresh host session now and in a host-launched review container later) and a short paragraph in the `architect-review` skill.
  - Critic pass on #624: architect, security-critic and docs-consistency ran for 2 rounds (the initial pass plus 1 fix-and-re-run round, under the cap of 4), converged: round 2 returned wording tightenings only, applied without a further re-run. Every round ran on the critics' own frontmatter models; no second-opinion round was run.
- The host review session's read credential is open on purpose: the reviewer mint has no Issues or Actions access and reaches one repo, so #623 (the host-launched review container) settles it. It blocks #398's review step, and #400 must not land before it.
- The private plan (local file and both draft advisories) and `603-Identity/devcontainers#392` were corrected to match.
- The no-op handoff did not apply (#622 merged before this handoff), so this is the ordinary ledger PR.

**Next:** plan the next task of milestone 19 with the maintainer: #433 is next in the build order and is human-only, so pick the next buildable open issue (or #433's human step), post its spec comment for the maintainer to react to, then `/way-of-working:handoff` to anchor it. On **opus** (architect), in a fresh session.

**HITL Gate: NONE OPEN** — next gate: maintainer reaction to the next task spec comment

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
