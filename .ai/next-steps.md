# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **implementing**. A sonnet coder lane is building #727 in `/tmp/lanes/727`.

**Just done (2026-10-18, driver session in the container, opus):**
- **#727 specced.** The v1 spec (comment `6253028302`) was posted unreviewed and left unreacted. `architect` and `security-critic` reviewed it over 4 rounds, on their default models, converging at the cap; round 4's tightenings were applied without a fifth round. v2 (comment `6253419026`) is the approved spec: the finder reads `found 6253419026 2026-10-18T18:17:05Z`.
- **#727 lane set up by hand** per the Lanes section: worktree `/tmp/lanes/727` on `feat/lane-sh` at `3bf07ea`, cut with `--no-track`, prompt in `/tmp/lanes/727-prompt.md`. It was launched with the one-line `docker exec`, and its cwd and plugin load were checked.
- **#627 closed** as completed: all six children and #666 are closed, so #629 is unblocked.
- **Filed #735:** the lane prompt's `export PATH=…` covers only one Bash call, so lanes may have run the stale installed scripts. Posted notes from this spec-review run on #629.
- No code diff in the driver session, so no critic pass on code here.

**Lessons, for the Lanes section and #629:**
- **Stale plugin.** The installed plugin (v0.19.0) is behind `main`: its `spec-issue.sh` predates #716 and refuses App-filed issues. Until a release, this session follows `main`'s skill text and runs `main`'s `bin/` scripts by absolute path.
- **App-filed issues.** Posting a spec comment on one moves the issue's `updated_at` past the maintainer's reaction on it, so a re-post needs that reaction removed and re-added first.
- **Maintainer account.** Only the `identities.maintainer` account's reaction counts; a reaction from another GitHub account is ignored.
- **One-line lane launch** now tried: `docker exec -it -u app -e GIT_TERMINAL_PROMPT=0 -w /tmp/lanes/N <container-id> bash -lc 'claude --model sonnet; exec bash -l'`.

**Next:** task #727 — on **opus** (driver): the lane builds and opens its PR. Read its status with `/way-of-working:pr-checks`, and the maintainer approves it. The lane's `ship` cannot set the PR's milestone (no `.ai/state.json` in the lane), so set milestone 19 on it by hand. After it merges, clean up `/tmp/lanes/727` per the Lanes section.
- Then: release v0.20.0 (#686), so the installed plugin catches up with `main`. Next, #629, the spec-mode critic gate, before the #729 and #728 specs.
- To file: a root-owned `/etc/claude-code/managed-settings.json` pinning `DISABLE_AUTOUPDATER` in the dev image (the #725 critics' follow-up, PR #733).
- The maintainer decides which host memory notes still apply in the container.
- Still open on the milestone: #696, #629, #708–#710, the #636 second live-run pass, #458, #398, #686, #728 and #729.

**Lanes:** follow the Lanes section of [docs/identity/DEV-CONTAINER.md](../docs/identity/DEV-CONTAINER.md), with #735's per-call `PATH` prefix.

**HITL Gate: NONE OPEN** — next gate: the maintainer approves the 727 lane PR

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [docs/identity/DEV-CONTAINER.md](../docs/identity/DEV-CONTAINER.md) · [.ai/parked/](parked/)
