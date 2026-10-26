# Cursor — claude-workbench

**Now:** **Sprint 18** (cursor id `sprint-18`), status **implementing**, working from milestone 20, *Identity M5: glunk-works repos cut over*. Every Claude build on it has merged; what remains is the v0.28.0 release, then the maintainer's cutovers.

**Just done (2026-10-26, driver session in the container, opus):**
- **Merged on milestone 20**, each from a reacted spec through a lane, critic pass and `wow-review`: the cutover runbook `reference/cutover.md` (#1158, #1173) and its fixes (#1176 with #1177 to #1179 folded in, #1185; #1191, #1196); `cursor-drift.sh` refuses revision names (#1159, #1170) and resume resolves `last_commit` through its `oid` mode (#1168, #1182); `review-token.sh` refuses a slash-less `$0` (#1171, #1174); `WB-D42` recorded (#1163, #1169); review-gate and attribution prose (#1175, #1183; #1181, #1190; #1189, #1193).
- **Escalations:** #1159 and #1158 escalated and were answered through `spec-task-answer:` (#1158 twice, `apply` then `amend`); #1080 closed on the first live answer read.
- **Cutover checklists reconciled** with the runbook and `WB-D42`: #406, #407, #408 and #410 now carry the eight-step order (reviewer App before PR 1 merges, dev App only after the approval read-back with `enforcement: active`), the release-tag step and the v0.28.0 dependency. #1165 records the maintainer's decision that a repo's container cutover waits for its whole ruleset cutover. #433 closed: immutable releases verified on all four repos as the admin account; none publishes tags.
- **Filed unmilestoned for plan-sprint:** #1167 (the pre-cutover someday list), #1172, #1180, #1184, #1188, #1192, plus the `wow-review` findings filed from #1193 and #1196.

**Next:** Release way-of-working v0.28.0 on **opus** (fresh session): one PR moving `CHANGELOG.md` [Unreleased] under [0.28.0] and setting `plugin.json` to 0.28.0 (as #1149), then, after the tag, a PR bumping `.claude/settings.json` to v0.28.0 (as #1151). Then `/way-of-working:plan-sprint` for the unmilestoned follow-ups, then the maintainer starts #406 bounty-infra by `reference/cutover.md`.

**HITL Gate: NONE OPEN** — next gate: the maintainer approves the v0.28.0 release PR

**Critic pass:** no diff in this driver session (issue, milestone and ledger writes only). Each lane ran its own critic pass, recorded in its PR body.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 20](https://github.com/glunk-works/claude-workbench/milestone/20) · [milestone 26](https://github.com/glunk-works/claude-workbench/milestone/26) · [.ai/parked/](parked/)
