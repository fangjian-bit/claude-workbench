# Cursor — claude-workbench

**Now:** **Sprint 15** (cursor id `sprint-15`) on [milestone 18, *Identity M3: host broker and dev container*](https://github.com/glunk-works/claude-workbench/milestone/18). Status: **implementing**.

**Just done (2026-10-14):**
- [#598](https://github.com/glunk-works/claude-workbench/pull/598) merged (`891ffc7`): one repo-wide `* text=auto eol=lf` rule in `.gitattributes`. #579 is closed.
- The #588 spec is posted as [a comment on #588](https://github.com/glunk-works/claude-workbench/issues/588#issuecomment-6168954541) by the architect (Seuss27). It defines the task as a spike, not a code change: measure GraphQL `createCommitOnBranch`, REST git data and REST contents commits made as the dev App on a private glunk-works scratch repo carrying `required_signatures`, then write the finding plus a build issue or a WB-D25 amendment.
- The anchor was re-taken with that spec comment; milestone 18's description verified as `match` against the prior anchor.
- This ledger supersedes [#599](https://github.com/glunk-works/claude-workbench/pull/599) (the earlier, unanchored sync for #588), which can be closed unmerged.
- No critic pass: no code diff this session.

**Next:** task #588 — run the signing spike exactly as the spec comment https://github.com/glunk-works/claude-workbench/issues/588#issuecomment-6168954541 says: measure the App-API commit routes on the scratch repo, then post the finding on #588 and draft the follow-up it calls for. On **opus** (architect), in a fresh session (this one read #588's body). #588 is authored by `glunk-dev[bot]`, not a declared maintainer, so resume never auto-starts it; the human says "go". After it: `/way-of-working:archive-sprint` for milestone 18.

**HITL Gate: OPEN** — a maintainer reacts to the #588 spec comment and sets up the signing-scratch repo the spec names before the spike runs

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 18](https://github.com/glunk-works/claude-workbench/milestone/18) · [.ai/parked/](parked/)
