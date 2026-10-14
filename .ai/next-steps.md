# Cursor — claude-workbench

**Now:** **Sprint 15** (cursor id `sprint-15`) on [milestone 18, *Identity M3: host broker and dev container*](https://github.com/glunk-works/claude-workbench/milestone/18). Status: **implementing**. All of milestone 18's issues are closed.

**Just done (2026-10-14):**
- #588's signing spike ran on `glunk-works/signing-scratch` as `glunk-dev`. The [finding](https://github.com/glunk-works/claude-workbench/issues/588#issuecomment-6170685713) recommends REST git data (route D):
  - it signs only with no `author`/`committer`, and keeps file modes;
  - GraphQL loses 100755, which invariants check 9 needs;
  - a contents `DELETE` comes out unsigned;
  - an unsigned branch reads `BLOCKED` while a D-route branch reads `CLEAN`.
- Follow-up filed: [#601](https://github.com/glunk-works/claude-workbench/issues/601), the `bin/api-commit.sh` build, in milestone 19. It includes the 603 re-checks: the CI-trigger check, the workflow-file limitation, and one full trial PR before use on the terraform repos.
- #588 closed as completed. The scratch repo's test branches and the token file are removed; the repo itself is the maintainer's to delete.
- No critic pass: no code diff this session.

**Next:** write sprint 15's done entry (milestone 18, all its issues closed) in [docs/decisions.md](../docs/decisions.md) after the Sprint 14 paragraph, and ship it as its own `docs: mark sprint-15 done` PR. After it merges, run `/way-of-working:archive-sprint` for milestone 18. On **opus** (architect).

**HITL Gate: NONE OPEN** — next gate: the human merges the sprint-15 roadmap PR

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 18](https://github.com/glunk-works/claude-workbench/milestone/18) · [.ai/parked/](parked/)
