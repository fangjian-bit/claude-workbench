# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **implementing**. The #797 lane is live (`lane-state.sh list`).

**Just done (2026-10-21, driver session in the container, opus):**
- **The API commit route is live and verified.** #800 merged as #833 (`0690677`) and was closed after #834's API-route commits (verified, dev-App author) merged through auto-merge.
  - Critic record carried from PR #833: no critic pass ran; the diff is one config line in `.ai/project.yml` and touches nothing under `code_paths`.
- **The first lane batch merged:**
  - #810 as #834 (`a970b7d`).
  - #789 as #840 (`fb8c24a`). It was checked live on Windows: an MSYS-form `WOW_HOME` launched the #797 lane. Recorded on #842.
  - #815 as #841 (`3b43ebc`).
  - Each lane ran architect, security-critic and docs-consistency, and the review poller posted each review without a human.
  - The host tools were reinstalled at `fb8c24a`.
- **Filed and placed:**
  - #831 (M19), the `spec-shape.sh` marker check.
  - #835 (M24), the `area/*` taxonomy as the commit-scope vocabulary.
  - #839 (M24), the PR-title scope check.
  - The reviewer's nine follow-ups: #842–#844 (M19), #845–#847 (M22) and #836–#838 (M24).
  - Every build-order edit went through `milestone-desc.sh` (`ok`).
- **Issue-body edits (each needs a maintainer re-reaction before its spec):**
  - #809 takes the `CLAUDE.md` slimming, and CI is out of its scope.
  - #808 now owns CI for the runner, and the other code owner approves after the maintainer's `.github/` push (`require_last_push_approval`).
- **#809's first spec (6321425223) is not approved.** It put `ci.yml` in scope, which the last-push rule would leave unmergeable. It is redrafted after #797 merges, since both touch `CLAUDE.md`.

**Next:** on **opus** (driver). No build starts here; the cursor's `next_action` has the steps.
1. Check the #797 lane's PR: files against spec 6321358625, API-route commits, checks, the review verdict. Then give the milestone 19 command, and `lane.sh done 797` after it merges.
2. After the maintainer re-reacts on #809, give one `wow-lane -Spec 809` command. Check that the redraft's critic line includes docs-consistency and that its Files touched has no `.github/` path.
3. After #809: #808's spec (re-react first), then #821, #835 and #839 in M24's order. #831 can be specced any time.
4. For the maintainer: delete the branch `chore/api-commit-live-811`.

**HITL Gate: NONE OPEN** — next gate: the maintainer approves the PR from the 797 lane

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [milestone 24](https://github.com/glunk-works/claude-workbench/milestone/24) · [docs/identity/DEV-CONTAINER.md](../docs/identity/DEV-CONTAINER.md) · [.ai/parked/](parked/)
