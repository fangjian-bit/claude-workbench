# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17). Status: **implementing**.

**Just done (2026-10-12):**
- **#497 merged** (#548, `b7366e7`): `plan-anchor.sh verify --maintainer-ids` prints `untrusted` unless the anchored spec comment's numeric author id is a declared maintainer; header, usage line and the resume, handoff and `project-schema.md` prose follow.
- Critic pass on #497: `security-critic`, `architect` and `docs-consistency`, 2 rounds, converged; critics on their frontmatter defaults. The second-opinion round on `fable` was offered and declined. Subagent critics only; no fresh-session review gate is configured.
- Milestone 17's description was re-verified by the human and re-anchored (same sha); nothing else changed it this session.

**Next:** task #529 — `architect-review` proves the reviewer App via GraphQL `viewer` before it posts (`gh-identity.sh role`), and the "unproven" wording follows in `project-schema.md`, `review-step.sh` and `resume`; then the green gate, `/way-of-working:critic-gate` (`architect`, `security-critic`; `docs-consistency` for the prose), then `/way-of-working:ship`. Run on **sonnet** (coder). Build order step 34; no dependency. Build-order step 33 (#496) is skipped for now: its issue says the human picks between two options first.

**HITL Gate: NONE OPEN** — next gate: the human's merge of #529's PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
