# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**. No lane is building. The #397 cutover stopped at its credential test and is now blocked by #720.

**Just done (2026-10-17, driver session, guided #397 cutover):**
- **Host prerequisites done:**
  - `dev.containers.gitCredentialHelperConfigLocation` is `none` in the Default, Personal and 603 Identity VS Code profiles.
  - The forwarded ssh-agent holds no key registered on GitHub.
  - The old `claude-workbench-home` volume, and the container that used it, are removed.
- **Container opened:** from a fresh full clone, `C:\Users\SR116\projects\glunk-works\claude-workbench-dev`, with only the expected mounts.
  - Passed: `draft-identity.sh check` printed `dev_app`, git's helper list holds only `dev-token`, and no GPG socket is forwarded.
  - **Failed:** VS Code's IPC channel still returns the host's GitHub credential to a direct call of its helper client.
  - The host clone this container came from on 2026-10-13 was checked: no planted hooks or config.
- **#720 filed:** milestone 19 step 7, ahead of #397 (now step 8, `depends_on: #720`), with a `BLOCKING` line on #397. The milestone write was read back.
- **#397:** the result is recorded in a comment on the issue.
- **#721 merged:** `docs/identity/DEV-CONTAINER.md` now records the open channel and its masked test, the per-profile setting, and the empty GPG check (5d374e7).
- No code diff this session, so no critic pass.

**Next:** as the driver session on the host, on **opus**:
1. Run `/way-of-working:spec-task 720`. The maintainer reacts to the spec comment.
2. A host lane builds #720: its own worktree and a fresh **sonnet** session. This is the one host-lane exception, because #720 blocks #397. Critics: `architect` and `security-critic`.
3. After that PR merges, guide the maintainer to rerun #720's credential test in the existing `claude-workbench-dev` container, from a VS Code-attached terminal.
   - On a pass, the #397 cutover resumes at its last step: delete the SessionStart `GH_TOKEN` hook from `.claude/settings.local.json`.
   - The clone and its container stay as they are. If the fix changes `.devcontainer/`, compare it with `main` from a different clone before the Rebuild.
4. After #397, everything queued in the container in milestone 19 still follows: #714 with #707 as the trial lane, #696, #629, #708–#710 and #715. The #636 second live-run pass, #458, #398 and #686 come after.

**Lane rules** (#714 replaces the host-only ones):
- Lane sessions never run `/resume`, `/handoff`, `/plan-sprint` or `/archive-sprint`.
- The lane prompt names the spec pin (`PIN_ID`, `PIN_UP`) from `spec-find.sh find`, the mode (`map`) and the critics.
- A session that drafted a spec has read that issue's body, so it never builds that issue: a lane does.
- `main`'s `spec-task` is ahead of v0.19.0, so a spec is drafted with `main`'s skill text and `main`'s `plugins/way-of-working/bin/`.
- Every PR needs a code-owner approval from JaredGroves-603. Approving one with auto-merge armed merges it.

**HITL Gate: NONE OPEN** — next gate: the maintainer reacts to the 720 spec comment, approves the 720 fix PR, then reruns the 397 credential test

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
