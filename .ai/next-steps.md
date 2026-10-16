# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**. A coder lane is building #661.

**Just done (2026-10-16, driver session; no code):**
- #666 merged (PR #675, 3346e77): loop dispatch preflight accepts a maintainer-reacted dev-App spec. Its worktree and branch are removed; the empty `../claude-workbench-666` folder was held open and can be deleted by hand, like `../claude-workbench-396`.
- Drafted the [#661 spec](https://github.com/glunk-works/claude-workbench/issues/661#issuecomment-6220823257) with `spec-task` from `main` (pinned at 291a229, re-pinned to 3346e77 after #666 merged, which touched nothing it cites). Critic pass on the draft, `architect` and `security-critic` on their frontmatter models: 3 rounds (initial plus 2 fix-and-re-run rounds), converged. Posted as Seuss27 at the maintainer's request; the maintainer reacted, `spec-comment.sh check` returned `ok` and `spec-reaction.sh` `approved`.
- The maintainer decided during drafting that `spec-task` posts only as the declared dev App; under any other login, or with no `identities` map, it holds the composed comment (marker included) for a human to post. Recorded in the spec as `WB-D29`, which supersedes `WB-D26` and binds #662 and #663 to the marker reader rules.
- Gave the maintainer the #661 lane command and prompt (sonnet, `../claude-workbench-661`, `feat/spec-task-posts-661`, cut from `origin/main`).
- The plan anchor on milestone 19 re-verified `match` with `main`'s `plan-anchor.sh` (the installed v0.18.0 copy still reads it `unreadable`, and lacks `spec-issue.sh`; run both from `main`'s `bin/`).

**Next:** as the driver session (the only session that writes `.ai/`), on **opus**:
1. When the #661 lane opens its PR, run `/way-of-working:pr-checks` on it and report. Never merge or approve. After it merges, remove its worktree and branch.
2. After #661 merges, draft the #662 spec with `spec-task` from `main`. As a maintainer-token session it holds the composed comment; post it as Seuss27 only when the maintainer asks. Critic-gate it (`architect` and `security-critic`) to convergence, and once reacted give the lane command and prompt. Then the same for #663, then #664 last.
3. #673 lands before #458. #458 holds until a release containing #636 is pinned here and the #636 live run (`docs/identity/REVIEW-LIVE-RUN.md`) passes. #397 is the maintainer's, when the container cutover is ready.

Lane sessions never run `/resume`, `/handoff`, `/plan-sprint` or `/archive-sprint`. Every PR here needs a code-owner approval; Seuss27-authored PRs are approved by JaredGroves-603, and approving one with auto-merge armed merges it.

**HITL Gate: NONE OPEN** — next gate: the maintainer reacts to each posted spec and approves each lane PR

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
