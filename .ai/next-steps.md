# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17). Status: **implementing**.

**Just done (2026-10-13):**
- **#557 merged** (#563, `0295161`): `bin/hitl-gate-closed.sh` is the one predicate for a closed `hitl_gate` — exactly `NONE OPEN — next gate: <prose>`, one line, printable ASCII, no `;`, never "open". `resume`, `unpark-sprint` and `plan-sprint` call it with the value read into a variable; `handoff` and `archive-sprint` write the canonical form; `invariants-check.sh` check 14 pins the call lines. Cursors in another shape now wait until a handoff rewrites them.
- Critic pass on #563: `architect`, `security-critic` and `docs-consistency`, initial pass plus 3 fix-and-re-run rounds, converged (the last round tightenings-only). Critics on their frontmatter defaults; the human skipped the `fable` second-opinion round. Subagent critics only; no review CI gate is configured.
- The plugin pin is still `0.17.0`, so the predicate is not live in this checkout's skills until the release below.
- Still unfiled follow-ups from #561: `architect-review` step 5 loads `#N`'s body under an `identities` map, and the comment at `bin/plan-anchor.sh:451` ("the issue body is the whole spec") is stale under a map.
- Re-anchored on task #391 with no spec comment; milestone 17's description is unchanged from the text confirmed last handoff.

**Next:** task #391 — release way-of-working v0.18.0: CHANGELOG entry with a Migration line (identities, rulesets list, CODEOWNERS, auto-merge), bump `plugin.json`, ship as its own PR via `/way-of-working:ship`; the maintainer dispatches the release. First confirm the issue's dependencies (#378–#390) are closed. On **sonnet** (coder); critic gate on the diff.

**HITL Gate: OPEN** — first anchor for milestone 17 (no verified baseline in this session); description sha `a333ea30d44e…` is the same text the human confirmed last handoff, and merging this cursor-sync PR is the confirmation. Then the human merges the #391 PR and dispatches the release.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
