# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**. The #663 lane is building.

**Just done (2026-10-17, driver session; no code):**
- #684 (the #678 lane) merged at `d51f495`, closing #662 and #678. The maintainer removed the `../claude-workbench-678` worktree.
- #663 spec drafted with `spec-task` against `main` `d51f495`. `spec-post.sh` held it under Seuss27, the maintainer posted it by hand and reacted, and `spec-find.sh find 663` prints `found 6233218596`.
  - Critic pass on the spec: 4 rounds, converged. `architect` and `security-critic` ran all 4 rounds and `docs-consistency` ran rounds 1–2. Round 4 found nothing blocking; its low items were fixed and not re-run.
  - The spec adds `bin/spec-fresh.sh`, `bin/draft-identity.sh`, a `spec-find.sh pending` mode and a new `WB-D31`. Resume drafts a missing spec only as the dev App with no stored login, which means the dev container. Host sessions here keep the "draft one with spec-task" wait line.
- The #663 lane was started: worktree `../claude-workbench-663`, branch `feat/spec-fresh-663`, on sonnet. The lane prompt names all three critics (`architect`, `security-critic`, `docs-consistency`).

**Next:** as the driver session (the only session that writes `.ai/`), on **opus**:
1. When the #663 lane opens its PR, run `/way-of-working:pr-checks` on it and report. Never merge or approve. After it merges, remove that worktree and branch.
2. Then draft the #664 spec with `spec-task` from `main`, using `main`'s `bin/`, and critic-gate it to convergence (`architect`, `security-critic`, plus `docs-consistency` when it touches load-bearing docs).
   - Give the maintainer the post command: `spec-post.sh` holds the comment under Seuss27.
   - Once it is reacted, give the lane command (Git Bash: `git worktree add ../claude-workbench-<N> -b <branch> origin/main`, then `GH_TOKEN=$(gh auth token --user Seuss27) claude --model sonnet` there) and the lane prompt. The prompt names the critics and the found spec pair, so they run without a pick-list.
   - Then do the same for #682.
3. #673 lands before #458. #458 holds until a release containing #636 is pinned here and the #636 live run (`docs/identity/REVIEW-LIVE-RUN.md`) passes. #397 is the maintainer's, when the container cutover is ready.
   - Still undecided: an interim release with #636 in it would let the cutover proof go ahead before #394, which waits on the whole #662–#664 chain.

**Lane rules.**
- Lane sessions never run `/resume`, `/handoff`, `/plan-sprint` or `/archive-sprint`.
- A lane starts with Seuss27's token passed per process, because a new worktree lacks the untracked `settings.local.json` hook.
- Every PR here needs a code-owner approval. Seuss27-authored PRs are approved by JaredGroves-603, and approving one with auto-merge armed merges it.
- The installed v0.18.0 plugin lacks `spec-find.sh`, `spec-issue.sh`, `spec-post.sh` and the current `plan-anchor.sh`, so run them from `main`'s `plugins/way-of-working/bin/`.
- A session that drafted a spec has read that issue's body, so it never builds that issue: a lane does.
- Windows still holds the empty `../claude-workbench-662` folder open; delete it once nothing has it open.

**HITL Gate: NONE OPEN** — next gate: the maintainer approves the 663 PR from the lane

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
