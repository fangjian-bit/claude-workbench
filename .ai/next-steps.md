# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **implementing**. The driver session runs in the dev container; no lane is building.

**Just done (2026-10-18, driver session in the container, opus):**
- Specs posted as the dev App and reacted by the maintainer: #707 (comment `6243971869`) and #714 (comment `6244019155`).
- **#707 built as the first container lane** (sonnet, worktree `/tmp/lanes/707`), merged as PR #726 (`f5e7400`), critics `architect` and `security-critic`. Lane worktree, branch and prompt file removed.
- Filed #727 (lane-prep), #728 (host PowerShell launchers for driver, lane and spec sessions) and #729 (driver context controls and lane state in the handoff), on milestone 19.
- Milestone 19's description rewritten live through `milestone-desc.sh write 19` (read back `ok`; first auto-mode run, no classifier refusal, for `WB-D28`): #720, #397, #699 and #707 marked done, #725 and #727–#729 placed after #714, the obsolete #720 BLOCKING line removed, Lanes rewritten for the container. It went outside plan-sprint's checks (frame edits), so no triage comments were posted.
- No code diff this session (the #707 lane ran its own critic pass), so no critic pass here.

Lane trial (#714): the proposed shape worked as written. The worktree was cut inside the container with `git worktree add -b <branch> /tmp/lanes/707 origin/main` and its upstream removed; the driver wrote the prompt to `/tmp/lanes/707-prompt.md` outside the worktree, carrying the spec pin, mode `map`, task issue and milestone (there is no `.ai/state.json` in the container clone, so coder.md's milestone check needed them named), the `PATH` line and the lane rules. The maintainer started the lane from the host with `docker exec -it -u app -e GIT_TERMINAL_PROMPT=0 -w /tmp/lanes/707 <container-id> bash -l` then `claude --model sonnet`, and it launched with no changes. The lane read the spec through the finder, built, ran the gate natively, ran critic-gate, and shipped as the dev App with no `GH_TOKEN` prefix; auto-merge armed and the maintainer's approval merged it. Cleanup: `git worktree remove /tmp/lanes/707`, `git branch -D <branch>` after `prune-verdict.sh` read `delete`, and removing the prompt file. Follow-ups filed: #727, #728, #729.

**Next:** task #714 — once this PR merges, as the driver session in the container on **opus**: run `spec-find.sh find 714` against `main`'s `.ai/project.yml`, set up `/tmp/lanes/714` from `origin/main` with its prompt file, and give the maintainer the `docker exec` line for a **sonnet** lane that builds the Lanes section of `docs/identity/DEV-CONTAINER.md` from the approved spec comment (it reads the `Lane trial (#714):` paragraph above from `main`).
- Then: specs for #725, #727 and #729 (the first parallel wave after #714), then #728. The dev App filed #727–#729, so the maintainer reacts to each issue before `spec-task` can read it.
- After #714 merges, the next handoff replaces this ledger's lane rules with a pointer to the new section, and the maintainer decides which host memory notes still apply in the container.
- Still open on the milestone: #696 (lane A), #629 (lane B, once #627 closes), #708–#710, the #636 second live-run pass, #458, #398 and #686.

**Lane rules** (until #714's section lands):
- Lanes never run `/resume`, `/handoff`, `/plan-sprint` or `/archive-sprint`, and never write `.ai/`.
- The lane prompt names the spec pin (`PIN_ID`, `PIN_UP`), the mode (`map`), the task issue and milestone, and the critics, and puts the worktree's `plugins/way-of-working/bin` first on `PATH` (the installed v0.19.0 lacks `spec-fresh.sh`).
- A session that drafted a spec, or read an issue's body, never builds that issue.
- Every PR needs a code-owner approval from JaredGroves-603; approving one with auto-merge armed merges it.

**HITL Gate: OPEN** — first anchor for milestone 19: the maintainer confirms the sprint works from milestone 19 and merges this cursor-sync PR before the 714 lane starts

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [docs/identity/DEV-CONTAINER.md](../docs/identity/DEV-CONTAINER.md) · [.ai/parked/](parked/)
