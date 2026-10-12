# Resume appendix — reading the derived review step

Loaded on demand from `SKILL.md`'s *Derive the review step from GitHub* step, when `review-step.sh
decide` printed `show`, or `none` with a `state.json` `review_pr`, and for the loop-PR note. The one-line verdicts stay in `SKILL.md`.

**`show <M> <reasons>`** — the review step is derived, but must not start. Show it:
`/way-of-working:architect-review <M>`, the reasons in words (`no-state` — a fresh machine, the
ledger's **Next:** is behind by design and says so; `review-pr` — `state.json` votes for a
different PR or none; `head-moved` — the PR's head moved since the pin, so a new no-op handoff
from the fixed head re-pins it (also when the gate already reads green on a head the pin does not
name: say so, it is not an unreviewed PR); `app-mode` — the session holds an installation token, whose App this
derivation does not prove (`#381`), so the step is shown and waits for a human "go"; `token` — `next_action` is not `` review PR #M — ``
then the task token (**when it begins `` reviewed PR #M — ``, the review was already posted and the
vote consumed — `/way-of-working:architect-review`'s *Compose and post* step, `#283` — so report that
and do not offer the "go" below: a second review on the same pin is what the consumption prevents**);
`checkout` — not on `{pr_base}` at `origin/{pr_base}`'s tip with a clean tree (the work branch is never the checkout: it would load the PR's own hooks, `CLAUDE.md` and `.mcp.json`; `git switch {pr_base} && git pull --ff-only origin {pr_base}`, or the no-op handoff's own switch, fixes it);
`last-commit` — `state.json`'s `last_commit` is not the pin, so the cursor disagrees with itself; `model` —
`assigned_model` is not `{models.architect}`; `not-fresh` — not a fresh session), and wait. One
"go" from the human runs the derived step.

**`none`, with a stale `review_pr`.** If `.ai/state.json`'s `review_pr` names a PR, check it:
Run it in the same Bash call as the `jq` that re-reads `$SRN` and `$R` (each call is a fresh shell;
an empty `$SRN` is rejected by the guard and the stale cursor would go unreported):
`gh pr view "$SRN" --repo "$R" --json state -q .state` (only after
`case "$SRN" in ''|0*|*[!0-9]*) …` has passed it as a plain number). `MERGED` or `CLOSED` is *the
cursor is stale* — report which, and wait. The next ordinary handoff picks the next task and
writes the ledger PR. A PR that is still open but whose head moved is `show … head-moved`.

**A loop PR never matches, intentionally** (`WB-D22`): the milestone-2 driver opens PRs under the
GitHub App's identity, never the login this session runs as, so the one path that starts a review
under the owner's identity never derives a step from one. The backstop is the loop-identity guard:
`decide` prints `none` when the acting login equals `orchestration.loop_identity` (default
branch's copy, folded for case and a trailing `[bot]`, as `plan-anchor.sh` does; `null` means no guard), so a user-mode session that
happens to run as the loop's own identity derives nothing either. In App mode the guard sees only the
declared dev App, not the token held; `mode=app` capping the verdict at `show … app-mode` covers that.

**Why the gate comes from the default branch.** The PR under review can edit the working tree's
`.ai/project.yml`; otherwise a PR could blank the gate, or name a check that is always green, and
an unreviewed PR would read as reviewed.
