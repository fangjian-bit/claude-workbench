# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**. Two lanes are building: #663 and #673.

**Just done (2026-10-17, driver session; no code):**
- Plan-sprint pass: placed #673 in milestone 19, ahead of #458. #223 and #334 stay unmilestoned, with the same reasons as last time and no new comment.
- Milestone 19 reordered so v0.19.0 is cut now, carrying #636, and the review-gate track (#636 live run, #673, #458, #397, #398) doesn't wait for the spec-flow track (#663, #664, #682, #629).
  - Filed #686, the v0.20.0 release, which depends on #627, #682 and #629.
  - Retargeted #394's body to the v0.19.0 release now.
  - Rewrote the description live through `main`'s `milestone-desc.sh` (`ok`). The plan anchor still verifies `match`.
- #673 spec drafted with `spec-task` against `main` `3d10cd5`. `spec-post.sh` held it under Seuss27, the maintainer posted it and reacted, and `spec-find.sh find 673` prints `found 6233905064`.
  - Critic pass: 4 rounds, converged. `architect` and `security-critic` ran all 4 rounds, `docs-consistency` rounds 1–3. Nothing was blocking in any round. Round 4's fixes were applied and not re-run. The architect built a scratch implementation and ran every fixture and mutant against it.
  - Measured for the spec: GitHub accepts a `github-actions[bot]` status for an Actions-pinned context with no bypass, and `GET /apps/<slug>` resolves a status poster's app id.
- #673 lane started: worktree `../claude-workbench-673`, branch `fix/pr-checks-status-pin-673`, on sonnet, with all three critics named.

**Next:** as the driver session (the only session that writes `.ai/`), on **opus**:
1. Draft the #682 spec with `spec-task` from `main`, using `main`'s `bin/`, and critic-gate it to convergence (`architect`, `security-critic`, plus `docs-consistency` when it touches load-bearing docs).
   - Give the maintainer the post command: `spec-post.sh` holds the comment under Seuss27.
   - Once it is reacted, give the lane command (Git Bash: `git worktree add ../claude-workbench-<N> -b <branch> origin/main`, then `GH_TOKEN=$(gh auth token --user Seuss27) claude --model sonnet` there) and the lane prompt, which names the critics and the found spec pair. Then hand off.
2. When the #663 or #673 lane opens its PR, run `/way-of-working:pr-checks` on it and report. Never merge or approve. After it merges, remove that worktree and branch.
3. After #663 merges, spec #664 the same way.
4. The maintainer cuts v0.19.0 (#394), bumps the pins here and on the scratch repo, then runs the #636 live run (`docs/identity/REVIEW-LIVE-RUN.md`). #458 waits for that and for #673. #397 is the maintainer's, when the container cutover is ready.
   - #458 also needs to measure whether `GET /apps/<slug>` resolves under the review container's App token. The #673 spec leaves that out of scope.

**Lane rules.**
- Lane sessions never run `/resume`, `/handoff`, `/plan-sprint` or `/archive-sprint`.
- A lane starts with Seuss27's token passed per process, because a new worktree lacks the untracked `settings.local.json` hook.
- Every PR here needs a code-owner approval. Seuss27-authored PRs are approved by JaredGroves-603, and approving one with auto-merge armed merges it.
- The installed v0.18.0 plugin lacks `spec-find.sh`, `spec-issue.sh`, `spec-post.sh` and the current `plan-anchor.sh`, so run them from `main`'s `plugins/way-of-working/bin/` until the v0.19.0 pin bump.
- A session that drafted a spec has read that issue's body, so it never builds that issue: a lane does.
- Windows still holds the empty `../claude-workbench-662` folder open; delete it once nothing has it open.

**HITL Gate: NONE OPEN** — next gate: the maintainer approves the 663 and 673 PRs from their lanes

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
