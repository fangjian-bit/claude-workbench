# Cursor — claude-workbench

**Now:** **Sprint 18** (cursor id `sprint-18`), status **planning**. No milestone picked yet. Live lanes: `lane-state.sh list`.

**Just done (2026-10-26, driver session in the container, opus):**
- **Milestone 25's follow-up lanes merged:** #1127 with #1128 (#1134), #1130 with #1131 (#1139), #1111 with #1112 (#1135), #1136 with #1138 (#1144), #1141 with #1142 (#1145); Dependabot #1133.
- **Milestone 24 finished:** #1018 (#1140) and #905 (#1146, its workflow half a maintainer host-side push; both host homes reinstalled at `3c79b37`).
- **`v0.27.0` released** at `8ae8197` (#1149, closing #1129), this repo's pin bumped (#1151) and the plugin reinstalled at the tag. Sprint 17's status entry merged (#1152) and sprint 17 archived at `0b6f0c3` (snapshot `.ai/archive/sprint-17-next-steps.md`).
- **Retro:** filed #1153 (lane prompts name folded issues) and #1154 (one review-findings issue per review), and, at the maintainer's request, #1155 and #1156; updated the lane host-push and milestone-description memories. #1143 (state.json `schema_version`) waits for the maintainer's pick of option.

**Milestone close:** closed — milestone 24, *Green gate in parallel* (0 open issues; `verify --plan` read `match`, read-back `closed`). Milestone 25, *Review follow-ups: tests, docs and guards*, was closed by hand beforehand (no sprint anchors it).

**Next:** on **opus** (driver, fresh session). Run the pre-cutover Fable pass on `v0.27.0`, after the maintainer confirms the fan-out: four read-only lenses on `models.second_opinion` (the 0.15.0 to 0.27.0 upgrade against bounty-infra's, global-bootstrap's and bedrock-serverless-rag's committed `project.yml`; the identities cutover from a repo's side, loop-orchestrator and scope-core included; several repos on one host plus what #715 must cover; the `bin/` trust-path sweep), each finding tagged blocks-cutover, soon or someday and verified against the code, then one triage table before anything is filed. Then pick sprint 18's milestone (likely milestone 20, *Identity M5: glunk-works repos cut over*) via `/way-of-working:handoff`.

**HITL Gate: NONE OPEN** — next gate: the maintainer triages the Fable pass findings and picks sprint 18s milestone

**Critic pass:** none in this driver session's own diffs (a release, a pin bump, a status entry and ledger edits); each lane ran its own critic gate, recorded in its PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · sprint plan: no milestone picked yet · [.ai/parked/](parked/)
