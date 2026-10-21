# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **implementing**. The #851 lane is live (`lane-state.sh list`).

**Just done (2026-10-21, driver session in the container, opus):**
- **Three lane PRs merged**, each reviewed by the poller with no blocking findings:
  - #797 as #849 (`2324114`).
  - #809 as #853 (`cc0ff65`). `bash scripts/test-all.sh` replaces CLAUDE.md's per-file test list.
  - #831 as #857 (`8dde342`).
  - Their `lane.sh done` cleanups ran.
  - Each lane ran architect, security-critic and docs-consistency, and each converged.
  - The reviewer's follow-ups were filed and placed: #850 and #858 (M19), #854–#856 (M24).
- **The review gate checks presence, not verdict** (WB-D37's residual). #851 now gates on the review's verdict, and #852 (dropping "HITL" from the frozen header) is folded into it. #851's spec (6324121751) was redrafted on `cc0ff65` after #809 merged.
- **The #809 spec's own critic pass skipped docs-consistency.** The driver ran it before the reaction, and it found nothing blocking. Check every spec's critic line for this.
- **Parallel plan for M19 and M24** (by file overlap):
  - Next batch, after a fresh maintainer reaction on each issue: #850; #842, #843 and #844 as one track (#843 and #842 need decisions); #837 and #838 as one track.
  - Held: #845, #846 and #847 wait for #851 (`wow-review` and the review test suite). #808 needs a re-react, with #821 and #836 folded in or closed as covered. #835 needs a re-react, then #839. #753 can go now that #809 has merged.
  - #728's work merged as #783 and #787; the issue only needs closing.

**Next:** on **opus** (driver). No build starts here; the cursor's `next_action` has the steps.
1. Check the #851 lane's PR against spec 6324121751, including the two `.github/workflows/` edits the builder leaves out for the maintainer. Give the milestone 19 command.
2. After the maintainer pushes the workflow edits, read the review verdict before they approve. Merge it only with no other gated PR open, then `lane.sh done 851`.
3. Propose the next lane from the plan above. The maintainer says which.
4. For the maintainer: remove the #851 spec session's worktree, which the launcher keeps because it moved to `cc0ff65`. Also delete the branch `chore/api-commit-live-811`.

**HITL Gate: NONE OPEN** — next gate: the maintainer pushes the 851 workflow edits and approves its PR

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [milestone 24](https://github.com/glunk-works/claude-workbench/milestone/24) · [docs/identity/DEV-CONTAINER.md](../docs/identity/DEV-CONTAINER.md) · [.ai/parked/](parked/)
