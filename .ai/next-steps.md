# Cursor — claude-workbench

**Now:** **Sprint 17** (cursor id `sprint-17`) on [milestone 24, *Green gate in parallel*](https://github.com/glunk-works/claude-workbench/milestone/24). Status: **implementing**. Live lanes: `lane-state.sh list`.

**Just done (2026-10-21 to 22, driver session in the container, opus):**
- **Sprint 16 closed:** milestone 19 (*Identity M4*) was closed, and sprint-16 was archived after its done entry merged (PR #906, `791c0ff`).
  - `v0.23.0` was released (PR #888) and pinned (PR #889). The container install was rotated and verified by commit.
  - #398 passes in full: the resume test of 2026-10-22 is written up in PR #887.
- **The verdict gate (WB-D38) works live.** On PR #897 a `changes-needed` review turned `architect-review` red, and the `pass` review turned it green.
  - The follow-up that drops the no-verdict form is #905. Every home's launcher must be reinstalled first, `603id-identity` included.
- **The retro now mines the repo's other sessions** (#895, PR #897).
  - Critic pass: architect, security-critic and docs-consistency converged after 3 rounds. Then 2 more architect rounds on the fix from the fresh-session review, which converged at round 5, the cap.
  - The retro filed #890–#894, #896, #898 and #905. Those reviews filed the follow-ups #899, #900, #903, #904 and #901 (fixed).
- **plan-sprint** rewrote M24's and M22's build orders live through `milestone-desc.sh`, checked by hash, and placed #823–#825 on M22.

**Next:** on **opus** (driver). Start no build here; `next_action` holds the lane loop. M24's build order names the tracks and their shared files. Tracks that can start in parallel:
- the CI track: #808, then #866, #877 and #881. It includes a host-side `ci.yml` push.
- #878, then #879.
- #882.
- #890 (needs security-critic).
- #862.
- #891, then #894.
- the retro follow-ups: #899 (with #903 folded in), then #900, then #904.
- #898.
- #896.
- #905, once every home is reinstalled.

**HITL Gate: OPEN** — first anchor for milestone 24: the maintainer confirms sprint-17 works from milestone 24

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 24](https://github.com/glunk-works/claude-workbench/milestone/24) · [milestone 22](https://github.com/glunk-works/claude-workbench/milestone/22) · [.ai/parked/](parked/)
