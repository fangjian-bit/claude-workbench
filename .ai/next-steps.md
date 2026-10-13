# Cursor — claude-workbench

**Now:** **Sprint 15** (cursor id `sprint-15`) on [milestone 18, *Identity M3: host broker and dev container*](https://github.com/glunk-works/claude-workbench/milestone/18). Status: **implementing**.

**Just done (2026-10-13):**
- #522 is closed (WB-D25: container commits are unsigned; `main` stays signed through GitHub's squash merge).
- Opened [PR #581](https://github.com/glunk-works/claude-workbench/pull/581) for #574 (`ce1a46f`): `containerEnv` forces `gpgsign` off, `gpg-check.sh` dropped from `postStartCommand`, `gpg`, `gpg-agent`, `gpgconf`, `gpg-connect-agent` and `gpgsm` deleted in the Dockerfile, DEV-CONTAINER.md and `conventions.md` reworded, WB-D25's rule and residual made conditional on the live check. It refs #574 and does not close it. Auto-merge was not armed on purpose.
- Critic pass on that diff (`security-critic`, `docs-consistency`): 4 rounds, converged; every critic on its frontmatter default model, no second-opinion round.
- Open on #574 and not mine to run: the live container checks, the `identity-ruleset-scratch` squash-merge test, the vigilant-mode check, and the entra repo read (404 to Seuss27). Two of #574's own checks are stale (the `gpg-connect-agent` one proves nothing now; change 3 lists four tools, not five).

**Next:** task #574 — after the human has run the live container checks on PR #581, record their results in the WB-D25 Residual bullet in `docs/decisions.md` and on the issue, and fix any wording the results contradict. PR #581 is not merged until then. On **sonnet** (coder). After it: draft the ruleset JSON and `gh api` commands for the two terraform repos.

**HITL Gate: OPEN** — the human rebuilds the dev container and runs the live signing checks listed on PR 581, then merges it

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 18](https://github.com/glunk-works/claude-workbench/milestone/18) · [.ai/parked/](parked/)
