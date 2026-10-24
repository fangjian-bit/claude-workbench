# Cursor — claude-workbench

**Now:** **Sprint 17** (cursor id `sprint-17`) on [milestone 24, *Green gate in parallel*](https://github.com/glunk-works/claude-workbench/milestone/24), with the work on [milestone 25, *Review follow-ups: tests, docs and guards*](https://github.com/glunk-works/claude-workbench/milestone/25). Status: **implementing**. Live lanes: `lane-state.sh list` (none at this handoff).

**Just done (2026-10-24, driver session in the container, opus):**
- **Second follow-ups and #790 merged:** #790 (PR #1070), #1054 (+#1055, #1056; #1071), #1066 (+#1067, #1068; #1073, closing keywords fixed by the driver), #1063 (+#1064, #1065; #1072). Each spec checked against its session transcript and `origin/main` before the maintainer reacted; each PR against its spec and review before approval.
- **CI lane merged:** #986 (+#985, #931, #930, #1017, #989, #963; PR #1081, `058b0c0`). The lane committed locally; the driver built the host patch with the `.ai/project.yml` `required_checks` edit, the maintainer pushed it, and the ruleset now requires `tests-1`, `tests-2`, `tests-launchers`, `tests-review-launcher` and `pr-title`, pinned to GitHub Actions.
- **#953 merged** (PR #1084, `57245da`): the type labels are `type/*`; the maintainer renamed them in place (counts preserved), deleted the six unused defaults and reinstalled the host tools.
- **Third follow-ups placed on milestone 25 and three merged:** #1074 (#1088), #1075 (+#1076, #1077; #1087), #1078 (#1089, spec light-refreshed after #953). #1083, #1082, #1079 and #1080 placed with their Build order lines.
- **v0.25.0 released** (`9ab3306`, PR #1093), pin bumped (PR #1094, `13b6735`), and the plugin reinstalled at the tag. Backlog #1074 and #1075 filed; memories `lane-merge-not-rebase` added and `spec-batch-size` sharpened.

**Next:** on **opus** (driver). Start no build here; `next_action` holds the steps: place the five new review findings (#1085, #1086, #1090, #1091, #1092) on milestone 25, then one `-Spec` session per lead (#1082 with the #1083 decision, #1079, and the new leads), check each spec, and prep lanes on the maintainer's reactions.

**HITL Gate: NONE OPEN** — next gate: the maintainer reacts to each spec comment before its lane is prepped, and approves each lane PR

**Critic pass:** none in this driver session (no code diff of its own); each lane ran its own critic gate, recorded in its PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 24](https://github.com/glunk-works/claude-workbench/milestone/24) · [milestone 25](https://github.com/glunk-works/claude-workbench/milestone/25) · [.ai/parked/](parked/)
