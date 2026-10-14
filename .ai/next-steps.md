# Cursor — claude-workbench

**Now:** **Sprint 15** (cursor id `sprint-15`) on [milestone 18, *Identity M3: host broker and dev container*](https://github.com/glunk-works/claude-workbench/milestone/18). Status: **implementing**.

**Just done (2026-10-14):**
- #574 closed. The leftover `chore/remove-sigtest` branches were deleted in terraform-cloudflare-dns (merged as #73) and terraform-microsoft365-entra (from #51, closed unmerged and superseded by #52). The entra workflows were read: none pushes to `main`.
- [#592](https://github.com/glunk-works/claude-workbench/pull/592) (`5ed5028`, open) records that read and cleanup in WB-D25.
- The human confirmed that milestone 18's re-anchored description (sha `0e783b0d`) is the one they approved. The anchor verified as `match` at this handoff and is re-taken on #578.
- No critic pass: this session's diffs touched no `code_paths`.

**Next:** task #578 — fix register-broker-task.ps1 so it no longer throws a null-property error when sh is not on PATH, built from #578's anchored spec comment only. On **sonnet** (coder). After it: #579, then #588 (milestone 18 steps 7–8); then `/way-of-working:archive-sprint` for milestone 18.

**HITL Gate: OPEN** — #578 has no spec comment: the maintainer posts the spec as a comment on #578 and reacts to it, and a handoff anchors that comment; also merge PR #592 (WB-D25 follow-up to the closed #574)

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 18](https://github.com/glunk-works/claude-workbench/milestone/18) · [.ai/parked/](parked/)
