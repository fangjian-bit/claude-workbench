# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17), anchored at `06656e9`. Status: **implementing**.

**Just done (2026-10-11):**
- **#385 merged** (#483, `bcd5167`); it closes #368. `cursor-sync-pr.sh` is report-only (two arguments; `none | open | refuse | ambiguous | unmerged | unreadable`), resume's step 2 *Report a forgotten cursor-sync PR* merges nothing, and no `--admin` remains in `plugins/`. `appendices/cursor-sync-offer.md` is deleted.
  - Critic pass: architect, security-critic, docs-consistency, 3 rounds, converged; all on the critics' default models; the second-opinion round was declined.
  - Not verified locally: `tests/invariants-gh-pipe.test.sh` (one fixture path changed) did not finish here (over 9 minutes); `tests/driver-core.test.sh` timed out at 110s and is untouched. CI ran them on #483.
  - Handoff's cursor-sync PR is opened with plain `gh pr create`; nothing arms auto-merge on it until #386 lands, so it still waits for a human merge.
  - Follow-ups not filed: a `next_action` vs ledger **Next:** comparison (nothing now shows `next_action` beside a merged ledger), an invariants check banning `--admin` and agent-run `gh pr merge`, and WB-D24's opening sentence ("until a repo's cutover … keeps today's model"), now inexact for #384 and #385.

**Next:** task #386 — make `ship` arm auto-merge after opening the PR, per the [issue body](https://github.com/glunk-works/claude-workbench/issues/386) (plan task 2.10; depends on #380, closed). Sync main first. Build on **sonnet** (coder); green gate, `/way-of-working:critic-gate`, `/way-of-working:ship`.

**HITL Gate: NONE OPEN** — next gate is the human's merge of the task PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
