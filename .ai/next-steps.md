# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **implementing**. The driver session runs in the dev container; no lane is building.

**Just done (2026-10-18, driver session in the container, opus):**
- **#714** built as a sonnet lane from the approved spec: the Lanes section of `docs/identity/DEV-CONTAINER.md`, merged as PR #731 (`2bc7730`).
- **#725** specced in a **separate spec session** (comment `6251301592`), then built as a sonnet lane: a pinned, checksummed `claude` baked into the dev container image, merged as PR #733 (`38e4229`). Lane critics: `architect`, `security-critic` and `docs-consistency`, 2 rounds, converged, default models.
- Filed #732: `spec-post.sh`'s `/home/` leak check blocks documented container paths such as the app user's home directory. No milestone yet.
- No code diff in the driver session itself (each lane ran its own critic pass), so no critic pass here.

**Lane lessons (from #714 and #725), for #727 and #728 and the Lanes section:**
- A lane's `claude` takes its project from the directory it **starts** in. The #714 lane was started in the leftover #707 shell (cwd `/`) and loaded 0 plugins. Close each lane's terminal at cleanup. Before the prompt goes in, the driver checks `readlink /proc/<lane pid>/cwd` is the worktree.
- Pasting the two-line launch block into Windows PowerShell runs `claude --model sonnet` on the **host** after the container shell exits. Launch with one line instead: `docker exec -it -u app -e GIT_TERMINAL_PROMPT=0 -w /tmp/lanes/N <container-id> bash -lc 'claude --model sonnet; exec bash -l'` (untried).
- The dev App has no Workflows permission, on purpose (`docs/proposals/GITHUB-APP-EVALUATION.md`). A lane commit that touches `.github/workflows/` is pushed by the maintainer from the host checkout (`claude-workbench-dev`, where the lane's branch already is). The lane then opens the PR as the dev App.
- `git -C /tmp/lanes/N branch --unset-upstream` is now tried: it works (the Lanes section still says untried).
- A separate spec session works: `/way-of-working:spec-task` writes no tracked file, so it runs in `/workspace` beside the driver.

**Next:** task #727 — in a fresh session on **opus**: the maintainer reacts to #727 itself first (the dev App filed it), then run `/way-of-working:spec-task 727`, and stop once the spec comment is posted or held. That session never builds #727.
- Then: once the maintainer reacts to the spec, the driver sets up `/tmp/lanes/727` per the Lanes section and gives the one-line launch. Then specs for #729 and #728 the same way.
- To file: a root-owned `/etc/claude-code/managed-settings.json` pinning `DISABLE_AUTOUPDATER` in the dev image (the #725 critics' follow-up, named in PR #733).
- A docs change to the Lanes section carrying the lessons above (it may fold into #727 or #728).
- The maintainer decides which host memory notes still apply in the container.
- Still open on the milestone: #696 (lane A), #629 (lane B, once #627 closes), #708–#710, the #636 second live-run pass, #458, #398 and #686.

**Lanes:** follow the Lanes section of [docs/identity/DEV-CONTAINER.md](../docs/identity/DEV-CONTAINER.md), plus the lessons above.

**HITL Gate: NONE OPEN** — next gate: the maintainer approves the 727 spec comment with a reaction

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [docs/identity/DEV-CONTAINER.md](../docs/identity/DEV-CONTAINER.md) · [.ai/parked/](parked/)
