# Cursor — claude-workbench

**Now:** **Sprint 14** (cursor id `sprint-14`) on [milestone 17, *Identity M2: dual-mode plugin v0.18.0*](https://github.com/glunk-works/claude-workbench/milestone/17). Status: **implementing**.

**Just done (2026-10-12):**
- **#476 merged** (#528, `d189e93`): ship's App-mode preflight now reads the acting App through GraphQL `viewer { login databaseId }` and tests it with `gh-identity.sh pr-actor` before the dry-run and the first push; the post-PR PR-user check stays as the backstop. `viewer` was measured on the dev and reviewer Apps (not the loop App) against the scratch repo, because the Apps are not installed on this repo.
- Critic pass on #476: architect, security-critic and docs-consistency, 2 rounds, converged; all critics ran on their frontmatter defaults (no second-opinion round). Subagent critics only; no fresh-session review gate is configured.
- Follow-ups filed: #529 (architect-review proves the reviewer App via `viewer` before posting) and #530 (coupling-check misses hardcoded App logins).

**Next:** task #479 — make archive-sprint read a null `backlog.repo` as the repo itself, stated once where it reads the config, and check the other skills that name `{backlog.repo}` in a call (resume, handoff beyond its derive line); add a fixture or a recorded run; run the green gate, then `/way-of-working:critic-gate` (`architect`, `security-critic`), then `/way-of-working:ship`. Run on **sonnet** (coder). Build order step 25; no dependency.

**HITL Gate: NONE OPEN** — next gate: the human's merge of #479's PR.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 17](https://github.com/glunk-works/claude-workbench/milestone/17) · [.ai/parked/](parked/)
