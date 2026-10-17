# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**. Two lanes are building: #663 and #682.

**Just done (2026-10-17, driver session; no code):**
- #673 merged (#688). Its worktree and branch are removed, and so are the seven empty lane folders left from earlier lanes.
- #682 spec drafted with `spec-task` against `main` `5ed5929`. `spec-post.sh` held it under Seuss27, the maintainer posted it and reacted, and `spec-find.sh find 682` prints `found 6234480392`.
  - Critic pass: 3 rounds, converged. `architect`, `security-critic` and `docs-consistency` ran all 3 rounds, and none found anything blocking in round 3. Round 3's last wording fix was applied and not re-run. In round 2 the architect built a scratch implementation and ran the suites under WSL.
  - The spec goes beyond the issue body in two places, both named in it as choices:
    - `--no-spec-comment` is refused under a map. `WB-D30` residual 11 assigns that to #682.
    - A maintainer's comment is refused when the dev App's id is on the maintainer list.
- Filed #689: `spec-comment.sh` lacks that dev-App-id check for a maintainer author. No reader reaches it today, because `spec-find.sh` runs first. It is unmilestoned.
- #682 lane started: worktree `../claude-workbench-682`, branch `fix/preflight-spec-reaction-682`, on sonnet, with all three critics named.

**Next:** as the driver session (the only session that writes `.ai/`), on **opus**:
1. When the #663 or #682 lane opens its PR, run `/way-of-working:pr-checks` on it and report. Never merge or approve. After it merges, remove that worktree and branch.
2. After #663 merges, spec #664 the same way:
   - Draft it with `spec-task` from `main`, using `main`'s `bin/`.
   - Critic-gate it to convergence (`architect`, `security-critic`, plus `docs-consistency` when it touches load-bearing docs).
   - Give the maintainer the post command: `spec-post.sh` holds the comment under Seuss27.
   - Once it is reacted, give the lane command (Git Bash: `git worktree add ../claude-workbench-<N> -b <branch> origin/main`, then `GH_TOKEN=$(gh auth token --user Seuss27) claude --model sonnet` there) and the lane prompt, which names the critics and the found spec pair.
   - Then hand off.
3. The maintainer cuts v0.19.0 (#394) now that #673 has merged. Then the maintainer bumps the pins here and on the scratch repo, and runs the #636 live run (`docs/identity/REVIEW-LIVE-RUN.md`).
   - #458 waits for that live run. It also needs to measure whether `GET /apps/<slug>` resolves under the review container's App token.
   - #397 is the maintainer's, when the container cutover is ready.
   - #689 waits for a `/way-of-working:plan-sprint` pass.

**Lane rules.**
- Lane sessions never run `/resume`, `/handoff`, `/plan-sprint` or `/archive-sprint`.
- A lane starts with Seuss27's token passed per process, because a new worktree lacks the untracked `settings.local.json` hook.
- Every PR here needs a code-owner approval. Seuss27-authored PRs are approved by JaredGroves-603, and approving one with auto-merge armed merges it.
- The installed v0.18.0 plugin lacks `spec-find.sh`, `spec-issue.sh`, `spec-post.sh` and the current `plan-anchor.sh`, so run them from `main`'s `plugins/way-of-working/bin/` until the v0.19.0 pin bump.
- A session that drafted a spec has read that issue's body, so it never builds that issue: a lane does.

**HITL Gate: NONE OPEN** — next gate: the maintainer approves the 663 and 682 PRs from their lanes

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
