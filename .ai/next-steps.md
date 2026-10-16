# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**. A coder lane is building #396.

**Just done (2026-10-16, driver session; no code):**
- #626 (PR #668), #659 (PR #669) and #660 (PR #670) merged. Their worktrees and local branches are removed; the empty `../claude-workbench-626` and `../claude-workbench-659` folders were held open and can be deleted by hand.
- Drafted the [#396 spec](https://github.com/glunk-works/claude-workbench/issues/396#issuecomment-6218600966) with `spec-task` from `main` at e64986d. Critic pass on the draft, `architect` and `security-critic` on their frontmatter models: 3 rounds (initial plus 2 fix-and-re-run rounds), converged. Posted as Seuss27 at the maintainer's request; the maintainer reacted, `spec-comment.sh check` returned `ok` and `spec-reaction.sh` `approved`. The maintainer kept `JaredGroves-603` out of `identities.maintainer`. Started the #396 coder lane on sonnet (`../claude-workbench-396`, `chore/declare-rulesets-396`).
- The live rulesets on `main` are now two, `main-required-checks` and `protected-integration-branches`, with no bypass actors; until #396 merges, `/resume` reports ruleset drift, as expected.
- Edited milestone 19's item 8 live through `main`'s `milestone-desc.sh` (`live ok`), as the maintainer confirmed: #397 waits for #396 and for no host lane session to be mid-build; its marker stays `[depends_on: #396]`. Record posted on [#397](https://github.com/glunk-works/claude-workbench/issues/397#issuecomment-6219217563). #636's live run is not a #397 prerequisite: it needs a release containing #636, which v0.18.0 is not.
- The plan anchor on milestone 19 re-verified `match` with `main`'s `plan-anchor.sh`. The installed v0.18.0 copy reads the hash-free anchor (#628) as `unreadable` until the pin moves.

**Next:** as the driver session (the only session that writes `.ai/`), on **opus**:
1. When the #396 lane opens its PR, run `/way-of-working:pr-checks` on it and report whether it awaits JaredGroves-603's approval. Never merge or approve. After it merges, remove its worktree and branch, and confirm `/way-of-working:resume`'s ruleset check reads healthy as Seuss27.
2. Draft the #666 spec with `plugins/way-of-working/skills/spec-task/SKILL.md` from `main`, critic-gate it (`architect` and `security-critic`) to convergence, post it on #666 as Seuss27 when the maintainer asks, and once reacted give the lane command and prompt. After #666 merges, do the same for #661.
3. After #396 merges, do the same for #458 (milestone 19 item 7).
4. #397 is the maintainer's, after #396 merges and once no host lane session is mid-build. #636 stays open until the maintainer's live run (`docs/identity/REVIEW-LIVE-RUN.md`), which needs a release containing #636.

Lane sessions never run `/resume`, `/handoff`, `/plan-sprint` or `/archive-sprint`. Every PR here needs a code-owner approval; Seuss27-authored PRs are approved by JaredGroves-603, and approving one with auto-merge armed merges it.

**HITL Gate: NONE OPEN** — next gate: the maintainer reacts to each posted spec and approves each lane PR

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
