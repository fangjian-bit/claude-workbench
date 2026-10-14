# Cursor — claude-workbench

**Now:** **Sprint 15** (cursor id `sprint-15`) on [milestone 18, *Identity M3: host broker and dev container*](https://github.com/glunk-works/claude-workbench/milestone/18). Status: **implementing**.

**Just done (2026-10-14):**
- #574's work is merged: [#581](https://github.com/glunk-works/claude-workbench/pull/581), [#583](https://github.com/glunk-works/claude-workbench/pull/583), [#584](https://github.com/glunk-works/claude-workbench/pull/584), [#585](https://github.com/glunk-works/claude-workbench/pull/585), [#587](https://github.com/glunk-works/claude-workbench/pull/587). The signing finding is recorded in WB-D25.
- `/way-of-working:plan-sprint` triaged the unmilestoned issues: #578, #579 and #588 placed on milestone 18; #589 (waits on #588's finding), #223 and #334 left unmilestoned on purpose, with triage comments.
- Milestone 18's description now lists #578, #579 and #588 as build-order steps 6–8, applied by this session at the human's request; re-anchored here (description sha `0e783b0d`).
- Could not re-verify the prior anchor: no `plan-anchor.sh verify` ran before this session's own milestone 18 edit. The description's hash matched the old anchor when read at triage and again just before the edit, and #574's `updated_at` is unchanged.
- No critic pass: this session's diffs touched no `code_paths`.

**Next:** task #574 — close the issue once the human has removed the leftover chore/remove-sigtest branch in terraform-cloudflare-dns, confirmed the entra cleanup and read the entra workflows for pushes to main. On **sonnet** (coder). After it: #578, then #579, then #588 (milestone 18 steps 6–8); then `/way-of-working:archive-sprint` for milestone 18.

**HITL Gate: OPEN** — the human deletes the leftover sigtest branch in the cloudflare repo, confirms the entra cleanup, reads entra workflows for pushes to main, and decides to close 574; could not re-verify the prior anchor: this session edited the milestone 18 description (plan-sprint steps 6-8: #578, #579, #588) with no plan-anchor verify run before the edit, so the human confirms the new description (sha 0e783b0d) is the one they approved

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 18](https://github.com/glunk-works/claude-workbench/milestone/18) · [.ai/parked/](parked/)
