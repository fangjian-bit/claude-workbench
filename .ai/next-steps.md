# Cursor — claude-workbench

**Now:** **Sprint 18** (cursor id `sprint-18`), status **implementing**, working from milestone 20, *Identity M5: glunk-works repos cut over*. Every Claude build on it has merged and v0.28.0 is released; what remains is triage of the follow-ups, then the maintainer's cutovers.

**Just done (2026-10-26, driver session in the container, opus):**
- **Released way-of-working v0.28.0:** #1200 (`8ec8a4d`) moved `CHANGELOG.md` [Unreleased] under [0.28.0] and set `plugin.json` to 0.28.0; the tag `v0.28.0` is published at `8ec8a4d`. No Migration line: no entry changes what a consuming repo must do before bumping.
- **Bumped this repo's pin** to v0.28.0 in `.claude/settings.json` (#1201, `a00405c`). The installed plugin was refreshed by `reference/conventions.md` § *Bumping a pinned plugin* with no other container session open; `installed_plugins.json` reads 0.28.0 at `8ec8a4d`, the tag's commit.

**Next:** Run `/way-of-working:plan-sprint` on **opus** to place the unmilestoned follow-ups filed on 2026-10-26 (#1167, #1172, #1180, #1184, #1188, #1192 and the `wow-review` findings from #1193 and #1196). Then the maintainer starts #406 bounty-infra by `reference/cutover.md`, which v0.28.0 now ships.

**HITL Gate: NONE OPEN** — next gate: the maintainer confirms the plan-sprint triage

**Critic pass:** none on #1200 or #1201, a version string, a CHANGELOG heading and a pin ref, as for #1149 and #1151. #1200 went through the `architect-review` gate.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 20](https://github.com/glunk-works/claude-workbench/milestone/20) · [milestone 26](https://github.com/glunk-works/claude-workbench/milestone/26) · [.ai/parked/](parked/)
