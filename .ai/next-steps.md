# Cursor — claude-workbench

**Now:** **Sprint 16** (cursor id `sprint-16`) on [milestone 19, *Identity M4: claude-workbench cutover*](https://github.com/glunk-works/claude-workbench/milestone/19). Status: **implementing**. #629 has no spec comment yet.

**Just done (2026-10-18, driver session in the container, opus):**
- **#727 done.** The lane's PR #738 (`a1ea71a`) merged and #727 closed. Milestone 19 was set on #738 by hand, and the lane was cleaned up with `scripts/lanes/lane.sh done 727`.
- **Released way-of-working v0.20.0 (#686, closed).**
  - #739 (`d6136db`) bumped `plugin.json` and the CHANGELOG. Critic pass: `docs-consistency`, 2 rounds, converged; a second-opinion round on `fable` was offered and declined. Round 1 fixed a false #689 claim, marked `spec-task`'s shape gate as reaching `identities: null` repos, and added a null-repo note to #664.
  - `release.yml` published the tag. #740 (`3af77f6`) moved this repo's pin to `v0.20.0`; no critic pass, since it touches no `code_paths` entry.
  - The plugin was reinstalled at `--scope project` and verified by commit (`d6136db`). The installed plugin now matches `main`, so the old "run `main`'s `bin/` by absolute path" workaround is retired.
- **Gate benchmark.** One gate pass takes 22.4 min on the ext4 copy and 26.0 min on the 9p `/workspace` mount. The dev image's uutils `timeout` adds about 100 ms per call; with GNU `timeout` the gate takes **10.5 min** (#741). The script is in this session's scratchpad, not the repo.
- **Filed:** #737 (release v0.21.0 placeholder), #741 (GNU `timeout` in the dev image), #742 (root-owned `managed-settings.json` pinning `DISABLE_AUTOUPDATER`, the #733 follow-up), #743 (`wow-review`'s 1 s inject-up poll), #744 (`WB-D31` wording on the shape gate).

**Lessons, for the Lanes section and #629:**
- **App-filed issues.** Posting a spec comment on one moves the issue's `updated_at` past the maintainer's reaction on it, so a re-post needs that reaction removed and re-added first.
- **Maintainer account.** Only the `identities.maintainer` account's reaction counts; a reaction from another GitHub account is ignored.
- **One-line lane launch:** `docker exec -it -u app -e GIT_TERMINAL_PROMPT=0 -w /tmp/lanes/N <container-id> bash -lc 'claude --model sonnet; exec bash -l'`.
- **uutils in the container.** `date +%3N`, `tail -N` on several files and `timeout`'s speed all differ from GNU (#741). `/usr/bin/gnu*` holds the GNU versions.
- **Auto mode** refused `lane.sh done` as workload interference, so the human ran it.

**Next:** task #629 — on **opus** (driver): `/way-of-working:resume` drafts and posts #629's spec comment as the dev App (its drafting branch) and ends without building. After the maintainer reacts, a fresh driver session sets up a coder lane with `scripts/lanes/lane.sh prep` per the Lanes section, and the lane builds it.
- Then: the #729 and #728 specs.
- The rest is on [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19). #743 and #744 are unmilestoned, left for `/way-of-working:plan-sprint` to place.
- The maintainer decides which host memory notes still apply in the container, and whether to report the uutils `timeout` delay upstream.

**Lanes:** follow the Lanes section of [docs/identity/DEV-CONTAINER.md](../docs/identity/DEV-CONTAINER.md), with #735's per-call `PATH` prefix.

**HITL Gate: NONE OPEN** — next gate: the maintainer reacts to the #629 spec comment

**Pointers:** [docs/decisions.md](../docs/decisions.md) · [milestone 19](https://github.com/glunk-works/claude-workbench/milestone/19) · [docs/identity/DEV-CONTAINER.md](../docs/identity/DEV-CONTAINER.md) · [.ai/parked/](parked/)
