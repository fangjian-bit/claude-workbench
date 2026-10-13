# Cursor — claude-workbench

**Now:** **Sprint 15** (cursor id `sprint-15`) on [milestone 18, *Identity M3: host broker and dev container*](https://github.com/glunk-works/claude-workbench/milestone/18). Status: **implementing**.

**Just done (2026-10-13):**
- Cursor-sync PR #571 merged (`e35762d`), confirming milestone 18's first anchor (description sha `dda71079f0aa…`); `verify --plan` still reads `match`.
- Sprint 15 planned: build order confirmed by the human as #522 → #570 → #515. #515 needs the human present for the live broker check under its scheduled task.
- Planning session only; no code diff, so no critic pass.

**Next:** task #522 — decide commit signing in dev containers and keep terraform main signed: read the issue, propose the decision for the human to confirm, record it in `docs/decisions.md` and ship it as its own PR via `/way-of-working:ship`. On **opus** (architect).

**HITL Gate: NONE OPEN** — next gate: the human confirms the commit-signing decision, then merges the #522 PR

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 18](https://github.com/glunk-works/claude-workbench/milestone/18) · [.ai/parked/](parked/)
