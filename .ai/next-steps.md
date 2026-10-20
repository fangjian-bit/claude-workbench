# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **implementing**. Lanes run when the maintainer calls them up. The #756 lane is in flight now.

**Just done (2026-10-20, driver session in the container, opus):**
- **#761:** the spec was redrafted, posted (`6280407609`) and approved, then built and merged as #776. The lane was cleaned up with `lane.sh done`.
  - Critic pass on the spec: 3 rounds (architect, security-critic, docs-consistency), all on opus, confirmed by `spawn-model.sh`. Round 3's fixes went back to the same drafter. The driver then checked the final draft by reading it end to end and posted it, with no fourth round.
- **#744:** its spec went stale when #776 changed `docs/decisions.md`, but in WB-D24, which #744 does not touch. It got a **light refresh**: the same text re-posted on the new base (`6281226099`, no critic round). It was then built and merged as #777, and its lane was cleaned up.
- **#756:** lane prepared (`/tmp/lanes/756`, branch `docs/resume-bad-shape-line`). It is building now.
- #776 and #777 are both on milestone 19.

**Lessons (also in the driver's memory):**
- **Respecs waste compute.** Draft a spec only when its lane is next, or when its files are disjoint from every lane queued ahead of it. Run tasks that share a file back to back. Mark append-only files `**(append)**` in Files touched.
- **Light refresh, approved by the maintainer.** A stale spec whose cited text, named sections and line numbers did not change is re-posted on the new base with no critic round, checked by diff.
- **Verify every critic sub-claim before forwarding it.** One #761 round was spent fixing a false claim the driver had passed on.
- **The next lane is #746, after its spec is redrafted.** `#728` overlaps #746 on `docs/decisions.md` and `CLAUDE.md`, so it waits until #746 merges. `#729` overlaps #756 and #728, so it waits for both. `#757`, `#732` and `#629` follow #746.

**Next:** on **opus** (driver), as the cursor's `next_action` says.
1. Redraft the stale #746 spec: a fresh drafter, critics to convergence, then post it with `spec-post.sh`. The maintainer then reacts and removes any reaction from the stale `6276937014`.
2. When the #756 PR merges and its lane has exited, run `lane.sh done 756` and give the maintainer the milestone command.

**HITL Gate: NONE OPEN** — next gate: the maintainer reacts to the 746 spec, says when each lane is up and merges its PR

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [docs/identity/DEV-CONTAINER.md](../docs/identity/DEV-CONTAINER.md) · [.ai/parked/](parked/)
