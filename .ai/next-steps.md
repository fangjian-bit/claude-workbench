# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **implementing**. No lanes are live.

**Just done (2026-10-21, driver session in the container, opus):**
- **The three lanes merged and were retired** (`lane.sh done`), each reviewed against its approved spec before the maintainer's approval:
  - #785 as #806 (`ac3fd8c`);
  - #601 as #807 (`ff87b6b`, `WB-D36`, the `api` commit route, not turned on here: #800);
  - #458 as #813 (`c49b654`, `WB-D37`). Pushed and opened as the admin App (`wow-admin`, since revoked).
- **The review gate is live.** `main` sets `review.ci_gate`, and the live `main-required-checks` ruleset requires `architect-review`, pinned to GitHub Actions (15368). Every PR touching `code_paths` now needs a reviewer-App review on its head.
- **`wow-review-poll` is registered** on the host (`glunk-wow-review-poll`, installed from `c49b654`) and polls this repo. It failed on every tick until the task's `WOW_HOME` was hand-edited to forward slashes, because the poller rejects the backslash form its own registration writes (#816). Do not re-register it until #816 merges.
- **Filed:** #808, #809 and #810 (parallel tests: CI split, a local runner, `invariants-check.sh --only`); #811 (the `api` route cannot publish a refreshed branch; blocks #800, commented there); #812 (`WB-D36`'s live checks on the 603-Identity repos); #814 (the banner's admin line watches the wrong path); #815 (scope `wow-review`'s cap and sweep to one identity home); #816.
- #806, #807 and #813 merged with no reviewer-App review, as planned before the gate. A fresh-session look at #807's code was offered and not taken up.
- **Milestone prose fixed:** M19's frame now says #601 came back and merged as #807; M22 marks #601 done and drops it from the lanes and model lines.
- **`plan-sprint` triage, all live, nothing staged:** #811 (before #800), #797 and #814 placed on M19; #815 and #812 on M22 (after #589); new milestone 24, *Green gate in parallel* (due 2026-11-20): #810, #809, #808. Both build-order edits went through `milestone-desc.sh` (`live ok`). #223, #334, #790, #791 and #792 stay unmilestoned, already recorded by their 2026-10-20 triage comments. #816 was left alone while its spec is drafted.

**Next:** on **opus** (driver). No build starts here; the cursor's `next_action` has the steps.
1. The maintainer launches a `wow-lane -Spec` session for #816. Once its spec comment has a reaction and the maintainer says so, prep the lane and hand over its `wow-lane -Issue` command.
2. #816's PR is under `scripts/`, so it is gated: the poller should launch its review once the other checks are green. That run is also a first live check of the gate for #398.
3. Once #816's spec comment is posted, place #816 on M19 (it was kept off the triage so the spec draft's issue check stayed fresh).
4. For the maintainer, by hand:
   - Queued spec work: #789, #403 (M23), #811, #814, #797, and #800 (after #811 and a release carrying `api-commit.sh`: v0.21.0 does not).

**HITL Gate: NONE OPEN** — next gate: the maintainer reacts to the 816 spec comment

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [docs/identity/DEV-CONTAINER.md](../docs/identity/DEV-CONTAINER.md) · [.ai/parked/](parked/)
