# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**. The #397 cutover is done, and sessions now run in the dev container. No lane is building.

**Just done (2026-10-17 to 18, host driver session):**
- **#720 fixed and closed.** The spec was drafted with `main`'s `spec-task`, held as Seuss27 and posted by the maintainer, who then reacted. A host lane on `sonnet` built it as PR #723 (`1ed31e2`): the container is entered only through the Dev Containers CLI, VS Code attach is unsupported, and the decision is recorded as `WB-D33`.
- **Live run passed** in `claude-workbench-dev`, after the VS Code-made container was removed and the clone was fast-forwarded and compared with `main`. The check is no IPC variable, no client files, no relay process, no GPG socket, `dev_app`, `gh api user` refused, and one container. Results are recorded on #720.
- **#397 closed.** The host SessionStart `GH_TOKEN` hook is removed from `.claude/settings.local.json`, so host sessions here no longer act as Seuss27 by default.
- The #720 worktree and branch are removed. No code diff this session, so no critic pass.

**Next:** as the driver session **inside the container**, on **opus**:
1. Run `/way-of-working:spec-task 707` and `/way-of-working:spec-task 714`. In the container they post as the dev App. The maintainer reacts to each.
   - `main`'s `spec-task` is ahead of the installed v0.19.0, so draft from `main`'s `plugins/way-of-working/skills/spec-task/SKILL.md`, with `main`'s `plugins/way-of-working/bin` first on `PATH`.
2. Once #707's spec is reacted, the maintainer launches #707 as the first container lane, on #714's trial shape below. Critics: `architect` and `security-critic`.
3. After that lane's PR merges, a fresh session that drafted no spec builds #714's write-up from what the trial showed.
4. Correct milestone 19's description: steps 7 and 8 are done, the #397 `BLOCKING` line is obsolete, and the **Lanes** line still names host lanes. Use `/way-of-working:plan-sprint`, which edits it through `milestone-desc.sh`.
5. #696 (lane A) and #629 (lane B, once #627 closes) are next in the container, then #708–#710 after #707. The #636 second live-run pass, #458, #398 and #686 come after.

**Entering the container** (`docs/identity/DEV-CONTAINER.md` is the authority):
- On the host: `docker ps -a --filter volume=claude-workbench-dev-tmp`, stop what it lists, and compare `.devcontainer/` with `main` from a different clone. Then `devcontainer up --skip-post-attach` and `devcontainer exec ... bash`.
- First time only: `claude /login`, and let the project's plugin install. `.ai/state.json` is git-ignored and does not exist in that clone, so `/way-of-working:resume` there runs on this ledger alone and never auto-starts.

**Lane trial shape** (#714's proposal, untested; the trial records what changes):
- A lane is a worktree under `/tmp/lanes/<N>`, cut inside the container from `origin/main`.
- A lane gets a second terminal through `docker exec -it -u app -e GIT_TERMINAL_PROMPT=0 -w /tmp/lanes/<N> <id> bash -l`, never a second `devcontainer exec`. DEV-CONTAINER.md forbids one beside a running session, because `exec` re-reads `devcontainer.json` from the host.
- In the lane: `claude --model sonnet`. No `GH_TOKEN` prefix: `gh` and git act as the dev App. Suites run natively, not in WSL, and commits are unsigned (`WB-D25`).

**Lane rules:**
- Lane sessions never run `/resume`, `/handoff`, `/plan-sprint` or `/archive-sprint`, and never write `.ai/`.
- The lane prompt names the spec pin (`PIN_ID`, `PIN_UP`) from `spec-find.sh find`, the mode (`map`) and the critics. It also puts the worktree's `plugins/way-of-working/bin` first on `PATH`, because the installed v0.19.0 lacks `spec-fresh.sh`.
- A session that drafted a spec, or read an issue's body, never builds that issue.
- Reviews run on the host through `wow-review`. Every PR needs a code-owner approval from JaredGroves-603, and approving one with auto-merge armed merges it.

**HITL Gate: NONE OPEN** — next gate: the maintainer reacts to the 707 and 714 spec comments, then approves the 707 lane PR

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [docs/identity/DEV-CONTAINER.md](../docs/identity/DEV-CONTAINER.md) · [.ai/parked/](parked/)
