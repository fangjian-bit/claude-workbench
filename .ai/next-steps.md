# Cursor — claude-workbench

**Now:** **Sprint 15** (cursor id `sprint-15`) on [milestone 18, *Identity M3: host broker and dev container*](https://github.com/glunk-works/claude-workbench/milestone/18). Status: **implementing**.

**Just done (2026-10-14):**
- #574's container half is finished and merged: [#581](https://github.com/glunk-works/claude-workbench/pull/581) (unsigned container commits), [#584](https://github.com/glunk-works/claude-workbench/pull/584) (the live check results and the squash-merge test on `identity-ruleset-scratch`), [#585](https://github.com/glunk-works/claude-workbench/pull/585) (the terraform repos). The squash merge satisfied `required_signatures` in all three test repos.
- [#583](https://github.com/glunk-works/claude-workbench/pull/583) declared `identities` on `main`, so ship's App-mode actor proof now passes for the dev App.
- The maintainer applied squash-only and a `wb-signatures` ruleset to `terraform-cloudflare-dns` and `terraform-microsoft365-entra`, and reports vigilant mode on for both accounts.
- No critic pass: this session's diffs touched no `code_paths` (docs and `.ai/project.yml` only).

**Next:** task #574 — close the issue once the human has removed sigtest.txt from main in terraform-cloudflare-dns and terraform-microsoft365-entra and checked both for workflows that push to main directly; PRs #581, #584 and #585 are merged and nothing else on it is code work. On **sonnet** (coder). After it: `/way-of-working:archive-sprint` for milestone 18.

**HITL Gate: OPEN** — the human removes sigtest.txt from main in both terraform repos, checks them for workflows that push to main directly, and decides to close 574

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 18](https://github.com/glunk-works/claude-workbench/milestone/18) · [.ai/parked/](parked/)
