# Cursor — claude-workbench

**Now:** **Sprint 15** (cursor id `sprint-15`) on [milestone 18, *Identity M3: host broker and dev container*](https://github.com/glunk-works/claude-workbench/milestone/18). Status: **implementing**.

**Just done (2026-10-13):**
- #570 shipped: PR #576 merged as `a232d57`, adding the phantom `.claude/settings.json` step to `reference/conventions.md` § *Bumping a pinned plugin*. Docs only, no critic pass.
- `/way-of-working:plan-sprint` placed #574 (apply `WB-D25` to the dev container) in milestone 18; #223 and #334 stay unmilestoned.
- Milestone 18's description now lists #574 as build-order step 5 (`depends_on: #522`) and widens the critic-gate and HITL lines to cover it. The anchor was re-taken against the new description.
- The prior anchor was not verified before that edit, so the gate below is open: the human confirms the description reads right.

**Next:** task #515 — verify the host token broker live under its scheduled task against the real dev App, including the container mount. The human must be present for the live check. After it: #574, whose `.devcontainer/` edits are the human's (`human_only_paths`). On **sonnet** (coder).

**HITL Gate: OPEN** — milestone 18 description was edited (#574 added to the build order) and re-anchored, but the prior anchor was not re-verified before the edit; the human confirms the description, then merges the cursor-sync PR

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 18](https://github.com/glunk-works/claude-workbench/milestone/18) · [.ai/parked/](parked/)
