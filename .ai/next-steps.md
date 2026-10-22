# Cursor — claude-workbench

**Now:** **Sprint 17** (cursor id `sprint-17`) on [milestone 24, *Green gate in parallel*](https://github.com/glunk-works/claude-workbench/milestone/24). Status: **implementing**. Live lanes: `lane-state.sh list`.

**Just done (2026-10-22, driver session in the container, opus):**
- **Test-speed push started.** Measured where suite time goes (locally on `/workspace`, which is 9p, and in CI's split jobs) and filed #934, #935, #936 (sharding folded in) and #937 on M24, with their Build order and Lanes entries in the milestone description.
  - `identity-review`'s stub-pacing waits are cut (#935, PR #943, `c625322`): about 124 s to 97 s alone on ext4.
  - The invariants fixtures copy from one pristine tree and CI's `tests` job runs as two shards (#936, PR #947, approved with auto-merge armed; the `ci.yml` half was pushed from the host). On its CI run the shards took 133 s and 91 s, against 207 s for `tests-launchers`, which is now the critical path.
- **Wave 2:** retro holds other-session findings until the human confirms (#900, PR #938, `e403d1a`; spec light-refreshed after a CHANGELOG-only stale). Retro states its path match is POSIX-only (#904, PR #945, `d3378d3`).
- Critic passes ran in each spec and lane session; their outcomes are in each PR body.

**Next:** on **opus** (driver). Start no build here; `next_action` holds the steps. Once #947 merges, clean up its lane, then bring the milestone description up to date and carry on with #937, #914 and later #934 as lanes.

**HITL Gate: NONE OPEN** — next gate: the maintainer reacts to each spec comment before its lane is prepped

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 24](https://github.com/glunk-works/claude-workbench/milestone/24) · [.ai/parked/](parked/)
