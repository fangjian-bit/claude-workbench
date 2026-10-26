# The identities cutover, GitHub side

What an operator does on GitHub to move a consuming repo from `identities: null` to a map and
to put the fresh-session review gate in front of its default branch (`WB-D24`, `WB-D37`).
The `identities` and `rulesets` keys themselves, and every shape the readers check, are in
`project-schema.md` (§ `identities`, § `rulesets`, § `review.ci_gate`); this file is the order
and the settings, written so the cutover can be finished from the plugin's docs alone. It
assumes the Apps exist and `identities` is ready to write; creating the Apps and the host
launcher's setup are not covered here.

Four parts: the gate workflow, the order, the approval side, the plugin pin.

## The gate workflow

The plugin does not carry the gate workflow. It lives in the plugin's source repository (the
marketplace repository the pin below names) as `.github/workflows/architect-review-gate.yml`.
Copy it from that repository at the tag the repo pins or will pin, a tag at or after the
release that ships this runbook, so the copy matches what is described here.

What the copy does:

- Its job asks for `contents: read`, `statuses: write` and `pull-requests: read`.
- It reads the **default branch's** `.ai/project.yml`, never the PR's. It fails without
  posting anything unless that copy has `identities` as a map with `reviewer_app` a map whose
  `id` is a positive integer; `review.ci_gate` as a map whose `header`, `attestation` and
  `check` are non-empty single-line strings; and a non-empty trigger list (`triggers_on`, or
  `code_paths` when `triggers_on` is `null`) of plain path prefixes: none of the characters
  `*?[]{}!`, no leading `/` or `./`, no `..` segment.
- `reviewer_app.id` is the App's bot account id (the `user.id` on its reviews), not the App ID
  its settings page shows.
- The status context it posts is the value of `review.ci_gate.check`, not the job's name.
- A PR that changes nothing under the triggers reads `success` (exempt). A PR whose compare
  result the gate cannot use (300 or more changed files, among other cases) reads `failure`
  whatever its review. A PR from a fork, exempt or not, does not pass by default: its token is read-only, so the status cannot be posted (a private repo's setting that sends write tokens to fork pull request workflows must stay off, since a fork's run uses the fork's own copy of the workflow). Any other PR reads `success` only with a fresh-session review by the
  reviewer App on its current head whose last matching review carries `Review verdict: pass`.
- It covers PRs into the default branch only: on a PR whose base is another branch it posts no
  status, and any run it makes there ends green.

The edits the copy needs:

- The `pull_request` trigger's branch `main` becomes the repo's default branch.
- Where an existing workflow holds the same path or the same `name:`, the copy takes another
  file name and another `name:`; the gate's concurrency group is keyed by the workflow's
  `name:`.

Require the check pinned to the GitHub Actions integration (`integration_id` 15368). An
unpinned required check can be satisfied by any token with `statuses: write`.

The pin's limit: a required check is met by a commit status or by a check-run of that name,
and a job's implicit check-run carries the job's name. So any job that holds `statuses: write`
or `checks: write` (granted by the job, by the workflow's `permissions:`, or by a read-write
default workflow token) and runs code a PR can change can post the context. For the gate's own
job that code is its workflow file, since a PR's run uses the PR's copy; only a human with write
access or an App holding Workflows write can add or edit a workflow, and every PR into the
default branch needs a code owner's approval to merge. For any other such job (a local action or
a repo script it runs) only that code-owner approval bounds it, since an App without Workflows
write can change a script. The pin also does not hold while a job in any workflow is named the
check's context (by its `name:`, or by its id when it has none), the gate's own `review gate`
included. It does not stop any workflow run in the repo, on any branch or trigger, that posts
the same context, nor a PR that changes only files outside the triggers (`.ai/project.yml`
among them, unless the triggers cover it).

## The order

Before PR 1 merges, these are in place: CODEOWNERS on the default branch from its own earlier
PR, the approval ruleset, the checks ruleset with every required check, the existing one included, pinned to the App that posts it, no bypass actor on either ruleset, the read default workflow token, and the dev App check (all in the
next part). Until then nothing holds a workflow or config edit. The pin (the last part) is on
the default branch no later than PR 1, and may ride in it.

**A repo whose ruleset already requires the check name** (for example through an existing
workflow whose reviews the reviewer App does not satisfy):

1. PR 1 sets a complete identities map as `project-schema.md` § `identities` requires (all
   four sub-keys, `reviewer_app` a map) and `review.ci_gate` in `.ai/project.yml` (its `check`
   equal to the required context), and adds the gate workflow, keeping the existing workflow.
2. PR 2 removes the existing workflow.

On PR 1 the new gate posts nothing while the default branch's `identities` or `review.ci_gate`
is not a map, and `wow-review` refuses such a repo, so PR 1 passes only through what the
existing workflow accepts. This two-PR order needs the existing workflow to pass every gated
PR that merges up to and including PR 1; the runbook covers no other case.

Between the two merges both workflows post the same context on a gated PR. So from PR 1's
merge no gated PR other than PR 2 merges until PR 2 has merged. After that, each gated PR
merges only after a fresh gate run on a head pushed after PR 2's merge, since what the old
workflow posted stays on its commit. That push needs a new review and a fresh approval, since
the review is matched on the head and stale approvals are dismissed on push.

**A repo whose ruleset does not yet require the check:** merge PR 1 first, then add the pinned
check to the live checks ruleset, then trigger the fresh runs, merging no gated PR in between.
Adding the check before the map is on the default branch deadlocks PR 1.

In either order:

- PR 1 lists `check` in `ruleset.required_checks` and in the checks entry of `rulesets`, the
  legacy `ruleset` key mirroring the checks ruleset.
- Before PR 1 merges, a repo admin turns off the repo's allow auto-merge setting and turns
  auto-merge off on every open PR that already has it armed, since an approved, armed PR would
  merge inside the window.
- Turning the setting back on, for a repo that allowed it before, is one manual step: the
  maintainer, as repo admin, turns it on after the cutover's last PR has merged and the pinned
  check has been confirmed in the default branch's checks ruleset.

## The approval side

Numbered, with who makes each change after the list:

1. **CODEOWNERS**: a file whose `*` line names only human code owners, each with write
   access, with no later line overriding it.
2. **The approval ruleset** on the default branch: a `pull_request` rule with code-owner
   review, stale reviews dismissed on push, last-push approval and a required approving
   review count of 1, plus `deletion` and
   `non_fast_forward` rules.
3. **The checks ruleset**, with every required check pinned to the App that posts it (15368
   for the gate's check).
4. **No bypass actor** on either ruleset.
5. **The repo's default workflow token set to read**, with any workflow that relied on the
   write default declaring its own permissions, and fork pull request workflows not sent
   write tokens.
6. **The dev App's registration holding no Workflows and no Administration permission**, checked in its App
   settings, since the integration pin's limit rests on only a human with write access or an
   App holding Workflows write adding or editing a workflow.
7. **The `rulesets` entries in `.ai/project.yml`** for both rulesets, with the legacy
   `ruleset` key kept in step, as `project-schema.md` § `rulesets` requires.

Who makes each: a repo ruleset needs repo admin, in the browser or through an admin App; an
org ruleset only an org owner in the browser, since a repo-scoped admin-App token cannot edit
it; never the dev App's token. The default workflow token and allow auto-merge settings are
repo admin, in the browser or through an admin App, unless an org policy fixes the token's.
The App permissions are the App owner's, in the browser. CODEOWNERS and `.ai/project.yml` are
PR changes.

A PR adding, editing or deleting a workflow file is pushed by a code owner or by an App
holding Workflows write, never the dev App (its registration holds no Workflows permission,
checked above; while an admin-App token is live in a container, everything in it is
elevated). It needs the approval of a code owner other than its author and last pusher, so on
a repo with one code owner the admin App pushes and opens it. No bypass actor is ever added to
unblock one.

## The plugin pin the review container requires

`.claude/settings.json` on the default branch carries:

- `extraKnownMarketplaces`, keyed by exactly `claude-workbench`. Its `source` has exactly the
  keys:
  - `source`, the value `github`;
  - `repo`, the value exactly `glunk-works/claude-workbench`. The review container accepts
    only these two values, so a fork or another marketplace name is refused;
  - `ref`, a `vMAJOR.MINOR.PATCH` tag at or after the release that ships this runbook,
    resolving to exactly one tag with no branch of the same name.
- `enabledPlugins`, setting `way-of-working@claude-workbench` to true.

A repo may have neither key today. Bumping the pin later follows `conventions.md`'s *Bumping a
pinned plugin* section, which this file does not restate.
