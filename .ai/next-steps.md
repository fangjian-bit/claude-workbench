# Cursor — claude-workbench

**Now:** **Sprint 15** (cursor id `sprint-15`) on [milestone 18, *Identity M3: host broker and dev container*](https://github.com/glunk-works/claude-workbench/milestone/18). Status: **implementing**.

**Just done (2026-10-14):**
- [#592](https://github.com/glunk-works/claude-workbench/pull/592) merged (`50c9a11`).
- #578's spec was posted as a [comment](https://github.com/glunk-works/claude-workbench/issues/578#issuecomment-6167697303) by Seuss27. It widens the fix to the same null `.Source` lookup in `broker.ps1` and `install-host-tools.ps1`, and adds a no-tool-on-PATH fixture group to `tests/identity-broker.test.sh`.
- The anchor was re-taken on #578 with that spec comment. Milestone 18's description verified as `match` against the prior anchor (sha `0e783b0d`).
- No critic pass: this session wrote no code.

**Next:** task #578 — fix the null `.Source` lookups in register-broker-task.ps1, broker.ps1 and install-host-tools.ps1 with a no-tool-on-PATH fixture, built from #578's [anchored spec comment](https://github.com/glunk-works/claude-workbench/issues/578#issuecomment-6167697303) only. On **sonnet** (coder), in a fresh session. After it: #579, then #588 (milestone 18 steps 7–8); then `/way-of-working:archive-sprint` for milestone 18.

**HITL Gate: NONE OPEN** — next gate: the human merges the #578 PR

**Spec approval:** resume waits (`unreacted`) until the maintainer reacts 👍, ❤️, 🎉 or 🚀 on the spec comment, after its last edit.

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 18](https://github.com/glunk-works/claude-workbench/milestone/18) · [.ai/parked/](parked/)
