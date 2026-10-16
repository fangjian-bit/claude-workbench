# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**. A coder lane is building #666.

**Just done (2026-10-16, driver session; no code):**
- #396 merged (PR #672, 6a11fea). Its worktree and branch are removed; the empty `../claude-workbench-396` folder was held open and can be deleted by hand. `/resume`'s ruleset check now reads healthy as Seuss27 against `main`'s `rulesets` list, with no bypass actors on the approval ruleset.
- Drafted the [#666 spec](https://github.com/glunk-works/claude-workbench/issues/666#issuecomment-6219860092) with `spec-task` from `main` at e6ec967. Critic pass on the draft, `architect` and `security-critic` on their frontmatter models: 3 rounds (initial plus 2 fix-and-re-run rounds), converged. Posted as Seuss27 at the maintainer's request; the maintainer reacted, `spec-comment.sh check` returned `ok` and `spec-reaction.sh` `approved`. Started the #666 coder lane on sonnet (`../claude-workbench-666`, `feat/dispatch-dev-app-spec-666`, cut from 6a11fea).
- Filed [#673](https://github.com/glunk-works/claude-workbench/issues/673): `pr-checks` block (a2) treats an app-pinned context posted as a commit status as unmet, which is how a status-shaped review gate reaches GitHub. Unmilestoned; it must land before #458.
- Held #458, as the maintainer agreed. Its gate would block every code PR here until the reviewer App can review this repo, which needs a release containing #636, the pin bumped to it, and the #636 live run. The design is settled for when it is drafted: a status-shaped gate that counts only the declared `reviewer_app` id, with `.github/` always in scope.
- The maintainer confirmed #433 is done for this repo; it stays open for the other repos. #397 waits until the maintainer says the container cutover is ready, not only for #396.
- The plan anchor on milestone 19 re-verified `match` with `main`'s `plan-anchor.sh` (the installed v0.18.0 copy still reads it `unreadable`).

**Next:** as the driver session (the only session that writes `.ai/`), on **opus**:
1. Draft the #661 spec with `plugins/way-of-working/skills/spec-task/SKILL.md` from `main`, critic-gate it (`architect` and `security-critic`) to convergence, post it on #661 as Seuss27 when the maintainer asks, and once reacted give the lane command (Git Bash) and prompt. #661 may build alongside #666, but it must merge after #666.
2. When the #666 lane opens its PR, run `/way-of-working:pr-checks` on it and report. Never merge or approve. After it merges, remove its worktree and branch.
3. After #661 merges, do the same for #662, then #663, then #664 last.
4. #673 lands before #458. #458 holds until a release containing #636 is pinned here and the #636 live run (`docs/identity/REVIEW-LIVE-RUN.md`) passes. #397 is the maintainer's, when the container cutover is ready.

Lane sessions never run `/resume`, `/handoff`, `/plan-sprint` or `/archive-sprint`. Every PR here needs a code-owner approval; Seuss27-authored PRs are approved by JaredGroves-603, and approving one with auto-merge armed merges it.

**HITL Gate: NONE OPEN** — next gate: the maintainer reacts to each posted spec and approves each lane PR

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
