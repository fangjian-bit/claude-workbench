# App-mode run sheet: the skills as interactive sessions under a dev-App token

For #464 PR 2 (WB-D24). Session 6 of `docs/proposals/IDENTITY-SCRATCH-RESULTS.md` ran the skills'
command sequences by hand; it did **not** run the skills as Claude Code sessions. This sheet is for
that run. A session cannot give itself a different token, so the maintainer launches each one.

Record results in `docs/proposals/IDENTITY-SCRATCH-RESULTS.md` as a new session (7), in the same
shape as session 6: what was run, what came back, what it means. If a step does not do what this
sheet expects, that is the finding. Write down what happened; do not adjust the sheet to match.

## Setup (once)

- **Repo:** `603-Identity/identity-ruleset-scratch` (private; the approval ruleset applies). Clone it.
- **`.ai/project.yml` in the clone:** `identities.dev_app` set to the dev App's `{login, id}`
  (session 6: `603id-dev[bot]`, id 340163647), `maintainer` listing the human's login and id, and
  the other keys the schema requires (`schema-complete.sh check .ai/project.yml` prints
  `complete`). Commit it to the scratch repo's default branch first: skills read the **default
  branch's** copy.
- **Token:** mint from the dev App with `scripts/identity/mint.sh` (host config, key `dev.pem`),
  `--repos identity-ruleset-scratch`, `--perms contents=write,pull_requests=write,issues=write`,
  `--out` a file in a scratch directory. Never print it.
- **Launch each session** with the token in the environment only for that process:
  `GH_TOKEN="$(sed -n 1p <file>)" claude` from the clone, with the way-of-working plugin enabled at
  the version under test. Tokens expire within the hour; mint again between sessions.
- **Before each session,** confirm the mode from outside it: `gh api user` must fail (403) and
  `gh api installation/repositories` must list the scratch repo. If `gh api user` succeeds, the
  token is a user's and the run proves nothing.
- **`git` must use the same token as `gh`.** ship pins it for the push; for the other sessions, if
  a `git push` is needed, note which credential it used.

## Per skill

For each: invoke it, let it run, and record the first point where it stops or diverges. "Expect"
is what the skill text says should happen, checked for resume, ship, pr-checks and handoff; for archive-sprint, plan-sprint and retro it is a guess from session 6, not from their text. It is not a result.

### 1. `/way-of-working:resume`

- Needs a cursor (`.ai/state.json`) and, under `github_milestones`, a milestone with an issue.
- **Expect:** the schema check runs; a cursor-sync offer, if one is open, needs the human's explicit yes and merges with `--admin`, which the App cannot do (record what happens; resume never merges on its own). The review-step derivation takes the identity from the
  declared `dev_app` (`gh api user` fails), and an App-mode review step is **shown, never
  auto-started** (`show <M> app-mode`). With `dev_app` null it derives nothing.
- **Record:** the ruleset-check line (`Ruleset check:`) and whether it reads healthy, weakened or
  inconclusive; the review-step verdict; whether anything auto-started (it must not).

### 2. `/way-of-working:ship`

- Make a small change on the scratch clone, then run it.
- **Expect:** in App mode the push preflight does **not** read `.permissions.push`; it requires
  `origin` to be the repo over HTTPS, `dev_app` to be declared, then `git push --dry-run` with
  git pinned to `gh`'s token. After `gh pr create` the PR's author must equal `dev_app`
  (`gh-identity.sh pr-actor` prints `match`). A different author must stop it.
- **Also run once with a wrong credential** (a user token in `git`'s helper, or a token for a
  different App) to see the stop.
- **Record:** the preflight lines, the PR's `user` login and id, and the `mergeable_state`
  (`blocked`: approval gate). Close the probe PR and delete its branch afterwards.

### 3. `/way-of-working:pr-checks <N>` (changed by #467)

- **Retired by #384:** block (c), the identity read this step exercised, was removed with the
  READY (admin merge) verdict it served. Run it on a `BLOCKED` PR with every check green and an
  `update` rule applying and expect COULD NOT TELL naming the `update` rule; with an approval rule
  and no approval, expect AWAITING APPROVAL. No identity or bypass value is printed.
- **Record:** the exact verdict line and the rules it names.

### 4. `/way-of-working:handoff`

- Run it at the end of a small task.
- **Expect:** handoff takes the acting login for its no-op-handoff check from the declared
  `dev_app` (a `null`, absent or malformed one makes it open the ledger PR instead); it never
  merges its own PR. The PR's author should be the dev App.
- **Record:** whether the no-op handoff or the ledger PR was chosen, and why; the PR's author.

### 5. `/way-of-working:archive-sprint`

- Needs a sprint with a milestone and one closed issue.
- **Expect:** the snapshot, compaction and cursor reseed work as files plus a PR; the milestone
  close is a write (`issues` write covers issues and comments; **record whether it covers closing a
  milestone**, which session 6 did not test).
- **Record:** which writes succeeded and which returned 403.

### 6. `/way-of-working:plan-sprint`

- Needs `planning.kind: github_milestones`, an unmilestoned issue and an open milestone.
- **Expect:** the read-only gather works (`plan-gather.sh`); issue-level writes work. Milestone
  description edits are refused by the host's policy and staged as a script, as the skill says.
- **Record:** which writes the App token was allowed or refused, and whether staging fired.

### 7. `/way-of-working:retro`

- Run it at the end of any of the sessions above.
- **Expect:** it files an issue or comment through `issues: write`; the created item's `user` is
  the dev App, `author_association` `NONE`.
- **Record:** what it filed and under which login.

## What would close #464

- Every skill above has an entry in session 7 saying what happened, including the ones that
  stopped. A skill that stopped in App mode is a finding and a new issue, not a failed run.
- ship's actor check was seen to `match` for the dev App and to stop for a different credential.
- `pr-checks` block (c) was seen under the dev App token.
