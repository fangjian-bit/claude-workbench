# Cursor — claude-workbench

**Now:** **Sprint 15** (cursor id `sprint-15`) on [milestone 18, *Identity M3: host broker and dev container*](https://github.com/glunk-works/claude-workbench/milestone/18). Status: **implementing**.

**Just done (2026-10-14):**
- #574's work is merged: [#581](https://github.com/glunk-works/claude-workbench/pull/581), [#583](https://github.com/glunk-works/claude-workbench/pull/583) (identities declared), [#584](https://github.com/glunk-works/claude-workbench/pull/584), [#585](https://github.com/glunk-works/claude-workbench/pull/585), [#587](https://github.com/glunk-works/claude-workbench/pull/587).
- Live test finding, recorded in WB-D25: under `required_signatures`, a PR with unsigned branch commits cannot merge by the normal route; only the REST endpoint got one through. A host-signed branch commit merged by auto-merge (`terraform-cloudflare-dns` #73). Unsigned container commits therefore do not fit a repo carrying the rule.
- The maintainer wants every repo to require signatures. Filed [#588](https://github.com/glunk-works/claude-workbench/issues/588) (evaluate signing container commits through the dev App's API) and [#589](https://github.com/glunk-works/claude-workbench/issues/589) (require signed commits on every default branch, including the GPG key's 2026-12-31 expiry); both unmilestoned.
- No critic pass: this session's diffs touched no `code_paths`.

**Next:** task #574 — close the issue once the human has removed the leftover chore/remove-sigtest branch in terraform-cloudflare-dns, confirmed the entra cleanup and read the entra workflows for pushes to main; the open signing decision now lives in #588 and #589. On **sonnet** (coder). After it: `/way-of-working:archive-sprint` for milestone 18, then `/way-of-working:plan-sprint` to place #588 and #589.

**HITL Gate: OPEN** — the human deletes the leftover sigtest branch in the cloudflare repo, confirms the entra cleanup, reads entra workflows for pushes to main, and decides to close 574

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 18](https://github.com/glunk-works/claude-workbench/milestone/18) · [.ai/parked/](parked/)
