# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **implementing**. Three lanes are building: #785, #601 and #458 (`.ai/state.json` `lanes`, from `lane-state.sh list`).

**Just done (2026-10-20, driver session in the container, opus):**
- **Launcher live run passed.** `wow-driver.ps1` and `wow-lane.ps1` started parallel spec sessions and coder lanes, each in its own worktree, and removed the worktree on exit. `wow-lane.ps1 -Issue` sends its own hash-checked first message. Findings: spec sessions can write the driver's memory (now forbidden by a memory rule), and the plugin cache lagged main (fixed by the reinstall below).
- **Merged:**
  - #729 (WB-D34) and #629 (WB-D35);
  - #794, #795 and #796;
  - v0.21.0, released (#801) and pinned (#802), with the plugin reinstalled at project scope;
  - #798, as #803.
- **#636 closed** by #804. The review live run's second pass is recorded in `docs/proposals/IDENTITY-SCRATCH-RESULTS.md` session 9, and `WB-D24` item 7 is marked live-verified. The maintainer accepted items 3 to 7 as unanswered and declined #799.
  - Critic pass on #804: docs-consistency only (the maintainer's choice), 2 rounds, converged.
- **Closed:** #770 (declined) and #799 (declined).
- **plan-sprint.** M19's build order was rewritten: #601 was moved in from M22, and #785, #789, #793, #798, #799 and #800 were added. Specs were posted, critic-gated by their own sessions, and approved by the maintainer for #458, #601 and #785 (#785's revised comment `6304272916`; `6303962552` stays unreacted).

**Next:** on **opus** (driver). No build starts here; the cursor's `next_action` has the steps.
1. Merge order: #785, then #601, then #458. #458 numbers its decision `WB-D37` (#601 takes `WB-D36`), merges main before its PR, and its workflow file is pushed by the maintainer.
2. As each lane PR is reported, review it against its spec. Once it merges and its session exits, run `lane.sh done <N>` and hand over the milestone-19 command.
3. Once #458 merges, every PR that touches `plugins/` needs a reviewer-App review, through `wow-review` or the poller (#626). Register the poller after scratch #32 (probe cleanup) merges.
4. For the maintainer, by hand:
   - M19's frame prose still says "#601 moved to milestone 22", and M22's description still lists #601. `plan-depends.sh` cannot edit frame text.
   - Queued spec work: #789's lane (approved), #403 (M23) and #800 (after #601 is released).

**HITL Gate: NONE OPEN** — next gate: the maintainer reviews and merges the 785, 601 and 458 lane PRs in that order

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [docs/identity/DEV-CONTAINER.md](../docs/identity/DEV-CONTAINER.md) · [.ai/parked/](parked/)
