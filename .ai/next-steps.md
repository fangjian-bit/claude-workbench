# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **implementing**. One lane is live: #814 (PR #820).

**Just done (2026-10-21, driver session in the container, opus):**
- **Three lanes built from approved specs and reviewed against them:**
  - #816 merged as #819 (`e189ffa`). It is verified on the host: the poller task was re-registered with its default `-WowHome`, and a tick ended with `LastTaskResult` 0.
  - #811 merged as #822 (`7d477bd`), after a live check by the dev App on the throwaway branch `chore/api-commit-live-811`, recorded on #822: the merge kept both parents and read `verified`.
  - #814 is PR #820, open: the `.devcontainer/` mount at `/run/wow`.
- **The review gate ran live without a human.** The poller launched `wow-review` for #819, #822 and #826, and `glunk-review[bot]` posted each review. The first launch failed for want of `$WOW_HOME/claude-credential` (now written from `claude setup-token`). This is recorded as Session 10 in `docs/proposals/IDENTITY-SCRATCH-RESULTS.md` (#828) and commented on #398. #623 is closed. #398's cursor-sync item was reworded to the manual merge.
- **v0.22.0 released** (#826, tag at `2b1c255`, carrying `api-commit.sh`) and pinned here (#829, `acf7710`). Critic gate on #826: architect and docs-consistency; 3 rounds; converged.
- **Triage.** The #601 prose in M19 and M22 is fixed. #811, #797, #814 and #816 were placed on M19, and #815 and #812 on M22. The new milestone 24, *Green gate in parallel*, holds #810, #809, #808 and #821. Every build-order edit went through `milestone-desc.sh` (`live ok`, in auto mode). Merged cursor sync: #818.

**Next:** on **opus** (driver). No build starts here; the cursor's `next_action` has the steps.
1. The maintainer merges PR #820 and recreates the container through `wow-driver.ps1`'s start of day, then runs the live check: six mounts, and the banner shows `ADMIN MODE` with a live `wow-admin` token and `off` after `--revoke`. After that, run `lane.sh done 814`.
2. Spec sessions, one `wow-lane -Spec` per issue, when the maintainer says: #800 (unblocked by v0.22.0), #789, #815, #810 and #809. Hold #797 until #810's spec shows its files, since both may touch `invariants-check.sh`. #808 waits on #809.
3. #398's last open item, resume waiting and then starting on a spec reaction, needs a handoff that anchors a task, for example #800 once its spec is approved.
4. For the maintainer: delete the branch `chore/api-commit-live-811`. Disable `glunk-wow-review-poll` at the end of the day if it should not run overnight.

**HITL Gate: NONE OPEN** — next gate: the maintainer merges PR 820 and recreates the container

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [docs/identity/DEV-CONTAINER.md](../docs/identity/DEV-CONTAINER.md) · [.ai/parked/](parked/)
