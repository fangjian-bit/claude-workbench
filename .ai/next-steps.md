# Cursor — claude-workbench

**Now:** **Sprint 17** (cursor id `sprint-17`) on [milestone 24, *Green gate in parallel*](https://github.com/glunk-works/claude-workbench/milestone/24), with wave 4 on [milestone 25, *Review follow-ups: tests, docs and guards*](https://github.com/glunk-works/claude-workbench/milestone/25). Status: **implementing**. Live lanes: `lane-state.sh list`.

**Just done (2026-10-23, driver session in the container, opus):**
- **Wave 3 merged:** #898 (PR #1000), #979 with #980 (PR #1001), #952 (PR #1002), #896 (PR #1004, `lane-groups.sh`), #999 (PR #1014, scheduled tasks start through `conhost --headless`) and #862 (PR #1019, lanes set their own PR's milestone after ship). #896 and #999 escalated at spec time and were resolved by maintainer edits to the escalated comment.
- **#999's host check found two broker gaps:** a stop orphans the broker `pwsh`, which then cannot mint (`0xC0000142`) while holding `broker.lock` (#1016), and a killed broker is not restarted because conhost exits 0 (#1015). #1015 is folded into #1016, whose spec converged and whose lane is building. #999 stays closed by the maintainer's decision.
- **way-of-working v0.24.0 released** (PR #1024, `e6eeee3`), pinned (PR #1025, `c2d3301`) and installed in the container at the tag's commit.
- **Planning pass:** milestone 25 created with a 35-item build order; lead issues carry their folded issues in their bodies; #790 narrowed (its second-opinion want is now #1020). Decisions: require all four test jobs (#989) and pr-title (#963) once the CI lane lands, with a docs-only skip limited to cursor-sync paths; document #992 only; protect the transcript-reader files in the loop list (#973); closed #948, #827 and #920; refresh comment on #223.
- Critic passes ran in each spec and lane session; their outcomes are in each PR body. Lanes 898, 979, 896, 952, 999 and 862 are cleaned up with `lane.sh done`.

**Next:** on **opus** (driver). Start no build here; `next_action` holds the steps: check the #1016 lane PR against its spec, then check the ten wave 4 specs and prep their lanes in batches on the maintainer's reactions.

**HITL Gate: NONE OPEN** — next gate: the maintainer reacts to each wave 4 spec comment before its lane is prepped, and approves each lane PR

**Until #1016 merges (maintainer, on the host):** never stop `glunk-wow-broker` on its own; end the broker's `pwsh` by command line first, or the token lapses within the hour.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 24](https://github.com/glunk-works/claude-workbench/milestone/24) · [milestone 25](https://github.com/glunk-works/claude-workbench/milestone/25) · [.ai/parked/](parked/)
