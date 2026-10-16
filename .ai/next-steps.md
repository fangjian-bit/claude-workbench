# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**. #662 part 1 has merged; the #678 spec is next.

**Just done (2026-10-16, driver session; no code):**
- #662 part 1 merged: `bin/spec-find.sh`, the approved-spec finder that nothing calls yet (PR #680, c3214e0). #662 stays open, since #678's PR closes it.
  - Its worktree and branch are removed. Windows still holds the empty `../claude-workbench-662` folder open, so delete it once nothing has it open.
- Raised with the maintainer, not yet decided: #458 waits for a release containing #636, and the planned release, #394, waits for #627, which is the whole #662–#664 chain. An interim release with #636 in it would let the cutover proof go ahead sooner.

**Next:** as the driver session (the only session that writes `.ai/`), on **opus**:
1. Draft the #678 spec (#662 part 2, switching the readers to `spec-find.sh`; its PR closes #662 and #678) with `spec-task` from `main`, using `main`'s `bin/`. Critic-gate it (`architect` and `security-critic`) to convergence. Post it as Seuss27 only when the maintainer asks, and once it is reacted give the lane command and prompt. Then do the same for #663, then #664 last.
   - **#678 blocking items.** These come from the #662 critic pass. Under a map, `verify` with `--maintainer-ids` and no `--spec-comment` prints `unreacted`, whatever is anchored. The resume body read and `architect-review` re-run the finder in their own Bash call and parse its line into variables, never pasting it. The coder stops when no found values are named.
   - **#678 scope.** The maintainer decided that `spec-find.sh` and its test join `scripts/loop/protected-paths.txt` in #678.
   - **#678 decision record.** `WB-D30` records these residuals:
     - An approved spec stays a candidate indefinitely.
     - With two approved specs, deleting one picks the other.
     - Removing a reaction does not stop a build already running.
     - No git record says which spec a build used.
     - The review may judge against a different spec than the build used.
     - The reaction alone selects the spec.
2. When a lane opens its PR, run `/way-of-working:pr-checks` on it and report. Never merge or approve. After it merges, remove its worktree and branch.
3. #673 lands before #458. #458 holds until a release containing #636 is pinned here and the #636 live run (`docs/identity/REVIEW-LIVE-RUN.md`) passes. #397 is the maintainer's, when the container cutover is ready.

**Lane rules.** Lane sessions never run `/resume`, `/handoff`, `/plan-sprint` or `/archive-sprint`. Every PR here needs a code-owner approval; Seuss27-authored PRs are approved by JaredGroves-603, and approving one with auto-merge armed merges it. The installed v0.18.0 plugin lacks `spec-find.sh`, `spec-issue.sh`, `spec-post.sh` and the current `plan-anchor.sh`, so run them from `main`'s `plugins/way-of-working/bin/`.

**HITL Gate: NONE OPEN** — next gate: the maintainer reacts to the 678 spec once posted

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
