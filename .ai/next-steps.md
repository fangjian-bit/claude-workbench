# Cursor — claude-workbench

**Now:** **Sprint 17** (cursor id `sprint-17`) on [milestone 24, *Green gate in parallel*](https://github.com/glunk-works/claude-workbench/milestone/24). Status: **implementing**. Live lanes: `lane-state.sh list`.

**Just done (2026-10-23, driver session in the container, opus):**
- **pwsh everywhere it is needed.**
  - The `tests-launchers` CI job now fails when `pwsh`, `git`, `yq` or `jq` is missing, instead of going green on a skip (#978, PR #984, `1d6b3c0`, pushed host-side).
  - The dev image installs a pinned, checksum-verified PowerShell 7.6.8 (#893, moved from M22, PR #995, `1a79fde`). The pin was checked against the release's hash list and a fresh download. The container must be recreated from this commit (the next action).
- **Wave 3.**
  - Lanes open with their issue number (#894, PR #987, `12738ad`).
  - test-all starts `identity-review` with the pool, and its header now claims bash 5, not 3.2 (#934 with #968 folded in, PR #988, `5d8242e`).
  - pr-title fails closed on an area outside the scope grammar (#972 with #970 and #965, PR #990, `c46b47f`).
  - The transcript reader's tilde rule is in words (#981 with #982, PR #991, `ec8edd9`).
- Every lane was cut before #984 merged, and the dev App's first branch creation got a 403. Rebasing onto `origin/main` fixed it; the likely cause is a branch tree with an older workflow file than `main`.
- Critic passes ran in each spec and lane session; their outcomes are in each PR body. Every lane has been cleaned up with `lane.sh done`.

**Next:** on **opus** (driver). Start no build here; `next_action` holds the steps. First recreate the container and check `pwsh` (below), then the next wave as lanes on the maintainer word: #952, #979 (with #980), #896 and #898.

**HITL Gate: NONE OPEN** — next gate: the maintainer reacts to each spec comment before its lane is prepped

**Before the next session (maintainer, on the host):** exit every container session, `docker stop` the container, run the driver launcher (start of day recreates it from `1a79fde`), and rerun `install-host-tools.ps1` before the next lane so lanes get #894's first message.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 24](https://github.com/glunk-works/claude-workbench/milestone/24) · [.ai/parked/](parked/)
