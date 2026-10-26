# Cursor — claude-workbench

**Now:** **Sprint 18** (cursor id `sprint-18`), status **implementing**, working from milestone 20, *Identity M5: glunk-works repos cut over* (the code-owner gate only). Live lanes: `lane-state.sh list`.

**Just done (2026-10-26, driver session in the container, opus):**
- **Dev-container route:** a second Fable design pass (three lenses) and the maintainer adopted this repo's App-identity model, carried by a dev-App flavour of the base image and the shared template; recorded in #1163's body, to be written as WB-D42 (#1163).
- **Critic pass on the decisions** (`security-critic`, `docs-consistency`, `architect` on opus, read-only, one round): every finding applied as a tightening of the issue text; the route stands.
- **Milestone 20 split:** it is now the code-owner gate (#1158, #1159, #1163, then the cutovers #406, #407, #408 and #410 behind #1158, then #419). New milestone 26, *Identity M5b: dev containers on the shared template*: #1164 (token and `-Reference` belong to the repo), #715, #1165 (add-a-repo host steps); route steps 3 to 5 are filed when it is planned. #1161 keeps four host-hardening items, unmilestoned.
- **loop-orchestrator:** #409 deferred off milestone 20; the rearchitecture is glunk-works/loop-orchestrator#215 (filed by the maintainer).
- **CI credentials:** a rule folded into #406 to #408 (no cloud credential for a PR's code before Environment approval; read-only plan role reading no secret values; apply only from `main`; secrets move from Infisical to AWS). #419 rewritten as the AWS role trust-policy audit.
- For later: CHANGELOG 0.26.0 says `WOW_REVIEW_MAX` defaults to 2; `scripts/identity/wow-review` says 1.

**Next:** task #1158 — on **opus** (driver, fresh session): draft its spec with `/way-of-working:spec-task 1158`, then wait for the maintainer's reaction; build it as a lane only when the maintainer says so. The cutovers follow #1158; #1159 and #1163 can be specd alongside.

**HITL Gate: NONE OPEN** — next gate: the maintainer reacts to the spec comment for 1158

**Critic pass:** no diff in this driver session (issue, milestone and ledger writes). The decision critic pass above was a read-only review of issue text, not a critic-gate pass on a diff.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 20](https://github.com/glunk-works/claude-workbench/milestone/20) · [milestone 26](https://github.com/glunk-works/claude-workbench/milestone/26) · [.ai/parked/](parked/)
