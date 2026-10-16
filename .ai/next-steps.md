# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**. A coder lane is building #662 part 1.

**Just done (2026-10-16, driver session; no code):**
- #661 merged (PR #677, 38495fa). Its worktree and branch are removed.
- #662 split into two PRs by the maintainer. Part 1 is `bin/spec-find.sh`, the finder that nothing calls yet. Part 2 is the reader switch-over, filed as #678 in milestone 19, with the critic pass's carry-forward in its scope.
  - The maintainer decided `spec-find.sh` and its test join `scripts/loop/protected-paths.txt` in #678.
- Drafted the [#662 part-1 spec](https://github.com/glunk-works/claude-workbench/issues/662#issuecomment-6224279943) with `spec-task` from `main`, pinned at 38495fa. Critic pass on the draft, `architect` and `security-critic` on their frontmatter models: 2 rounds, converged. Round 1 drove the split; round 2 left one test-setup fix, applied.
  - `spec-post.sh` held the comment (`not-dev-app`). It was posted verbatim as Seuss27 at the maintainer's request and verified byte-identical. The maintainer reacted; `spec-comment.sh check` returned `ok` and `spec-reaction.sh` `approved`.
- Gave the maintainer the #662 lane command and prompt (sonnet, `../claude-workbench-662`, `feat/spec-find-662`, cut from `origin/main`). The lane ships with `Refs #662`, and #678's PR closes both issues.

**Next:** as the driver session (the only session that writes `.ai/`), on **opus**:
1. When the #662 lane opens its PR, run `/way-of-working:pr-checks` on it and report. Never merge or approve. After it merges, remove its worktree and branch.
2. After it merges, draft the #678 spec with `spec-task` from `main`, using `main`'s `bin/`. Critic-gate it (`architect` and `security-critic`) to convergence, post it as Seuss27 only when the maintainer asks, and once it is reacted give the lane command and prompt. Then the same for #663, then #664 last.
   - **#678 blocking items.** These come from the #662 critic pass. Under a map, `verify` with `--maintainer-ids` and no `--spec-comment` prints `unreacted`, whatever is anchored. The resume body read and `architect-review` re-run the finder in their own Bash call and parse its line into variables, never pasting it. The coder stops when no found values are named.
   - **#678 decision record.** `WB-D30` records these residuals:
     - An approved spec stays a candidate indefinitely.
     - With two approved specs, deleting one picks the other.
     - Removing a reaction does not stop a build already running.
     - No git record says which spec a build used.
     - The review may judge against a different spec than the build used.
     - The reaction alone selects the spec.
3. #673 lands before #458. #458 holds until a release containing #636 is pinned here and the #636 live run (`docs/identity/REVIEW-LIVE-RUN.md`) passes. #397 is the maintainer's, when the container cutover is ready.

**Lane rules.** Lane sessions never run `/resume`, `/handoff`, `/plan-sprint` or `/archive-sprint`. Every PR here needs a code-owner approval; Seuss27-authored PRs are approved by JaredGroves-603, and approving one with auto-merge armed merges it. The installed v0.18.0 plugin lacks `spec-issue.sh`, `spec-post.sh` and the current `plan-anchor.sh`, so run them from `main`'s `plugins/way-of-working/bin/`.

**HITL Gate: NONE OPEN** — next gate: the maintainer approves the 662 lane PR and reacts to the 678 spec once posted

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
