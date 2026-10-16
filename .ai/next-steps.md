# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**. Three lanes are building.

**Just done (2026-10-16, driver session at 843d058; no code):**
- Gave the maintainer the lane B command and prompt for [#626](https://github.com/glunk-works/claude-workbench/issues/626). Lane B is building and under test (worktree `../claude-workbench-626`, branch `feat/review-poller-626`).
- Split [#627](https://github.com/glunk-works/claude-workbench/issues/627) into six children, #659 to #664, each one PR, in milestone 19; #627's *Split* section gives the build order. Filed [#666](https://github.com/glunk-works/claude-workbench/issues/666): the loop's dispatch preflight must accept a reacted dev-App spec before #661.
- Drafted the #659 and #660 specs with `spec-task` from `main` at 843d058 and posted them as the maintainer: [#659 spec](https://github.com/glunk-works/claude-workbench/issues/659#issuecomment-6216240319), [#660 spec](https://github.com/glunk-works/claude-workbench/issues/660#issuecomment-6216240711). The maintainer reacted to both after their last edit; `spec-comment.sh check` returned `ok` and `spec-reaction.sh` `approved` on each.
- Critic pass on both drafts, `architect` and `security-critic` on their frontmatter models: 4 rounds each (initial plus 3 fix-and-re-run rounds), converged. The maintainer declined the offered `fable` second-opinion round. It reshaped #660: a dev-App-authored spec is used only with a fresh maintainer reaction, enforced in `spec-comment.sh`, with readers fetching the reactions before the comment.
- Started lane C1 on #659 (`../claude-workbench-659`, `feat/spec-issue-659`) and lane C2 on #660 (`../claude-workbench-660`, `feat/spec-dev-app-author-660`), on sonnet, in parallel. They overlap only in `plugins/way-of-working/reference/project-schema.md`, on different sentences.
- The plan anchor on milestone 19 re-verified `match`.

**Next:** as the driver session (the only session that writes `.ai/`), on **opus**:
1. When a lane opens its PR (#626, #659 or #660), run `/way-of-working:pr-checks` on it and report whether it is ready for the maintainer's merge. Never merge.
2. After each merges, remove its worktree and local branch.
3. After #660 merges, draft the #666 spec with `plugins/way-of-working/skills/spec-task/SKILL.md` from `main`, critic-gate it (`architect` and `security-critic`) to convergence, and post it on #666 for the maintainer's reaction. After #659, #660 and #666 merge, do the same for #661.
4. #636 stays open until the maintainer's live run (`docs/identity/REVIEW-LIVE-RUN.md`).

Lane sessions never run `/resume`, `/handoff`, `/plan-sprint` or `/archive-sprint`.

**HITL Gate: NONE OPEN** — next gate: the maintainer merges each lane PR

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
