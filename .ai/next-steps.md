# Cursor — claude-workbench

**Now:** **Sprint 15** (cursor id `sprint-15`) on [milestone 18, *Identity M3: host broker and dev container*](https://github.com/glunk-works/claude-workbench/milestone/18). Status: **implementing**.

**Just done (2026-10-13):**
- #522 decided and closed: `WB-D25` recorded in `docs/decisions.md`. Container commits are unsigned, and `main` stays signed by GitHub's squash merge. PR #573 merged as `390a295`; the human confirmed Option B.
- Filed #574 (unmilestoned, `status/needs-human`) for applying `WB-D25`: the `.devcontainer/` changes, `DEV-CONTAINER.md`, the "Sign commits." line in `conventions.md`, and the live-container and terraform checks.
- Docs-only work; no code diff, so no critic pass.

**Next:** task #570 — add the phantom `.claude/settings.json` step to `reference/conventions.md` § *Bumping a pinned plugin* (after the install commands: if `git status` shows `.claude/settings.json` modified and `git diff` is empty, `git checkout -- .claude/settings.json`), run the green gate and ship it as its own PR via `/way-of-working:ship`. On **sonnet** (coder). After it: #515, which needs the human present for the live broker check.

**HITL Gate: NONE OPEN** — next gate: the human merges the #570 PR

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 18](https://github.com/glunk-works/claude-workbench/milestone/18) · [.ai/parked/](parked/)
