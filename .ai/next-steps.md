# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **planning**.

**Just done (2026-10-14):**
- **Sprint 15 archived** at `0e6d60b`; snapshot in `.ai/archive/sprint-15-next-steps.md`. Its `docs/decisions.md` entry landed in PRs #603 and #605. Nothing to compact.
- Filed [#604](https://github.com/glunk-works/claude-workbench/issues/604): the live re-run of `register-broker-task.ps1` with no `sh` on PATH (#578's fix is hermetically verified only).
- **plan-sprint:** #604 placed in milestone 19, #589 in milestone 22 (#588 has reported); #223 and #334 left unmilestoned (their earlier triage stands). 
- **Milestone 19's build order rewritten** (description read-back match; not yet anchored): #567, #566, #514 (human decision), #433, #395, #396, #458, #397, #398, with #601 as a parallel track. #394 is done (pin `v0.18.0` since #568) and is left for the maintainer to close. Every Claude-built item needs a maintainer-reacted spec comment before it is built; #601's spec also settles its schema key, the WB-D25 amendment and its release timing.

**Milestone close:** closed milestone 18, *Identity M3: host broker and dev container* (0 open issues, `verify --plan` match, read-back `closed`).

**Next:** plan sprint 16 on **opus** (architect), milestone 19: the build order is set; `/way-of-working:handoff` anchors the milestone and names task #567 first, with its spec comment posted for a maintainer reaction.

**HITL Gate: NONE OPEN** — next gate: plan the next unit

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [.ai/parked/](parked/)
