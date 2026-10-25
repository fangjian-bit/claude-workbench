# Cursor — claude-workbench

**Now:** **Sprint 17** (cursor id `sprint-17`) on [milestone 24, *Green gate in parallel*](https://github.com/glunk-works/claude-workbench/milestone/24), with the work on [milestone 25, *Review follow-ups: tests, docs and guards*](https://github.com/glunk-works/claude-workbench/milestone/25). Status: **implementing**. Live lanes: `lane-state.sh list` (none at this handoff).

**Just done (2026-10-25, driver session in the container, opus):**
- **Follow-up lanes merged:** #1082 with #1083 (ci.yml host push, #1101), #1104 (check 26, #1110), #1096 with #1105 and #1106 (#1113), #1107 (concurrent wow-review-poll, #1116; host tools reinstalled, poll every 2 min), and the retro rerun fixes (#1100, #1108).
- **#1109 merged** (#1119, `WB-D41`): critic-gate's diff mode selects critics from `agents.diff_rule`. **v0.26.0 released** (#1122, `d2ee363`), pin bumped (#1123) and the plugin reinstalled at the tag; the first three lanes on it selected their critics by rule with no pick-list.
- **Their follow-ups merged:** #1114 with #1115 (#1124), #1117 with #1118 (#1126), #1120 with #1121 (#1125), each assessed against its spec and review before approval.
- **Five new review findings placed on milestone 25** (#1127 to #1131) in the Build order; 149 stale merged branches deleted on GitHub.

**Next:** on **opus** (driver). Start no build here; `next_action` holds the steps: confirm #1130 with the maintainer, fold #1128 into #1127 and #1131 into #1130, then one `-Spec` session per lead, check each spec, and prep lanes on the reactions. #1129 rides the next release PR.

**HITL Gate: NONE OPEN** — next gate: the maintainer confirms #1130 and reacts to each spec comment before its lane is prepped, and approves each lane PR

**Critic pass:** none in this driver session's own diffs (release and pin PRs only, a version string and a CHANGELOG heading, as for #1093); each lane ran its own critic gate, recorded in its PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 24](https://github.com/glunk-works/claude-workbench/milestone/24) · [milestone 25](https://github.com/glunk-works/claude-workbench/milestone/25) · [.ai/parked/](parked/)
