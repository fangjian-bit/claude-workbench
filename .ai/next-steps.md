# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **implementing**. No lanes are live.

**Just done (2026-10-21, driver session in the container, opus):**
- **#814 landed and was checked live.** PR #820 merged (`ce714ed`). The container was recreated with six mounts. The banner read `ADMIN MODE` with a live `wow-admin` token and `off` after `--revoke`. The lane was retired with `lane.sh done 814`.
- **Four specs were drafted in parallel `wow-lane -Spec` sessions, critic-gated and approved**, all on `ce714ed`. Their Files touched are pairwise disjoint: #800, #789, #815 and #810. #815's first run was refused at posting (`has-marker`) and re-run. The old #789 spec 6298073066 no longer counts.
- **Filed #831:** `spec-shape.sh` should catch a marker-prefixed draft line before the critic gate. Two specs (#814, #815) were refused only at posting.
- **The installed plugin was updated from 0.21.0 to 0.22.0** (`2b1c255`), matching the pin. Before that, every container session loaded 0.21.0.

**Next:** task #800 — build the approved spec on **sonnet** (coder), in a fresh session via `/way-of-working:resume`, and ship it as its own PR that leaves #800 open.
1. After #800 merges, and when the maintainer says, prep the lanes for #789, #815 and #810 in parallel. #789's lane is the first test of `commit_route: api`. Give its lane this typed note: the new broker test case must remove `bin` first, as the neighbouring install cases do.
2. Hold #797 until #810's lane merges (both touch `invariants-check.sh`). Spec #809 as #810's lane nears merge. #808 waits on #809.
3. For the maintainer: delete the branch `chore/api-commit-live-811`. Place #831 on a milestone.

**HITL Gate: NONE OPEN** — next gate: the maintainer merges the PR for task 800

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [docs/identity/DEV-CONTAINER.md](../docs/identity/DEV-CONTAINER.md) · [.ai/parked/](parked/)
