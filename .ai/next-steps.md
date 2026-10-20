# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **implementing**. Lanes run one at a time when the maintainer calls them up. The next ones are #756 and #744, then #761 once its spec is posted.

**Just done (2026-10-19/20, driver session in the container, opus):**
- **Three lanes built and merged:** #759 (#772), #754 (#773) and #755 (#774). Each was cleaned up with `lane.sh done`, and the maintainer set milestone 19 on each PR.
- **Redrafted specs, file-based:** each drafter (a `general-purpose` subagent on opus, model confirmed with `spawn-model.sh`) wrote its own `draft.md` and returned only the path and check words. Critics returned a verdict and terse findings, which went back to the same drafter.
  - #756: posted `6280054245`, 2 rounds plus a one-phrase fix, converged (architect, security-critic, docs-consistency). Approved.
  - #744: posted `6280128174`, 2 rounds plus two small fixes, each checked by diff. Approved.
  - #761: round 1 had 7 findings, all addressed. The confirming round has not run, so it is not posted.
- **Commented on #770** (`6280136680`): proposes a dedicated `spec-drafter` agent with Write limited to its draft directory, so file-based drafting is sanctioned rather than improvised.

**Lessons:**
- **Each merge can make later specs stale.** #772 staled #744, #756, #746 and #728, and #774 staled #761 and #729. Check `spec-fresh.sh` right before each prep.
- **Auto mode blocks the driver's own GitHub writes other than `spec-post.sh`** (a PR's milestone, an issue comment). Hand the maintainer a one-line `!` command, and keep `lane.sh done` in its own call.
- **A removed reaction must be re-added** before `spec-issue.sh` passes. #761's first re-reaction did not take.

**Next:** on **opus** (driver), as the cursor's `next_action` says. First finish the #761 spec: its revised draft is at `/tmp/tmp.vE2I1IYk0V/draft.md`, on base `9c895d6`. Run one confirming critic round on it, then post it with `spec-post.sh`. The maintainer then reacts and removes the reaction from the stale `6276728284`. After that, prepare one lane at a time when the maintainer calls it up: #756 and #744 (disjoint files), then #761. Check freshness before each prep. Redraft the stale #729, #728 and #746, at most 3 per session (#770). #762 waits on #728.

**HITL Gate: NONE OPEN** — next gate: the maintainer says when each lane is up and merges its PR

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [docs/identity/DEV-CONTAINER.md](../docs/identity/DEV-CONTAINER.md) · [.ai/parked/](parked/)
