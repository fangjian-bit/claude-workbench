# Cursor — claude-workbench

**Now:** **Sprint 18** (cursor id `sprint-18`), status **implementing**, working from milestone 20, *Identity M5: glunk-works repos cut over*. Every Claude build on it has merged and v0.28.0 is released; what remains is triage of the follow-ups, then the maintainer's cutovers.

**Just done (2026-10-26, driver session in the container, opus):**
- **Plan-sprint triage of 35 unmilestoned issues**, confirmed by the maintainer, every write live and read back, a `[plan-sprint]` comment on each issue:
  - **New milestone 27**, *v0.28.0 follow-ups: runbook and reference docs* (due 2026-11-06): #1197, #1198, #1188 (`cutover.md`, first), #1192, #1194, #1195, #1186, #1187, #1184, #1143, #1160, #791.
  - **New milestone 28**, *Fewer manual steps per lane and review* (due 2026-11-13): #1155, #1154, #1153, #1021, #1023, #1022.
  - **New milestone 29**, *Follow-ups: host and script hardening* (due 2026-11-20): #1172, #1180, #1033, #1032, #1035, #1028, #1029, #1030, #1156.
  - **Milestone 26** gained #1161 as step 4, through `milestone-desc.sh` (`live ok`; order `1164, 715, 1165` → `1164, 715, 1165, 1161`).
  - **Decisions taken:** #1143 delete `schema_version`; #1160 record the fresh-session residual in `WB-D22` (option C); #1156 the review proxy is the likely 403 cause, so confirm it, then per-suite annotations from `test-all.sh`; #791 notify-only through the GitHub Slack app's label filter (the maintainer sets up the subscription); #1022 doc-only. #1150 closed as not planned.
  - **Left unmilestoned:** #223, #334, #409, #792, #1020, #1167.

**Next:** The maintainer starts #406 bounty-infra by `reference/cutover.md`; #1197 (milestone 27 step 1) says what that runbook's approval-ruleset read-back must show, so it is worth landing first. Claude-side, specs for milestone 27's items, then 28 and 29; which milestone the cursor anchors next is the maintainer's pick, followed by `/way-of-working:handoff`.

**HITL Gate: NONE OPEN** — next gate: the maintainer's #406 cutover, and their pick of the next milestone to anchor

**Critic pass:** none on #1200 or #1201, a version string, a CHANGELOG heading and a pin ref, as for #1149 and #1151. #1200 went through the `architect-review` gate.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 20](https://github.com/glunk-works/claude-workbench/milestone/20) · [milestone 26](https://github.com/glunk-works/claude-workbench/milestone/26) · [.ai/parked/](parked/)
