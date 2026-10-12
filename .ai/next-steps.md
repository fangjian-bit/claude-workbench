# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17). Status: **implementing**.

**Just done (2026-10-12):**
- **#510 merged** (#537, `af10ffe`): archive-sprint step 8 and the `CHANGELOG.md` header now point at `reference/conventions.md` § *Bumping a pinned plugin* instead of restating the superseded `claude plugin update` recipe; conventions gained a paragraph on why `claude plugin list`, a new cache directory and the `Base directory` header do not settle which commit is loaded. WB-D6 left as the past record.
- Critic pass on #510: docs-consistency 2 rounds and architect 1 round, converged; all critics ran on their frontmatter defaults (no second-opinion round). Subagent critics only; no fresh-session review gate is configured.

**Next:** task #517 — carry the drive-letter mirror step and the every-record verify check into `.github/workflows/release.yml`'s generated release notes by pointing at `reference/conventions.md` § *Bumping a pinned plugin* rather than restating the jq; archive-sprint step 8 already points there after #537, so confirm it needs nothing more. Run the green gate, then `/way-of-working:critic-gate` (`docs-consistency`, `architect`), then `/way-of-working:ship`. Run on **sonnet** (coder). Noted while auditing #510, outside it: `release.yml` runs `git ls-remote` without the `'<ref>^{}'` form conventions requires for annotated tags (harmless while tags are lightweight).

**HITL Gate: NONE OPEN** — next gate: the human's merge of #517's PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
