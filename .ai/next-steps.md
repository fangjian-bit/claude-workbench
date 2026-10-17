# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**. The #678 lane is building.

**Just done (2026-10-16, driver session; no code):**
- #678 spec drafted with `spec-task` against `main` e126e97. It was posted as Seuss27 by hand (`spec-post.sh` held it), and the maintainer approved it with a reaction. `spec-find.sh find 678` prints `found 6226967338 2026-10-16T23:57:59Z`.
  - Critic pass on the spec (`architect`, `security-critic`): 3 rounds. The 3rd round's one remaining item, from each critic, was fixed and not re-run.
  - The two scope additions below came after the critic pass and were not re-reviewed.
- Maintainer decisions taken into the #678 spec:
  - `spec-reaction.sh`, `gh-identity.sh`, `spec-comment.sh` and their tests join `scripts/loop/protected-paths.txt` with `spec-find.sh` (2026-10-17).
  - Filed #682 (milestone 19): the loop preflight still accepts a maintainer-authored spec comment with no reaction. `WB-D30` records it as a residual.
- The #678 lane was started: worktree `../claude-workbench-678`, branch `feat/spec-find-readers-678`, on sonnet. The lane runs all three critics unattended (`architect`, `security-critic`, `docs-consistency`).

**Next:** as the driver session (the only session that writes `.ai/`), on **opus**:
1. When the #678 lane opens its PR, run `/way-of-working:pr-checks` on it and report. Never merge or approve. After it merges, remove that worktree and branch.
2. Then draft the #663 spec with `spec-task` from `main`, using `main`'s `bin/`, and critic-gate it to convergence (`architect`, `security-critic`, plus `docs-consistency` when it touches load-bearing docs).
   - Give the maintainer the post command: `spec-post.sh` holds the comment under Seuss27.
   - Once it is reacted, give the lane command (Git Bash, `GH_TOKEN=$(gh auth token --user Seuss27) claude --model sonnet` in a new worktree) and the lane prompt. The prompt names the critics, so they run without a pick-list.
   - Then do the same for #664, then #682.
3. #673 lands before #458. #458 holds until a release containing #636 is pinned here and the #636 live run (`docs/identity/REVIEW-LIVE-RUN.md`) passes. #397 is the maintainer's, when the container cutover is ready.
   - Still undecided: an interim release with #636 in it would let the cutover proof go ahead before #394, which waits on the whole #662–#664 chain.

**Lane rules.**
- Lane sessions never run `/resume`, `/handoff`, `/plan-sprint` or `/archive-sprint`.
- A lane starts with Seuss27's token passed per process, because a new worktree lacks the untracked `settings.local.json` hook.
- Every PR here needs a code-owner approval. Seuss27-authored PRs are approved by JaredGroves-603, and approving one with auto-merge armed merges it.
- The installed v0.18.0 plugin lacks `spec-find.sh`, `spec-issue.sh`, `spec-post.sh` and the current `plan-anchor.sh`, so run them from `main`'s `plugins/way-of-working/bin/`.
- Windows still holds the empty `../claude-workbench-662` folder open; delete it once nothing has it open.

**HITL Gate: NONE OPEN** — next gate: the maintainer approves the 678 PR from the lane

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
