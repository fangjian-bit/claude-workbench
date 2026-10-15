# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**.

**Just done (2026-10-15, review and planning sessions; no code):**
- Filed #627 (the agent posts each spec, the maintainer's reaction approves it, no per-task anchor PR; reverses WB-D26), #628 (plan-sprint rewrites a build order live; retires the description hash) and #629 (critic-gate runs unattended on every drafted spec, to convergence or escalation, GitHub first and Slack later).
- plan-sprint passes: #627, #628 and #629 placed in milestone 19; #601 moved to milestone 22 (this repo's `main` requires no signatures); #394 retargeted to the v0.19.0 release and pin bump; #223 and #334 left unmilestoned. Triage comments are on each issue.
- Milestone 19's build order was rewritten into lanes that can run at once (maintainer; lane B: #623 then #626; lane C: #628, #627, then #629; the driver), then edited again to give #629 build-order step 12, from plan-sprint's staged text (posted on #629). The maintainer applied both edits. This handoff re-anchored milestone 19 on the live description, which matches that staged text byte for byte.
- Critic gate on #623's spec comment: security-critic and architect, 1 round, not converged. Seven blocking findings, recorded with the maintainer's decisions (the Claude credential stays behind `scripts/loop/inject.py`; #623 splits into four child issues) in [the findings comment](https://github.com/glunk-works/claude-workbench/issues/623#issuecomment-6192033842). The old spec must not get a reaction.
- Removed the merged `claude-workbench-392` worktree.

**Next:** as the driver session (the only session that writes `.ai/`), on **opus**: (1) split #623 into its four child issues per its findings comment, placed in milestone 19 and ordered in #623's checklist; (2) split #628 into its three child issues the same way; (3) draft the first child spec of each with `/way-of-working:spec-task`, run `/way-of-working:critic-gate` on each to convergence before posting, and post it for the maintainer's reaction; (4) give the maintainer one start prompt and the worktree commands per lane, per milestone 19's *Lanes* paragraph. Lane sessions never run `/resume`, `/handoff`, `/plan-sprint` or `/archive-sprint`.

**HITL Gate: OPEN** — milestone 19 description edited since last anchor: the maintainer applied the plan-sprint staged edit giving #629 build-order step 12 on 2026-10-15; the new anchor sha 0e45c15b0e2b9a9afdd12a32350ab4e6e145c9e5d8b5bfe7f60e40d7f3d74b5b equals that staged text (posted on #629, issuecomment-6192412581); confirm the live description is the plan

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
