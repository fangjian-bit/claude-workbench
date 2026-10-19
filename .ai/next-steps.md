# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **implementing**. Next is driving lanes from the critic-gated specs.

**Just done (2026-10-19, driver session in the container, opus):**
- **Planned milestone 19** with `/way-of-working:plan-sprint`. Eight unmilestoned issues were placed on M19 and #735 was left unmilestoned as covered. The milestone 19 and 23 descriptions were rewritten twice, each through `milestone-desc.sh` with the diff confirmed. Each Build order and Lanes change is recorded as a comment on #732 (M19) and #760 (M23).
- **Filed:** #759 (#708's rule in `spec-issue.sh`/`spec-post.sh`), #760 (uutils in the review and loop images, on M23), #761 (sweep labels for the review sidecars), #762 (`wow-lane.ps1`, split from #728).
- **Five specs posted by the dev App, each critic-gated to convergence** (architect, security-critic, docs-consistency, all opus at high effort), awaiting the maintainer's reaction:
  - #696 → comment 6267647750
  - #708 → comment 6267553144 (also remove the reaction on 6257500217)
  - #741 → comment 6268260494
  - #729 → comment 6268262034
  - #728 → comment 6268263676
  - The earlier comments on those issues predate the critic pass and stay unreacted.
- **Critic passes, per spec:** #741, #708 and #696 took 2 rounds each and converged. #729 took 4 rounds and converged after the maintainer simplified it (no PR field in the lane record; the driver supplies `M` from resume's report). #728 took 4 rounds and converged after the maintainer split it (#762) and changed its compare to GitHub's API.
  - +1 attempted on `fable` (second_opinion) for #708 (2 rounds) and #728 (4 rounds): unconfirmed. `spawn-model.sh` reads every spawn as `mismatch` until #749 lands, and the five specs carry `Model provenance: mismatch (unconfirmed)`.
- No code was written.

**Lessons:**
- **Critic-gate every spec before the maintainer reacts.** This is the maintainer's standing SOP; the milestone 19 Lanes section says so. Wording and test fixes converged in 2 rounds. A blocker found in two consecutive rounds came from one design element each time, and it converged only after the design changed, not after another patch.
- **Re-react after posting.** Any comment, label or milestone change on a dev-App-filed issue makes the maintainer's issue reaction stale, so `spec-post.sh` refuses (`unreacted`) until the maintainer re-reacts.
- **Shared scratchpad.** Parallel critics writing to the scratchpad root overwrite each other's files. Give each its own `mktemp -d`.
- **This dev container predates main's Dockerfile.** It has no `/usr/local/bin/claude`, and its `claude` is the home volume's 2.1.303, not the pinned 2.1.289. Rebuild it, compare first, before #728's launcher is used.

**Next:** on **opus** (driver), as the cursor's `next_action` says:
- For each spec the maintainer has reacted to, prepare its lane per milestone 19's Lanes section (Lane B #708 first; #696, #741 and #728 touch human-only paths).
- Then draft the remaining specs whose `depends_on` is met and whose issue the maintainer has reacted to: #749, #756, #744 and #754 now; #746 and #759 after #708 merges; #761 after #696; #762 after #728. Critic-gate each to convergence.
- Maintainer: close #735 as covered. React to the issues #749, #756, #744 and #754. Clean up lane 709 with `! sh scripts/lanes/lane.sh done 709`, run from `/workspace`.

**HITL Gate: NONE OPEN** — next gate: the maintainer reacts to each critic-gated spec comment before its lane is built

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [docs/identity/DEV-CONTAINER.md](../docs/identity/DEV-CONTAINER.md) · [.ai/parked/](parked/)
