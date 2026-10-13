# Global Conventions (portable skill repository)

Referenced from the lean root `CLAUDE.md`. This is the engine's **global
directive/skill repository**: repo-agnostic ground rules the personas load as
conventions, and the block the bootstrapping/maintenance workflows inject into
every managed `glunk-works` repo. Keep it self-contained — no references to
files that only exist in *this* repo — so it stays valid when copied elsewhere.
Names in braces (`{roadmap}`, `{gates.green}`, …) are keys each repo sets in its own
`.ai/project.yml`; the schema that defines them travels with the plugin that injects
this file.

## Python conventions
- **Formatting is not negotiable:** `ruff format` (line length 100) is the single source of truth; never hand-format against it. Lint with `ruff check` under rule sets `E, F, I, B, S` (pycodestyle, pyflakes, isort, bugbear, bandit). Import order is isort-managed — do not hand-order.
- **No `# noqa` without an inline justification** on the same line (`# noqa: RULE — reason`). A bare `# noqa` fails review.
- Target `python >= 3.12`. Full type hints on public functions; prefer `X | None` over `Optional[X]`, `list`/`dict` over `typing.List`/`Dict`.
- **No hardcoded secrets anywhere** — not in source, tests, or committed state/snapshot files. Credentials come from the OS keyring (or the documented double-gated CI fallback), never CLI flags or plain env vars.
- Every Pydantic-validated I/O boundary needs a test proving invalid input is rejected. Pin dependencies to CVE-free versions and regenerate the SBOM whenever deps change.

## OpenTofu / IaC conventions
- Format with `tofu fmt`; every change must pass `tofu validate` with exit 0 (this is the deterministic gate — no LLM judges IaC).
- One concern per module; expose inputs via `variables.tf`, outputs via `outputs.tf`, pin provider **and** module versions (no floating `latest`).
- Remote, locked state only — never commit `.tfstate` or `.terraform/`. No secrets in `.tf` or `.tfvars`; source them from the secret manager at plan/apply time.
- Name resources `snake_case`; tag every resource with owner + managing-repo so the factory can attribute drift.

## Commit / PR conventions

- Commits are small, self-contained, and green (`ruff check` + `ruff format --check` + the test suite all pass before committing). Sign commits made on the host. Commits made in a dev container configured to disable signing are unsigned; where the repo squash-merges, the commit that lands is signed by GitHub.
- PRs target the integration branch (`develop`), never `main`/`master` directly, and never merged directly by an agent. Where the repo allows auto-merge and the base requires a code-owner approval, `/way-of-working:ship` arms it (`WB-D24`), so the merge waits for that approval and every other rule on the base; with no required code-owner approval it arms nothing. If an armed, approved, clean PR does not merge, `/way-of-working:pr-checks` reports the stall and the pinned command; the merge stays the human's (`#432`).
- A change touching a versioned state schema must bump its `schema_version` and extend the migration path in the same commit.

### Message grammar: Conventional Commits

```
type(scope): imperative subject, lower-case, no trailing period
                                            <- 72 chars max
<blank>
Body: why the change exists and what it trades off. Wrap at 80.
Not a restatement of the diff — the diff is already in the commit.
<blank>
Sprint: 31
Finding: F-RALPH-FALSE-COMPLETION
Co-Authored-By: ...
```

- **`type`** is one of: `feat`, `fix`, `docs`, `test`, `refactor`, `perf`, `chore`, `ci`,
  `revert`. There is deliberately **no `style`** — the formatter owns formatting, so a
  style-only commit should not exist.
- **`scope`** is the module the change lives in, drawn from the repo's *enforced module
  boundaries* (in this engine: `core`, `personas/ralph`, `tools/mcp`, `tools/git_io`,
  `flows`, `trigger`, `mcp_servers`, `ci`, …). The commit vocabulary and the
  architectural vocabulary are deliberately the same words — if a change doesn't fit one
  scope, that is a signal it is really two commits.
- **`!` marks a breaking change** (`feat(core)!:`). For a versioned-state repo this has a
  precise meaning: a `State` shape break, which must carry a `schema_version` bump and a
  migration-path extension **in the same commit** (see above). The `!` makes that
  visible in one line of `git log`.
- **The type prefix is not a licence for a vague subject.** `fix(personas/ralph): fix bug`
  is worse than no convention at all. The subject still has to say what changed:
  `fix(personas/ralph): gate task completion on successful edit application`.
- **Trailers link a commit to the project's own ID space** — `Sprint: NN`,
  `Finding: <ID>`, `Closes: #N`. This is what makes "which commit closed this finding?"
  a `git log --grep` instead of an archaeology session.

### PR titles use the same grammar — and are the enforced surface

The merge is a squash, so **the PR title becomes the commit subject on the integration
branch**. It is therefore the only message that must be well-formed, and the only one
worth a CI check (`pr-title` job). Commits *within* a branch may be messy WIP; the
history that survives is the PR title. Enforcing every WIP commit buys nothing and adds
friction mid-sprint.

### Branch names

`sprint/NN-slug` for planned sprint work; `feat|fix|chore|docs/slug` for one-offs.
The prefix matches the commit `type` the branch will land as.

### Merge method: squash by default, merge-commit for integration → main

- **Squash-merge every ordinary PR.** The sprint (not the individual task commit) is the
  atomic unit: it is reviewed, archived, and attributed to a finding as one thing, and
  you would never want to revert half of it. Squashing also means **every commit on the
  integration branch is known-green** — WIP commits inside a branch are never CI'd on
  their own, only the PR head is. Keep the squash *message* set to the branch's commit
  messages, so per-task rationale and the `Sprint:`/`Finding:` trailers survive in the
  body and stay greppable.
- **Set the squash *title* source to the PR title, not "PR title or commit details."**
  With the default, a **single-commit PR silently uses the commit subject instead**,
  bypassing the CI-validated PR title entirely. The `pr-title` gate is only real once
  this is set.
- **Merge-commit (never squash) the long-lived integration branch into `main`.** Squashing
  that PR would collapse the entire multi-sprint effort into one commit and destroy the
  history. This is the one deliberate exception to the default.
- **Enable "automatically delete head branches."** A squash-merged branch is dead (its
  original commits are still "unmerged" against the new squashed commit and will
  conflict). Auto-deletion makes that structural rather than remembered — you cannot push
  to a branch that no longer exists.

### Acting identity and reach: a token is not always a user's

A skill that needs to *name* who is acting (to report a reach failure) or to *prove* it can see
a repo must not assume the token is a human's. GitHub refuses `GET /user` to an **installation
token** (an App acting as itself), and `gh api repos/{repo} --jq .permissions` reads **all
`false`** under one even on a repo it reaches (measured, claude-workbench's identity scratch results (`docs/proposals/IDENTITY-SCRATCH-RESULTS.md` there)
case i: "not a reach signal"). So a bare `gh api user` as the "name the identity" fallback turns the
report itself into a second failure, and an all-`false` `.permissions` is not "no access"
(`WB-D24`, `#380`). One procedure, used by every skill that says *"report the actor"*:

1. **Name the actor.** Try `gh api user --jq .login`. It succeeds for a user token, and for a
   GitHub App *user-to-server* token it names the human that App acts for. If it **fails**
   (refused, or any other failure: the cause is not read from the failure), probe whether the token is an
   installation token that reaches the repo (capture first, so a failed call can never read as
   an empty list):
   ```bash
   T=$(mktemp -d) &&
   gh api --hostname github.com --paginate installation/repositories \
     --jq '.repositories[].full_name' >"$T/repos.txt" &&
   gh-identity.sh reach {repo} <"$T/repos.txt"
   ```
   (with `GH_HOST` and `GH_ENTERPRISE_TOKEN` unset, as `token-check.sh`'s recipe has it.)
   `reached` — report `an installation token that reaches {repo}; which App is not established`.
   Anything else (`unreached`, a failed call, exit 2) — report `could not establish the actor:
   GET /user failed and the installation probe did not reach {repo}` and stop. Never report an
   empty or guessed login.
2. **Name the mode only when a decision turns on it.** `gh-identity.sh classify` over the
   *default branch's* committed `identities` (`reference/project-schema.md` § `identities`)
   answers `user` or `app` from a login and numeric id. The *Name the actor* probe reads no login
   under an installation token, but the `user` object of a **write response** the token made (an
   issue or PR it created) does carry the App's `[bot]` login and id, and `classify` returns
   `app` for it (measured, `#380`). That arrives only *after* a first write, so it cannot gate that
   write. What precedes any write is GraphQL `{ viewer { login databaseId } }`, which an
   installation token may call and which names the App (measured, `#476`: `<slug>[bot]` and the
   App's bot user id). A decision that needs the dev App *proven* beforehand — not merely an
   installation that lists the repo — reads it and passes both values to `gh-identity.sh pr-actor`.
3. **Reach is asked of the repo, never of `gh auth status`** (token *scope* is not *reach*).
   `gh api repos/{repo} --jq .permissions` is the user-token probe. When it reads all `false`,
   run the *Name the actor* probe: `reached` is **read** reach only (the repo is listed for the installation;
   not that Issues, rulesets or contents are readable, and not that it may write). A read that
   follows is chained with `&&`, and a 403 there is a stop, never an empty result. **`reached`
   never proves write reach.** The write probe is `git push --dry-run` of the work branch,
   creating nothing (measured: passes with a `contents: write` token, `403 Write access to
   repository not granted` with `contents: read`). It tests the credential `git` holds, not
   which App it is, so by itself it would pass any credential with write: a reviewer-style or
   loop App, or a human's stored login. `ship`'s *Push-reach preflight* therefore runs it in App
   mode with `git` pinned to `gh`'s token (see *Push identity*), after proving through `viewer`
   that the token is the declared `identities.dev_app` (`#476`), so a wrong-App token that can push
   is refused before any branch exists. It keeps a check after the first write that returns an
   actor as the backstop (`#464`): the opened PR's `user` must be the declared
   `identities.dev_app` (`gh-identity.sh pr-actor`), else ship stops and touches nothing further.

Every consumer of this procedure fails closed: a step that cannot be completed is a stop or the
skill's own safe fallback (handoff opens the ledger PR), and its report names which step failed.


### Push identity: `git` and `gh` can silently disagree

On some machines, `git push` and `gh` resolve GitHub identity through **different**
mechanisms and can disagree without either tool reporting it. `gh` prefers a `GH_TOKEN` /
`GITHUB_TOKEN` environment variable when one is set (the common case in CI, devcontainers,
and Codespaces) and otherwise falls back to its keyring's active account; `git push` uses
whatever credential helper is configured (`credential.helper=manager` on Windows, for
example), which can hold a stored credential for a different account — one with no write
access to the repo being pushed to.

**Symptom:** `git push` fails with
`remote: Permission to OWNER/REPO.git denied to <account>` /
`fatal: … 403`, while every `gh` command in the same session — `gh pr create`,
`gh issue create`, `gh api repos/OWNER/REPO --jq .permissions` — succeeds, and
`gh auth status` shows green checkmarks. This is the trap: `gh auth status` reports token
*scope*, never push *reach*, and says nothing about which identity `git` itself will use.
A clean `gh auth status` does not mean the next `git push` will succeed.

**Diagnosis** (a user token; for any other token, name the actor as above first): compare the identity `gh` is using against the identity `git`'s credential
helper will hand over. `git credential fill` prints the **full** credential record,
including a live token as `password=…` — never run it unfiltered where the output is
logged or captured; only the `username=` line is needed here. Its behavior also varies by
helper and, with no stored credential for the host, some helpers prompt interactively
(`GIT_TERMINAL_PROMPT=0` makes that fail fast instead of hanging):

```bash
gh api user --jq .login
GIT_TERMINAL_PROMPT=0 git credential fill <<< $'protocol=https\nhost=github.com\n' | grep '^username='
```

A mismatch is the defect. This is also why a reach preflight (`gh api repos/OWNER/REPO
--jq .permissions`, or `.permissions.push` to check write access specifically) is not
sufficient on its own: it only verifies `gh`'s identity, and reports healthy even when
this split is present, because it never touches the credential helper `git push` actually
uses.

**Per-push workaround** (no global config change, safe to run every time):

```bash
git -c credential.helper= -c credential.helper='!gh auth git-credential' push …
```

In **App mode** a skill's push goes through `bin/app-push.sh`, which spells this pin once
(adding `-c http.extraHeader=`, which clears only the generic key). The pin is not only a 403
workaround there: a push made with the maintainer's own stored credential makes the human the
*last pusher*, and a base whose approval rule sets `require_last_push_approval` then refuses
the human's approval of the App-opened PR — a one-code-owner repo cannot merge it (`#478`).
The pin works only over HTTPS with no URL-scoped `http.<url>.extraheader` set, so the script
refuses (exit 2) any remote whose fetch or push URL is not `https://github.com/` — `pushurl`
and `pushInsteadOf` count; over SSH no helper is consulted — or that has such a header. It also
accepts only `-u` and `-n`, a remote name and plain refspecs, never a force, delete, mirror or
prune spelling. `tests/app-push.test.sh` holds every pushing skill to that script.

**Durable fix** (changes global git config — offer it, don't do it unasked): either
`gh auth setup-git`, or clear the stale credential-manager entry for `github.com` so it
stops resolving to the wrong account.

## Bumping a pinned plugin: the pin is not the registration

A repo that pins a plugin marketplace to an exact ref has **two** pieces of state, and only
one of them lives in the repo:

- the **pin** — `extraKnownMarketplaces.<marketplace>.source.ref` in `.claude/settings.json`,
  which is versioned and reviewed; and
- the **registration** — the same marketplace's entry in
  `~/.claude/plugins/known_marketplaces.json`, which is per-*user*, not per-project, and is
  what actually resolves at load time.

Editing the pin changes what is *declared*. It does not change what is *registered*, and
nothing reconciles the two on its own.

**Symptom:** `claude plugin update <plugin>@<marketplace> --scope project` reports
`already at the latest version (<old>)` right after the ref was edited to a newer tag —
success, no error, no change. `claude plugin marketplace update <marketplace>` likewise
reports `Successfully updated` and leaves the registered ref alone. The session goes on
loading the old tag while every surface reports an enabled, healthy, correctly-pinned
plugin. Two further traps sit next to it: `claude plugin update` defaults to
`--scope user`, so on a project-scoped install it fails outright with *not installed at
scope user*; and if the marketplace was **first** registered without a `ref` at all — a
bare `/plugin marketplace add`, or a user-level `extraKnownMarketplaces` entry — that
registration wins permanently and a project-level pin has never once taken effect.

**What actually rotates the pin** — re-register the marketplace, then re-resolve the
install:

```bash
# 1. edit .claude/settings.json → extraKnownMarketplaces.<marketplace>.source.ref
claude plugin marketplace add <owner>/<repo>@<ref> --scope project
# the uninstall is load-bearing: a plain install short-circuits on "already installed"
claude plugin uninstall <plugin>@<marketplace> --scope project
claude plugin install   <plugin>@<marketplace> --scope project
# then restart or /reload-plugins (not /clear) — a running session keeps executing the copy it started with
```

**Then clear a phantom `.claude/settings.json` change.** The commands rewrite that file with
LF endings. On a Windows checkout with `core.autocrlf=true`, `git status --short` then shows
` M .claude/settings.json` while `git diff` is empty, and `git update-index --refresh` does
not clear it. If so, run `git checkout -- .claude/settings.json` to restore the checked-out
copy: a tree that reads dirty fails resume's clean-tree condition for auto-start,
`archive-sprint`'s precondition and `handoff`'s checks over a change that is not one. If
`git diff` shows a real change, it is yours; leave it.

**Verify by commit, never by version string.** The version is read from the plugin's
`plugin.json`, so it reports whatever that file said at the commit installed — which is
exactly right when the wrong commit is installed, and therefore proves nothing:

```bash
jq -r '.plugins["<plugin>@<marketplace>"][] | "\(.projectPath) \(.version) \(.gitCommitSha)"' \
  ~/.claude/plugins/installed_plugins.json
git ls-remote --tags <marketplace-repo-url> <ref> '<ref>^{}'
```

The two shas must be equal, **and every record whose `projectPath` is this project — each
drive-letter casing — must carry that sha**, not just one of them. For an annotated tag
`ls-remote` prints two lines, the tag object and then the commit on the `<ref>^{}` line;
compare against the `^{}` one. A lightweight tag prints one line, which is the commit.
A version string that matches while the shas differ is the failure this section exists
for, and it is silent in every other surface.

`claude plugin list` reads the same `plugin.json` version, so it is no better a check. Nor
is a new directory under the plugin cache: a bump does not remove the old version's
directory (an unreferenced one is only marked orphaned and swept later), so a new directory
appears even while the session still runs the old code. To see whether a running session
loaded an older *version*, re-invoke a skill — its `Base directory` header names the cache
directory it came from. Cache directories are named by version, not commit, so the header
cannot tell two commits of one version apart; the commit check above is what settles that.

**On Windows, mirror the record onto the other drive-letter casing.**
`installed_plugins.json` keys each project-scoped install by `projectPath` as an exact,
case-sensitive string. A terminal `claude` resolves `C:\…\repo`; VS Code sessions pass
`c:\…\repo`. The install commands in *What actually rotates the pin* rewrite only the
record whose casing matches the CLI's working directory, so the other record keeps the
old version and the other session keeps running it, with nothing warning. When the `jq`
listing above shows **more than one casing** of the project path and one of them lacks
the tag's sha, copy the record that carries it onto the stale one. `fresh` and `stale`
are the two `projectPath` spellings exactly as that listing prints them, so the same
filter serves either direction; close other `claude` sessions first, since one rewriting
this file mid-edit would undo it:

```bash
jq --arg fresh '<projectPath of the record carrying the sha>' \
   --arg stale '<projectPath of the record that does not>' \
   --arg sha '<commit sha from ls-remote, never from the jq listing>' \
  '.plugins["<plugin>@<marketplace>"] as $r
   | ($r | map(select(.projectPath == $fresh and .gitCommitSha == $sha)) | .[0]) as $g
   | if $g == null then error("no record at \($fresh) carries \($sha)")
     elif ($r | any(.projectPath == $stale) | not) then error("no record at \($stale)")
     else .plugins["<plugin>@<marketplace>"] |= map(
            if .projectPath == $stale then ($g + {projectPath: $stale}) else . end)
     end' \
  ~/.claude/plugins/installed_plugins.json > ~/.claude/plugins/installed_plugins.json.new &&
  mv ~/.claude/plugins/installed_plugins.json.new ~/.claude/plugins/installed_plugins.json
```

The filter fails closed: a spelling that matches nothing, or a source record not carrying
the sha, is an error, so the `&&` stops before the `mv` (delete the empty `.new` the redirect leaves).
If no casing carries the sha, re-run the install commands first.
The temp file sits beside the target so it stays out of the repo and the `mv` is a
rename. Then **re-run the `jq` listing**: every casing must now show the sha.

## Issue + label taxonomy

- **No title prefixes.** `[BUG] thing is broken` is noise — the label already says `bug`,
  and the prefix wastes the most scannable characters in the UI. Issue titles are plain
  imperative statements, same as a commit subject.
- **Labels carry structure on three orthogonal axes**, not one flat list. A label picked
  from each axis answers a different question, and mashing them together (the common
  failure) makes filtering useless:
  - **type** — `bug`, `feature`, `chore`, `docs`: what kind of work.
  - **`area/*`** — one per module boundary in *this* repo, using **the same vocabulary as
    its commit scopes**, so an issue and the commit that closes it are filterable by the
    same word. **Derive the list, never copy one.** In the engine these read `area/core`,
    `area/personas`, `area/tools`, `area/flows`, `area/ci`; in another repo they read
    whatever that repo's scopes read. `git log --format=%s | grep -oE '^[a-z]+\(([a-z-]+)\)'`
    is usually the whole answer. Copying a list from elsewhere creates labels for modules
    the repo does not have — which is worse than no area axis, because a label nobody can
    correctly apply gets applied incorrectly.
  - **`status/*`** — `status/blocked`, `status/needs-human`: where it is.
- **Machine-emitted labels stay namespaced under the emitting system** — the automation that
  writes the label, which is **not** reliably the repo it writes in. A repo that runs an
  engine of its own namespaces under the engine (`loop-engine/needs-human`, in a repo not
  called `loop-engine`); a repo whose only emitter *is* its own automation namespaces under
  itself (`bedrock-serverless-rag/needs-human`). "Namespace by repo" reproduces the second
  case correctly and the first case wrongly, which is why it survives as a mental model —
  and why this bullet states the rule as *the emitter*, twice, rather than trusting one
  example to carry it. This is the load-bearing rule: a namespace makes "did a human or a
  robot put this here?" answerable at a glance, without a separate identity for the machine.
  Never let an automated writer apply an un-namespaced label.

  **The exception is exactly where that rationale does not apply:** a bot that *has* its own
  identity — Dependabot posting as `dependabot[bot]`, applying the ecosystem-standard
  `dependencies` — already answers the question the namespace exists to answer. Namespacing
  those is churn that breaks the tooling's own conventions. The rule targets automation
  writing labels *as you*, which is the case a reader cannot otherwise detect.

## Prose economy — the deep record has a lifecycle

`/way-of-working:handoff` bounds the cursor; nothing bounds the deep record (`{roadmap}`,
a file-kind `{backlog}`) unless these rules do. An unbounded deep record is a standing
per-session token cost — every load-bearing doc is context some session must load — and
every hand-maintained claim in it is a future stale claim a critic round will be spent
correcting. The recurring defect class this section exists for: prose restating current
state that then drifts, and correction narratives accreting on top of corrections.

- **Derive, don't restate.** A fact a command can produce — a count, a list, a status, a
  live setting — is never hand-written into prose. Name the deriving command instead, or
  state nothing. A number in prose is a stale claim with a fuse. If several docs need the
  same figure, that is the signal to add the deriving command, not to copy the number.
- **One authoritative site per fact.** Every other mention points at it. Two statements of
  the same fact are a drift pair, and a critic finding one skewed corrects it by deleting
  the copy, not by synchronizing it.
- **Corrections replace text.** What was wrong and why belongs in the commit message and
  the PR — immutable, greppable — not inline. Strikethrough-and-annotate is reserved for a
  stale claim that still gates an open action, and it comes out once that action closes:
  an annotation that outlives its gate is text to delete, not history to keep.
- **Evidence, then prose — trust but verify.** A claim about live state records the
  command and the date it was read. A correction is re-verified as hard as the claim it
  replaces — fix rounds mint defects of their own, which is why
  `/way-of-working:critic-gate`'s convergence rule never stops on the round that applied
  fixes. A claim that cannot be evidenced is recorded as a risk the human accepts, not
  as fact.
- **The deep record is not append-only — it is compacted.** Resolved *or declined* backlog
  items and completed execution narrative belong in an archive file **beside the live
  record and tracked in git** — not
  under `.ai/`, whose archive holds git-ignored cursor snapshots and would drop the content
  at the next clone (tracked `.ai/parked/` is not a counter-example: it holds in-flight
  state, not archives — `reference/workflow.md` § *Two sprints, one cursor*). Moving
  them is content-preserving — same text, same ID anchors — so
  existing citations still resolve by grep, and anything that reads the live record to
  learn what is already decided reads the archive alongside it. The live record holds:
  open items, locked decisions, whatever status table or index other tooling orients from,
  and a current-action section that fits on one screen — compaction moves *finished
  narrative*, never the surfaces a reader navigates by. The destination is **derived, not
  configured**: the `_archive` sibling of the live file's own path, by the single rule in
  `reference/project-schema.md`, applied to a file-kind `{backlog}` and to `{roadmap}`
  alike. One rule, so the archive is always beside the record it came out of and no repo
  has to name a path — and so a repo with no sprint cadence can compact its roadmap too.
- **Write to the artifact's budget.** A decision is a decision-log entry stating the choice
  and why — not a narrative of how it was reached. A lesson that must survive is a rule in
  the relevant skill or convention, not a war story where it happened. And when the mistake
  a paragraph warns against has actually occurred, the durable form is a check that fails
  the same way the prose warns — a `{gates.green}` check, either a new entry or a new case
  inside one, verified by a deliberate regression — after which the paragraph shrinks to a
  pointer at the check. Where the class is worth blocking a merge rather than only a local
  run, promote it to CI as well: `{gates.green}` is a local pre-check, and CI on the PR is
  the gate of record. Promoting means all three, in order — a workflow job whose id is the
  check name, that name added to the repo's GitHub ruleset, and only then the name
  mirrored into `{ruleset.required_checks}`, which records GitHub's state rather than
  requesting it. Mirror it first and every later session reports the ruleset as weakened.
  Prose is the interim control for defects that have not yet earned a gate.

## Definition of Done
A unit of work is done only when: formatting + lint + the full test suite pass; new validated boundaries have negative-input tests; dependencies are pinned and CVE-clean with the SBOM regenerated; no unjustified `# noqa`; and no secrets in any committed file. For managed repos the repo's own `sprints/GLOBAL_DEFINITION_OF_DONE.md` (if present) extends, never relaxes, this bar.

**A Definition of Done enumerates the unit's blocking preconditions, not only its
deliverables.** A DoD listing outcomes alone is how a precondition reaches a completion
review unaudited: the deliverables are all visibly shipped, so the unit reads as done while
the thing that was supposed to gate it was never checked.

### Blocking preconditions

A **blocking precondition** is something that must be true *before* a specific step may run
— a backup taken and verified restorable before a destructive migration, a snapshot copied
off-host before an irreversible transfer, a rollback path exercised before a one-way change.
It is not a deliverable. It gates one.

Two rules, and they are cheap:

- **Mark it.** In a sprint plan, prefix the criterion with the literal word **`BLOCKING:`**
  and name the step it gates. Under `{planning.kind}: github_milestones` there is no
  `sprint_plan.md` file — the marker lives in the **milestone description** instead, in the
  same shape (`reference/project-schema.md` § `planning`). A convention that can be
  recognised mechanically is what lets a later check find every one of them without
  re-reading the plan for intent — and "read the plan and use judgment" is precisely what
  fails, because a satisfied criterion and a skipped one look identical in hindsight.

  ```markdown
  - BLOCKING: <state is copied out-of-band and verified restorable>
    — gates: <the first apply of this sprint, and again before Task 3>
  ```

- **Record its satisfaction where the work that relies on it lands.** A blocking precondition
  records its satisfaction **in the PR that relies on it** — one line naming what was done,
  when, and how it was verified. Evidence that lives in someone's memory has already failed
  for the next reader; six weeks later, "we definitely did that" is indistinguishable from
  "we definitely meant to."

**Prefer a precondition that can be evidenced.** A criterion whose satisfaction leaves no
artifact — no command output, no PR line, no tracked item — cannot be audited by anyone,
including its author. If it genuinely cannot be evidenced, say so in the plan and treat it as
a risk the human is accepting, not as a gate that was met.

### A fixture that passes on a broken implementation is not coverage

The DoD's "full test suite" counts only fixtures that turn red when the rule they name is
removed. A fixture that exercises a feature inside a context that *independently produces
the same answer* passes whether or not the feature is there at all — and it reads exactly
like a fixture that is worth something, which is what makes it dangerous: it files the
feature as covered while guarding nothing. The verdict attaches to the **(fixture, rule)
pair**, not the fixture: one row can genuinely pin one rule and be decorative for another,
and the remedy there is a new fixture beside it, not deleting the row.

- **A fixture counts only if removing the rule it names turns *it* red — verify by doing
  it, not by reading it.** The rule is pinned if any fixture catches the deletion; a
  fixture that claimed the rule but stayed green while another row caught it is still
  decorative.
- **Beware the fixture that tests feature X inside a context that already yields the same
  answer without X.** This is the common failure, not the exotic one: realistic fixtures
  carry realistic context, and the context is exactly what can shadow the feature.
- **Only mutation separates a real fixture from a decorative one — and the unit of
  mutation is the sub-expression, not the line.** Deleting a whole line answers a
  different question whenever the line carries more than the rule. Bound every run — a
  mutant can hang instead of failing, and a hang counts as detected — and check that a
  red mutant still runs at all before counting it as a pin: one that no longer parses
  pins nothing.
- **Read the survivor list; never just count it.** An uncaught mutant is either a missing
  fixture or a survivor recorded with its own reason — a survivor asserted harmless
  rather than checked is how a live guard stays filed as covered. Record the sweep's
  scope as what was measured — a list of mutated sites is evidence; "every rule" is a
  claim the sweep cannot make — and re-derive the result by running the sweep, never by
  carrying a previous result forward.

Scope: fixtures a unit of work adds or changes are verified within that unit. Sweeping a
whole standing suite is a tracked obligation on its own cadence, recorded when it runs —
not a per-unit gate.
