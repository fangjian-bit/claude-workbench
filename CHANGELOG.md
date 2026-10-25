# Changelog

Consuming repos **pin a tag**, so nothing here reaches a repo until it bumps its pin in
`.claude/settings.json`. This file exists so that decision can be made with the contents in
view — `/way-of-working:archive-sprint`'s *Consider bumping the plugin pin* step prompts for
one at every sprint close, and a prompt that cannot say *"this one needs a migration"* is a
trap.

**Read the `⚠️ Migration` line, if a release has one, before bumping.**

**Editing the pin does not change what is loaded**, and `claude plugin update --scope project`
after a ref edit reports success while changing nothing on a project-scoped install. The procedure that
works (re-add the marketplace at the new ref, reinstall at `--scope project`, restart or
`/reload-plugins`, verify by commit) is *Bumping a pinned plugin* in
`plugins/way-of-working/reference/conventions.md` — including the Windows two-casings
`installed_plugins.json` trap and why neither the version string, `claude plugin list` nor a new cache directory proves anything.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Releases before
`v0.5.0` are summarized from their tags; the full record is `docs/decisions.md` (`WB-D*`) and
the GitHub release notes.

## [Unreleased]

### Changed

- The `identities` config read that the five spec scripts shared as copies now lives in `bin/declared-ids.sh`, with no change to any word they print (`#1079`).

### Fixed

- **`/way-of-working:retro`'s run-again remedy names the window the first run used (`#1092`).**
  After a reply that only asks a question, the human runs retro again naming the window the first
  run said it used, so a sprint close's transcripts are not left outside the second run's window.
- **A `/way-of-working:retro` rerun takes nothing an earlier run reported as evidence, and states its window as an absolute start (`#1097`, `#1102`).**
  Neither the earlier run's reader report nor its held list, in context or in a staged transcript,
  is evidence for the rerun or confirms anything. The *Which sessions* bullet gives the window as
  the absolute date and time it starts, so the human can name it when running retro again.

## [0.25.0] — 2026-10-24

**⚠️ Migration** — in each repo that labels by type, rename the four type labels in place
(`gh label edit bug --name type/bug`, and likewise `feature`, `chore`, `docs`), which keeps them on
existing issues and PRs. Where the host launcher (`wow-review`) files findings into that repo (the reviewed
repo's `backlog.repo`, else the reviewed repo itself), also reinstall the host tools from a default branch at
or after this release in every home; while only one of the two is done, the findings it files carry no
type label (`WB-D40`). Optional: this repo also deleted the six GitHub default labels (`duplicate`, `invalid`,
`question`, `wontfix`, `good first issue`, `help wanted`), each once it had no uses; an adopter need not (this
sentence was added after the release).

### Added

- **A later `spec-task` run continues an escalated spec from a maintainer's answer (`#790`, `WB-D39`).** Under an `identities` map, a declared maintainer answers the newest `spec-task-escalated:` comment with a `spec-task-answer: escalated=<id> choice=apply|amend` comment; `spec-find.sh answer` finds it, the new `spec-answer.sh` is the only reader that prints either comment, and `spec-task` redrafts, critic-gates and posts as usual. The redraft still needs a maintainer's reaction. `spec-find.sh find` and `pending` print what they printed before.
- **`scripts/invariants-check.sh` check 25 fails when an agent is missing from a manifest description (`#932`).**
  Every `plugins/*/agents/*.md` frontmatter `name` must appear as a whole token in the `description`
  of its plugin's `plugin.json` and in the `description` of the matching `marketplace.json` entry, so
  an agent added without a description edit (as `transcript-reader` was in `#911`) fails CI. A name
  right after a `:` (a skill's `/way-of-working:NAME` mention) does not count.

### Changed

- **The type labels are now `type/bug`, `type/feature`, `type/chore` and `type/docs` (`#953`, `WB-D40`).**
  The conventions, the ship skill and the review launcher's issue filing use the prefixed names.

### Fixed

- **`cursor-drift.sh` lists both paths of a rename, so a file renamed into `.ai/parked/` from outside the allowlist reads `drift` (`#1074`).**
- **`/way-of-working:retro`'s *When to run* follows archive-sprint's retro offer (`#1075`, `#1076`, `#1077`).**
  At a sprint close retro runs on a yes to the offer `/way-of-working:archive-sprint` makes after
  its report, not before it. Step 6 now says a reply that only asks a question confirms nothing
  and leaves every held item deferred. The `#1066` entry below is rewrapped, its wording unchanged.
- **`/way-of-working:retro`'s held-items question states the reply form, and the routing report no longer waits on a reply (`#1066`, `#1067`, `#1068`).**
  The question tells the human to confirm each item by its own number with a yes to both parts (a
  range or "all" confirms nothing; only the human's next message is the reply), the routing report
  goes in the same message as the question with the held material deferred, and the reply gets a
  short follow-up. The retro test's greps on the skill now match across line breaks, and the hold
  paragraph is rewrapped.
- **`/way-of-working:retro` asks once about held cross-session items (`#939`, `#940`, `#927`).**
  The *Implement the cheap; propose the rest* step now asks the human in one message, listing
  every held item numbered with its caveat, and routes each item the human's reply confirms
  by number; each held item needs its own confirmation, and an unconfirmed one stays deferred.
  Retro's config read list also names `{repo}`.
- **The broker's scheduled task no longer leaves a broker running after a stop, and a killed broker is restarted (`#1016`, `#1015`).**
  `register-broker-task.ps1 -Unregister` and the reinstall's task stop now also end the `pwsh` whose
  command line carries the task's own `-File` path (stopping conhost did not), and wait for it; the
  install disables the task across the swap and enables it again after (if it was enabled), on failure too;
  that applies to the review poll task's reinstall as well, though its registration is unchanged and it ends no process. The task's
  repeating trigger runs every minute and the `-RestartCount` settings are gone, since conhost exits 0
  when the broker is killed and the restart never fired.
- **`/way-of-working:archive-sprint` gives the pin-bump note in the same message as the retro offer (`#1003`).**
  Step 7 said the *Consider bumping the plugin pin* step "follows on any answer", which read as
  waiting for a reply to the offer, so with no reply the note was never given. The note now goes
  before the offer in the same message, and retro runs only on a yes typed later.
- **`/way-of-working:archive-sprint`'s pin step states where its note goes (`#1048`, `#1052`).**
  The *Consider bumping the plugin pin* step now says its note goes in the *Report* step's message,
  between the report and the retro offer, so the order is readable from either step.
- **`bin/lane-groups.sh` prints only `unreadable` when its final pass fails (`#1009`).**
  Before, a failure partway left some rows on stdout followed by `unreadable`.
- **`spec-task` says when a maintainer's `spec-task-answer:` comment is not used (`#1078`).**
  When the answer branch does not apply, `spec-find.sh answer` prints `ignored <ids>` and the skill names those comments before drafting from the body.

## [0.24.0] — 2026-10-23

### Added

- **`bin/lane-groups.sh` prints which open tasks on a milestone can run as parallel lanes (`#896`).**
  For each open issue it shows the spec state, the paths its approved spec lists under *Files
  touched* (an issue without one is unknown, never guessed), the open issues it shares a path with
  and the ones it waits for from the Build order, then the groups that can start together now.
  It is display only: the driver still writes the Lanes line through `milestone-desc.sh`. A new
  `spec-fresh.sh paths` mode prints the checked paths, so there is one parser.

### Changed

- **The leak screen also drops a report on slash-led text with a second slash (`#952`).**
  A new last shape, `abspath`, catches an absolute path outside the existing shapes, and a file
  URL with an empty host (any colon followed by three slashes). Slash commands, plain URLs, and
  repo-relative paths and star globs still pass; the header comment states its known misses and
  false drops.
- **archive-sprint offers a retro at every sprint close (`#898`).**
  The offer no longer depends on the closing session having done the sprint's work, since retro now
  reads the repo's other recent sessions. It stays one optional line and never a gate.
- **The transcript reader's instructions no longer trip the leak screen (`#981`, `#982`).**
  The agent file describes a home-relative path in words instead of writing it, so a report that
  restates the rule is not dropped, and retro's sentence about a path-shape drop no longer lists
  the shapes, so it cannot fall behind the screen. The screen and its drop-whole rule are unchanged.
- **The transcript reader writes repo paths repo-relative and no credential-shaped text (`#961`, `#957`).**
  Its instructions now say to describe any other path in words and to name a finding about a
  secret only in words, so retro's leak screen should drop its report less often. The screen
  and its drop-whole rule are unchanged.
- **`/way-of-working:retro` also mines the repo's other recent sessions (`#895`).** A new step
  selects the host's top-level Claude Code transcripts whose `cwd` is the main worktree or a
  path under `lanes.dir`, changed since the reviewed sprint began (from the newest
  `.ai/archive/` snapshot, else the last 7 days, or a window the human names), newest first and
  at most 50. One subagent reads them and returns a
  paraphrased friction list, never verbatim transcript text. Anything drawn from other
  sessions carries a path-match caveat and needs the human's OK before it is filed, noted as
  "confirmed again" on an existing item, becomes a memory or becomes a fix; the human confirms
  both that the sessions are this repo's and the finding itself (`#900`).
- **An App-filed issue's spec reaction is judged by its content time, not `updated_at` (`#890`).**
  `spec-issue.sh` and `spec-post.sh` compare a maintainer's reaction with the latest of the
  issue's creation, its body's last edit and its newest title rename (one GraphQL read), so a
  comment, a label or a milestone change, spec-task's own spec post included, no longer stales
  it. An edit to the title or body still does; a failed or malformed read fails closed.
  `invariants-check.sh` check 18 pins that query as a fourth line of `spec-post.sh`.

- **Retro's transcript reader is confined by its tool list (`#899`).** The reader is now the
  plugin agent `transcript-reader`, whose frontmatter grants only `Read`, `Grep` and `Glob`, over
  text the parent stages with one fixed `jq` filter into a temporary directory, instead of a
  subagent told in prose to run only a few commands.

### Fixed

- **Retro's other-session path match is stated as POSIX-only (`#904`).** Separators and drive
  letters are compared as written, with no normalization, so on a host whose recorded `cwd` and
  the paths it is matched against differ in form (native Windows) the step finds no transcript
  and says so, as it does for any host with no matching transcript.
- **Invariants check 24 no longer reads a hash inside a quote that closes on the same line, or a
  hash after a Unicode space, as a comment (`#882`).** A gate call such as `bash
  scripts/invariants-check.sh " #" || true`, or one followed by U+2003 and `# || true`, left the
  check silent while bash still ran a narrowed or empty call. The whole-line test and the
  trailing-comment strip now see only ASCII spaces and tabs, and a line whose trailing comment holds
  a quote now fails.
- **Both manifest descriptions now name the `transcript-reader` agent (`#915`).** The plugin
  manifest and the marketplace's `way-of-working` entry listed only the architect, coder,
  security-critic and docs-consistency agents; they now add the read-only `transcript-reader`
  that `/way-of-working:retro` spawns.
- **Retro screens the transcript-reader's report before using it, and the staging line shows
  an empty extraction (`#914`, `#916`).** The reader can Read any path, so injected transcript
  text could steer a credentials file into its paraphrase. The session now writes the report to
  the staging directory and runs the new `leak-screen.sh` over it (`spec-post.sh`'s six leak
  shapes plus an `sk-ant-` key and a `~/` path); a report that matches is dropped whole, with
  one line naming only the shape and line number. Each staged transcript now reports `ok
  COUNT`, `empty` or `failed`, so a format change that extracts nothing no longer shows as `ok`.

## [0.23.0] — 2026-10-22

**⚠️ Migration** — on a repo whose reviews post through the host launcher (`wow-review`), reinstall
the host tools from a default branch at or after this release in every home before bumping the pin
(`WB-D38`). An older launcher ignores the review's verdict file and posts without a `Review verdict:`
line, which the gate still accepts as a pass until the follow-up drops that form.

### Added

- **`review-outbox.sh verdict` and the architect-review container-mode verdict step (`#851`).** The
  review session writes `pass` or `changes-needed` to the outbox before the findings, and the
  `architect-review` gate fails a head whose latest review reads `changes-needed`. The verdict reaches
  a posted review only through a host launcher installed at or after this change; `review.ci_gate.header`
  drops the word HITL (`#852`). `WB-D38`.
- **Invariants check 24 fails a gate call that carries an argument (`#874`).** A tree where a workflow
  or the project file puts an argument after `scripts/invariants-check.sh` now fails, so
  a narrowed `--only` call written that way cannot stand in for the gate.

### Fixed

- **`park-sprint` no longer publishes the derived `lanes` array (`#797`).** Park writes the
  tracked snapshot with `"lanes": null`, and `unpark-sprint` restores the cursor with
  `"lanes": null` whatever the snapshot holds; the next handoff derives the live array. A new
  invariants check (23) fails a tree where either skill drops the literal.
- **`spec-shape.sh check` refuses a marker-prefixed line (`#831`).** A draft with a line beginning
  with `spec-task:` or `spec-task-escalated:` now reads `has-marker` at the first shape check,
  before any critic runs, instead of only at `spec-post.sh` after the critic gate. spec-task fixes
  it once and re-checks, as for `missing`. `spec-post.sh` is unchanged and keeps its own
  `has-marker` check as a backstop, but now stops such a draft `bad-shape`, as it runs the shape
  check first.

## [0.22.0] — 2026-10-21

### Added

- **`bin/api-commit.sh`, a second App-mode publishing route (`WB-D36`, `#601`).** It replays a
  branch's local commits through the REST git data API as the dev App, with no `author` or
  `committer`, so GitHub signs them and a PR from a repo that requires signed commits reads `CLEAN`,
  then resets the local branch onto the commits GitHub made. A repo selects it with the new optional
  sub-key `identities.dev_app.commit_route` (`git` or `api`); an undeclared one selects `git`, so no
  existing `.ai/project.yml` needs a change. `ship`, `handoff`, `archive-sprint` and `resume`'s schema
  interview read the key in App mode. `schema-complete.sh` rejects a present value other than `git`
  and `api`. A new invariants check fails a skill, agent or bin script that sends `git/commits` an
  `author` or `committer`. Workflow edits stay host-side: the route refuses a commit that touches
  `.github/workflows/`, and a merge is checked on its diff from its first parent. A merge of a
  base-set branch into the branch is published with both parents (`#811`) unless it brings in a
  `.github/workflows/` change; every other merge is refused, as is a rebase of an
  already-published branch.

## [0.21.0] — 2026-10-20

**⚠️ Migration** — on a map repo a build now refuses, as `bad-shape`, an approved spec whose body
carries a zero-width, bidi, soft hyphen or Unicode tag character anywhere, not only in *Files touched*
(#709, `WB-D31`). Re-draft it with `/way-of-working:spec-task` and move the maintainer's reaction to
the new comment.

**⚠️ Migration** — a map repo whose `identities.maintainer` lists the id of its declared reviewer or
loop App, or whose reviewer or loop App entry is neither null nor well formed, now has `spec-find.sh`, `spec-comment.sh` and the loop
preflight refuse its spec approvals (and `plan-anchor.sh verify`, which resume now passes the App ids, as a second check for a collision), and a
reviewer or loop App id not written in canonical decimal is refused by the shell readers and by resume's
`gh-identity.sh role` read, until the config is corrected on the default branch (the dev
App's id already was, #660, #682, #689, #707). Resume also
waits until `reviewer_app` and `loop_app` are present, each a null value or a map that
`gh-identity.sh role` confirms.

**⚠️ Migration** — on a map repo, `/way-of-working:spec-task` now stops `unreadable` (from `spec-issue.sh` or `spec-post.sh`), until the config is corrected on the default branch (#759): on a maintainer's or the dev or reviewer App's task issue when `identities.maintainer` lists a declared App's id (other than the author's own, which stops `untrusted`), the dev App's included, or when a declared App entry, the dev App's included, is neither null nor well formed or its id is not canonical decimal; and, for a maintainer's issue too, when `identities.maintainer` carries an entry that is not well formed, which passed before.

**⚠️ Migration** — on a map repo a build now refuses, as `bad-shape`, an approved spec carrying any newly refused form:
a `<` followed by `!` or `?`, a `<` and a slash followed by a non-letter or the end of the line, a link reference definition line, any numeric character
reference, a named reference to an invisible character, or a default-ignorable character such as a variation selector (#757, `WB-D31`).
`spec-task`'s shape gate refuses such a draft on every repo, and an App-filed issue carrying one stops `hidden`. Re-draft the spec
and move the maintainer's reaction to the new comment.

**⚠️ Migration** — `/way-of-working:spec-task` now spawns critic subagents on every draft (real spend,
bounded by the cap) and stops `no-critics` on a repo whose `agents.enabled` lacks `architect`. `spec-post.sh`
refuses a draft without a critic line, so re-posting a body drafted before this change needs one (#629,
`WB-D35`).

### Added

- **Context controls and lane state for the long-running driver session** (#729, `WB-D34`). A
  `PreCompact` and a `PostCompact` hook (matcher `auto`, `hooks/compact-handoff.sh`) tell the driver
  to run `/way-of-working:handoff` when an automatic compaction happens; they are silent outside a
  main worktree, never block, and a manual `/compact` is untouched. This repo's `.claude/settings.json`
  gains a `statusLine` that shows `ctx NN%`. `bin/lane-state.sh` derives the live lanes from the
  `dir/<N>` worktrees, the spec finder and GitHub's same-repository PRs; `/way-of-working:handoff`
  writes them to the cursor's new `lanes` field and `/way-of-working:resume` prints a `Lanes:` line
  and compares it with the record. The new key `lanes` (`null` or `{ dir }`) is optional and never
  asked (`reference/project-schema.md` § `lanes`). No consuming repo needs a migration: a repo opts in
  to the lane state by adding `lanes` to its project file.
  **Behaviour change:** the compaction hooks are not gated on `lanes`. In every consuming repo, a
  session in the main worktree of a checkout with `.ai/project.yml` now gets the hooks' compaction
  instructions and a "run `/way-of-working:handoff`" line after an automatic compaction.

### Changed

- **`critic-gate` gains a spec mode, and `spec-task` runs it on every draft** (#629, `WB-D35`): critics chosen by
  rule, unattended, under the same cap; a converged draft is posted with a critic line, a draft that hits the cap
  or stops converging is posted through `spec-post.sh escalate` with its open findings. `spec-post.sh` stops
  `no-critic-line` on a draft without a well-formed critic line for its mode. Nothing writes to Slack.
- `spec-post.sh escalate` posts a draft under the `spec-task-escalated:` marker and adds `status/needs-human` when the repository has that label (otherwise it reports `label-absent` and writes no label); `spec-find.sh find` prints `escalated <ids>` and `pending` counts a newer escalated comment (#746). `spec-task` calls the mode as of #629, in the same release as this finder.
  **Behaviour change:** `reference/conventions.md` names `status/needs-human` as an un-namespaced label a machine writes, the declared dev App under its own identity, so an adopter's automation keyed to that label (an `issues: labeled` workflow, for example) now also fires on the dev App's write.
- **`spec-task` refuses a declared App id on the maintainer list** (#759): `spec-issue.sh` and `spec-post.sh` stop `unreadable` under a map, for a maintainer or App author, when any declared App's id is on `identities.maintainer` or an App entry is neither null nor well formed or its id is not canonical decimal, or, for a maintainer's issue too, `identities.maintainer` carries an entry that is not well formed, which passed before, all before the issue's reactions are read; `WB-D30` residual 7 is amended.
- **No declared App is a spec approver** (#708): `spec-find.sh`, `spec-comment.sh` and
  `scripts/loop/preflight.sh github-dispatch` refuse a config that lists the id of the dev, reviewer or
  loop App on `identities.maintainer`, and `plan-anchor.sh verify` does when given the new flag. It gains `--declared-app-ids <id,id,...>`, which
  resume passes; `WB-D30` residual 7 is amended.
- **`spec-fresh.sh` refuses a hidden character anywhere in a spec comment** (#709, `WB-D31`): `check` and
  `shape` print `bad-shape` for a `HID` character on any line of the body, `HID` gains the soft hyphen
  (U+00AD) and the Unicode tag block (U+E0000 to U+E007F, widened to U+E0000 to U+E0FFF by #757 below) in all three copies, and the `hidden` screen of
  `spec-issue.sh` and `spec-post.sh` for App-filed issues is wider by the same two ranges.
  **Behaviour change, `identities: null` repos:** `spec-task`'s `spec-fresh.sh shape` gate has no map
  condition, so a draft carrying such a character is refused on every repo.
- `/way-of-working:plan-sprint` shows each unmilestoned issue's author as `trusted`, `agent`, `untrusted`, `legacy` (or `unjudged`), judged by `gh-identity.sh task-author` through the new read-only `plan-gather.sh authors`, so an issue filed by the declared dev or reviewer App no longer reads `untrusted`. An `agent` row carries a note that drafting its spec needs a declared maintainer's approving reaction after the issue's last change. Display only: nothing is gated on the word (#710, `WB-D32`).
- **One hidden-text screen for spec comments and App-filed issues** (#757, `WB-D31`): `spec-fresh.sh`, `spec-issue.sh` and `spec-post.sh`
  use the same opener test and share `HREF` and `LDEF` lines, and `HID` is now Unicode's default-ignorable set (variation selectors included). Residual 19 of
  `WB-D31` records the forms that still pass. **Behaviour change, `identities: null` repos:** `spec-task`'s `spec-fresh.sh shape` gate has no map
  condition, so a draft carrying a newly refused form is refused on every repo.
- `spec-post.sh`'s `leak` stop now prints `leak <line> <shape>`, and `spec-task` names the leak shapes in its drafting step (#732).

### Fixed

- **`spawn-model.sh` reads `confirmed` again for a spawn on the expected model** (#749): it skips `api-request-blob` records, request-payload copies that carry no model, some with an assistant role. Tested by new fixtures in `tests/spawn-model.test.sh`.
- **Resume's `bad-shape` waiting line names every cause** (#756): a refused hidden character, a markup opener (after #757: `<!` or `<?`, a bogus closing tag, a link reference definition, or a numeric or named invisible reference) or a stray CR anywhere below the marker line, as well as a *Files touched* section the check cannot read, where it named only the section.
- **Drafting a spec ahead is now stated for map repos only** (#764, `WB-D31`): `spec-task`'s description and body, `reference/workflow.md` and `docs/decisions.md` (`WB-D31`'s *Drafting ahead* bullet and the `WB-D26` reversal note) scope it to an `identities` map; on an `identities: null` repo no build re-checks the paths a spec lists against the base. Docs only, no behaviour change.

## [0.20.0] — 2026-10-18

**⚠️ Migration** — on a map repo a build now refuses a spec whose *Files touched* section is not one
`- ` bullet per file with the path in backticks (`bad-shape`), or whose listed paths changed on the
base since its commit (`stale`) (#663, `WB-D31`). Re-draft an already-approved spec that reads either,
with `/way-of-working:spec-task`, and move the maintainer's reaction to the new comment.

### Added

- **An issue the dev or reviewer App filed can be drafted once a maintainer reacts to it, and built once its spec is approved** (#664, `WB-D32`):
  `gh-identity.sh task-author` judges a task issue's author (`trusted`, `agent`, `untrusted`, `legacy`);
  `spec-issue.sh` and `spec-post.sh` read an `agent` author's issue only after a declared maintainer's
  approving reaction strictly after its last update, and screen its decoded title and body for hidden
  text; `resume`, the `coder`, `architect-review` and the loop preflight accept such a `#N` on the strength of
  its approved spec comment. Invariants check 21 guards the three skill and agent readers. Repos with
  `identities: null` are unchanged: `task-author` reads them as `legacy`, the allowlist as before.
- **`bin/spec-fresh.sh`, `bin/draft-identity.sh` and `spec-find.sh pending`** (#663, `WB-D31`): on a
  map repo a build now re-checks the paths its spec lists under *Files touched* against the commit
  in the spec's marker and refuses a stale spec (`resume`'s body read and the `coder` agent run
  `spec-comment.sh check`, then `spec-fresh.sh check`, then `spec-comment.sh body`). As the declared
  dev App with no stored login behind it, `resume` may instead draft and post one spec comment (when
  the finder finds none, or when the approved one is stale and no newer draft is waiting) and end without
  building. `spec-task` may be run ahead for any task whose `depends_on` is met, and runs
  `spec-fresh.sh shape` on its draft. Tested by `tests/spec-fresh.test.sh`,
  `tests/draft-identity.test.sh` and the new `pending` fixtures in `tests/spec-find.test.sh`; invariants
  check 17 now covers `spec-fresh.sh`. **Behaviour change, `identities: null` repos:** `spec-task`'s
  `spec-fresh.sh shape` gate has no map condition, so a draft whose *Files touched* section is not one
  `- ` bullet per file with the path in backticks is refused as `bad-shape` after one fix, on every
  repo. Its path allowlist is `A-Za-z0-9._/-`, so a path such as `+page.svelte` or `[slug]` always
  reads `bad-shape` (`WB-D31`, residual 17).

### Changed

- **The loop's dispatch preflight needs a maintainer's reaction on every spec comment under a map** (#682,
  `WB-D30`). A maintainer-authored spec comment now passes only with a declared maintainer's approving
  reaction after its last edit, as a dev-App one already did (#666), `--no-spec-comment` is refused under a
  map, a config listing the dev App's id among the maintainers is refused, and a maintainer's comment under
  a malformed non-null `dev_app` is unreadable. Repos with `identities: null` are unchanged.

### Fixed

- **`spec-find.sh` refuses a dev App id that is not canonical decimal** (#707). `+2001`, `0x7D1` and `02001` are
  `!!int` to yq and passed the maintainer-list collision check as written; the finder now prints `unreadable`.
- **`architect-review`'s container-mode exempt check reads the file list again** (#698). In v0.19.0 its
  `pulls/<N>/files` filter applied an object projection to each page's array, failed with `expected an
  object but got: array`, and stopped every container-mode review as `needs-human`. Invariants check 20
  now runs the skill's `pulls/<N>/files` filter on a canned page and compares the output; tested by
  `tests/invariants-files-filter.test.sh`.
- **`spec-comment.sh` refuses a maintainer's spec comment when the dev App's id is on the maintainer list** (#689).
  The check ran only for a dev-App author, so a maintainer-authored comment with a dev-App reaction read `ok`; the
  dev App has Issues write and could edit the text, then approve it. A `dev_app` entry that is neither null nor
  well formed (a map with a canonical decimal `id` and a string `login`) is `unreacted` too. No reader reaches this check
  today: every reader runs `spec-find.sh` first, which reads such a config as `unreadable`, a non-canonical spelling
  (`+2001`) included since #707, so it is defence in depth. Tested by new fixtures in
  `tests/spec-comment.test.sh`.

## [0.19.0] — 2026-10-17

**⚠️ Migration** — move every session that reads a repo's cursor to this release together
(#637, `WB-D27`). Under `planning.kind: github_milestones`, `/way-of-working:handoff` no longer
records `description_sha256` in `pointers.plan_anchor`, and a 0.18.0 `plan-anchor.sh verify` reads
an anchor without it as `unreadable`, so a `/way-of-working:resume` still on 0.18.0 (another
machine, another worktree) waits. Anchors written before this release still verify.

**⚠️ Migration** — after this release, a map repo's in-session review posts nothing:
`/way-of-working:architect-review` on a host prints the `wow-review` command and stops, and App-mode
review needs Docker, the host tools (`install-host-tools.ps1`, `wow-review`; optionally
`wow-review-poll`) and the reviewer App's new
permissions (Issues write, Actions read), accepted by each installation. Repos with
`identities: null` are unchanged.

**⚠️ Migration** — on a map repo the readers (`resume`, the `coder` agent, `architect-review`) now
find the spec with `bin/spec-find.sh` (#662, #678, `WB-D30`): a spec comment without the
`spec-task:` marker is no longer used, so post it with `/way-of-working:spec-task`; every spec
comment, a maintainer's included, needs a declared maintainer's approving reaction after its last
edit; and `/way-of-working:handoff` no longer anchors the spec (`plan-anchor.sh verify` takes the
finder's `found` pair as `--spec-comment <id> <updated_at>` instead). Repos with `identities: null`
find the spec as before.

### Added

- **`bin/spec-find.sh`** (#662, #678): finds the one approved spec comment on a task issue and
  prints its id and `updated_at`, or a word that means wait. Called by `resume`, the `coder` agent
  and `architect-review`. Tested by `tests/spec-find.test.sh`; invariants checks 16 and 17 cover it.
- **`/way-of-working:spec-task <N>`** (#611, #659, #661, `WB-D26`, `WB-D29`): drafts a task issue's
  spec comment in a fixed shape (goal, files touched, done when, tests, out of scope, restated from
  the issue body), reading `#N` only for a trusted author and checking every name it cites against a
  pinned commit, then posts or holds it through `bin/spec-post.sh`. As the declared dev App it posts
  with no terminal stop, so it needs Issues write on `backlog.repo`; any other login, or a repo with
  no `identities` map, gets the composed comment held for a human to post. Read the reaction rule in
  `WB-D29` before bumping the pin.
- **`bin/spec-post.sh`** (#661, `WB-D29`): posts `spec-task`'s checked draft as
  one new comment on the issue when the session acts as the declared dev App, with a first-line marker
  naming the issue, base and commit, and otherwise holds the composed comment for a human to post.
  Approval is unchanged: a declared maintainer still reacts on GitHub. Tested by `tests/spec-post.test.sh`;
  invariants check 18 pins its two `gh` lines and keeps any posting form out of the skill's text.
- **`bin/spec-issue.sh`** (#659): `spec-task`'s one fetch of the task issue and its author-trust
  decision, made before any of the issue's text is read; it prints `ok` or a fixed stop word. Tested
  by `tests/spec-issue.test.sh`.
- **`bin/spec-shape.sh`** (#611): checks a drafted spec has its six sections, in order, each with a
  non-empty body; `spec-task` posts or holds only on `ok`. Tested by `tests/spec-shape.test.sh`.
- **`bin/spec-comment.sh`** (#614, #660): the one implementation of the spec comment's checks
  (comment id, `updated_at`, issue, author and, under a map, a declared maintainer's approving
  reaction after its last edit). Its `body` verb prints the comment only after every check passes,
  so unchecked text never reaches a reader's context. `resume`, the `coder` agent and
  `architect-review` print the spec comment only through it (invariants check 17). Tested by
  `tests/spec-comment.test.sh`. **Behaviour change, `identities: null` repos under
  `github_milestones`:** `architect-review` now loads the anchored spec comment only through this
  check (author by `author_association`), and only when the anchor's `task_issue` is the issue this
  PR names and `review_pr`, when set, is this PR.
- **`bin/spec-reaction.sh`** (#613): the one rule for "a declared maintainer reacted after the spec
  comment's last edit", shared by `plan-anchor.sh verify`, `architect-review`, `spec-comment.sh`,
  `spec-find.sh` and the loop's dispatch preflight (invariants check 16). Tested by
  `tests/spec-reaction.test.sh`.
- **`bin/milestone-desc.sh`** (#638, `WB-D28`): a checked writer for one milestone's description,
  from a scratch file, read back after the write (`ok`, `refused` or `mismatch`). Called by
  `plan-sprint`. Tested by `tests/milestone-desc.test.sh`.
- **`bin/blocking-criteria.sh`** (#640): prints only a milestone description's `BLOCKING:` criteria,
  sanitized and capped. Tested by `tests/blocking-criteria.test.sh`.
- **`bin/review-outbox.sh`** (#636, `WB-D24` item 7): the one writer of the review container's
  outbox, and the skills' test for "is this a review container" (`where`; `review-sandbox.sh`
  checks the same marker itself). `outcome`, `body` and
  `findings` apply the launcher's own checks before writing, so a refusal reaches the session
  while it can still fix the text. Tested by `tests/review-outbox.test.sh`.
- **`docs/identity/REVIEW-LIVE-RUN.md`**: the maintainer's one-time live-run checklist.

### Changed

- **The plan anchor no longer hashes the milestone description** (#637, `WB-D27`; see the first
  Migration line). **Behaviour change, every `github_milestones` repo:** `plan-anchor.sh write`
  records the milestone by its number, with no description hash, and `verify` never
  fetches the description and ignores a `description_sha256` an older anchor carries, so a
  build-order edit no longer reads as `drift` or needs a re-anchoring handoff.
- **`/way-of-working:plan-sprint` edits a build order live** (#639, `WB-D28`). **Behaviour change,
  every `github_milestones` repo:** a newly placed issue goes into an existing milestone's numbered
  build order, the anchored milestone included, through `milestone-desc.sh write` after the human
  confirms the full `diff -u`, checked with `plan-depends.sh`'s new `order`, `frame` and `items`
  verbs (`tests/plan-depends.test.sh`). A write that does not go
  through falls back to the staged script, and the triage comment records the old and new order. The
  refusal to edit the anchored milestone's description is gone.
- **Under an `identities` map, `architect-review`'s task spec is the spec comment only, never the
  issue body** (#566, #613, #678): the one comment `spec-find.sh` prints as `found`, loaded only
  after `spec-comment.sh` says `ok` and labelled maintainer- or dev-App-authored,
  maintainer-approved. Any other result loads no spec, and the review says why.
- **The declared dev App may author a spec comment** (#660). `bin/spec-comment.sh` judges the author by
  `gh-identity.sh role`, and `plan-anchor.sh verify` takes `--dev-app-id`. A dev-App spec is used only
  with a declared maintainer's approving reaction created after its last edit (`unreacted` otherwise),
  so an agent can write the spec it obeys but never approve it. Readers that call `spec-comment.sh`
  under an `identities` map (`resume`, the `coder` agent, `architect-review`) fetch the comment's
  reactions before the comment and pass them as its last argument. Check 16 pins `spec-comment.sh`'s
  call to `spec-reaction.sh`.
- **The loop's dispatch preflight accepts a declared dev-App spec comment** (#666) that a declared
  maintainer reacted to after its last edit, through a new optional `--spec-reactions` file judged by
  `bin/spec-reaction.sh`. Check 16 pins its call. The task issue's author stays maintainer-only.
- **`/way-of-working:architect-review` has a container mode** (#636). Inside the review container
  it reviews with no local execution and writes the launcher's outbox; it never posts, files or
  mints a token. On a host or in a dev container under a map it prints the launcher command and
  stops. The in-session App-mode post is gone. The legacy post under `identities: null` is
  unchanged. `review-sandbox.sh make` and `run` refuse wherever the image's root-owned marker file
  exists, before any argument check (#634).
- **`/way-of-working:pr-checks` in the review container** never runs `gh run rerun`, polls or
  reschedules; STALE-RED is reported as the verdict.
- `bin/review-token.sh` is no longer called by any skill; it is kept until a later cleanup.
- `reference/conventions.md`: *Bumping a pinned plugin* gains a step that clears a phantom
  `.claude/settings.json` change left by the marketplace re-add (#570), and *Sign commits* now
  separates host commits from dev-container commits (`WB-D25`).
- **`ship` and `archive-sprint` read a milestone description only through `bin/blocking-criteria.sh`** (#640).
  **Behaviour change, every `github_milestones` repo:** `ship`'s blocking-precondition step, `archive-sprint`'s
  precondition 5 and its close step's display each captured the whole, author-editable description
  into the session. They now write it to a file and print only the `BLOCKING:` criteria, each with
  its item header and continuation lines (the `— gates:` line included), sanitized and capped by
  lines and bytes, and close with a `[read status: N]` line. The close step's `PATCH` prints only
  the state. A new invariants check (19) keeps an unprojected milestone read from coming back. This
  narrows exposure and binds nothing: whoever edits the description still chooses the lines selected.

### Fixed

- **`/way-of-working:pr-checks` counts an app-pinned context posted as a commit status** (#673).
  **Behaviour change, every repo:** a context the branch's rule pins to an app now reads as met when
  the newest commit status for that context, from any poster, was posted by the pinned app at
  `success`, so a status-shaped pinned gate no longer reads NOT READY while a green PR waits for
  approval. A passing check-run no longer meets a pin when the context has a status whose newest
  entry is not the pinned app's `success`; with no status for the context, the check-run rule is
  unchanged. A status carries no app id, so its poster is matched by `creator`: a `Bot` whose login is
  `<slug>[bot]` is the app `GET /apps/<slug>` returns, and a user or any other login never meets a pin.
  The new statuses read needs Commit statuses read on the token; without it `pr-checks` reads COULD NOT
  TELL on a BLOCKED PR wherever a pin exists.

## [0.18.0] — 2026-10-13

**⚠️ Migration required** — one new required `.ai/project.yml` key, `identities`. Answer
`identities: null` to keep the pre-`WB-D24` model; a repo that pins this release reads
`incomplete` (and `/way-of-working:resume` will not auto-start) until it answers. Everything
else is opt-in through that key or the repo's own rulesets, apart from the changes marked "every repo" under *Changed*. This is
the dual-mode release of the identity rollout (`WB-D24`, milestone 17): under `identities: null` the skills keep their
pre-cutover trust model, and a repo that declares a map moves to human code-owner
approval, with agents acting as Apps instead of the maintainer's login. Behaviour changes that
reach **every** repo, cut over or not, are marked there. `/way-of-working:ship` arms auto-merge from the
base's rulesets, not the key, so a repo that has not declared a map but whose base already requires
a code-owner approval will see it armed.

### Added

- **`identities` and an optional `rulesets` list in the project schema** (#378, `WB-D24`).
  `identities` is a nullable map like `orchestration`: `null` means no cutover; a map requires
  `maintainer` (a non-empty list of `{login, id}` pairs) and `dev_app`, `reviewer_app`,
  `loop_app` (each a `{login, id}` pair or `null`). Trust is by the numeric `id`, never the
  login alone. `rulesets` is a non-empty list of every ruleset that applies to `pr_base`
  (repo- or org-level), each with `name`, `source`, `rule_types` and, for an entry carrying `required_status_checks`, an optional `required_checks`; it is
  silent when absent, and the legacy `ruleset.*` keys stay required beside it. `bin/schema-complete.sh`
  checks both down to each element, with fixtures.

  **⚠️ Migration:** add `identities: null` to `.ai/project.yml`. `rulesets` needs no answer.

- **`bin/gh-identity.sh`** (#379) classifies the acting identity (`user`, `app` or `unknown`) and,
  with `author`, answers whether an issue, comment or PR author is `trusted`, `untrusted` or
  `legacy` (`identities: null`). **`bin/token-check.sh`** (#436) verifies a minted token's actor
  and App before use and fails closed; **`bin/app-push.sh`** (#523) is the one pinned App-mode
  push; **`bin/review-token.sh`** requests and discards the reviewer token; **`bin/auto-merge-arm.sh`**
  and **`bin/stall-merge.sh`** decide arming and a stalled auto-merge; **`bin/hitl-gate-closed.sh`**
  (#557) is the single predicate for a closed `hitl_gate`. Each has fixtures.
- **Trust by declared identity** (#382, #383, #495). Under an `identities` map, `resume`'s author
  check, `review-sandbox.sh trust`, `plan-sprint` and the loop's dispatch preflight read
  `identities` instead of `author_association`, and `resume` requires a maintainer's reaction on
  the spec comment before an unattended start. The spec comment is the only body read under a
  map (#561), and `plan-anchor.sh verify` checks its author (#548).
- **`/way-of-working:resume` and `/way-of-working:pr-checks` name the acting identity and reach**
  under an App token (#465, #469, #472), and the SessionStart banner shows the identity and
  `ADMIN MODE` (#504).
- **`/way-of-working:ship` arms auto-merge** (#485, #386) with `gh pr merge --auto --squash
  --match-head-commit` after opening the PR, only where a code-owner approval is required and the
  PR is waiting; it proves the dev App before the first push (#471, #528). `pr-checks` reports an
  approved PR whose auto-merge stalled (#491).
- **The host token broker and dev container** (#373, #426, #509, #519): the App installation-token
  mint script, `wow-admin` and `wow-review-mint` host commands, the scheduled token broker, and
  the claude-workbench dev container. Host tooling, not shipped to adopters' repos.

### Changed

- **`/way-of-working:resume` no longer merges a cursor-sync PR** (#483, #385). **Behaviour change, every
  repo:** the agent-run
  `--admin` merge is gone: resume reports an open sync PR and the human's merge (a code-owner
  approval under a map) is the approval. No other merge in this plugin carries `--admin`.
- **`pr-checks` judges rulesets as a set** and reports a PR *awaiting code-owner approval* instead
  of a generic BLOCKED (#384, #481). **Behaviour change, every repo:** it no longer gives an
  admin-merge verdict, so a green PR under an `update` rule reads COULD NOT TELL until the repo
  cuts over. Merge-approval prose across the skills now reads as code-owner approval (#387, #493).
- **`/way-of-working:architect-review` posts every run through `POST …/pulls/<N>/reviews`
  with `commit_id`** (#502), in place of `gh pr review`. **Behaviour change, every repo:** a
  harness that refuses that `gh api` write now stops the run, and the REST form has not yet posted
  on a gated repo, so an adopter's first run is its live check. Under an `identities` map the post
  is made as `reviewer_app` with a token requested after the sandbox is destroyed (#389, #500),
  after proving the App through `viewer` (#550). **⚠️ Migration:** a repo with a review CI gate that
  declares an `identities` map must make `reviewer_app` a map (a `null` one is a stop); under
  `identities: null` nothing changes but the REST post.
- **The loop's dispatch preflight accepts the code-owner approval rule** (#388, #462).
- **A closed `hitl_gate` is exactly `NONE OPEN — next gate: <prose>`** (#557, #563): the value is
  one line with no `;`, and `<prose>` is non-empty printable ASCII that never contains "open" in any
  case. `resume`, `unpark-sprint`, `plan-sprint` and `handoff` read it through
  `hitl-gate-closed.sh`; `handoff` and `archive-sprint` write that form.
  **Behaviour change, every repo:** a cursor in another shape now waits until a handoff rewrites it.
- **A null `backlog.repo` reads as the repo itself** in the skills that did not already (#533).

### Fixed

- **`parked_from_commit` is validated on unpark** (#554), and a parked or done cursor's open gate
  is carried through `unpark-sprint` (#535, #559).
- **`resume` verifies the plan anchor on a waiting resume** (#507), binds ruleset names as values
  and constrains their shape (#525), and has its HITL Gate wording fixed (#556).
- **`coupling-check.sh` catches hardcoded App logins** (#552); the schema checker requires
  `required_checks` to be a list and validates every `identities` and `rulesets` entry
  (#526, #532).
- **Pin-bump prose points at one procedure** in `conventions.md` and names `/reload-plugins`
  (#511, #537, #544).

## [0.17.0] — 2026-10-06

**⚠️ Migration required** — one new required `.ai/project.yml` key, `orchestration` (see the
first *Added* entry for the exact answer). This is the first release of the sprint-orchestrator
work (milestone 9): the loop's schema keys, its identity guard, and a no-op handoff with a
review step `/way-of-working:resume` derives from GitHub. Two behaviour changes to expect: a
no-op handoff now ends by switching the checkout to `{pr_base}`, and `/way-of-working:resume`
will not auto-start while an orchestrator driver holds its lock.

### Added

- **`orchestration.*` schema keys for the sprint-orchestrator loop** (#234, plan v9 § 8.4, § 8.5,
  § 8.13d). `.ai/project.yml` gains `orchestration`, a nullable map like `review.ci_gate`:
  `null` means the loop never dispatches into this repo; a map requires `critics` (the
  allowlist of critics the loop may spawn) and `human_only_paths` (path prefixes a loop task may
  never touch), both non-empty lists; `round_cap` (a bare decimal positive integer, at most three
  digits); `restrict_updates` (the name of the separate ruleset that restricts updates of
  `pr_base` to the admin bypass actor); and `loop_identity` (a login or an App's `<slug>[bot]`;
  `null` until one is declared, which a dispatch will refuse). `bin/schema-complete.sh` checks
  all of it, with fixtures, and `/way-of-working:resume`'s schema interview asks it with no
  suggested answers. The block is required of every adopting repo, not only one the loop
  dispatches into: absent stays an unanswered question (`WB-D17`). No skill reads these keys yet
  (but see the `loop_identity` entries below, #235 and #295); the driver that will is not built.

  **⚠️ Migration:** `orchestration` is a new required key. A repo that pins this release reads
  `incomplete` (and `/way-of-working:resume` will not auto-start) until it answers it:
  `orchestration: null` if the loop will never dispatch into it.

- **The loop identity is untrusted by name** (#235, plan v9 § 8.1, § 8.13d).
  `bin/plan-anchor.sh verify` takes `--loop-identity <login>` and prints a new `untrusted`
  verdict, before any drift comparison, when the milestone's creator, the task issue's author or
  the anchored spec comment's author equals it (case-insensitive, a trailing `[bot]` ignored on both sides; the last two in full mode
  only); a failed or empty author read is `unreadable`. `bin/review-sandbox.sh trust` reads
  `orchestration.loop_identity` from the default branch's copy of `.ai/project.yml` and refuses
  that author before any association check: its output line gains `loop=0|1` before `trusted=`,
  and it now needs `yq` on `PATH` (a STOP without it, like an unreadable copy). `/way-of-working:resume`
  waits on `untrusted`; `/way-of-working:handoff` and `/way-of-working:archive-sprint` treat it as
  a refusal (a gate and a staged close, never a re-anchor or a close). A `loop_identity` left stale
  after the loop's login changes protects nothing against the new login; the driver's preflight
  owns that check.

- **`/way-of-working:resume` derives no review step when it runs as the loop identity** (#295,
  `WB-D22`). `bin/review-step.sh decide` takes two more required keys, `login` (the running
  login) and `loop_identity` (`orchestration.loop_identity` from the default branch's copy, `-`
  when `null`), and prints `none` ahead of every other verdict when they are equal (case-folded,
  one trailing `[bot]` ignored on both sides, as `plan-anchor.sh` does). A non-null value outside
  the schema's shape (judged case-insensitively) exits 2. The resume skill reads it with the gate's discipline: an absent
  `orchestration` or `loop_identity` is a failed read, never `null`. **A caller of `decide`
  outside this plugin must pass both keys, or it exits 2.**

- **`/way-of-working:resume` won't auto-start while an orchestrator driver holds its lock**
  (#233, sprint-orchestrator plan § 7.5). New `bin/driver-lock.sh` (no arguments) prints
  `present`, `absent` or `unreadable`; resume waits on anything but `absent` — an unreadable
  location or lock reads as present — and names it in the pick-up summary. The driver
  directory is host config, never an `.ai/project.yml` key: `$WOW_DRIVER_DIR` when set, else
  an absolute `$XDG_CONFIG_HOME` or else `$HOME/.config`, plus `/way-of-working/driver`; lock = the entry `lock` in it. Absolute paths only. A
  declared directory that is missing reads `unreadable`; a default one that does not exist
  reads `absent` (no driver on this host) unless something above it is a file or cannot be
  searched, which reads `unreadable`. The lock is host-wide for now. No schema change.

- **`/way-of-working:plan-sprint` records a per-issue `depends_on` marker** (#232).
  The recommendation table proposes it, the human confirms it like the build-order slot, and
  a NEW milestone's drafted **Build order:** list carries it as a last-on-the-line
  ` [depends_on: none]` / ` [depends_on: #N, #M]` token. New `bin/plan-depends.sh read
  <description-file> <N>` reads it back (`independent`, `after <N>…`, or `all-earlier
  <reason>`) and reads anything it cannot confirm — no token, a malformed or repeated one, a
  dependency on a later or unlisted item, a damaged list — as `all-earlier` (the item waits for every
  earlier one). A placement into an existing milestone never rewrites its description, so
  those issues read `all-earlier` (`not-listed`, or `unreadable` when the description has no well-formed list). No `.ai/project.yml` key changes.

- **A no-op handoff, and a review step resume derives from GitHub** (#230, `WB-D22`). A work PR
  was usually followed by a docs-only cursor-sync PR whose only news was "review or merge PR
  N next". Under `planning.kind: github_milestones`, when that is the only cursor change,
  `/way-of-working:handoff` now writes `.ai/state.json` (with `pointers.review_pr:
  {number, head_oid}`, a `review PR #M — task #N — …` or `merge PR #M — task #N — …`
  `next_action`, and the architect assignment when `review.ci_gate` is set), puts the critic
  record in the work PR's `## Critic pass` section, and opens no ledger PR.
  `/way-of-working:resume` derives the step from GitHub only — an open same-repo PR authored by
  the running login that names the anchored task — and auto-starts
  `/way-of-working:architect-review <M> --pin <oid>` only when `state.json` exists and names the
  same PR and head, the token check passes, HEAD is the pin with a
  clean tree, (as first built; #283 moved this to the synced base), `assigned_model` is the default branch's `models.architect`, and the session is
  fresh; otherwise it shows the step and waits. A fresh machine with no `state.json` shows it
  and waits for one "go". Loop PRs, authored by the App, never match. New:
  `bin/review-step.sh` (derive and decide), `bin/critic-section.sh` (replace or read back the
  PR-body section), each with fixtures. **Behaviour change:** `WB-D20`'s display property
  does not hold for a review-step `next_action`, which never reaches `main`. No
  `.ai/project.yml` key changes; `pointers.review_pr` is a `state.json` field, nulled by every
  other writer that sets pointers (`archive-sprint`, `park-sprint`, `unpark-sprint`, and any other handoff).
  `derive` takes the `--limit` it was fed and refuses a list that may be truncated; a green gate
  on a head the pin does not name reads `head-moved`, not `reviewed`; `critic-section.sh` follows
  CommonMark fences, and its `put` (not `get`) refuses a body that ends inside an open one. Known
  residuals are listed in `WB-D22`'s *Build* bullet.
- **`/way-of-working:architect-review --pin <sha>`**: stops if the head it pins differs, if the
  gate already reads `success` on the pin, if the head moved before the post, or if the poll
  sees another head; counts `success` only on the pin; and ends without the `handoff` pointer.
  On a pinned run it now posts through `POST …/pulls/<N>/reviews` with `commit_id=<pin>` and
  `event=COMMENT`, so the review attaches to the pin even if a push lands after the pre-post
  re-read (not verified live: no gate in this repo).
  **This release carries both** this and #283 (see *Changed*), so the pair is safe to take
  together. Neither is safe alone: the pin-only form starts the pinned review session on the PR's
  own tree, where that PR's project settings (hooks, permissions, env), `.mcp.json` and
  `CLAUDE.md` are active in the reviewer's session. Do not pin a commit between them.
  The `commit_id` post is likely to be refused by the harness on org repos on a host that blocks
  `gh api` writes; that is a stop, never a fallback.

### Fixed

- **`/way-of-working:archive-sprint` precondition 3 no longer fails at every close** (#209).
  `/way-of-working:handoff` refuses to write `done` before the sprint's roadmap entry is on
  `origin/{pr_base}`, and says the entry belongs in the sprint's last work PR.
- **`/way-of-working:plan-sprint` no longer offers "continue uncommitted" when `handoff` is not
  next** (#220). A ledger left modified blocked `archive-sprint`'s branch cuts; it now opens the
  cursor-sync PR unless the cursor's `next_action` is or begins with `/way-of-working:handoff`.
- **`/way-of-working:archive-sprint` checks that `.ai/archive/` is git-ignored before it
  snapshots** (#219). The Snapshot step assumed it; a repo whose `.gitignore` never listed it saw
  the snapshot as untracked, and `/way-of-working:resume` would read the tree as dirty. The step now
  stops before writing, with a one-line fix. Adopters: list `.ai/archive/` in `.gitignore`
  before your next sprint close.

### Changed

- **The pinned review session starts from the base branch, not the PR's tree** (#283, `WB-D22`).
  The no-op handoff now ends with `git switch {pr_base} && git pull --ff-only origin {pr_base}`
  (the pin travels in the git-ignored `.ai/state.json`), so **a no-op handoff now changes the
  checkout**. Resume's review-step auto-start requires the base, synced to `origin/{pr_base}` and
  clean, instead of HEAD at the pin; `review-step.sh decide` takes four new keys (`branch`, `base`,
  `base_head`, `last_commit`) and prints the new reason `last-commit`. The review shape's drift
  rule is `last_commit` equal to the pin, in place of `cursor-drift.sh`, which reads `drift` on the
  base. `architect-review` rewrites the local cursor's `next_action` once its post succeeds, so a later
  resume on the base never starts a second review. Residuals are listed in `WB-D22`.

- **The branch prune now deletes a merged branch whose local tip is *behind* the merged head**
  (#271). `/way-of-working:resume` and `/way-of-working:archive-sprint` deleted a branch only
  when its local tip equalled the `headRefOid` GitHub merged, so a branch whose PR picked up
  more commits after the local copy stopped (pushed from another checkout, edited on
  GitHub) was skipped and re-reported as possible stranded work every session, though every
  local commit was in what merged. The tip test is now `bin/prune-verdict.sh <branch> <oid>`:
  `delete` when the tip is the merged commit or an ancestor of it (it fetches the oid by
  SHA when not already local, bounded and without prompting; that does not need the remote
  branch to exist), `skip-ahead` when the tip has a commit the merged head lacks (the real
  stranded-work case, still reported), `skip-unfetchable` when the oid cannot be fetched,
  `unreadable` on bad input. The oid is validated as full lowercase hex before it reaches
  `git fetch`. No `.ai/project.yml` key changes.

- **`/way-of-working:pr-checks` no longer reads a rule it cannot see as absent** (#248).
  `bin/blocked-state.sh` was fed rule type names only, so a green `BLOCKED` PR under a
  `pull_request` rule demanding thread resolution or required reviewers, or under
  `required_deployments`, `code_scanning`, `required_signatures`, a merge queue, or a status
  check pinned to an app (`integration_id`), still read `admin-merge-ready` (or `lag`). Its
  stdin is now one line per rule: the type plus `key=value` words for `pull_request` and
  `required_status_checks`, which the skill builds with `gh`'s embedded jq. When such a rule
  applies to a green `BLOCKED` PR the script exits 2, naming the rules on stderr, and
  pr-checks reports COULD NOT TELL naming them instead of its generic caveat; a bare
  `pull_request` or `required_status_checks` line (parameters dropped) is the same refusal;
  a repeated key or a wrong-type key is a malformed line, refused in any state. `not-blocked` and `blocked` are unchanged.
  **Behaviour change:** on a repo whose `pull_request` rule requires an approval, required
  reviewers, thread resolution or code-owner review, a green `BLOCKED` PR now reads COULD NOT TELL, never READY (admin
  merge). No `.ai/project.yml` key changes. **Known limit:** other rule types (`workflows`,
  commit-message patterns) and parameters the projection omits are still ignored, and
  bypass actors are not read — `current_user_can_bypass` is `never` to a non-admin viewer.

- **`/way-of-working:resume`'s `BLOCKED` cursor-sync offer now sees a required check that
  never reported** (#245). `bin/cursor-sync-pr.sh` took a rollup of all-green present checks
  as enough, so a required check absent from it (a workflow `paths:` filter excluding
  `.ai/`, a job not yet registered) could not refuse the PR. It now takes
  `{ruleset.required_checks}` as an optional third argument, comma-separated, and offers a
  `BLOCKED` PR only if every listed name is a green entry (CheckRun `name` or StatusContext
  `context`, matched whole and case-sensitively). An empty or missing list refuses; a `CLEAN`
  PR is unaffected. resume passes the list from `.ai/project.yml`. No key changes. **Known
  limit:** it checks the list in `.ai/project.yml`, not the contexts the ruleset currently
  carries.

- **`/way-of-working:resume` no longer offers an `--admin` cursor-sync merge the active
  `gh` identity cannot perform** (#250). `--admin` only gets past `gh`'s client-side
  refusal; the server applies the ruleset bypass per account, so a session whose `gh` was
  active as a non-bypass account was shown the offer, took the confirmation, and had the
  merge refused. For a `BLOCKED` PR, `bin/cursor-sync-pr.sh` now reads each ruleset carrying
  an `update` rule on the base and its `current_user_can_bypass`: `never` prints
  `refuse <N> bypass-never` (resume names the identity and points to the web UI or a
  bypass-capable account), a `BLOCKED` PR with no `update` rule is `refuse <N>
  state-blocked`, and a failed read or unknown value is `unreadable`. `/way-of-working:pr-checks`'
  READY (admin merge) verdict now names the identity and its `current_user_can_bypass`
  instead of "if you hold the bypass". No `.ai/project.yml` key changes.

## [0.16.0] — 2026-10-05

**No migration required.** No `.ai/project.yml` key was added, removed, or renamed. This
release makes the plugin work under a restrict-updates ruleset (an `update` rule whose only
bypass actor is the repository admin role), where every green PR reads `BLOCKED`. Two
behaviour changes to expect: `/way-of-working:resume` may now merge a cursor-sync PR with
`--admin` (still only on your confirmation), and `/way-of-working:pr-checks` now calls the
rules API for a `BLOCKED` PR and can give the new verdict **READY (admin merge)**.

### Changed

- **`/way-of-working:resume`'s cursor-sync merge works under a restrict-updates ruleset**
  (#229). With the repository admin role as the ruleset's only bypass actor, GitHub reports
  `mergeStateStatus: BLOCKED` to the admin on a green PR, so `bin/cursor-sync-pr.sh` — which
  offered only `CLEAN` — refused every sync PR as `state-blocked`. It now also offers a
  `BLOCKED` PR when every present check is green (non-empty rollup;
  `SUCCESS`/`NEUTRAL`/`SKIPPED`) and `reviewDecision` is not
  `REVIEW_REQUIRED`/`CHANGES_REQUESTED`; a red, pending or empty check set stays refused.
  **Known limit:** a required check that never reported is absent from the rollup, so it
  cannot refuse the PR — it matters only where the admin's bypass also covers required
  checks (the script header lists this and the other residuals). The merge command now
  carries `--admin`, since `gh` refuses the plain merge client-side in that state; the prose
  that forbade `--admin` says why this one merge carries it and that no other merge in the
  plugin does.
  `--match-head-commit`, the human's confirmation, and the no `--delete-branch` / `--auto`
  rules are unchanged.
- **`/way-of-working:pr-checks` no longer tells you to wait on a PR the restrict-updates
  ruleset is blocking** (#224). It read `BLOCKED` with nothing red or pending as GitHub
  re-evaluation lag, but under an `update` rule (measured with the repository admin role as
  its only bypass actor) every green PR reads `BLOCKED` to every viewer for good, so it
  could never again return a merge-ready verdict. A new tested
  predicate, `bin/blocked-state.sh`, reads the PR's own base branch's rule types: every
  required check green (over `{ruleset.required_checks}` and the contexts the branch's own
  rule names), a non-blocking review and an `update` rule is the new verdict **READY (admin
  merge)**, which names `gh pr merge <N> --repo <repo> --squash --admin --match-head-commit <headRefOid>` as
  advice and still never runs it; no `update` rule keeps the lag reading. It never says
  "bypass the checks" — where the admin cannot bypass the ruleset holding them, `--admin`
  still enforces required checks — and a failed rules call, or any answer other than one
  of the three words it can give on a `BLOCKED` PR, is "could not tell", never ready. **Known limit:** it cannot see a
  rule nobody passes it (unresolved conversations, required deployments, code scanning,
  merge queue), and the admin's bypass would skip those too.

### Fixed

- **The `SessionStart` cursor-banner hook is now stored executable** (#214).
  `hooks/ai-cursor-banner.sh` was mode `100644` at every tag from `v0.1.0` through `v0.15.0`,
  and `hooks/hooks.json` runs it directly, so an install that takes the git mode left the hook
  unable to execute. It failed silently — "the hook didn't run" reads exactly like "nothing
  to report" — so the banner never appeared. `scripts/invariants-check.sh` check 9 now fails
  the gate if any `hooks/*.sh` or `bin/*.sh` is not `100755` in the index, and fails closed on
  a `git` error or an unlisted script. **Not cured:** a copy that drops mode bits (`cp`
  without `-p`, a zip extract); running the hook through `bash` would be, and was not done.

## [0.15.0] — 2026-10-02

**No migration required.** No `.ai/project.yml` key was added, removed, or renamed. One
behaviour change to expect: `/way-of-working:resume` now calls `gh pr list` at session start,
and **auto-start waits** whenever a handoff cursor-sync PR is still open, HEAD is on a
`docs/sync-cursor-*` branch no merged PR carries, or that check could not run (`gh` missing or
unauthenticated). A repo that habitually leaves cursor-sync PRs open will see `/resume` stop
for a "go" until they are merged — which `/resume` now offers to do.

### Added

- **`/way-of-working:resume` offers to merge a forgotten handoff cursor-sync PR** (#215, PR
  #216, `WB-D20`). A new step before *Read the cursor* runs `bin/cursor-sync-pr.sh`; when
  exactly one PR qualifies — same repository, changes only `.ai/next-steps.md`, `CLEAN`, and
  a local branch on this machine sits at exactly its head commit — it shows the PR's
  **Next:** paragraph and **HITL Gate** line beside the local `next_action` and `hitl_gate`
  auto-start would run, and merges with `gh pr merge --squash --match-head-commit` only on the
  human's explicit confirmation. Never on a headless host. Handoff itself still never merges,
  and its `docs/sync-cursor-` branch prefix is now required rather than an example.
  Rejected alternative, recorded in `WB-D20`: letting handoff merge its own PR when the commits
  are signed.

### Changed

- **Auto-start has a new fail-closed condition**: the cursor-sync check found nothing open
  and no unmerged sync branch under HEAD, or its offered merge succeeded. This narrows a gap
  that already existed — a session left on an unmerged sync branch could auto-start a
  `next_action` nobody had approved. The residuals that remain are listed in `WB-D20`.

## [0.14.0] — 2026-09-29

**No migration required.** No `.ai/project.yml` key was added, removed, or renamed. One
tooling note: `bin/schema-complete.sh` now needs a `yq` that supports `to_json(0)`,
`to_string`, `//` and `select` (verified on v4.53.6; older v4 releases are untested). On a
`yq` that cannot parse it, `/way-of-working:resume` reports the schema `unreadable` and stops
before reading the cursor — upgrade `yq`.

### Changed

- **`/way-of-working:plan-sprint` leads with a recommended placement** — instead of a neutral
  menu, it proposes a recommended milestone, build order, and the cited evidence for each
  unmilestoned issue, which the human accepts as a table or overrides one at a time. It now
  reads every unmilestoned issue's title **and body** and every open milestone's description
  up front (recorded in the `planning` trust boundary, `project-schema.md`), and sends a new
  milestone's `due_on` as midday UTC (`T12:00:00Z`) — a midnight-UTC value has been observed
  to store the previous calendar date. New decision `WB-D19` (#197, PR #198).
- **`/way-of-working:architect-review` handles a trusted PR that changes dependency manifests
  or lockfiles differently** — any reproduction that installs or fetches dependencies would
  execute the new registry code locally, so every such claim now comes from the CI witness
  read instead, and a claim CI cannot witness is marked *not witnessed* rather than falling
  back to `review-sandbox.sh run`. The posted review body has a third shape, *trusted with a
  dependency change*, and a Dependabot PR is expected to be classed untrusted
  (`assoc=CONTRIBUTOR`/`NONE`). See `WB-D13`'s amendment (#158, PR #194).

### Fixed

- **`bin/schema-complete.sh` reads each key table in one `yq` call** instead of one per key;
  its fixture suite went from about 2m15s to about 15s on Git Bash. The batching closed two
  exploits found in review — a percent-encoded YAML tag could forge a row, and a
  multi-document file read `complete` — both now covered by fixtures (#189, PR #204). Stricter
  outcomes follow: a trailing empty `---` document or a sequence root
  now reads `unreadable`, and an enum value such as `"opus\n"` now reads `invalid`.
- **`bin/` scripts are executable** (`plan-anchor.sh`, `review-base-anchor.sh`,
  `review-sandbox.sh`: mode `100644` → `100755`), and `review-sandbox.sh`'s header now records
  that the container option (#158) is deferred rather than scheduled (PR #194).

## [0.13.0] — 2026-09-26

**⚠️ Migration:** every key `reference/project-schema.md` documents must now be **present**
in `.ai/project.yml` (#142, `WB-D17`). No key was added, removed, or renamed, but an absent
key is no longer silently defaulted. It is an unanswered question, and
`/way-of-working:resume` stops auto-starting until it is answered. Expect a repo last
pinned before this release to read `incomplete`. The keys most often absent are the ones
earlier releases documented as optional: `migration_base`, `planning.kind`,
`models.second_opinion`, `backlog.repo`, and `review.ci_gate.triggers_on` when
`review.ci_gate` is set. **Fix:** after bumping, run `/way-of-working:resume`. It interviews
for each missing key and opens a completion PR with your answers; merge it and resume again.
Two things it will not do for you:
- An `invalid` finding (a key that is present but malformed, e.g. `roadmap: null` where a
  path is required) is reported, never rewritten. Fix those by hand.
- A headless session cannot run the interview. Resume once attended, or add the keys by
  hand from `project-schema.md`'s Full schema block.

`yq` (mikefarah v4) is now a hard dependency of `/way-of-working:resume` itself, not only of
auto-start. (This line was missing from the notes as first published; corrected after the
release.)

### Changed

- **Every `.ai/project.yml` key is required-present** — `null` stays the explicit no-value
  where a key's own reference allows it; absent means unanswered, everywhere. New
  `bin/schema-complete.sh` (`check <file>` → `complete | incomplete | unreadable`, `keys`
  lists the required paths). `/way-of-working:resume` gains a first step, *Ensure the schema
  is complete*, that interviews for each missing key (pick-list where the kind fits, no
  suggested defaults) and lands the answers as a pull request rather than a working-tree
  value. The two `migration_base` readers now tell a key absent from the default branch's
  copy apart from one declared `null`. `scripts/invariants-check.sh` checks the script's key
  set against both schema example blocks. This reverses #127's documented defaults. New
  decision `WB-D17`. Critic gate: `architect` + `security-critic` + `docs-consistency`, 5
  rounds (the round cap), converged (#142, PR #185).

### Added

- **`/way-of-working:plan-sprint` skill** — owns the planning pass between
  `/way-of-working:archive-sprint` and `/way-of-working:handoff` under
  `planning.kind: github_milestones`: gather unmilestoned issues and open milestones
  (`bin/plan-gather.sh`, a tested read-only script — `unmilestoned`, `milestones`, `titles`,
  `milestone-issues`), propose placement and build-order one issue at a time, apply only
  what the human confirms via `gh issue edit --milestone`, stage the milestone writes the
  session can't make as a script plus proposed text for the human to run, post a dated
  triage comment per issue, and sync the cursor. Never derives *which* milestone is the live
  sprint from a title or ordering — that stays the milestone **number**, per the existing
  rule; `due_on` now orders the github.com milestone list page (undated sorts last),
  read by no other skill. New decision `WB-D18`. Critic gate: `architect` +
  `security-critic` + `docs-consistency`, 5 rounds (the round cap), converged — plus three
  independent adversarial architect reviews of the plan itself before any code was written
  (#152, PR #187).

## [0.12.0] — 2026-09-25

**No migration required.** No `.ai/project.yml` key was added, removed, or renamed.

### Added

- **`zizmor` job in `ci.yml`** — a GitHub Actions workflow security linter, modeled on
  `bounty-infra`'s own but resolved and verified independently
  (`zizmorcore/zizmor-action@cc914d7f3750a2d13d75c7f184a1060aa0e9d482` # v0.6.4). Runs
  twice: a real gate (`advanced-security: false, annotations: true`, confirmed live to
  exit non-zero on a finding) plus an `if: !cancelled()` SARIF upload to the Security tab
  — a single default-mode run, as first drafted here and as `bounty-infra`'s own job does,
  always exits 0 regardless of findings and could never actually fail; caught live during
  this diff's own critic-gate pass. `security-events: write` stays job-scoped, not yet in
  `ruleset.required_checks`. New decision `WB-D15`, which also files
  `bedrock-serverless-rag#134` asking a human to enable CodeQL default setup there — the
  toggle itself is a repo/org setting this harness cannot flip. Critic gate: `architect` +
  `security-critic` + `docs-consistency`, 3 rounds, converged (#45, PR #176).
- **`/way-of-working:critic-gate`'s hard cap raised from 2 to 4 fix-and-re-run rounds;
  critic selection now goes through a structured pick-list** (e.g. `AskUserQuestion`)
  wherever the host can present one, never a free-text reply, in both the initial
  proposal and the second-opinion offer. Requested directly by the maintainer — not a fix
  for an observed failure of 2; an invented technical rationale for the raise didn't
  survive its own critic-gate pass and was removed rather than kept. New decision
  `WB-D16`. Critic gate: `architect`, 3 rounds, converged (#177, PR #178).

## [0.11.0] — 2026-09-25

**No migration required.** No `.ai/project.yml` key was added, removed, or renamed. One
behavioral change a reviewer will notice: `/way-of-working:architect-review` no longer runs
an untrusted-author PR's code locally at all — a required-check witness stands in — and runs
a trusted one only inside the new `bin/review-sandbox.sh`, never a `git worktree add`.

### Added

- **`bin/review-base-anchor.sh`** — `/way-of-working:architect-review`'s PR-base
  resolution chain (anchor the repo and default branch, take the base from GitHub, check it
  against `migration_base`, sync on full refnames), extracted from inline SKILL.md prose into
  a tested script with `tests/review-base-anchor.test.sh`. The extraction also closed a
  local branch ahead of origin passing `--ff-only` as a silent no-op, a `.ai/project.yml`
  read resolved against the current directory instead of the repo root, an untested
  `check-ref-format` guard (a `-Cmain` base reaching `git switch` parses as `-C main`), and a
  human override replayable against another PR — now scoped to the exact `repo#N:base`.
  Critic gate: `architect` + `security-critic`, 3 rounds, converged (#126, PR #156).
- **`/way-of-working:resume` verifies the default branch's own protection while a migration
  is live.** `architect-review` accepts a non-default base only because the default branch's
  `.ai/project.yml` names it as `migration_base`, which is sound only if that branch cannot
  be pushed to directly. Triggered by `migration_base` read from the default branch's
  committed copy (never by `{pr_base}` drift, which misses a session resuming on the default
  branch), with repo and branch derived from `origin` rather than the local, untrusted copy.
  Critic gate: `architect` + `security-critic`, 3 rounds, converged (#125, PR #163).
- **`bin/milestone-close-line.sh`** — `archive-sprint`'s milestone-close outcome now always
  reaches a fixed `**Milestone close:**` line in `.ai/next-steps.md`, carried by whichever
  of `archive-sprint`, `park-sprint`, `handoff`, or `unpark-sprint` last wrote the ledger;
  `resume` echoes a recorded outcome and flags a missing one. Critic gate: `architect` +
  `docs-consistency`, 3 rounds, converged (#153, PR #167).

### Fixed

- **`/way-of-working:architect-review`'s *Review by execution* step ran the PR's code with
  the reviewer's credentials in a worktree sharing the main checkout's `.git`**, where it
  could rewrite `.ai/project.yml` or `origin` before the posting step re-read them. Replaced
  by `bin/review-sandbox.sh` (`trust`/`make`/`run`/`destroy`): a fresh `git init` with an
  empty template and a single-ref fetch, a stripped `env -i`, and no local execution for an
  untrusted PR. Stated as **accident containment, not isolation** from a deliberately hostile
  trusted author; a full container is tracked as #158. New decision `WB-D13`. Critic gate:
  `architect` + `security-critic` + `docs-consistency`, 6 rounds, converged; suite verified
  on both Git Bash and WSL Ubuntu/dash (#113, PR #160).
- **`archive-sprint` precondition 3's roadmap fix had no branch procedure**, and at Sprint
  2's close landed on an already squash-merged branch. It now checks `origin/{pr_base}`,
  cuts a fresh branch with the *Compact the deep record* step's chain, and ships the fix as
  its own PR, the precondition staying unmet until it merges. Critic gate: `architect` +
  `docs-consistency`, 3 rounds, converged (#150, PR #165).

## [0.10.0] — 2026-09-24

**⚠️ Migration:** `migration_base` is the only `.ai/project.yml` key this release adds,
removes, or renames, and it matters only for a repo currently mid-migration under the *old*,
undeclared behavior — where only the integration branch's own `pr_base` named the migration,
with no declaration on the default branch. Such a repo will now see
`/way-of-working:architect-review` stop on PRs to that integration branch. **Fix:** merge
`migration_base: <integration branch>` into the *default* branch's `.ai/project.yml`.
`planning.kind` and `models.second_opinion` (also new since `0.9.0`) are both optional and
additive — absent means today's behavior for each, so neither needs a change.

### Added

- **`planning.kind: github_milestones`.** Sprint planning can now live in a GitHub
  milestone's description plus a task issue's body and an approved spec comment, instead of
  a git-tracked `sprint_plan.md`. Adds `bin/plan-anchor.sh`, the deterministic write/verify
  predicate over a `plan_anchor` cursor field that binds the milestone description, the task
  issue, and its spec comment against tampering, mirroring `cursor-drift.sh`'s contract.
  Wires `resume`, `handoff`, and the remaining touchpoints to branch on `{planning.kind}`
  while `files` behavior is unchanged. Critic gate: `architect` + `security-critic` +
  `docs-consistency`, 3 rounds, converged (#86, PR #135).
- **`archive-sprint` now closes a sprint's GitHub milestone** under
  `planning.kind: github_milestones` — gated on 0 open true issues (PRs excluded) and a
  `plan-anchor.sh verify --plan` match on a known-usable anchor. Stages the close for the
  human instead of running it on drift, an unreadable anchor, a harness refusal, or an
  unconfirmed read-back, and reports an already-closed milestone or a blocked open issue
  distinctly rather than silently. Critic gate: 3 rounds, converged (#128, PR #137).
- **`models.second_opinion`** — an optional, human-authorized, spawn-time override on the
  Agent tool's `model` parameter for one late `/way-of-working:critic-gate` round on a
  different model, so a diff gets fresh eyes from a model that did not already accept it.
  Provenance is verified from harness-written transcript evidence (never the subagent's own
  report text) via a new `bin/spawn-model.sh`, fail-closed to `unconfirmed`/`mismatch` on
  anything it cannot verify. Critic gate: 2 rounds, converged (#72, PR #139).

### Fixed

- **`/way-of-working:architect-review`'s long-migration fallback trusted a non-default
  `pr_base`** gated only by ruleset criteria a PR author could write, from the same
  `.ai/project.yml` a PR author controls. The base now comes from the PR on GitHub and is
  accepted only if it is the default branch, or the default branch's own `.ai/project.yml`
  names it as the new key `migration_base` above. Refs are spelled in full, closing a
  shadowing bug where a pushed tag named `origin/<branch>` won over the real branch
  (reproduced); the base name passes `check-ref-format` before reaching git; a failed chain
  stops and prints the values a human override needs, and an unattended run stops rather
  than guessing. Critic gate: `security-critic` + `architect` + `docs-consistency`, an
  initial pass plus 3 fix rounds (round 3 human-authorized past the 2-round cap), converged
  (#112, #114, PR #123).
- **66 "step N" cross-references across the plugin — silently broken by any later
  renumbering — now cite the step's own bolded name instead.** `invariants-check.sh` gains a
  guard against the form coming back, verified by a deliberate regression. A fix round
  closed gaps the critic gate found: the guard missed plural/hyphenated forms ("steps 3 and
  4", "step-5"), leaving one live reference uncaught, plus a misattributed citation and a
  grammar slip (#61, PR #131).
- **`.ai/project.yml` never declared `planning.kind` explicitly**, though this repo's own
  cursor had pointed at GitHub milestones since #86/#135 shipped — it defaulted to `files`,
  contradicting what the cursor already did. Declares the key and drops the now-stale "no
  sprint cadence" comment that predated the milestone adoption (PR #141).
- **The absent-is-unreadable rule contradicted three keys that already document their own
  absent-means-X meaning** (`backlog.repo`, `review.ci_gate.triggers_on`, `migration_base`) —
  qualifies the general rule with the exception (#127, PR #133).

## [0.9.0] — 2026-09-23

**No migration required.** No `.ai/project.yml` key was added, removed, or renamed by any
of the four fixes below. One behavioral edge, the same shape `v0.7.0` named: an absent key
is not a `null` key, so a skill that newly reads one reports it as unreadable where it
previously said nothing. `/way-of-working:architect-review` now also reads
`{ruleset.rule_types}` (previously only `{ruleset.name}`/`{ruleset.required_checks}`) — the
key already exists in the schema and in every `.ai/project.yml` that sets `ruleset` at all,
so this reads as "no migration required" the same way `0.8.0`'s `.ai/parked/` addition did.

### Fixed

- **`/way-of-working:architect-review` now syncs onto `{pr_base}` unconditionally before its
  first read**, rather than trusting whatever branch the session happened to be on. Critic
  gate: `architect` + `docs-consistency`, 3 rounds, converged (#97, PR #110).
- **`/way-of-working:architect-review`'s `{pr_base}` check was self-consistency, not an
  independent anchor** — a checkout on a branch whose own `.ai/project.yml` named itself as
  `pr_base` (and named a `repo` it controlled) satisfied every later check. Both `{repo}` and
  `{pr_base}` are now anchored to `gh repo view` against the checkout's own git remote, with
  a ruleset-based fallback for the schema's long-migration case. Also fixes an independent
  bug in `/way-of-working:resume` step 4's ruleset-name lookup found along the way. Critic
  gate: `architect` + `docs-consistency` + `security-critic`, 4 rounds (human-authorized past
  the 2-round cap), converged (#98, PR #115).
- **`/way-of-working:pr-checks` said `missing` where `review-gate-state.sh` says `absent`
  for the same fact.** Now `absent` everywhere. Critic gate: `architect` +
  `docs-consistency`, 2 rounds, converged (#100, PR #116).
- **Four low tightenings in `/way-of-working:architect-review` (steps 3/4/8).** Critic gate:
  `architect` + `docs-consistency`, 3 rounds, converged — round 1 caught a real, live-
  verified bug in the fix itself: the new step-8 polling loop broke on
  `review-gate-state.sh`'s exit code (always `0` for all four words) rather than its printed
  word, so it never actually polled; fixed to test the captured word instead (#99, PR #117).

## [0.8.0] — 2026-09-23

**No migration required.** No `.ai/project.yml` key was added, removed, or renamed. One
new directory, `.ai/parked/`, is **tracked** — a consuming repo whose `.gitignore` swallows
all of `.ai/` cannot park a sprint, and `/way-of-working:park-sprint` refuses rather than
committing nothing. One behavioral edge: `cursor-drift.sh`'s allowlist now admits
`.ai/parked/*`, so a delta that is only a parked snapshot reads `cursor-sync` where it read
`drift`, and `/way-of-working:resume` may auto-start across it.

### Added

- **`/way-of-working:architect-review <PR>`, the fresh-session review gate's satisfier.**
  One skill for the act `review.ci_gate` enforces, assembled until now from five prose
  sites and improvised with `/code-review` plus a hand-typed `gh pr review`: it refuses
  without a gate or inside the authoring session, pins the head SHA and the exemption,
  runs `/way-of-working:pr-checks` first, reviews by execution in a scratch worktree,
  pastes the frozen header and attestation out of `.ai/project.yml`, posts with
  `--comment` only, then does the two things nobody owned — verifies the check went green
  on that SHA on both surfaces a gate can post to, and files every non-blocking finding
  as a backlog item instead of into `next_action`. The five sites (`reference/workflow.md`'s
  review section and both switch-points diagrams, `/way-of-working:resume` step 6,
  `/way-of-working:ship` step 7, `/way-of-working:critic-gate`'s callouts, the `architect`
  agent) now point at it instead of carrying the procedure; the frozen-string warning
  survives in `reference/project-schema.md` only. `/way-of-working:handoff` step 6's
  next-session block names the skill when the next action is the review. No new schema
  key; `review.ci_gate.runner_job` is noted as a possible later one.
  `scripts/coupling-check.sh`'s first tier matched the bare token `architect-review` as a
  pasted check name, which is now also the skill's own name; the tier now misses the
  token only after `:`, after `/`, or as a `key: token` value (the three contexts that
  name occupies) and catches it everywhere else, the gap included, pinned by
  `tests/coupling-check.test.sh` (`#90`).
- **`bin/review-gate-state.sh` resolves a review gate from both surfaces GitHub can carry
  it on.** Fed one SHA's commit statuses and check-runs as `gh api --jq … @tsv` records,
  it prints `success | pending | failure | absent` — any success on either surface wins,
  since a posted review cannot be un-posted; pending beats failure; the name match is
  exact, so a `-runner` job is not the gate — and exits 2 rather than guess on a record
  it cannot read. `tests/review-gate-state.test.sh` pins both shapes, absent, the mixed
  case (status success beside a stale check-run failure resolves to `success`), the
  superseded-run trap, and every refusal. `WB-D10`'s third landing (`#91`).
- **`/way-of-working:park-sprint <next-id>` and `/way-of-working:unpark-sprint <id>`.**
  One live cursor stays the design; a sprint set aside mid-flight becomes a tracked
  snapshot beside it — `.ai/parked/<id>-state.json`, carrying `parked_at`,
  `parked_from_commit` (recorded on `{pr_base}`, so it is normally an ancestor of later HEADs)
  and `parked_reason`, plus `<id>-next-steps.md` unchanged — and the live cursor is
  re-seeded for the next sprint by `/way-of-working:handoff` steps 2 to 4 by reference.
  Unpark restores the pair behind a `hitl_gate` naming what merged since, so a
  `next_action` written against an older HEAD never auto-starts. A park whose next sprint
  is already parked is a swap: it hands straight to unpark and one PR carries both. Each
  fails closed on its own preconditions — a dirty tree for both; for park an ignore rule
  that would swallow a snapshot or an existing parked id; for unpark an in-flight live
  cursor — and both ship as the docs-only cursor-sync PR shape; both are mechanical, so
  any model may run them. The `SessionStart` banner gains a `Parked: <ids>` line derived
  from the directory, which is the authority (the ledger records a park as a **Just done**
  event, never a copy of the list), and nothing when there are none, pinned by
  `tests/ai-cursor-banner.test.sh`. `WB-D12` records the rejected alternative, a
  multi-sprint `state.json` map (`#88`).

### Changed

- **`/way-of-working:pr-checks` step 3 reads a review gate posted as a commit status.** It
  queried check-runs only, so on a repo whose gate posts a status from a job named
  something else the step saw nothing and the STALE-RED verdict could never fire. It now
  feeds both surfaces to `review-gate-state.sh`, says which shape carried the gate, and
  chains the two `gh api` calls with `&&` so a call that failed never reads as `absent`
  (`#91`).
- **`/way-of-working:handoff`, `/way-of-working:archive-sprint` and `/way-of-working:resume`
  know about parked sprints.** Handoff stops, before it determines the new cursor, when
  the session's work was on a sprint other than `current_sprint_id` — its wholesale
  rewrite would overwrite the cursor's sprint's only in-flight record — and names the two ways
  out: `/way-of-working:park-sprint` the cursor's sprint first, or hand off out of band and
  leave `.ai/` untouched; unsure which sprint the work belonged to is the same stop, never
  a guess, and a `null` `current_sprint_id` has nothing to guard. Its ledger's
  **Pointers** carry `.ai/parked/` while that directory is non-empty, since a park's
  **Just done** line is written by one pass over the ledger and gone at the next
  regeneration.
  Archive-sprint
  closes only the live cursor's sprint — a parked one is unparked first, and a `done` one
  is closed before anything is unparked over it, because unpark's free-cursor precondition
  admits `done` — and, when `.ai/parked/` is non-empty, offers
  `/way-of-working:unpark-sprint <id>` in place of seeding a blank next sprint, then
  resumes at its own steps 5 to 7. Resume reports parked sprints with their `parked_at`
  in at most one line, derived from the directory, and never treats one as the cursor.
  `scripts/invariants-check.sh` gains a fourth known-wrong form — a handoff with no park
  guard, or one that does not precede its *Determine the new cursor* step; the
  consuming-repo near-miss `WB-D12` records — and `reference/conventions.md` says why
  tracked `.ai/parked/` is no counter-example to its rule that the deep record's archive
  never lives under `.ai/` (`#89`).
- **`cursor-drift.sh` classifies `.ai/parked/*` deltas as `cursor-sync`.** The allowlist
  widens from exactly `.ai/next-steps.md` to that file plus anything under `.ai/parked/`; a
  delta carrying any other path — a *file* at `.ai/parked`, or the sibling `.ai/parked.md`,
  included — still reads as `drift`. This is the ground `/way-of-working:park-sprint` will
  stand on: its cursor-sync PR commits the parked snapshot beside the ledger, and under the
  one-file allowlist every park would cost the next session its auto-start. It is not the
  "docs-shaped paths" widening `/way-of-working:resume` step 2 rejects — a parked file
  describes a different sprint and cannot invalidate the live `next_action`; the resume
  text, `WB-D7`, and `/way-of-working:handoff` step 5 now say so. `tests/cursor-drift.test.sh`
  pins the edges, including the `core.quotePath` quoting of a non-ASCII parked name and the
  shell-portability of the verdict (`#87`).

## [0.7.0] — 2026-09-02

**No migration required.** No `.ai/project.yml` key was added, removed, or renamed — the
archive destinations added this release are *derived* from paths a repo already sets, not
configured. Three behavioral edges, all the same shape: an absent key is not a `null` key,
so a skill that newly reads one reports it as unreadable where it previously said nothing.
`/way-of-working:critic-gate` now reads `{ruleset.required_checks}`;
`/way-of-working:archive-sprint` now reads `{agents.enabled}` and `{load_bearing_docs}`;
and `/way-of-working:ship` now reads `{backlog}`, `{roadmap}` and `{decisions.prefix}` for
its ledger-conflict rule.

### Added

- **Prose economy: the deep record gets a lifecycle.** Repeated critic-gate rounds (the
  evidence is gathered in `#57`) found the dominant defect class to be prose restating
  current state — each fix round minting the next round's defects — while `{roadmap}` and a
  file-kind `{backlog}` grew without bound as a standing per-session token cost. The class
  fix is less load-bearing prose, not more review:
  - `reference/conventions.md` — new **Prose economy** section: derive-don't-restate, one
    authoritative site per fact, corrections replace text (the story lives in git),
    evidence-then-prose (a correction is re-verified as hard as the claim it replaces),
    the deep record is compacted rather than append-only, and — once the mistake a
    paragraph warns against has actually occurred — the paragraph shrinks to a pointer at
    a check that fails the same way, verified by a deliberate regression.
  - `/way-of-working:handoff` — the regenerated cursor states no regenerable aggregates
    (no counts, no check inventories); it names the deriving command or authority
    instead. The cursor's own fields (status, hashes, model) and the critic pass's
    round count + stopping condition stay.
  - `/way-of-working:critic-gate` — findings checkable by execution are checked before
    being acted on (trust but verify); prose fixes prefer deletion/derivation over
    hand-correction, and a recurring prose defect class is promoted to a gate check.
  - `reference/workflow.md` — the `/way-of-working:critic-gate` line no longer says
    "iterates to clean", the formulation that skill explicitly rejects as unbounded.
  - **A file-kind `{backlog}` gets a defined archive sibling, and the surfaces that read
    the backlog read it too.** `reference/project-schema.md` derives the path rather than
    configuring it; `/way-of-working:retro`, the `docs-consistency` agent, and
    `/way-of-working:archive-sprint`'s evidence preconditions now consult it alongside the
    live file. Without it a resolved item reads as missing — a re-proposed finding in
    `retro`, a false "dangling citation" in `docs-consistency`, and a blocked sprint close
    in `archive-sprint`. A sibling that does not exist yet is empty, not an error — the
    derivation names a path, it does not promise a file.
  - **Two silent `gh issue list` traps are now named where the contract is defined**
    (`reference/project-schema.md`), and the readers follow it. A bare call shows only
    *open* issues, so citing a closed one reads as dangling; and `--state all` does not
    widen the result window but repopulates it against a `--limit` that defaults to 30, so
    an old issue can fall off the page and read as absent — for one cited id, worse than
    the bare call. To check a cited id, `gh issue view <N> --json state` answers directly.

  **For anyone who injects `reference/conventions.md` into a managed repo:** it now
  carries schema keys in braces (`{roadmap}`, `{gates.green}`, `{ruleset.required_checks}`)
  where before it had none, and a new preamble says so. Injected verbatim, those read as
  placeholders — the file is meant to be read in place beside the `project-schema.md` that
  defines them.

  The rules and the readers landed first, then **the writer** — the entries below.

- **One archive rule, now applied to `{roadmap}` as well.** Part A derived an `_archive`
  sibling for a file-kind `{backlog}` and left `{roadmap}`'s destination "a per-repo choice
  until one is defined." The writer defines it — as the *same* derivation, not a second
  convention and not a new schema key. That keeps the archive **beside the live record**, as
  the Prose economy rules require (an archive parked in a sprint directory is not), needs
  nothing added to `.ai/project.yml`, and lets a repo with **no sprint cadence** compact its
  roadmap — which the sprint-directory destination structurally could not, leaving the repos
  most prone to roadmap bloat unable to do anything about it.

- **The writer: `/way-of-working:archive-sprint` now performs the compaction, on its own
  PR.** A new **step 2**, before the cursor advances (advance/seed renumbered 3–4;
  prune/report/pin 5–7): the closed sprint's execution narrative moves out of `{roadmap}`
  to its `_archive` sibling, file-kind `{backlog}` items closed during the sprint —
  **resolved *and* declined**, matching what every reader of the sibling already expects to
  find there — move to theirs keeping their id anchors, and correction annotations whose
  gated action is confirmably closed are deleted. **Move, don't rewrite**, and the guardrail
  is checkable rather than a claim about intent: a line may leave a source only when the
  identical bytes are in an archive file staged in the same change — verified before the
  commit, since a move that cannot show its destination is a deletion whatever it was meant
  to be. It surveys first, confirms the sprint actually merged, cuts its branch from
  `{pr_base}` before editing a file (editing first can abort the checkout, and git's own
  advice then strands the work on a branch step 5 deletes), stages by explicit path, and
  stops at an open PR the human merges. A repo with nothing to move takes a one-line exit.

  Four details that are the difference between a working procedure and a plausible one, the
  first three verified against git rather than reasoned about:
  - the branch cut ends in **`git merge --ff-only origin/{pr_base}`, not `git pull`** —
    where `pull.rebase=false` is configured, a plain pull *succeeds* on a diverged local
    `{pr_base}`, merging silently, so every link in the chain returns zero and the compaction
    branch is cut from a base carrying an unrelated commit. (With no pull config at all git
    refuses instead, so the hazard is config-dependent — which is exactly why the procedure
    should not depend on the operator's config. The ref is named for the same reason: a bare
    merge follows `@{upstream}`, wherever that points.);
  - **`git check-ignore` runs before `git add`, not after** — it is index-aware, so once a
    path is staged it reports nothing even when `.gitignore` matches, making the check pass
    by construction and prove nothing;
  - **a non-zero `git add` is a stop** — given an ignored destination it stages the sources
    anyway and exits 1, leaving exactly the deletion-without-destination in the index;
  - the addition-side check is **scoped to the archive paths** — unscoped, the pointer lines
    left at vacated anchors supply insertions and the check passes with no archive staged.

  The correction-annotation exception has no destination to verify, so every removal claiming
  it must be **enumerated with its evidence in the commit and PR body**. In a repo with a
  `github_issues` backlog that exception can be all a compaction does, which would otherwise
  leave the bright line resting entirely on the agent's own say-so. Relatedly, `state` alone
  cannot tell a completed item from a declined one — both read `CLOSED` — so the check now
  asks for `state,stateReason`.

  The guardrail this replaces — *"archival only moves the `.ai/` cursor snapshot"* — was
  true until this step existed and is now removed rather than annotated.

- **The reader half: `/way-of-working:ship` gains a ledger-conflict rule.** Without it
  the "keep both sides" default silently resurrects whatever a compaction archived, the
  first time a stale branch is refreshed against `{pr_base}` — and the human is never told
  which removals were even in question. A compaction's removal and your branch's new
  neighbouring item look identical in a conflict, so the step compares two revisions instead
  of reading the hunk: `git show :1:<ledger>`, the base the merge itself used, against
  `git show MERGE_HEAD:<ledger>`, the incoming side.

  **Every branch still keeps both sides — this step never deletes an entry.** What the
  comparison buys is not a decision but a *sorted report*, per entry rather than per hunk:
  not removed → keep both, say nothing (the ordinary two-additions conflict, and the common
  case); removed and the archive appears to carry it → keep both, and flag it as **probably
  moved by a compaction**, so the likely resolution is to drop it; removed and not → keep
  both, flagged **unresolved**. Where a `git show` on the ledger fails — a renamed ledger, or
  an add/add conflict with no stage 1 — the default stands unchanged.

  An earlier draft of this release *did* accept the removal automatically on a positive
  answer. It does not any more, and `WB-D11` records why: every critic round found a new
  ledger shape where an ordinary **citation** answers positive, the predicate's own cost
  section now describes itself as "a floor, not a proof", and an unrecoverable deletion
  cannot hang on a predicate that honest.

  **What that costs, stated plainly:** `#66` asked for step 1 to resolve per entry *instead
  of handing every removal to the human*, and for the prose to shrink to a pointer. Per-entry
  **ranking** shipped instead of per-entry **resolution**, and the step-1 prose grew by half
  again rather than shrinking. That is the right trade against an unrecoverable deletion, and
  it is still a reduction in what the issue asked for — `WB-D11` carries the full record.

- **The predicate behind that ranking: `bin/entry-anchor.sh`, with
  `tests/entry-anchor.test.sh`** (`#66`, per `WB-D10`). It answers one question — *does this
  file carry `<id>` at its own entry anchor?* — as `0` yes, `1` no, `2` could not tell, and
  the caller's policy for `2` is the policy for `1`. It exists because prose could not:
  three critic rounds each shipped a line-shaped `grep` broken in a new direction, missing
  real entries (`- **BL-3** — …`, `1. BL-3 …`, `| BL-3 | …`) and, worse, *matching* a wrapped
  citation whose continuation line begins with the id — which in an `_archive` means silently
  dropping a live item, and `/way-of-working:retro` mandates the citation shape that produces
  those. Three design commitments, each from a round that failed without it: the id is
  matched as a **literal**, never compiled (an interpolated `A.1` also matches `AX1`, and an
  id holding `[` makes the matcher *error*, which a surrounding `if` reads as a clean "no");
  the id must be delimited at **both** ends, so `BL-1` does not fire inside `BL-14` and
  `BL-3` does not fire inside `12BL-3`; and — the load-bearing one — a line anchors only if
  it **opens a top-level entry of the file it is in**: a bullet/ordered/heading marker
  followed by whitespace, or a table pipe, at **column 0**, outside every container the
  script tracks (fenced code, HTML comments, YAML front matter).

  **Every earlier version of that rule was wrong, and always the same way — which is the
  reason to trust this one and the reason to read its cost section.** Each asked whether the
  *line* looked like an entry, and each was defeated by a structure containing it: markup
  before the id (a **bolded** or `backticked` citation on a wrapped continuation line); then
  "does the line open a *block*?", which admits every line of a blockquote since `>` is
  unimpeachably a block start; then a citation written as a **nested list item** under its
  own parent entry — the shape `/way-of-working:retro`'s "cite the id you supersede" mandate
  actually produces; then, once containers were tracked, a fence *closed early* by a shorter
  delimiter run or an info string, exposing the example entries inside it. Indentation,
  quoting, fencing, commenting and front matter are all ways Markdown says *this line belongs
  to something else*, and none is visible in the line's own marker. So the rule stops asking
  about the line and requires the position a top-level entry necessarily occupies.

  Fences and comments are opened permissively and closed strictly, and the asymmetry is
  deliberate: a missed *open* exposes content, while a missed *close* only skips more of the
  file. Front matter is the deliberate exception — line 1 and column 0 only, since a `---`
  anywhere else is a thematic break rather than a container.

  Nested means subordinate to the entry above it; quoted means someone else's ledger is being
  reproduced; fenced or commented means it is an example. None is *this file's own* entry,
  which is the question actually asked. Only the first failure was reproducible against this
  repo's own `docs/decisions.md` — it has no blockquotes, and no ledger here nests an
  id-bearing entry — so the rest were reproduced on constructed archives. Worth stating
  precisely: an earlier draft claimed a live in-repo instance of the nested shape, and there
  is none. The genuinely open-ended part — inline decoration between the
  marker and the id — stays a shape test rather than a list: no letters, once
  bracket-delimited *whitespace-free* spans are dropped, so a **checked** `- [x]` box anchors
  like an unchecked one while `- [the note about this](#BL-3)` does not.

  **Its cost is named in the script's header, false matches included, and stated there as a
  floor rather than a proof.** Every miss is chosen — keep-both is recoverable — and the
  header names the false matches it knows of, each with a `KNOWN false match` fixture pinning
  it at its current answer. **That list is not repeated here**, deliberately: it was
  enumerated in this entry twice and drifted short of the header both times, the second time
  within a single review round, because a mechanism was added to the script and the copy here
  was not. Per `reference/conventions.md` § *Prose economy*, the fix for a drift pair is to
  delete the copy rather than synchronise it — read
  `plugins/way-of-working/bin/entry-anchor.sh`, which is where the list is true by
  construction. Every earlier revision offered a cost section listing
  only misses while carrying an unlisted false match, which is why the honest form is a
  general shape plus today's instances. The keep-both asymmetry is also why "could not tell" is
  `2` and never `1`, and why misuse — a missing argument, an empty id, a directory, an `awk`
  without POSIX bracket classes — exits `2` rather than the shell's default `1`: `1` is this
  script's word for a confident negative.

  Fixtures cover `#66`'s shape table row for row, both citation collisions it mandates, all
  false-match classes above, and at least one row per rule — `sh tests/entry-anchor.test.sh`
  lists them. Mutation-tested to completion: 86 candidate lines (every line that is not blank,
  not a comment, and not brace-only) — 69 red, 6 non-terminating, 11 green — plus a
  sub-expression pass over the fifteen sites that carry a condition made of parts: 31
  variants, 27 red, and the 4 green are exactly the four guards the suite names as
  unpinnable. Three of those need a non-conforming `awk` to reach; the fourth
  (`[ ! -r "$file" ]`) is a Windows platform limit, since `chmod 000` there does not deny the
  owner a read. A fifth green line is not a guard at all — the `exit` after `found = 1`
  short-circuits the rest of the file and cannot change the answer, so a status-only contract
  can never pin it.

  **Three things about the sweep the earlier note got wrong by construction.** A whole-line
  deletion answers a different question whenever the line carries more than the guard: delete
  the four guards at their own lines and you get two reds for no longer parsing, one red for
  removing the surrounding assignment, and one hang — no green among them, and not one of the
  four an answer about the guard. A red can be **vacuous**: 22 of the 69 are mutants that no
  longer run at all, so they pin nothing. And a deletion can make the script
  **non-terminating** rather than wrong, which hangs a suite that has no timeout instead of
  failing it — how an earlier attempt at this sweep stranded partway. Mutate sub-expressions,
  check runnability before counting a red, and bound every run.

  **The sweep found four live guards the note had filed as covered.** `col = 0` is an awk
  global reset, not a redundant initialiser: without it the previous fence line's column count
  carries into the next one, a 2-space-indented fence pair accumulates past the four-column
  threshold, the closer reads as indented code, and the file goes dark from there. That one
  turned up when a critic asked what the "initialisers" actually did; the other three turned
  up one commit later, behind the word *every* — the `~~~` alternative of the fence opener,
  and the "nothing else on the line" tail on both halves of the front-matter delimiter, two of
  them failing toward a false match. The tilde one is the shape worth remembering: the only
  other `~~~` fixture nests it inside a backtick fence, where a matcher that does not know
  `~~~` at all behaves identically, so it read as covered and pinned nothing. All four have
  fixtures now, which is why the green count is 11 rather than 12.

  **It asks a revision, never a merge base.** The obvious form — diff `git merge-base HEAD
  MERGE_HEAD` against `MERGE_HEAD` and call the result "the incoming side's changes, with
  your side absent" — is **false under squash-merge, this project's own default**, and was
  written that way first. A squash commit is not a descendant of the branch's commits, so
  the merge base does not advance past it (`WB-D7`'s premise in a different command): once a
  PR squash-merges and work continues on the branch, that diff replays the branch's *own*
  additions and deletions as the incoming side's. Stage 1 is the base **git itself resolved
  for this merge**, virtual bases included, so it is right where a recomputed base is not.
  Reproduced before the fix — a decline and
  an addition made on the work branch were both attributed to `{pr_base}`, which inverts the
  rule's conclusion. `git show MERGE_HEAD:<path>` has no fork point to be wrong about.

- **`/way-of-working:retro`'s "confirmed again" path is now defined for an archived item.**
  Step 1 reads the `_archive` sibling, so it will match resolved and declined items;
  neither annotating one in place nor reopening it is right. Archive files are never
  edited — historical record, and a compaction moves text without rewriting it — and a
  resolved item recurring is new information that earns a new item citing the old ID, not a
  reopen that buries it. A declined one goes back to the owner rather than being reversed.

### Fixed

- **`reference/workflow.md` no longer describes the repo the plugin was extracted from**
  (`#52`). A load-bearing shipped doc asserted a `hatch run` green gate, a review-gate
  workflow and its config test as existing files, `src/` paths, a hardcoded reviewer
  identity, three agents the plugin does not ship, and origin backlog/PR ids. Every such
  claim is now parameterized against the schema (`gates.green`, `code_paths`,
  `load_bearing_docs`, `review.ci_gate.*`, `models`, `agents.enabled`) or reframed as
  explicit origin-repo history; the skills section lists all seven shipped skills; the
  frozen review header/attestation fence is byte-identical.
- **The cursor banner pointed every session at a `CLAUDE.md` model-routing rule no
  consuming repo is obliged to have** (`#54`). Both the runtime string and the header
  comment now point at `models` in `.ai/project.yml` — the schema's home for role→model
  routing — changed together so the hook's output and its own source comment keep agreeing.
- **`/way-of-working:ship` step 1 cited a decision id from this repo's own log** (`#77`) —
  a dangling reference in any consuming repo, and invisible to the coupling gate, whose
  tiers cover repo names, acceptance strings and paths, not decision ids. The citation now
  points at `bin/cursor-drift.sh`'s shipped header, which carries the same
  squash-non-ancestry premise.
- **The branch prune in `/way-of-working:resume` and `/way-of-working:archive-sprint` could
  delete unpushed work without warning.** Both fused the merged test onto the deletion
  (`grep -qxF "$b" && git branch -D "$b"`), which makes `-D` safe per *branch* while the
  risk is per *commit*: a branch whose PR GitHub reports `merged` can since have taken a
  local commit, and because a squash-merged branch's commits are unreachable from
  `{pr_base}`, `-D` takes that commit with no complaint and nothing to recover it from.
  The deletion is now gated on the commit GitHub actually merged — `headRefOid`, which the
  same `gh pr list` call already returns — and fires only when the local tip **is** that
  commit; anything else is reported as a skip rather than deleted.

  The first attempt at this fix tested `git rev-list --count origin/$b..$b` ("is my tip
  pushed?"). That failed *safe* — it deleted nothing — so it was never as dangerous as the
  bug, but it was not a fix either: it reads the remote-tracking ref, which stops resolving
  once the head branch is deleted on the remote (`deleteBranchOnMerge`, the PR page's
  *Delete branch* button, or by hand) and the local ref is pruned. The count then fails for
  that branch and the safe fallback skips it permanently, reporting stranded work that does
  not exist. What makes it a trap rather than a plain bug is that **the blast radius is set
  by a repo setting the test never consults**: where branches are deleted on merge it
  eventually disables the prune entirely, and where they are not — as here, where
  `deleteBranchOnMerge` was `false` and 37 of 41 merged head branches still existed on
  2026-08-31 — it looks
  flawless. `headRefOid` does not depend on that setting. Found while working #57 and
  carved out of it.

- **`/way-of-working:handoff` step 5 could cut the cursor branch off the wrong base.** The
  switch to `{pr_base}` was chained but the `checkout -b` after it was not, so an aborted
  switch was followed by a branch cut from wherever the session was standing — quietly
  producing the exact outcome the step exists to prevent. There are two abort paths, not
  one, and the step now names both — and names the right determinant, which is whether
  `.ai/next-steps.md`'s *committed* content differs between the branch being left and
  `{pr_base}`, not whether the local base is stale. Where it differs, `git checkout`
  refuses; where it does not — the ordinary case — the checkout succeeds and carries the
  modification across, and `git pull` aborts instead once the fetch brings a change to that
  file. Unchained, the first lands the cursor branch on the **code branch** and the second
  on a **stale `{pr_base}`**. The cut is now one `&&` chain; a failed link stops,
  names the blocking file, and hands it to the human rather than committing or stashing on
  their behalf — including the case where the chain stops with the session parked on
  `{pr_base}`. Found while working #57 and carved out of it.

- **`coupling-check.sh`'s component loop was an allowlist, which is what let the
  `plugins/*/hooks/` gap below (#49) happen in the first place: a new component directory
  had to be added to a hardcoded list by hand before the gate would ever look at it.**
  Inverted to a denylist -- the loop now scans every entry under `plugins/*/` except
  `reference/` (documentation, legitimately quotes concrete example values),
  `.claude-plugin/` (plugin metadata, `plugin.json`'s `author` field legitimately carries
  the org name), and `.git/` (defensive only, for a plugin vendored as a nested clone;
  git refuses to commit a `.git` path, so in CI the arm is unreachable). `shopt -s
  dotglob` was required for the `.claude-plugin/` exclusion to be a real decision rather
  than an accident: bash globs skip dot-directories by default, so without it the
  exclusion `case` arm was unreachable and `.claude-plugin/` was already being skipped for
  the wrong reason.

  Two rounds of critique on this change found five further ways the gate could report a
  pass over something it had not read, all now closed and each covered by a regression in
  `tests/coupling-check.test.sh`:
  - **Files at a plugin's root were never scanned** -- the inner glob was `*/`, so only
    directories were examined. `.mcp.json` lives there and carries MCP server commands.
    The glob is now `*`; `grep -r` takes a file as happily as a directory.
  - **The exclusions matched on name alone**, so a plugin-root *file* called `reference`,
    `.claude-plugin` or `.git` was skipped as though it were the directory of that name --
    a green pass over unread content, and new surface created by scanning root files at
    all. Each exclusion is justified by what the entry *is*, so it now matches on type too.
  - **A whole plugin could be skipped silently.** The zero-scanned guard was one repo-wide
    counter, so any one scannable directory anywhere satisfied it -- a second plugin whose
    every entry was excluded passed green. The guard is now per-plugin.
  - **`$(basename ...)` stripped trailing newlines**, so a directory named `reference` plus
    a newline compared equal to `reference` and was skipped. A newline is a legal path
    character in git, making that a committable bypass. Now `${target##*/}`, which
    compares the value actually used.
  - **`grep` exiting 2 (a real error) was read as "no match"** by the `if hits=$(grep ...)`
    form, discarding any hits already found -- a gate that dies quietly reporting the same
    "nothing to see" as a gate that passed, the failure `invariants-check.sh` already
    names. Exit status is now captured, and anything `>= 2` fails the gate.

  An empty or missing `plugins/` tree and a wrong cwd all fail the gate too, rather than
  reporting a pass having read nothing. (`.` and `..`, which `dotglob` yields on bash
  before 5.2, are *skipped* rather than failed -- left in they would send `grep` up into
  the whole repo and make the documented local run permanently red on macOS's system
  bash.) The cases the gate still does *not* cover -- a file directly in `plugins/`
  outside any plugin directory, a symlink below a component directory, a plugin-root
  symlink named like an exclusion, and an empty directory satisfying the per-plugin
  counter -- are enumerated in the script's header rather than left to be discovered. `CLAUDE.md`,
  `README.md`, `reference/project-schema.md`, and the two CI workflow step names were all
  widened to match, per the precedent #49 set below. See #53.

- **The coupling gate never scanned `plugins/*/hooks/`, and a stale literal was sitting in
  the blind spot.** The scanned set was `skills/`, `agents/`, and `bin/`. `hooks/` carries
  shipped, executed plugin code by exactly the argument that added `bin/` in #21:
  `hooks/ai-cursor-banner.sh` is a `SessionStart` hook registered in `hooks.json` and runs in
  every consuming repo. Adding `hooks` to the scanned set immediately caught the one live hit
  it had been blind to — the hook's header comment pointed at `.ai/context/workflow.md` and a
  CLAUDE.md section heading, **neither of which exists here**: that workflow content moved
  into the plugin's own `reference/workflow.md`. Reworded to name the concept rather than the
  path. The two CI workflow step names that enumerated the old three-tree set
  (`ci.yml`, `release.yml`) were corrected with it — the `coupling` **job id**, which is what
  `ruleset.required_checks` matches, is deliberately untouched. The gate's rule sentence and
  failure banner now say "shared plugin code" rather than "a skill or agent", which had
  under-described the scanned set since `bin/` joined it — as did the same sentence in
  `CLAUDE.md`, `README.md`, and `reference/project-schema.md`, all widened to match. The
  last of those matters most: it is where the failure banner sends a reader for the fix.
  Found by the architect critic during #43's `/way-of-working:critic-gate` pass and filed
  separately. See #49.

- **`coupling-check.sh` guarded only 4 of the org's 8 repos.** `TIER2` itself listed 3
  (`bounty-infra`, `global-bootstrap`, `scope-core`); the 4th (`loop-orchestrator`) was
  covered only via `TIER1`, and the check's other four org repos had no coverage anywhere.
  Added the missing four (`claude-workbench`, `bedrock-serverless-rag`, `pm-agent-loop`,
  `appsec-triage-agent`), plus the `loop-engine` worked-example emitter name and
  `loop-orchestrator` itself, to `TIER2`, and restated its comment as a membership rule
  instead of an ad-hoc list. `claude-workbench` is the repo a contributor is most likely to
  be sitting in while editing the plugin, and was the highest-risk gap. Two pre-existing,
  legitimate self-references to `claude-workbench` in `archive-sprint`/`retro`'s own prose
  (describing the plugin's distribution source, not a leaked local-repo literal) were
  reworded to name the concept instead of the repo. See #43.

- **The pin-bump procedure was wrong for a second time, and this release changes where it
  lives rather than only what it says.** `claude plugin update` resolves against the ref
  registered in `~/.claude/plugins/known_marketplaces.json`, not the ref just edited into
  `.claude/settings.json`, so it reported *"already at the latest version"* and loaded the
  old tag — a silent no-op reporting success. Corrected in
  `reference/conventions.md` § *Bumping a pinned plugin*, which also covers the two
  adjacent traps: `update` defaulting to `--scope user` on a project-scoped install, and a
  first registration made **without** a `ref` shadowing a project pin permanently. See #37.
- **The corrected steps now ship in the generated release notes** (`release.yml`), because
  `CHANGELOG.md` is the wrong channel for this by construction: a consuming repo reads the
  pin-bump instructions from the version it *already has*, so a fix here is only readable
  after the bump it describes. Release notes are read at bump time and stay editable after
  the tag is cut. `WB-D6`'s lesson, applied to the delivery mechanism instead of the prose.
- **Verification is now by commit, not by version string.** `claude plugin list` reports the
  `version` field from the installed `plugin.json`, which is self-consistent at the wrong
  commit and therefore proves nothing; the check compares `gitCommitSha` in
  `installed_plugins.json` against the tag. Found live: a consuming repo reporting `0.5.1`
  while running a `main` commit two merges past that tag.
- **The machine-namespace rule shipped with an example that contradicted it — and a second
  doc that contradicted the rule outright.** Global Conventions § *Issue + label taxonomy*
  stated the namespace as *the emitting system*, then illustrated it with the **repo** name,
  which is only coincidentally the same thing: in the repo the example was drawn from the
  emitter is `loop-engine`, so the label reads `loop-engine/needs-human`, and the one
  instance a reader had to generalize from taught the wrong rule. `project-schema.md` then
  stated that wrong rule flatly, in three places, as a plain property of the `repo` key.
  Fixed together — the conventions bullet now names the emitter and gives both cases (the
  one where the namespace matches the repo and the one where it does not), while
  `project-schema.md` and `/way-of-working:ship` step 6 still derive a skill's namespace
  from `{repo}` but now say **why** that is correct: a skill's emitter *is* the repo's own
  automation, so it is the general rule applied, not an exception to it. **No emitted label
  changes and no key moved** — every namespace any skill produced was already right; what
  was wrong was the reason given for it, which is what a reader generalizes from. Closes
  #28's decision 1.

## [0.6.0] — 2026-08-13

**No migration required.** No `.ai/project.yml` key changed and no skill contract moved.
Two things behave differently after the bump, though, and neither is visible in a diff of
your own repo: `/way-of-working:ship` step 1 now runs a preflight that can **stop** a ship
before anything is committed, and the plugin ships its first executable — `bin/` is on the
Bash tool's `PATH` while the plugin is enabled, so a name collision with a script of your
own on `PATH` is possible in principle. Only `cursor-drift.sh` is claimed today.

### Added

- **`/way-of-working:ship` step 1 gains a push-reach preflight** (`gh api repos/{repo}
  --jq .permissions.push`), so a wrong-identity push is caught before anything is
  committed rather than at `git push`. It only verifies `gh`'s identity, not `git`'s — see
  the new Global Conventions section below for the case it can't catch.
- **Global Conventions documents the `git`-vs-`gh` push-identity split**
  (`reference/conventions.md` § *Push identity*): `git push` and `gh` can resolve
  different GitHub accounts on the same machine, so a healthy `gh` preflight does not
  guarantee the next `git push` succeeds. Includes the diagnosis, a per-push workaround,
  and the durable fix.
- **`/way-of-working:handoff`'s own push (step 5) gets a pointer to the same section** —
  it has the identical exposure but, per #23's own preferred shape, no preflight of its
  own; only `ship` does. Closes #23.
- **`plugins/way-of-working/bin/cursor-drift.sh`**, a tested extraction of
  `/way-of-working:resume` step 2's cursor-freshness classifier (`clean | cursor-sync |
  drift | unreadable`), proven by `tests/cursor-drift.test.sh` against real throwaway git repos —
  including the squash-merge case `WB-D7` names. `bin/` is on the Bash tool's `PATH` while
  the plugin is enabled, so the skill calls it by bare name; `${CLAUDE_PLUGIN_ROOT}` was
  confirmed **not** set in that context first (issue #21 step 1), which is what made `bin/`
  the right delivery mechanism rather than the interpolated path the issue proposed. A new
  `tests` CI job runs the fixtures on every PR (not yet a required check). See `WB-D10`.
- **`coupling-check.sh` and `invariants-check.sh` now also cover `plugins/*/bin/`** — the
  no-repo-specific-literal rule and the drift-classifier regression guard both apply to the
  script the same way they already applied to skill/agent prose.

## [0.5.1] — 2026-08-10

**No migration required.** Docs-only. Worth taking before a fan-out, though: it corrects the
pin-bump instructions themselves, which a repo reads from the version it already has.

### Fixed

- **The pin-bump instructions named no command.** Every mention of the plugin cache said
  "clear it" and "confirm the version rotated" without saying how, and the directory-rotation
  test was wrong — the cache keeps the old version's directory alongside the new one. Now
  states the three steps (edit the ref, `claude plugin update`, **restart**) and verification
  via `claude plugin list`. `WB-D6` updated: the mechanism it left open is now understood.

### Changed

- `WB-D8` records that the reporting repos confirmed their hubs can expose findings as
  issues, so the breaking file-based cross-repo backlog is **not scheduled** rather than
  deferred. See #5.

## [0.5.0] — 2026-08-10

**No migration required.** Every existing `.ai/project.yml` stays valid untouched;
`backlog.repo` is optional and defaults to the current behavior. Bump the pin, clear the
plugin cache, confirm the version rotated.

Closes five issues raised upstream by `/way-of-working:retro` in consuming repos: #5
(partially), #6, #7, #12, #13.

### Added

- **`backlog.repo`** — a `kind: github_issues` backlog may name the repo that holds it, for
  the hub-and-spoke shape where one repo carries the record for a family of sibling repos.
  Reads *and* writes work cross-repo (`gh issue list/create --repo …`). Not supported with
  `kind: file`; see `WB-D8` for why that asymmetry is the design. (#5, partial)
- **Blocking preconditions get a convention and two checks.** `reference/conventions.md`
  defines the `BLOCKING:` marker and extends the Definition of Done to enumerate
  preconditions, not only deliverables; `/way-of-working:ship` records a precondition's
  satisfaction in the PR that relies on it; `/way-of-working:archive-sprint` gains
  precondition 5, which checks it at close. (`WB-D9`, #7)
- **`invariants` CI job** (`scripts/invariants-check.sh`) — asserts that three
  already-shipped defects have not returned: cursor freshness compared by commit range,
  `gh auth status` being parsed, and the reach check ordered after the ruleset call.
- **This changelog.**

### Changed

- **`/way-of-working:resume` compares cursor freshness by content, not ancestry.** The
  `v0.4.0` carve-out used a commit *range* (`<last_commit>..HEAD`), which is meaningless
  unless `last_commit` is an ancestor of `HEAD` — and under squash-merge it frequently never
  becomes one, so auto-start could not fire whenever a handoff ran with a code PR still open.
  Now a two-argument `git diff <last_commit> HEAD`. (`WB-D7`, #6)
- **`/way-of-working:critic-gate` has a bounded stopping rule.** *"Iterate until the critics
  are clean"* is replaced by a severity-based convergence test, an unconditional re-run on
  the fixed tree, cross-round finding tracking, and a hard cap of 2 fix-and-re-run rounds
  before the decision returns to the human. (#12)
- **`/way-of-working:resume` establishes repo reach before the ruleset preflight.** An
  identity that cannot see a ruleset gets `404`, not `403`, so the old behavior reported a
  reachability failure as *"the ruleset does not exist"*. (#13)

### Fixed

- `/way-of-working:handoff`'s cursor-PR note described the superseded range-based rule.
- `/way-of-working:critic-gate`'s closing rationale claimed the spawn decision stays with the
  human, which stopped being true of re-spawns when the round cap replaced per-round
  confirmation.
- The README described `project-schema.md` as `v0.2.0`; the schema carries no version of its
  own and had changed since.

## [0.4.0]

`WB-D6` dispositions from the pilot's real-work exercise: tier-3 coupling patterns for
path-shaped literals, a `/way-of-working:critic-gate` proposal row for newly-added docs, and
a `/way-of-working:handoff` step-5 clarification for stacked handoffs. The first (later
superseded) fix for the cursor-drift check. A release workflow that derives its tag from
`plugin.json`, and the published `/way-of-working:<skill>` command names.

## [0.3.0]

Interim tag; see the release notes.

## [0.2.0]

`.ai/project.yml` and `reference/project-schema.md` — the parameterization contract
(`WB-D2`). Full generalization of the 7 skills and the 4 agents against it (`WB-D5`), and the
grep-based `coupling` CI job that enforces it mechanically.

## [0.1.0]

The plugin skeleton: marketplace and plugin manifests, 7 skills, 4 agents, the `SessionStart`
cursor-banner hook, and the Global Conventions (`WB-D1`, `WB-D3`, `WB-D4`). Skills were
copied across still coupled to their source repo **on purpose** — generalizing them was
`v0.2.0`'s job.
