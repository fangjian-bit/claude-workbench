# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17). Status: **implementing**.

**Just done (2026-10-12):**
- **#506 merged** (#535, `4723bbc`): unpark-sprint now appends a parked sprint's open gate (cursor and ledger HITL Gate paragraph) to the gate it writes, flattened to one line, with a fixed "parked gate unreadable" marker when neither has text.
- Critic pass on #506: architect, security-critic and docs-consistency, 3 rounds, converged; all critics ran on their frontmatter defaults (second-opinion round offered and skipped). Subagent critics only; no fresh-session review gate is configured.
- #479 merged earlier (#533) but its issue still reads open on GitHub; the human closes it or says why not.
- Follow-ups from the #506 pass are named in #535's body and not yet filed as issues.

**Next:** task #510 — make archive-sprint step 8 and the `CHANGELOG.md` header give the current pin-bump procedure (`reference/conventions.md` § pin bump), or point at it instead of restating it; WB-D6 stays as the past resolution. Run the green gate, then `/way-of-working:critic-gate` (`docs-consistency`, plus `architect` for the `plugins/` edit), then `/way-of-working:ship`. Do #517 after it, since it depends on #510. Run on **sonnet** (coder). Build order step 27; no dependency.

**HITL Gate: NONE OPEN** — next gate: the human's merge of #510's PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
