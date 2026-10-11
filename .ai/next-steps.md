# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17). Status: **implementing**.

**Just done (2026-10-11):**
- **#432 merged** (#491, `b719f95`), as a **report-only** stall check: `stall-merge.sh` (predicate, 50 fixtures, in CI) and a `pr-checks` step that prints the pinned `gh pr merge --match-head-commit` command for the human. No agent merge: `pr-checks` cannot prove which App holds the token (the App-mode probe compares `project.yml` with itself), so the agent-run merge was cut.
  - Critic pass: architect and security-critic, 2 rounds, converged; on the critics' default models. An Opus second opinion on the disposition agreed with report-only; the second-opinion model was not otherwise used.
  - Not confirmed locally: `tests/driver-core.test.sh` under WSL (nothing it covers changed); `invariants-gh-pipe` passed.
  - Follow-ups filed: #490 (agent-run stall merge once the dev App is proven), #488 (observe a natural stall on scratch), #489 (protect `stall-merge.sh` and its test in the loop's protected paths).

**Next:** task #387 — reword the merge-approval prose for the code-owner gate, per the [issue body](https://github.com/glunk-works/claude-workbench/issues/387) (plan task 2.11; depends on #385, merged). Sync main first. Build on **sonnet** (coder); green gate, `/way-of-working:critic-gate` (docs-consistency, per the milestone), `/way-of-working:ship`.

**HITL Gate: OPEN** — first anchor for milestone 17 in this cursor (no verified baseline this session; description sha `601be343…`, unchanged from the previous anchor); confirm the milestone description is as intended, then go. Next gate after that: the human's merge of the task PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
