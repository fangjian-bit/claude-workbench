# Cursor — claude-workbench

**Now:** **Sprint 15** (cursor id `sprint-15`) on [milestone 18, *Identity M3: host broker and dev container*](https://github.com/glunk-works/claude-workbench/milestone/18). Status: **planning**.

**Just done (2026-10-13):**
- **v0.18.0 released** (#391, PR #565; tag `8486e4f`); this repo's pin bumped (#568) and the plugin reinstalled at project scope; the sprint 14 roadmap entry landed in `docs/decisions.md` (#569).
- **Sprint 14 archived** (milestone 17 closed, `verify --plan` match); snapshot in `.ai/archive/sprint-14-next-steps.md`. This was the recorded run of archive-sprint's milestone steps with `backlog.repo: null`, so #479 is closed.
- **Retro:** one finding filed, #570 (the pin-bump procedure leaves a phantom `.claude/settings.json` diff on Windows).
- **plan-sprint:** #566 and #567 placed in milestone 19, #570 in milestone 18; #334 and #223 left unmilestoned (their earlier triage stands).
- Critic pass on #565: `docs-consistency` only, 2 rounds, converged (round 1 found 4 problems, round 2 two framing ones; all fixed). Critics on their frontmatter defaults; no second-opinion round.

**Milestone close:** closed milestone 17, *Identity M2: dual-mode plugin v0.18.0* (0 open issues, `verify --plan` match, read-back `closed`).

**Next:** plan sprint 15 on **opus** (architect), milestone 18's remaining items: #515 (live broker verification under its scheduled task, needs the human), #522 (commit-signing decision for the dev container) and #570 (docs fix, buildable now on sonnet). Confirm the order and pick the first task.

**HITL Gate: OPEN** — first anchor for milestone 18 (no verified baseline); description sha `dda71079f0aa…` is what this session read, and the human merging this cursor-sync PR confirms it. Then confirm the build order and pick the first task.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 18](https://github.com/glunk-works/claude-workbench/milestone/18) · [.ai/parked/](parked/)
