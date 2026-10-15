# Decisions log — `glunk-works/claude-workbench`

This repo's own decision log, in the `WB-D*` namespace. It restates the four decisions
that created this repo — locked in `glunk-works/bounty-infra`'s SW sprint planning pass
(2026-07-22) as **BI-D10..D13** — as this repo's own record, since this repo is where they
take effect. Full reasoning and the task breakdown that implements them:
`bounty-infra`'s `sprints/SW_way_of_working/sprint_plan.md` and
`docs/hardening_roadmap.md` § *Locked decisions (SW planning pass, 2026-07-22)*.

- **WB-D1 (= BI-D10) — the shared way of working ships as a Claude Code plugin, tag-pinned.**
  Each consuming repo commits a `.claude/settings.json` naming this repo as a marketplace
  and enabling the `way-of-working` plugin; skills, agents, hooks, and the Global
  Conventions arrive with it as a **native** mechanism — no sync script, no submodule, no
  vendored copies. A repo-local skill of the same name shadows the plugin's, which is the
  extension seam. **Tag-pinned, never a branch** — a mutable ref on something that shapes
  agent behavior is a handoff to whoever moves it. (Rejected: a git submodule — Claude Code
  does not discover skills nested in a submodule path without symlinks or a sync step, and
  submodules are friction on Windows. A Copier template — duplicates files per repo, DRY at
  the template level rather than runtime. A `raw.githubusercontent` URL — uncacheable,
  unpinnable, silent when upstream moves.)
- **WB-D2 (= BI-D11) — `.ai/project.yml` is the parameterization seam.** A shared skill may
  **never name a repo-specific value**; it reads the contract instead. Every literal removed
  from a skill becomes a schema key (`reference/project-schema.md`), enforced by a
  grep-based CI job in this repo, not by convention. If a value cannot be expressed in the
  schema, the skill is not portable and belongs in the consuming repo, local. A repo-local
  override of a shared skill is a **bug report against the schema, not a fork** — the
  override shadows the whole skill and silently stops receiving upstream fixes. The frozen
  review header/attestation strings live in the schema **as data**, precisely so they are
  pasted rather than retyped. (Rejected: prose in a `CLAUDE.md` — unstructured, unverifiable
  by a skill. `project.yml` as truth with `CLAUDE.md` rendering it — adds a sync obligation
  between two files, exactly the failure mode being eliminated.)
- **WB-D3 (= BI-D12) — the plugin holds only what works in any repo.** The skills
  (`resume`, `handoff`, `critic-gate`, `ship`, `pr-checks`, `archive-sprint`, `retro`,
  `park-sprint`, `unpark-sprint`) +
  the 4 general agents (`architect`, `coder`, `security-critic`, `docs-consistency`). Anything
  that encodes one product's internals rather than a way of working stays local to that
  product's own repo. (Rejected: shipping everything gated by `project.yml` — ships
  definitions referencing tools most repos do not have. Skills-only with agents kept local —
  agents are the layer most worth sharing; per-repo re-authoring of them is the problem this
  repo exists to remove.)
- **WB-D4 (= BI-D13) — `bounty-infra` pilots; the source repo migrates after.** The pilot
  needs to be a genuinely different shape from this plugin's source material — different
  language stack, different CI check taxonomy, no fresh-session review-gate CI check — so
  that the parameterization is forced to be general rather than flavored by the repo it was
  extracted from. In particular, `review.ci_gate: null` must be a clean path through every
  skill for a repo that has not wired up a review gate. The source repo keeps its own working
  local copies of these skills/agents until a real sprint has run cleanly through the plugin
  at the pilot, closing the duplication window deliberately rather than immediately.
  (Rejected: migrating the source repo first — touches the repo everything else depends on
  before the schema has been proven anywhere.)

- **WB-D5 — a shared agent ships the taxonomy, never the instances.** Found while
  generalizing the 4 agents (`v0.2.0`), and it is a different problem from the skills. The
  skills' coupling was **values** — check names, commands, paths — each of which became a
  schema key cleanly. The agents' coupling is **knowledge**: the source repo's module
  boundaries, its named subprocess surfaces, its specific trust boundaries, its specific
  high-value doc claims. None of that is expressible as a schema key, and paraphrasing it
  into generic advice would have shipped an agent that reviews every repo against one repo's
  invariants. So each agent now carries the *shapes* that reliably hold invariants (import
  layering, I/O ownership, subprocess surfaces, credential holders, taint source and sink
  classes, the claim shapes that drift in prose) and **builds the instance list at spawn
  time** by reading `.ai/project.yml`, the consuming repo's `CLAUDE.md`, `{threat_model}`,
  and the guarding tests. An agent that cannot read the contract reviews only what needs no
  contract value and says so — it never substitutes a threat model it remembers.
  Consequence, accepted: the agents are **thinner** than the originals and start colder, and
  that is the correct trade — a warm start against the wrong repo's map is worse than a cold
  start against the right one. The source repo's specific invariants are not lost; they live
  in that repo's own `CLAUDE.md` and threat model, which is where the agent now reads them.
  (Rejected: schema keys enumerating a repo's invariants — that is the repo's `CLAUDE.md`
  restated in YAML, a second copy of exactly the kind WB-D2 exists to eliminate. Rejected:
  keeping the rich source-repo agents in the plugin and letting other repos ignore the
  irrelevant parts — an agent asserting a boundary the repo does not have produces confident
  false findings, the most trust-destroying output a critic can emit.)

- **WB-D6 — the pilot's Task-5 real-work exercise, dispositioned.** The bounty-infra pilot
  ran a genuine piece of work end-to-end through the plugin loop (SW Task 5, sessions 6–7)
  and logged six findings. Their disposition, per the *Overriding is a bug report* rule
  (two outcomes only — a schema seam, or not-portable — never a local override):

  - **F1–F4 were already fixed and did not reproduce against the pinned tag.** The four
    "hardcoded loop-orchestrator value" findings (a stale required-check list, a
    `docs/migration_roadmap.md` path, three `.ai/context/*.md` references) all describe the
    **`v0.1.0` skeleton**, whose skills were copied *as-is, still coupled on purpose* (WB-D3
    /Task 2). The generalization that fixes every one of them landed in `v0.2.0`
    (`{roadmap}`, `{ruleset.required_checks}`, `{models}`, `reference/workflow.md`).
    Session 6 reproduced them only because the harness served a **stale `v0.1.0` local
    checkout** despite the consuming repo pinning `v0.2.0` — a plugin-cache staleness
    problem, not a portability defect. **Disposition: already-fixed-upstream via existing
    schema keys; no skill change.** The two real actions are (a) the consuming repo bumps
    its pin and clears the stale checkout to force a re-fetch, and (b) a regression guard so
    the same *class* of leak is caught mechanically next time (below). This is the plan's own
    "tag-pinning ⇒ updates are opt-in ⇒ never" risk in a sharper form: even an explicit pin
    bump was not honored by the local cache, so a pin change must be paired with a cache
    clear until the mechanism is understood.

    **Resolved during the `v0.5.0` release — the mechanism is now understood, and the
    guidance above was imprecise.** A pin bump is **three** steps: edit the ref, run
    `claude plugin update <plugin>@<marketplace>`, and **restart the session** — `update`
    itself reports *"restart required to apply"*, and a running session keeps executing the
    copy it started with. Verification is `claude plugin list`, **not** an inspection of the
    cache directory: the cache keeps one directory per version and does not remove the old
    one, so a `0.1.0` directory sitting beside a `0.5.0` directory is normal and proves
    nothing. Confirmed live — a session mid-release was served skills from the `0.1.0`
    directory (recognisable by pre-`v0.4.0` bare command names) while `claude plugin list`
    correctly reported `0.5.0`. This is why the failure reads as "the fix did not work"
    rather than "the plugin did not reload."

  - **The coupling gate was blind to path-shaped literals, now less so.** F1–F4's shared
    root cause: the `coupling` grep matched repo/org **names** and a curated string list, so
    a hardcoded *path* that is not a repo name ("zero hits") proved only that no name leaked.
    `scripts/coupling-check.sh` gains a **Tier 3** of structural literal *shapes* —
    `docs/<...>roadmap.md` (always `{roadmap}`) and `.ai/context/<file>.md` (either moved
    into this plugin's `reference/` or the consuming repo's local truth, referenced as the
    bare directory, never a named file). A bare `.ai/context/` with no filename stays
    legitimate and unmatched. Check **names** are deliberately *not* added: they appear in
    illustrative example output (`/way-of-working:pr-checks`' report shape), so grepping them false-positives;
    check-name coupling is caught instead by `/way-of-working:resume` and `/way-of-working:pr-checks` reading
    `{ruleset.required_checks}` and reporting *inconclusive* on a mismatch. A grep cannot
    prove portability — it catches how portability actually rots — and Tier 3 narrows the
    blind spot without pretending to close it.

  - **F5 — `/way-of-working:critic-gate` gained a third proposal row: a newly-added doc.** A brand-new
    load-bearing doc cannot already be in `{load_bearing_docs}`, so keying the docs critic
    only off that set silently skipped a doc on the commit where it is most worth a look —
    its first version. **Disposition: a portable behavior fix, no new schema key** — the
    added/edited split is derivable from git (`--diff-filter=A`), so it derives from existing
    keys rather than growing the schema (the "a schema that grows a key per repo has failed"
    corollary). The row proposes `docs-consistency` (plus `security-critic` for a
    security/credential/operational procedure) and flags adding the file to
    `{load_bearing_docs}`; it remains a proposal the human confirms or trims.

  - **F6 — `/way-of-working:handoff` step 5's branch rule clarified, not exempted.** The finding argued that
    a "stacked" handoff (a second session syncing the cursor while the first session's PR is
    still open) needs to commit the sync onto the code branch, because `{pr_base}` lacks that
    PR's content. **Disposition: the finding's rationale is wrong and the rule is right** —
    `.ai/next-steps.md` is *regenerated wholesale* (step 4), not patched, so it carries no
    code context and a fresh `{pr_base}`-cut branch always applies. Step 5 now says so
    explicitly, closing the ambiguity that led the pilot's own history to deviate (`cb6d698`)
    toward the default (separate docs-only PR), rather than adding a permissive exception that
    would license bundling cursor churn into code-PR reviews.

- **WB-D7 — cursor freshness is a content question, never an ancestry one.** `/resume`'s
  drift check decides whether the tree still matches what the cursor describes, and it must
  answer that under **squash-merge**, which is this project's default merge method. Squash
  replays a branch as a brand-new commit object, so the branch tip a cursor recorded never
  becomes an ancestor of `{pr_base}` — not when the PR merges, not ever. Any check keyed on
  SHA equality or on commit *ancestry* is therefore structurally wrong here, and both of the
  first two attempts were: `v0.3.0` compared `last_commit` to HEAD by SHA, and `v0.4.0`
  replaced that with a commit-*range* carve-out (`git rev-list --count <last_commit>..HEAD`
  is 1, `git diff --name-only <last_commit>..HEAD` is the cursor file). The range form works
  only while `last_commit` is an ancestor of HEAD, which it is not whenever a
  `/way-of-working:handoff` runs with a code PR still open — an ordinary occurrence in a
  one-task-per-PR flow, not an edge case, and it was reproduced live within one tag of the
  fix landing. The check is now a **two-argument `git diff <last_commit> HEAD`**: it compares
  trees, is indifferent to ancestry, and reports exactly the cursor file once the work has
  squash-merged. The allowlist is `.ai/next-steps.md` plus files under `.ai/parked/` — a
  parked sprint's snapshot, which describes a different sprint and so cannot invalidate the
  live `next_action` (`#87`). (Rejected: widening it to
  "docs-shaped paths," which would survive squash equally well but is a genuine loosening —
  a roadmap or sprint-plan edit between sessions can invalidate the very `next_action` that
  auto-start is about to run unattended, which is the one thing the drift check exists to
  catch. Rejected: having `/way-of-working:handoff` record `last_commit` *after* its own
  commit — the same squash property mints a different SHA on `{pr_base}`, so the mismatch
  returns, and `last_commit` would stop meaning "the commit whose work this cursor
  describes.") Consequence, accepted: while a code PR is still unmerged, its files appear in
  the path list and `/resume` waits. That is a true report — the cursor describes work
  `{pr_base}` does not have — not a false alarm.

- **WB-D8 — a backlog may name its owning repo; a backlog *file* may not.** Three adopting
  repos hit the same seam at once: the record-pointing keys are all repo-relative, so a
  satellite repo whose findings are tracked in a **hub** repo — one repo carrying the roadmap
  and backlog for a family of sibling module repos — cannot say so. The three available moves
  were all bad: a relative path escaping the repo (works on one checkout, breaks in CI), a
  `kind` that is factually wrong (findings route into a channel nobody reads), or `null`
  (honest, but the skills then have nowhere to route a finding in a repo that demonstrably
  has somewhere). Per the *Adding a key* corollary this is a **shape**, not a per-repo key —
  one seam three repos hit, not a bespoke value for one of them — so it earns a key.

  **The key is `backlog.repo`, and it is supported only with `kind: github_issues`.** That
  asymmetry is the whole design, not a limitation to fix later. With issues, cross-repo is
  free in **both** directions — `gh issue list --repo X` and `gh issue create --repo X`, no
  clone, no branch, no PR, no second review surface, no cross-repo push identity. With a
  backlog *file*, reads need an API and **writes need a PR opened against a repo whose owner
  did not ask for it**, which is a genuinely expensive and differently-governed act. The
  cheap half is therefore shipped whole rather than shipping both halves crippled: a
  `github_issues` backlog works completely, and a `file` backlog stays repo-local.
  (Rejected: cross-repo file reads with writes reporting-and-stopping — the write case is the
  one the reporting repos were actually blocked on, and a read-only file pointer leaves it
  exactly as broken as the `null` workaround while charging a schema change for it. Rejected:
  declining the seam entirely — hub-and-spoke is an ordinary shape for an org with a
  monorepo-ish hub and satellite module repos, and this project is arguably that shape too.)

  **Every cross-repo call establishes reach before believing its answer**, per `WB-D7`'s
  sibling lesson: GitHub answers an unreachable resource with `404`, not `403`, so an
  unreachable backlog is indistinguishable from an *empty* one — and "nothing is tracked"
  is exactly the wrong conclusion to hand a retro whose first step is reading what has
  already been decided. `gh api repos/{backlog.repo} --jq .permissions` disambiguates it in
  one call. Deliberately not extended to `roadmap`, `threat_model`, or `decisions.log`: those
  are strings today, mappings only in a breaking change, and nothing has yet demonstrated it
  needs them.

  **Confirmed by the reporting repos (2026-08-10): the hubs can expose findings as issues**,
  so the `github_issues` path is a complete answer for the half they were blocked on, and the
  breaking file-based half is **not scheduled** — not merely deferred. What that leaves open
  is narrower than the original report: a satellite still cannot *read* a hub's `roadmap`,
  `threat_model`, or `decisions.log`, because a document is not a finding and cannot be
  routed to an issue. No repo has yet reported that gap costing anything, and until one does,
  the honest position is that a required `schema_version` and two converted keys are a real
  cost paid against a hypothetical benefit. Reopen this if a consuming repo hits the read
  half; the evidence to design against will arrive with it.

- **WB-D9 — a blocking precondition is marked, and records its satisfaction where the work
  that relies on it lands.** `/way-of-working:archive-sprint`'s verification ledger was the
  only place in the plugin asking *"is this claim backed by evidence?"*, and it is scoped to
  one shape: a **deliverable** marked complete that was only hermetically verified. Nothing
  covered the other shape — a **precondition** gating a specific irreversible act, whose
  satisfaction is recorded nowhere. Such a criterion can be fully satisfied and remain
  **indistinguishable from one that was skipped**, which is the same thing as not having it.

  The fix lands in three places because the gap has three moments, and only the first two
  were ever proposed as sufficient on their own:

  - **`reference/conventions.md` defines the marker** (`BLOCKING:` + the step it gates) and
    extends the Definition of Done to enumerate preconditions, not only deliverables. This is
    **load-bearing, not framing**: the plugin owns no sprint-plan *format* — `sprints_dir` and
    `pointers.sprint_plan` are locations — so without a marker convention a skill has nothing
    to key on and degrades to "read the plan and use judgment," which is exactly what failed.
    `conventions.md` is the right home because it is the plugin's own shipped convention set,
    already dictating commit grammar, branch names, and the label taxonomy.
  - **`/way-of-working:ship` records satisfaction in the PR that relies on it** — the moment
    of truth, and the only one that catches the gap *in time*. It reads `pointers.sprint_plan`
    from the cursor rather than prompting from memory: a prompt answered from recall is a
    weaker instance of the defect it is meant to close.
  - **`/way-of-working:archive-sprint` precondition 5 catches what got through** — mechanical,
    at close, keyed on the marker. Late is where it is most expensive to discover, but
    late-and-mechanical beats a human happening to ask.

  (Rejected: the `architect` agent checking it in `/way-of-working:critic-gate` — this is a
  documentation-of-evidence question, not a diff question, and a diff reviewer has no way to
  see it. Rejected: guidance alone, on the reasoning that plans should not use unverifiable
  blocking criteria — true and now stated, but nothing would enforce it, and the observed case
  had a criterion that *was* satisfied and still left no trace. Rejected: giving
  `/way-of-working:ship` the whole sprint plan to reason about — it reads one cursor field for
  one marker, which is a bounded read, not a scope increase.)

- **WB-D10 — a deterministic predicate moves to a tested script; `bin/` is how a plugin ships
  one.** Filed as issue #21 after `v0.5.0`: three of five findings that `/way-of-working:retro`
  raised upstream were mechanical procedures whose *English* was subtly wrong (`WB-D7`'s own
  drift check shipped wrong twice). The narrower claim, not "prose is bad": where a skill
  describes a computation with one correct answer given its inputs, prose buys nothing and
  costs the ability to test it — that passage should be a script the skill *invokes*, keeping
  only the policy (what to do with each answer) in prose.

  The proposal's own step 1 was to verify its precondition before extracting anything:
  `${CLAUDE_PLUGIN_ROOT}` is set for a `hooks.json`-invoked hook (the harness spawns it
  directly) but **confirmed empty** in the shell a skill's own Bash tool calls run in — a
  skill cannot reliably build `"${CLAUDE_PLUGIN_ROOT}"/scripts/foo.sh` paths. That would have
  stopped the effort at step 1, except a second mechanism is already documented and stable: a
  plugin's `bin/` directory is added to the Bash tool's `PATH` while the plugin is enabled, so
  a script placed there is callable by **bare name** — no path-building, no missing-variable
  failure mode, and arguably better ergonomics than the interpolated form the issue proposed.

  Landed this pass: `plugins/way-of-working/bin/cursor-drift.sh`, the `WB-D7` classifier,
  called from `/way-of-working:resume` step 2 as `cursor-drift.sh <last_commit>` and proven by
  `tests/cursor-drift.test.sh` — real throwaway git repos exercising the squash-merge case
  `WB-D7` names, not a mock of git's behavior. A fixture catches a **wrong answer**; the
  `invariants` regex only ever caught one **wrong shape** of answer (the range form
  literally reappearing), so both stay: the fixture is authoritative, the regex is a cheap
  independent check that now also scans `bin/` scripts, not just prose. `coupling-check.sh`'s
  scope widened to include `bin/` alongside `skills/` and `agents/` — it is shared, executed
  plugin code under the same no-repo-specific-literal rule. A new `tests` CI job runs the
  fixtures on every PR but was deliberately **not** added to `{ruleset.required_checks}` in
  this pass — that is a live branch-protection change, made against a running repo rather
  than reviewed in a diff, and `WB-D8`'s own precedent is to defer exactly that kind of
  change until there is a concrete reason to make it, not as a side effect of an unrelated
  pass.

  Deliberately **not** done in this pass, per the issue's own staging: the
  branch-prune block that `/way-of-working:resume` and `/way-of-working:archive-sprint` both
  carry (each under its own *Prune squash-merged local branches* step — cite the heading, not
  a number, which renumbers whenever either skill gains a step, as `archive-sprint` did when
  compaction landed), byte-identical in both skills today, is a stronger duplication case
  but the issue's own order asks for one
  extraction to run through a real `/way-of-working:resume` session before a second one
  starts — this repo consuming its own plugin (`WB-D1`) makes that the very next tag-pinned
  session, not a hypothetical one. (Rejected: reaching for `${CLAUDE_PLUGIN_ROOT}` with a
  documented workaround, e.g. having the *hook* export it somewhere a skill could read it —
  no such channel exists between a hook process and the agent's own Bash tool shell; they are
  different processes. Rejected: shipping the script under `scripts/` like the repo's own
  gates — those run in CI and this repo's own shell, never inside a consuming repo's session,
  so they cannot be what a plugin skill invokes portably.)

  **Second landing:** `bin/entry-anchor.sh` + `tests/entry-anchor.test.sh` (issue #66),
  invoked from `/way-of-working:ship`'s ledger-conflict rule. Same shape, same reason, and
  the sharpest evidence yet for the decision itself — the predicate was attempted in prose
  in three consecutive `/way-of-working:critic-gate` rounds and was wrong in a **different**
  direction each time, so no fourth round of careful reading was going to converge. The
  design decision that predicate carries is `WB-D11`.

  **Third landing:** `bin/review-gate-state.sh` + `tests/review-gate-state.test.sh` (issue
  #91), invoked from `/way-of-working:pr-checks` step 3 and
  `/way-of-working:architect-review` step 8. A review gate can reach a commit as a
  check-run or as a commit status, and the prose read only the first; one predicate now
  resolves both surfaces under a stated precedence (any success wins, pending beats
  failure, exact name), so neither caller re-derives the rule.

  **Fourth landing:** `bin/review-base-anchor.sh` + `tests/review-base-anchor.test.sh`
  (issue #126), replacing the ~20-line preflight chain PR #123 first wrote inline in
  `/way-of-working:architect-review`. That chain's own critic gate needed four hand-verified
  rounds, plus throwaway scratch scripts, before it shipped — each round finding a *new* git
  edge case (a tag shadowing the remote-tracking ref, a tag hijacking a short-name fetch, a
  PR base reaching `git switch` as an option, a failure path printing nothing with a stale
  value on the `STOP` line, a fork with two remotes carrying the same branch) rather than
  converging, the same shape `WB-D11`'s predicate went through. The script also keeps the one
  behavior the inline chain had that the issue's own proposal didn't ask for back:
  `REVIEW_BASE_ANCHOR_ALLOW_UNDECLARED_BASE`, the human override for an undeclared
  `migration_base` base — still a deliberate re-run after reading an unmodified `STOP` line,
  never read from PR content.

  This extraction's own pre-handoff critic pass (architect + security-critic) then found
  four more edge cases in the *new* script, each reproduced live rather than taken on a
  critic's word: `-Cmain` reaching `git switch` parses as `-C main`, a force-reset of
  whatever branch is named `main`, not a switch to a branch literally named `-Cmain` — the
  `check-ref-format` guard is what stands in front of this, so its output is now compared
  back to the value it was given, not just its exit status; a local branch already AHEAD of
  `origin`'s tip passed `--ff-only` as a silent no-op, so "verified synced" was not, in
  fact, always true; the `git show <rev>:./.ai/project.yml` read resolved relative to the
  CURRENT directory rather than the repo root, so the script now `cd`s to
  `git rev-parse --show-toplevel` before doing anything else; and the override above was
  first shipped as a bare on/off switch, which a PR author could silently ride past by
  retargeting the base between the human's read of an unmodified `STOP` line and the
  deliberate rerun — it was pinned, in that first fix, to the exact base name the human
  saw, printed and reread, not a boolean.

  A second, human-authorized round on the same pass (past its own stated 2-round cap, on
  the human's explicit go-ahead — the *Convergence* rule that crossing it is their call,
  not a reason to keep looping unasked) closed what the first round's own fixes had left
  open. The re-spawned critics independently converged on the same shell-portability edge
  case — `cd "$(cmd)" || stop` tests only what `cd` does with an empty string on `cmd`'s
  failure, not `cmd`'s own exit status, and some shells treat `cd ""` as a no-op rather
  than an error — now split into `TOP=$(cmd) || stop; cd "$TOP" || stop`. The architect
  round also caught a gap in its OWN round-1 fixture: the `-Cmain` regression test asserted
  `main`'s tip was unmoved, but with `HEAD` already on `main` in that fixture, a `-C main`
  force-reset lands on the same commit it started from — a no-op that the equality check
  could never have told apart from the guard actually working. Reproduced live with `HEAD`
  moved to a throwaway branch first: `main` visibly moves under the guard's removal, and
  the strengthened fixture now catches it (confirmed by mutation). Security-critic's own
  round 2 found the base-name-only override was still too wide: pinned to a NAME, one
  human's approval for one review could be replayed by ANY other PR, in any other repo,
  whose base happened to share that name — a long-lived branch name like `release/2` is
  easy to guess, and nothing tied the string to the specific review it was typed for. The
  override is now `repo#N:base`, scoped to the one review it was actually decided for.
  fixture.** `/way-of-working:ship` needs to know whether a ledger's `_archive` sibling
  carries a removed item *at its own entry anchor*. Two lines are byte-identical in shape —
  a wrapped citation continuing onto a new line, and an unmarked sub-entry — so the question
  is not answerable exactly without a Markdown block parser, and a wrong guess by an
  approximation of one is worse than no guess.

  The rule: where a predicate cannot be exact, choose the direction by **which error is
  recoverable**, not by which is rarer. Here a *miss* falls through to the keep-both default
  and a resurrected entry can be deleted again by hand; a *false match* reports a live item
  as already archived and drops it from the live file, on a branch that is then squash-merged
  and pruned — leaving its own commits unreachable, recoverable from nowhere.

  **Choosing the direction is not the same as implementing it, and the rule that implements
  every earlier version of it was wrong inside this pass's own critic gate — always the same
  way.** Each asked whether the *line* looked like an entry, and each was defeated by a
  structure that contained it. The first asked "is there markup before the id?", believing a
  continuation line offers only whitespace; but a ledger cites ids *in* markup (`retro`
  mandates the citing shape), so a **bolded** or `backticked` id on a continuation line has
  markup before it too. The second asked "does the line open a **block**?" — and a block
  quote is a block, so every line of a quoted paragraph qualified. The third still accepted a
  citation written as a **nested list item** beneath its own parent entry, which is exactly
  what the citing mandate produces. The fourth finally tracked containers, but closed a fence
  on any delimiter line — so a shorter run or an info string ended the block early and exposed
  the example entries inside it. The same failure, one level in.

  Only the first was reproducible against this repo's own `docs/decisions.md` — it carries no
  blockquotes, and no ledger here nests an id-bearing entry — so the rest were reproduced on
  constructed archives. Worth recording precisely, because "reproduced against our own files"
  is a stronger claim than "reproduced", and this entry asserted the stronger one twice before
  it was true: first of the blockquote shape, then of the nested shape, citing a file whose
  nested list items carry paths rather than ids. A critic supplied the citation; strengthening
  it on the way into prose was mine.

  That is `WB-D10` arriving one level deeper, and the durable part of this entry: **a script
  is not a tested predicate — its rules are.** The predicate had a fixture suite and a green
  gate through every one of those defects, and several of its own fixtures asserted one of
  them as correct behaviour. What found them was mutation and adversarial shapes, never the
  suite passing.

  **The rule that works stops asking about the line and requires a position.** An entry
  anchors only at **column 0, outside every container the script tracks** — because
  indentation, quoting, fencing, commenting and front matter are all ways Markdown says *this
  line belongs to something else*, and none is legible in the line's own marker. None of them
  marks *this file's own* entry, which is the question the caller asked. Fences and comments
  are opened permissively and closed strictly: a missed open exposes content, a missed close
  only skips more of the file. Front matter is the deliberate exception and the strictest test
  in the script — line 1, column 0, nothing else on the line — because a `---` anywhere else
  is a thematic break, and treating one as a container would blank the rest of the ledger.

  The full cost is named in the script's header rather than restated here — **false matches
  included, and stated as a floor rather than a proof.** Every broken version offered a cost
  section listing only misses while carrying an unlisted false match; after every revision so
  far did that, the
  honest claim is the general shape — any container this does not track presents its lines as
  if they were entries — plus the instances known today, not a closed list.

  **When enumeration is legitimate — and the two answers this pass got wrong first.** Three
  prose rounds had failed by listing markers, so the first cut treated *all* enumeration as
  the defect; the second reintroduced a list and justified it as "the closed set CommonMark
  defines". Both were wrong, and the blockquote bug is the proof of the second: `>` is
  unimpeachably a CommonMark block start, and admitting it is exactly what reopened the hole.
  **Specification membership is not what makes a list member safe.** What matters is the
  direction a wrong member fails in — here, every marker *omitted* from the list makes an
  entry invisible rather than spurious, so omissions can only cost recall. (The list can
  still cost precision through what it *admits* — a lazy paragraph continuation beginning
  with a marker — which is a separate defect, named in the cost section.) Enumerate where
  omission is recoverable; shape-test where it is not.

  And the deeper one, which the third failure taught: **a per-line list cannot be made safe
  by improving the list.** Each of the three *per-line-marker* versions had a defensible
  marker set; what defeated them was context the line does not carry. When a predicate's
  errors come from containment, the fix is a positional or stateful test, not a better
  enumeration.

  **The last lesson, and the one that decided the design: a predicate that honestly declares
  itself not-a-proof cannot carry an unrecoverable action.** Every critic round found a
  new shape where a *citation* answers 0, at a roughly constant rate, and the cost section
  ended up retreating — correctly — to "a floor, not a proof". At that point the question
  stopped being *how do we make the predicate right enough to delete on* and became *why is
  anything deleting on it*. `/way-of-working:ship` now keeps both sides on **every** branch
  and uses the answer only to sort the removals it reports: `0` reads "probably moved,
  likely safe to drop", `1`/`2` read "unresolved". The triage benefit that motivated `#66`
  survives, but **not intact, and the record should not pretend otherwise.** `#66` was filed
  to let step 1 "resolve per entry *instead of handing every removal to the human*", and to
  shrink the prose to a pointer; what shipped hands every removal to the human *ranked*, and
  the step-1 prose grew rather than shrank. Per-entry **ranking** replaced per-entry
  **resolution**. That is the right trade against an unrecoverable deletion, and it is a
  reduction in what the issue asked for.

  The part that cost nothing was removing the destructive branch itself — it was never the
  valuable half. Five rounds went by before anyone asked whether it had to be there,
  including the round that wrote a header sentence forbidding precisely what the caller three
  files away was doing.

  One supporting commitment, from a round that failed for want of it: the id is matched as a
  **literal** and never compiled as a pattern — an interpolated `A.1` also matches `AX1`, and
  an id containing `[` makes the matcher *error*, which a surrounding `if` reads as a clean
  "no match", the worst available failure.

  A third answer follows from the same asymmetry: "could not tell" (`2`) is never folded into
  "no" (`1`), and misuse — a missing argument, an empty id, a directory in place of a file, or
  an `awk` whose POSIX bracket classes are unsupported and would fail *open* — exits `2`
  rather than the shell's default `1`, because `1` is this predicate's word for a confident
  negative. This is `WB-D7`'s lesson in a second command: a check that cannot distinguish
  *couldn't look* from *isn't there* is the defect it exists to catch.

  **A fixture only counts if removing the rule it names turns it red.** Both suites here
  looked thorough and left guards unpinned — a boundary row caught by a *different* rule than
  the one it claimed to test, a "the scan must continue" row that answered the same either
  way, an error-mapping branch no input could reach. Deleting the intended guard left the
  suite green in every case. Found by mutation, never by reading, and the discipline
  generalizes: a suite guarding a predicate with several rules is checked by mutating each
  rule in turn — each sub-expression on its own, under a bounded timeout, for the two reasons
  the paragraph below records. Every guard here is pinned that way except four, and those
  four for **two** different reasons — the part that kept going wrong. Three need a non-conforming
  `awk` to reach (the POSIX bracket-class probe, the `(pos > 1)` guard on the preceding
  character, and `exit rc` rather than a bare `exit`); one, `[ ! -r "$file" ]`, is a Windows
  platform limit, because `chmod 000` there does not deny the owner a read. The suite names
  all four with both reasons.

  **Every previous version of that note was wrong, and wrong about the count every time** —
  it climbed one, two, three, four, with `[ ! -r "$file" ]` sitting unpinned throughout and a
  fresh live guard turning up in most rounds. An earlier draft of this very paragraph claimed
  the opposite: that the count had always been right and only the universal attached to it
  was wrong. That was false, and false in the flattering direction — it recast a series of
  miscounts as a subtler error already diagnosed. A decision entry whose subject is
  overclaiming had shipped an overclaim about its own history, and a critic caught it. That
  has now happened twice: the round-9 critics caught this entry doing it again, in the very
  commit that recorded the sweep. The general form is worth more than the
  incident: **a record of one's own errors drifts toward the version that reads better**, so
  it needs the same mechanical check as any other claim. Here that check exists — but running
  it was never as simple as the sentence that used to end this entry ("re-run the sweep and
  count what stays green"). That sentence prescribes an operation too coarse to establish what
  the paragraph around it claims — see below — though it is not the only reason the count was
  wrong, and this entry should not guess at a single cause for its own history.

  **The sweep has now been run to completion, and the procedure it corrected is the finding.**
  86 candidate lines — every line that is not blank, not a comment, and not brace-only — give
  69 red, 6 non-terminating, 11 green. The four named guards are confirmed unpinned, but only
  under **sub-expression** mutation, and the reason generalizes past them: a whole-line
  deletion answers a different question whenever the line carries more than the guard. Delete
  those four at their own lines and you get two reds for no longer parsing, one red for
  removing the assignment around the guard, and one hang — no green among them, and not one of
  the four an answer about the guard. That is what "delete each rule in turn" had always meant
  here, and it cannot test them.

  Two more ways the old procedure under-measured. A red can be **vacuous** — 22 of the 69 are
  mutants that no longer run at all, as shell or as `awk`, so they pin nothing. Where such a
  line carries a condition, what covers it is the sub-expression pass: 31 variants over the
  fifteen sites that carry a condition made of parts, 27 red, and the 4 green are exactly the
  four guards named above. Where the line is scaffolding — `fi`, `esac`, the `awk` invocation,
  a loop header — nothing covers it and nothing needs to. And a deletion can make
  the script **non-terminating** rather than wrong: six do, and the suite has no timeout, so
  those hang it forever rather than failing it. That is how an attempt at this sweep stranded
  partway and left it recorded as owed; its orphaned processes were still running when this
  session finished the job. So: mutate sub-expressions, check runnability before counting a
  red, and bound every run.

  **The sweep's own result was a live guard this record had filed as covered.** `col = 0`
  (`entry-anchor.sh`) sat in the green list as one of two harmless initialisers. It is an awk
  global reset: without it the previous fence line's column count carries into the next one, a
  2-space-indented fence pair accumulates past the four-column threshold, the closer reads as
  indented code, and the file goes dark from there — an ordinary ledger shape, pinnable in
  three lines. It went unnoticed because "initialiser" was asserted of it rather than checked,
  in the same paragraph that demands the count be measured. A fifth green line really is not a
  guard: the `exit` after `found = 1` cannot change the answer, so a status-only contract can
  never pin it — named at the site, not deleted.

  **Then it happened again, in the commit that recorded all of the above.** That commit widened
  a correctly-scoped sentence — "each conjunct of the *two compound guards*" — into "every
  compound condition … all red". The pass had covered five sites. Behind the widened word sat
  three more live, fixture-less guards: the `~~~` alternative of the fence opener, and the
  "nothing else on the line" tail on each half of the front-matter delimiter, two of the three
  failing toward a false match. The sentence was also self-refuting — it sat one sentence
  before "four guards stay green", and both cannot be true. So the count of guards this record
  filed as covered while they were live is **four**, found across two rounds, and the second
  three were found by swapping the reviewing model rather than by another pass of the same one.
  All four have fixtures now.

  The `~~~` case is the one worth carrying forward, because it is not an oversight — it is a
  fixture that *looks* like coverage. The suite's only other `~~~` row nests the tildes inside
  a backtick fence, where a matcher that does not know `~~~` at all behaves identically. It
  would have passed forever. The generalization: **a fixture exercising a feature in a context
  where a broken implementation still passes is worth nothing, and reads exactly like a
  fixture that is worth something.** Only mutation tells them apart — which is this entry's
  own thesis, arriving a third time, at the level of the fixtures rather than the guards.

- **WB-D12 — a second sprint is a tracked snapshot beside the one live cursor, never a
  second cursor.** One live cursor stays the design. When a sprint must be set aside
  mid-flight — blocked on an outside decision while another sprint has to run —
  `/way-of-working:park-sprint` copies `.ai/state.json` and `.ai/next-steps.md` into
  tracked `.ai/parked/<id>-*` and re-seeds the live cursor; `/way-of-working:unpark-sprint`
  restores them behind a `hitl_gate`, because the parked `next_action` was written against
  an older HEAD and must never auto-start. `.ai/parked/` is tracked, unlike git-ignored
  `.ai/archive/`, because a parked cursor is the *only* copy of in-flight state, and
  `cursor-drift.sh` admits it as `cursor-sync` (`#87`) so parking costs the next session
  nothing. Two shape choices follow from the same design: `parked_from_commit` is recorded
  on a freshly pulled `{pr_base}`, never on a code branch, so the `<commit>..HEAD` range
  unpark hands the human normally means what it looks like (the same squash-merge trap
  as `WB-D7`, closed at write time instead of read time); and a park whose next sprint is
  already parked is a swap, handed straight to unpark so one PR carries both and no
  sprint is left with two cursors. (Rejected: a multi-sprint map inside `state.json` — a `schema_version` 2 break
  that forks every skill and the banner hook, for a case two files beside the cursor cover
  with no `.ai/project.yml` key and no migration.) Evidence, from a consuming repo: its
  cursor held one sprint `blocked` for two weeks while two later sprints ran as unrecorded
  "activity slots" — pasted handoff blocks, no resume, no handoff, no archive, and a memory
  telling every session to ignore the banner; the one handoff that did run had to be closed,
  because handoff regenerates the cursor wholesale and would have overwritten the blocked
  sprint's in-flight state. The workaround was a standing per-session cost that lived
  outside the plugin.

- **WB-D13 — a PR's own code runs in an isolated sandbox, not a shared-`.git` worktree; an
  untrusted PR gets no local execution at all.** `/way-of-working:architect-review`'s *Review
  by execution* step ran a PR's own tests and gate scripts with the reviewing session's
  credentials via `git worktree add`, which shares `.git` with the main checkout — PR code
  there could rewrite `.ai/project.yml` or `.git/config`'s `origin` before the *Compose and
  post* step re-read them to post the frozen attestation strings (`#113`, from a
  security-critic finding on `#98`'s base-anchor work).

  The fix went through two design-spec revisions on the issue before a human decision, and
  the gap between them is the record worth keeping. Revision 1 proposed a throwaway `git
  clone --no-local --no-hardlinks` under a stripped `env -i`, argued to close the trust gap
  outright. A critic pass (security-critic + architect, one round each) reproduced three
  vectors it claimed closed: `gh auth token`/`gh auth git-credential` return the invoking
  user's real credential from the OS keyring regardless of what the process environment
  carries — stripping an env removes the credential *handle*, not the *reach*; `PATH`'s
  first entry is a plantable shim directory, and the plugin's own `bin/` (which would hold
  the sandbox script itself) is writable from inside a naive sandbox; and `git clone
  <workspace>` writes the absolute workspace path into the clone's own reflog and its
  `origin` remote config (a round-5 verification pass caught this record claiming
  `FETCH_HEAD` too — verified live that `clone` never creates one; that leak is specific
  to revision 2's single-ref fetch design, below, not to `clone`), so "the attacker would
  have to guess the path" was false. Revision 1's own
  claim — that a container changes nothing about the reviewing skill's text — was also wrong:
  an untrusted PR's branch changes shape (from "run nothing" to "run in the container") the
  moment a container exists, which revision 2 corrected directly.

  Revision 2's mechanism (**option A**) is `git init --template=<empty>` plus a single-ref
  fetch **from the workspace**, replacing `clone`: no local branches or tags copied, no
  `clone: from` reflog entry, no `origin` remote to remove. `FETCH_HEAD` — the actual leak;
  a single-ref fetch with no destination branch writes no reflog entry, so there is nothing
  under `.git/logs` for the path to leak into either, a distinction a round-4 verification
  pass caught this record getting wrong — is scrubbed immediately after the fetch, before
  checkout, closing THAT specific leak directly rather than hoping cloning-differently
  avoids it. The workspace path stays discoverable other ways that need no prior
  compromise — an ancestor process's own cwd, or simply listing the filesystem for the
  fetch's own ref namespace — which this fix does not touch; **D** (below) is what catches
  a write made through one of those, not **A**. It states its own limit plainly, in its
  header and in every review it produces: this is **accident containment, not isolation
  from a deliberately hostile trusted-author PR** — the keyring reach, and any write that
  persists as the reviewing user (a PATH directory, a dotfile, a shell rc file, or the
  WORKSPACE's own `.git/config`/hooks, which a round-4 pass named as the most consequential
  instance of this class — see below), stay open until a container exists.

  The human approved **option 1**: **A (the corrected sandbox above) + C (no local execution
  for an untrusted PR — the required checks' own witness on the pinned SHA stands in,
  never silently treated as verified) + D (a pre-step transcript snapshot re-verified,
  byte for byte, before the frozen attestation strings are read) now; B (a container,
  closing the keyring and persistent-write residuals, needing its own `.ai/project.yml`
  key) filed as `#158` and milestoned to Sprint 5 ("every config key is an explicit
  decision" — fitting, since B is the one part of this design that needs one), not
  parked.** Confirmed separately: an untrusted
  PR gets *reviewed without local execution*, never *no review at all* — the required-check
  witness, marked per claim as witnessed or not, is real signal even without a local run.

  The accepted residual is stated, not implied, and it is wider than the keyring alone: until
  B lands, a compromised **trusted** author's PR still reaches the reviewing session's real
  GitHub credential in one command (`gh auth token`) run inside `review-sandbox.sh run`; the
  SAME credential, if the invoking shell exported it as `GH_TOKEN`, is separately readable
  from an ANCESTOR process's environment (`timeout`, the wrapping subshell, the script
  itself) via `/proc/<pid>/environ` — a property of what `env -i` strips (the direct child
  only) rather than a gap in its allowlist, found on the second critic round, not the first;
  and a leftover process from an earlier `run` that this script's best-effort kill failed to
  reach can still plant a local git-config value that executes under `make`'s full
  environment during a later rebuild — found reachable for several specific config keys, not
  closed as a class, on the THIRD round. The posted review says (in substance) that a
  trusted-PR review executed under accident containment, not a container, so a reader knows
  what the witness actually covers. (Rejected, all three rounds it came up: treating the
  credential-handle strip as sufficient on its own — the keyring, and now the
  ancestor-environ read, both make that false regardless of how thorough the strip is; and
  skipping review for an untrusted PR outright, which trades a real, if narrower, signal for
  none.)

  A FOURTH round, run in a fresh session specifically to verify the third round's own fixes
  held (rather than continuing in the session that had just hit the critic-gate's 2-round
  cap), found the fixes themselves sound but not fully guarded or disclosed: the fix for
  `run`'s wall-clock-bypass hang (a backgrounded child inheriting `run`'s output pipe, so
  `head -c` never saw EOF) had no test that could fail if it regressed, and the
  leftover-process fixture could never fail on any platform, whatever the kill mechanism did
  — both closed with new fixtures, verified by mutation. Two disclosure gaps were also
  found and named directly in the script's own residual list: direct reads of any
  same-uid-readable credential file (not just the OS keyring) and unrestricted network
  egress, neither previously named; and the WORKSPACE's own `.git/config`/hooks as a plant
  route distinct from the sandbox-local one already documented, plus a gap in the
  pre/post transcript snapshot (it records hook file names, not contents). No new trust
  boundary was opened, and no round-4 finding changed the accepted scope — accident
  containment, not a container, same as revision 2's own framing.

  A FIFTH round, scoped to verifying round 4's own fixes rather than a fresh full pass,
  found one round-4 fix incomplete as CODE, not merely as prose: `run`'s best-effort kill
  used `kill -TERM -- "-$child"`, and dash (Debian/Ubuntu's `/bin/sh`, the shell this
  repo's own CI runs) rejects `--` in that position and errors, an error the surrounding
  `2>/dev/null || true` silently swallowed — so the kill was a no-op on every dash-based
  Linux host, not merely "untested by CI" as stated. Reproduced live on WSL Ubuntu, where
  round 4's OWN new leftover-process fixture (added specifically to stop this class of
  claim going unverified) correctly failed red against the unpatched code. Fixed by
  dropping `--` (`kill -TERM "-$child"`), portable across dash, bash-as-sh, and this
  repo's own Git Bash `sh`. A smaller regression from round 4's own `mktemp` switch was
  also found and fixed: the status file's fallback (`|| echo 1`) could no longer fire —
  `mktemp` pre-creates the file, so `cat` always succeeds, and an empty status (the
  subshell dying before writing one) crashed `run` on a non-numeric `return` instead of
  exiting 1. Two of round 4's own disclosures were themselves corrected: the `mktemp` fix
  narrows the status-file race, it does not close it (the file is still discoverable by
  directory-listing or via the wrapped command's own inherited stdout fd), and the
  "`make` applies a SUPERSET of `run`'s isolation" correction had swapped one overclaim
  for another ("narrower" — wrong the other way, since `make` alone carries several `-c`
  config overrides `run` doesn't); both are now stated as narrowed-not-closed and
  different-not-ranked, respectively. A completeness gap was added to the workspace
  `.git/config` residual: a plant there (`url.<x>.insteadOf`, a rewritten `origin`) can
  redirect a LATER review's own trust read, not just execute code under it — `trust`/`make`
  resolve `{repo}` from this checkout's own `origin` before ever reading a PR, so a plant
  present before that read can point an entirely different review at an attacker-controlled
  repo. And one claim predating round 4 was corrected in the course of re-checking it: `git
  clone`'s workspace-path leak (revision 1, above) is through the reflog and `origin`
  remote config, not `FETCH_HEAD` — `clone` never creates a `FETCH_HEAD` file at all; that
  leak is specific to revision 2's own single-ref-fetch design. No new trust boundary was
  opened by round 5's findings either; the kill fix closes a real functional gap in the
  documented leftover-process residual, not a new one.

  A SIXTH round, again scoped to verifying round 5's own patch, converged: nothing found
  beyond stale comments the round-5 patch left behind and one disclosure gap, no new code
  defect. The disclosure gap was the more consequential of the two: round 5's own
  origin-redirect completeness note named only THIS script's trust read, but
  `bin/review-base-anchor.sh` — invoked earlier, as the first step of
  `/way-of-working:architect-review` itself — resolves `{repo}` the same way and, verified
  live, fast-forwards the reviewer's own local default branch onto whatever a redirected
  `origin` holds; the whole review session then reads `.ai/project.yml` from that
  fast-forwarded tree, and SKILL.md's own `{repo}` cross-check does not catch it, because
  both sides resolve from the same redirected `origin`. Named directly in both this
  script's header and here. The stale leftovers: a comment beside `run`'s job-control
  setup still quoted the pre-round-5 `kill -- "-$child"` form dash rejects (the code
  itself was already fixed); the header said the `-c` config overrides `make` adds are "on
  the checkout call specifically" when they are on both of `make`'s git calls; and the
  `[ -n "$st" ] || st=1` guard round 5 added checked only non-emptiness, not that a forged
  status value (from the already-accepted, narrowed-not-closed mktemp-discoverability
  residual) is actually a valid exit code -- tightened to validate digits and range. No
  new trust boundary, no regression from round 5's own patch.

  **Amended (2026-09-28, `#158`): B is deferred, not built.** The human worked `#158`
  through 13 design decisions and posted them as a build spec, then asked for one more
  critical pass against how the plugin is actually used. That pass (checked against the
  consuming repos' own `.ai/project.yml` and PR history) found B aimed at a risk that is
  small **for this maintainer's own setup**, at a cost out of proportion to what it would
  buy. The acceptance below is scoped to that setup, never a property of the plugin: a
  consumer whose trusted authors are not the reviewer is exactly the case B was filed for.

  - **The trusted-author residual is accepted here because of identity, not prior
    execution.** In the repos that set `review.ci_gate` today, a trusted PR is expected to
    be the maintainer's own, or a Claude session's opened under the maintainer's account
    (checked on one of them, `terraform-cloudflare-dns`: its last 33 PRs were opened by
    the maintainer's account or Dependabot, nothing else — PR openers, not per-commit
    authorship), so the
    credentials `run` leaves in reach belong to the same person whose code is running —
    there is no second principal for a container to defend against. (Usually the code has
    also already run on a host: `coder` and `/way-of-working:critic-gate` run
    `{gates.green}` before `/way-of-working:ship`. That is supporting, not load-bearing —
    a reviewer's reproductions and planted mutations run more than the gate, and a gate
    that fetches at run time, `npx --yes` or `tofu init`, does not re-run the same bytes.)
    Installing a container engine would add its own exposure (docker-group membership is
    root-equivalent on Linux).
  - **`--network none` defeats the gates the consuming repos actually run.** Those gates
    (`tofu init` fetching providers, `npm run build` on a fresh checkout, `npx --yes`)
    need the network, so nearly every containerised claim would read "not reproducible
    offline", and every run would end in a host-mode override that stops being a real
    decision once it is routine.
  - **C already covers the realistic untrusted author.** That author is a dependency
    bot: Dependabot's PRs read `author_association: CONTRIBUTOR` (seen live on
    `bounty-infra` and `bedrock-serverless-rag`; `NONE` before its first merged PR),
    outside the trust allowlist either way, so they already take option C, whose witness
    is GitHub's own networked CI with no local credential in reach. That is the right
    executor for a dependency bump. The reverse case is **not** covered: a trusted PR that
    carries a dependency bump (grouped or cherry-picked by the maintainer) runs registry
    install scripts on the reviewer's host if a reviewer reproduces it through `run`, so
    `/way-of-working:architect-review` takes every claim on such a PR that would install
    or fetch dependencies from C's CI witness instead.

  So option 1 stands as A + C + D. The residuals above, keyring and persistent-write
  included, remain as stated, and `bin/review-sandbox.sh`'s header keeps disclosing them.
  **Revisit B** (the spec comment on `#158` is the starting point) when any of these
  becomes true:
  - anyone besides the maintainer can open a same-repo PR that reads trusted — a new
    org member or collaborator (MEMBER needs no write access to read trusted, only an
    existing branch to open from), whatever their permission level;
  - automation that can push commits onto a trusted PR's branch after its author's gate
    ran — a GitHub App (a Claude or Copilot agent, Renovate), an Actions workflow with
    `contents: write`, or a web-UI suggestion committed by someone else;
  - trusted PRs authored off the reviewer's host (a cloud session) whose code the
    maintainer does not read before review;
  - this repo or a consuming one opens to fork PRs whose claims a reviewer needs to
    witness locally rather than through CI;
  - reviews start running unattended (headless or cloud sessions) against PRs the
    maintainer did not write;
  - anyone else installs this plugin in a repo whose trusted authors are not its
    reviewer — for them, this acceptance never applied.

  The reduced shape the pass proposed for that day: container for untrusted PRs only, trusted PRs
  stay on A, a machine without an engine falls back to C, and the schema key is required
  only when `review.ci_gate` is a map. Moving `make`'s fetch into a container, `#193`, is
  deferred with it.

- **WB-D14 (`#48`) — `TIER2` in `scripts/coupling-check.sh` stays hand-maintained.**
  Membership rule unchanged: every `glunk-works` repo, plus any name the reference docs use
  as a worked example. (Rejected: deriving at run time — `gh repo list` inside the gate. It
  turns an offline, instant gate into a network-dependent one that fails on a `gh` outage,
  and worse, it fails **open**: in CI, `GITHUB_TOKEN` cannot list any private org repo, so a
  future private repo would silently drop out of the derived list instead of erroring — the
  org has none today, but the gate exists for exactly this case. Rejected: a
  generated-and-committed list plus a regenerate script — the same weakness as
  hand-maintenance, since someone still has to remember to run it when a repo is added, so it
  buys no drift protection; and `TIER2` is not purely derivable, since `glunk-works` (the org
  name) and `loop-engine` (a worked example in `reference/conventions.md`) are not repos, so
  the generator's output would still need a hand-kept remainder. Rejected for now: a
  scheduled drift check — gate stays offline, a cron job compares `gh repo list` against
  `TIER2`. It is the only option that actually catches a new repo, but it needs new CI
  infrastructure this repo does not have, which isn't worth it for an 8-repo org that rarely
  adds repos; revisit if the org starts adding repos often.) **Accepted gap:** a new org repo
  is unguarded until someone adds it to `TIER2`. Verified 2026-09-25: all 8 current repos are
  listed. **`TIER1`/`TIER2` overlap:** `loop-orchestrator` stays in both — the `TIER2`
  comment already explains why, and pruning `TIER1` buys nothing.

- **WB-D15 (`#45`) — code scanning on two repos, split by what each one needs; the rest
  wait.** `#45` surveyed **7 of 8** `glunk-works` repos as having no code scanning at all
  (verified 2026-08-13 via the code-scanning-analyses API) and asked which of them CodeQL
  can meaningfully analyse. The 2026-09-25 planning pass overturned that framing on two
  points: `bounty-infra`'s 73 analyses are **zizmor** output (a workflow linter whose SARIF
  a `ci.yml` job uploads), not CodeQL — CodeQL default setup is `not-configured` on all 8
  repos — and "CodeQL can't analyse this repo" missed the point for a repo like this one,
  whose real scan surface is `.github/workflows/` (this repo's own `release.yml` holds an
  app token), which both zizmor and CodeQL's `actions` language read. All 8 repos are
  public, so scanning and Actions minutes are free; the cost that scales per repo is triage
  attention, which is why this splits by need rather than rolling out uniformly.

  **This repo** gets `zizmor`, not CodeQL: a job in `ci.yml`, modeled on `bounty-infra`'s
  own (`security-events: write` scoped to that job only, `zizmor-action` pinned by full
  commit SHA, resolved and verified independently of `bounty-infra`'s pin rather than
  copied). Not promoted to `ruleset.required_checks` yet — a later human call, once it has
  a track record. **Runs twice, not once**: `bounty-infra`'s own job (and this job's first
  draft) inherits `zizmor-action`'s default `advanced-security: true`, which passes
  `--format=sarif` to zizmor — and in that format zizmor itself always exits `0`, whatever
  it finds, so the job could never actually fail. Caught by `/way-of-working:critic-gate`
  (`architect` and `security-critic` independently), verified live. The job's first run is
  the real gate (`advanced-security: false`, `annotations: true`, confirmed to exit
  non-zero on a finding); the second uploads SARIF to the Security tab (`if: !cancelled()`,
  so a failing gate still uploads). Findings at first run: `dependabot-cooldown` (medium) —
  fixed, `.github/dependabot.yml` now sets `cooldown: default-days: 7`, matching zizmor's
  own default threshold; `adhoc-packages` (low) ×2, one on each `npm install -g
  @anthropic-ai/claude-code` step (`ci.yml`'s PR-time install and `release.yml`'s pinned
  release-time one) — suppressed inline (`# zizmor: ignore[adhoc-packages]`) with the same
  justification `dependabot.yml`'s own SCOPE/NOT COVERED notes already give: no
  `package.json` exists for either to lock against, and the audit fires on the ad-hoc
  install shape itself, not on whether the package version is pinned (`release.yml`'s
  already was, and still triggered it).

  **`bedrock-serverless-rag`** gets CodeQL default setup (Python + Actions) — Python source
  plus a real workflow surface, and (per `#28`'s original survey; not re-measured for this
  decision) one of the org's more active repos. The toggle itself is a repo/org setting this
  harness cannot flip:
  [bedrock-serverless-rag#134](https://github.com/glunk-works/bedrock-serverless-rag/issues/134)
  asks a human to enable it and name who triages.

  **Waiting list**, with what brings each back:
  - `global-bootstrap` — HCL, which CodeQL doesn't support. `zizmor` would apply if it
    grows workflows worth scanning.
  - `appsec-triage-agent` — dormant (0 issues, 0 PRs), same reasoning as `#28`'s
    decision 4. Revisit when activity resumes.
  - `pm-agent-loop` — off the list: archived 2026-10-05, superseded by
    `loop-orchestrator` (its own description called it that repo's prototype). Was dormant
    (0 issues, 12 PRs) by the same measure.
  - `scope-core` — dormant by the same measure as of `#45`'s 2026-08-13 survey (0 issues, 2
    PRs); has since opened one hygiene issue (`#3`, 2026-09-11) but no push since
    2026-07-25, so it stays on this list. Revisit if real activity resumes, not just one
    issue.
  - `loop-orchestrator` — quiet since 2026-08-10 despite heavy earlier activity. Revisit
    when activity resumes; it is the next candidate (Python plus workflows).

- **WB-D16 (`#177`) — `/way-of-working:critic-gate`'s hard cap moves from 2 to 4
  fix-and-re-run rounds; critic selection goes through a pick-list wherever the host can
  present one, instead of free text.** Requested directly by the maintainer on 2026-09-25,
  in the same session that ran `WB-D15`'s critic-gate pass (2 fix-and-re-run rounds,
  converged — under the cap being raised here, not an example of needing it raised). Two
  independent choices, one entry because both are the same interaction surface:
  - **Cap 2 → 4.** More headroom before a still-open diff is handed back for a human
    decision. Not a fix for an observed failure of 2 — none was found. A first draft of
    this entry's own skill-prose edit tried to give the raise a technical justification (a
    scenario that supposedly exceeded the old cap); `architect`, reviewing that draft
    during this same decision's own critic pass, verified the arithmetic and found the
    scenario actually converged safely inside the old cap. The invented rationale was
    removed rather than kept. This is a plain preference call, not a technically-forced
    one, and the skill records it as such.
  - **Pick-list wherever available.** The proposal step (and the second-opinion offer)
    must collect the human's confirmation through a structured multi-select UI (e.g.
    `AskUserQuestion`) whenever the host has one and the candidate list fits it, never a
    typed reply — removes an avoidable source of confusion once more than one critic is on
    the list, which is the common case. The recommendation logic itself (which critics, in
    what order, why) is unchanged.

  **Accepted gap:** a host with no pick-list tool, or a candidate list too long for one,
  falls back to a plain enumerated list — same as before this decision, not a regression.

- **WB-D17 (`#142`) — every `.ai/project.yml` key is an explicit decision: absent prompts,
  `null` is the explicit no-value, no key has a default, and a prompted answer becomes a
  pull request, never a working-tree value. Reverses `#127`'s Optional-key clause (PR
  #133).** Prompted by this repo running two sprints on an undeclared `planning.kind` that
  silently defaulted to `files` while the cursor behaved as `github_milestones` — a gap the
  schema's own "absent means X" text made invisible. `#127` correctly found the general
  absent-is-unreadable rule contradicted three documented Optional keys (`backlog.repo`,
  `review.ci_gate.triggers_on`, `migration_base`; `planning.kind` and `models.second_opinion`
  were written the same way) and resolved it by documenting each default; this entry resolves
  the same contradiction the other way, by removing the defaults. Absent now means one thing
  everywhere: unanswered, and asked for.
  - **Mechanism.** `bin/schema-complete.sh` (`WB-D10`'s pattern: verdict on stdout, fixtures
    in `tests/`) checks the checkout's file against the union of both documented examples'
    key paths (`reference/project-schema.md`) and the hardcoded enum/shape checks;
    `/way-of-working:resume` runs it as its own *Ensure the schema is complete* step, first,
    and asks for each missing key one at a time, through a pick-list where the host has one
    (`WB-D16`'s rule, extended from `critic-gate` to `resume`). Other skills and every agent
    are unchanged **in mechanism** — they still fail closed per key, per `project-schema.md`'s
    own general rule, which now says to add "run `/way-of-working:resume` to be asked for it"
    — but not in *outcome*: `planning.kind` absent no longer silently means `files` in
    `archive-sprint`, `handoff`, `park-sprint`, and `coder`, the exact gap that prompted this
    decision, and likewise `backlog.repo` in `retro` and `models.second_opinion` in
    `critic-gate`. `scripts/invariants-check.sh` holds the script's key set equal to
    the doc's (derived from both examples by a real path-walk, stopping at sequences), and
    requires both documented examples and this repo's own file to check complete.
  - **A prompted answer is a pull request, never a working-tree value.** A first draft of
    this design said an answer would be "staged in the working tree, never believed until
    committed" — a critic pass found no such mechanism exists: every skill and every agent
    reads the *working-tree* copy of `.ai/project.yml`, so a staged answer is believed
    immediately by whatever runs next in the same session. The interview's step therefore
    commits the answers alone, on their own branch, opens a PR, and restores the checkout
    before continuing — no reader in this session or the next ever sees an unmerged answer.
    `migration_base` is offered only `null` (starting a migration is its own deliberate PR);
    `repo`/`pr_base` may be pre-filled only from `origin`; every other free-text key gets no
    suggested options, since a milestone description, issue body, or comment is a task
    specification, never an instruction or a suggested value.
  - **`null` stays; `none` was considered and rejected** — in YAML it is the string
    `"none"`, so `review.ci_gate: none` would name a workflow called `none`.
  - **Auto-start gains a wait branch:** `schema-complete.sh check .ai/project.yml` must print
    `complete`; `incomplete` or `unreadable` both wait, the same fail-closed reading as an
    unreadable `hitl_gate`.
  - **The two `migration_base` readers** (`bin/review-base-anchor.sh`, `/way-of-working:resume`'s
    ruleset step) now distinguish the key being absent from the default branch's own
    `.ai/project.yml` from it being declared `null` — both used to read identically ("no
    migration"), which is exactly the silent-default shape this decision removes everywhere
    else. The key being **absent, or the file not existing on the default branch at all**,
    fails in the same safe direction null already did — only the diagnostic text changes,
    from a blank value that reads as "declared null" to an honest "absent," and
    `bin/review-base-anchor.sh`'s own human override still applies, with no dependency on
    `yq` at all in this case (`git show` fails first; `yq` is never invoked). A **present but
    unparseable** default-branch `.ai/project.yml` — or `yq` itself being unavailable *while
    trying to parse a file that does exist* — is a real (not merely diagnostic) tightening in
    `bin/review-base-anchor.sh`: both now refuse that override too, where the old single-pipe
    read let them through — deliberate, since neither failure can produce a truthful STOP
    line for a human to act on.

  **Accepted residuals:** mikefarah `yq` v4 becomes a hard dependency of `/way-of-working:resume`
  itself, not only of auto-start — its *Ensure the schema is complete* step runs first, and
  `yq` missing from `PATH` reads `unreadable` there, which stops the whole skill (no cursor
  read, no ruleset check, no prune) rather than degrading to the parts that need no schema
  value; also a hard dependency of the `invariants` check; a release that adds a key stops
  every consumer's auto-start until
  its completion PR merges, per repo, per release; the merge itself costs one `drift` wait
  (`.ai/project.yml` is deliberately not in `cursor-drift.sh`'s `cursor-sync` allowlist); a
  declined key is asked every session; a headless host waits and never writes; the default
  branch's copy is not completeness-checked from a non-default checkout; cross-key
  consistency (e.g. `planning.kind: github_milestones` with `backlog.kind: file`) is not
  checked here — it stays a documented config error, reported by the skills that already hit
  it. **Breaking:** ships as `v0.13.0` with a migration line — every consumer writes out the
  keys it had left absent.

- **WB-D18 (`#152`) — `/way-of-working:plan-sprint` reverses `due_on: ignored`, and deviates
  from its own issue's "via `ship`" wording for its cursor-sync commit.** `due_on` was
  documented as ignored ("no sprint cadence"); the new skill writes it deliberately, so the
  live milestone list's own display order matches the human's confirmed triage sequence —
  reversed in the same PR that ships the skill (`reference/project-schema.md` § `planning`).
  Separately, issue #152's own *Shape* section named `/way-of-working:ship`'s branch-cut
  chain for the final cursor-sync commit; `ship`'s own chain commits the working tree
  generally, with no built-in single-file scope guarantee, which risks sweeping other dirty
  state into a nominally docs-only PR — issue #150's failure mode one level up.
  `/way-of-working:plan-sprint` instead cites `/way-of-working:handoff`'s own docs-only
  cursor-sync step by reference, the same pattern `/way-of-working:park-sprint` already cites
  directly instead of reimplementing it (and `/way-of-working:archive-sprint` reaches on its
  own parked-branch path via `/way-of-working:unpark-sprint`).
  - **No new `.ai/project.yml` key.** The milestone-description template and the
    triage-comment format are both fixed plugin prose the skill renders, not per-repo
    config — same reasoning as `ship`'s PR-body shape or `reference/conventions.md`'s commit
    grammar.
  - **Mechanism.** The read-only gather step (open issues with no milestone; open milestones
    in due-date order; every milestone's title, for a naming-collision check; a specific
    milestone's own open issues, for the denied-write fallback-comment location) is a tested
    `bin/plan-gather.sh`, with fixtures in `tests/` — the sprint's own build-order note for
    this task required it, mirroring `WB-D10`'s pattern. The placement dialogue, the
    denied-milestone-write staging, and the cursor sync stay skill prose. Issue-level
    milestone placement uses `gh issue edit --milestone <title>` (the write channel that still
    works when this org's own harness classifier refuses a `gh api` milestone write), always
    confirmed against the milestone **number** on read-back before being trusted, never a
    title match this skill found on its own.
  - **Injection safety.** Untrusted content (issue titles/bodies, which anyone on a public
    repo can author) never interpolates into a shell command, staged or live — every
    free-text value goes through a file written by the file-editing tool itself, descriptions
    via `gh api -F description=@<file>` (`-F`, not `-f` — confirmed live against `gh api
    --help` that `-f`/`--raw-field` has no `@<path>` file-read behavior at all, an initial
    draft's bug), and the staged script the calling environment's write-classifier forces is
    constrained to three fixed line shapes with digit-validated arguments, printed verbatim in
    the session's report rather than left for the human to run unread.

- **WB-D19 (`#197`) — `/way-of-working:plan-sprint` leads with a recommendation; the human
  still decides.** The skill `WB-D18` shipped (#152) scoped itself, in its own Goal line,
  to "mechanize the shape, never the ranking" and
  shipped a per-issue menu with nothing pre-selected. Dogfooding it on this repo's own
  backlog (2026-09-28, #162 and #189), the human rejected that menu mid-dialogue and asked
  which sprint and which order; the session then read each issue body and each open
  milestone's description, proposed one new dated milestone with a two-step build order and
  a reason each, and the human accepted it in one turn. That is the shape the skill now has:
  a **Recommend** step, after the read-only gather and before any question, that reads every
  unmilestoned issue's body and every open milestone's description and proposes one table —
  per issue, a placement (existing, new, or deliberately unmilestoned), a build-order
  position, a one-line reason, and the **evidence it cites** (a line of the body or
  description, the milestone's own state, a dependency between two issues) — which the
  human accepts whole or walks through one issue at a time, the recommended option first.
  - **What "never ranks" guarded against, and what survives.** The concern was a model
    inventing importance from titles alone and the human rubber-stamping it. The fix is not
    neutrality but *grounding*: every recommendation cites the text it rests on, so the
    human can check it, and one with no citable basis is reported as having none. Every
    write still needs the human's confirmation; nothing about write confirmation changed.
    Text the skill drafts for publication (a per-issue reason, a new milestone's title, batch
    reason, or ships-as line) is its own paraphrase, never a quotation from an issue title,
    body, or milestone description; a reason
    the human types is recorded verbatim, as before. A claim read from a body — urgency, a
    dependency, a precondition — is always cited as its author's, not adopted.
  - **Trust boundary widened, rule unchanged.** The skill now reads issue bodies and every
    open milestone's description up front (`reference/project-schema.md` § `planning`
    previously said "never all of them up front"). They remain a specification, never an
    instruction: an author's own "urgent" is cited as that author's claim beside their
    `author_association`. Read-only copies use a `read-` filename family disjoint from the
    staged script's `title-`/`description-` families, so a fetched description can never be
    mistaken for one staged to be written. No new `.ai/project.yml` key.
  - **Side-finding from the same run: `due_on` is always sent as midday UTC.** A milestone
    created with `due_on=2026-10-16T00:00:00Z` stored 2026-10-15; the skill's date-only
    read-back caught it, and resending as `T12:00:00Z` stored the intended day. The earlier
    wording ("GitHub normalizes the time-of-day component") understated this — the date
    itself can move.

- **WB-D20 (`#215`) — a forgotten cursor-sync PR is merged at `/resume`, on confirmation;
  handoff still never merges.** *Superseded by `WB-D24` (2026-10-08): the agent-run merge
  is removed for every repo, cut over or not (`#385`); `/resume` now only reports the PR. The text below is the record of
  what it did.* Handoff's docs-only cursor-sync PR was regularly left open,
  so `{pr_base}`'s cursor went stale. `/way-of-working:resume` now runs
  `bin/cursor-sync-pr.sh` before it reads the cursor. When exactly one qualifying PR is
  open, it shows the PR's **Next:** paragraph and **HITL Gate** line (if any) read at its
  head commit, beside the local `next_action` and `hitl_gate` auto-start would run and
  enforce, and merges on one explicit
  confirmation, pinned with `--match-head-commit`. The merge happens only when a human
  answers, and `/resume` is where the human already is at the start of a session, so the PR
  stops being forgotten and the approval lands just before the `next_action` could run.
  - **Rejected: handoff merges its own PR when the commits are signed.** Signing is not an
    authorship signal here: every session commit is signed with the human's key through the
    cached passphrase, so a signature cannot tell "the human approved this" from "a session
    wrote this". Squash merge (`WB-D7`) also replaces the signed branch commit with one
    GitHub signs, so the check could never apply to what lands. And it would open a
    persistence channel for prompt injection: a session steered by untrusted text (an issue
    body, a PR comment, review output) could write a harmful `next_action`, approve it
    itself, and the next session would run it unattended.
  - **The human sees the `next_action`, not just the ledger.** `next_action` lives in the
    git-ignored `.ai/state.json` and is never part of the PR; the PR carries only the
    ledger's **Next:** line. Showing the ledger alone would let a session write a harmless
    **Next:** and a harmful `next_action` and have the first approved for the second, so
    both are shown, and `next_action` is printed inside one compact JSON object so its own
    text cannot fake where it ends. Nothing mechanically compares them: under `planning.kind: files` the
    two are free prose, and the human judges whether they agree. This holds only for a merge
    made through the offer. A merge on GitHub still approves the ledger alone, as it always
    did.
  - **Trust is "this machine's own sync branch", not "same author".** The predicate offers a
    PR only when it is same-repository, changes exactly `.ai/next-steps.md`, is `CLEAN` (or, since #229, `BLOCKED` with every
    present check green and no blocking review — the shape GitHub shows the admin when only
    a restrict-updates ruleset is unmet), and
    a local branch of the same name sits at exactly its head commit. Same-repository alone is
    not enough on a public repo: anyone with read access can open a PR from an existing
    branch, and this repo keeps merged branches (49 stale `docs/sync-cursor-*` heads beside
    one live sync when this was written). The local binding also matches what auto-start runs, since
    `.ai/state.json` is machine-local. A sync opened from another machine is refused
    (`not-local`) and merged on GitHub as before. The PR author is not checked:
    `author_association` depends on the viewer, and read by a `gh` account other than the
    PR's author it reported `CONTRIBUTOR` for the maintainer's own PR #210.
  - **It narrows a gap that already existed.** Handoff leaves the checkout on the sync branch.
    Once the code it describes has merged, `cursor-drift.sh` reads that branch as
    `cursor-sync`, so a session could auto-start a `next_action` whose PR no one had merged.
    Auto-start now also requires that the step found no open sync PR and no `unmerged` sync
    branch under HEAD (a failed push, a PR the human closed, or one merged at a different
    commit), or that its offered merge succeeded. Every other outcome waits. **What
    remains.** These three were also possible before this change:
    - A GitHub-side merge auto-starts a `next_action` no one was shown.
    - A sync PR closed unmerged after the checkout already left its branch reads `none`, and
      so does a detached HEAD. The `unmerged` check looks only at the branch HEAD is on.
    - A hand-edited `state.json` is not detected.

    The offer itself carries these, narrower than the auto-start exposure above:
    - A sync PR the human closed unmerged, then reopened by an outsider as a new PR while
      the local branch survives, passes the binding. The display shows the same text that
      was rejected, and the merge needs the human's pinned confirmation.
    - Since #229 the offer also admits a `BLOCKED` PR and merges with `--admin`, on evidence
      the script can only partly see: a rule the admin role can bypass that the script cannot
      read (unresolved conversations, deployments, code scanning, merge queue) is bypassed
      with it, and check state can change between the offer and the confirmation. The server
      still enforces any required rule the admin cannot bypass. The script header lists these.
    - Since #245 a `BLOCKED` offer also requires every name in `{ruleset.required_checks}`
      (passed as the script's third argument) to appear in the rollup as a green entry, so a
      required check that never reported — a `paths:` filter excluding `.ai/`, a job not yet
      registered — no longer slips past the all-present-checks-green test. An empty or
      missing list refuses. What it checks is the list in `.ai/project.yml`, not the contexts
      the ruleset currently carries, so a context added to the ruleset and not to the file is
      still not looked for.
    - Since #250 the `BLOCKED` offer also requires the **active `gh` identity** to be able to
      perform that merge: `--admin` only switches off `gh`'s client-side refusal, and the
      server applies the bypass per viewer (measured: one account on a machine saw
      `current_user_can_bypass: never`, another `pull_requests_only`). `cursor-sync-pr.sh`
      reads the rulesets carrying an `update` rule on the base and each one's
      `current_user_can_bypass`; `never` is `refuse <N> bypass-never`, and resume names the
      identity and sends the human to the web UI or a bypass-capable account. No `update`
      rule, a failed read or an unknown value does not offer. `pr-checks`' READY (admin
      merge) verdict named the same identity and value instead of "if you hold the bypass";
      `WB-D24` task `#384` retired that verdict for every repo, cut over or not (a green PR
      under an `update` rule now reads COULD NOT TELL), so only resume's offer remains.
  - **Cost, accepted: anyone who can open a PR can make auto-start wait.** A fork PR on a
    `docs/sync-cursor-*` branch reads `refuse`, or `ambiguous` beside a real one, until
    someone closes it. That fails closed, so it costs a "go", never an unapproved run.
  - **Park and unpark PRs are never offered.** They share handoff's branch prefix but also
    touch `.ai/parked/`, so the predicate refuses them as `files`. Setting a sprint aside or
    restoring one stays the human's separate decision. No `.ai/project.yml` key.

- **WB-D21 (`#247`) — `hooks.json` keeps invoking the SessionStart hook directly, not
  through `bash`.** #240 (#214) stores `hooks/ai-cursor-banner.sh` as mode 100755, with
  invariants check 9 keeping it that way, which fixes every install that takes the git index
  mode. It left open whether `hooks.json` should run the hook as `bash
  "${CLAUDE_PLUGIN_ROOT}/hooks/ai-cursor-banner.sh"` so that a copy which drops mode bits
  (`cp` without `-p`, a zip extract) would still show the banner. It should not.
  - **A `bash` prefix would fix one script in thirteen.** The plugin's `bin/` scripts are
    called by bare name on the Bash tool's `PATH` (`WB-D10`) and need the exec bit just as
    much, and nothing in `hooks.json` can reach them. A copy that drops modes breaks
    `/way-of-working:resume`'s own preflight whichever way the hook is invoked; the prefix
    would only make the banner the one part that still works, hiding a broken install.
  - **That copy is not how the plugin is installed.** It arrives through the marketplace
    cache, which keeps the index mode (this machine's `v0.16.0` cache holds the hook and every
    `bin/` script as `-rwxr-xr-x`), and check 9 stops the mode regressing at the source for
    the hook and `bin/` alike.
  - **Rejected for its cost too:** it changes how every session starts, on every host, and
    would need checking on each, Windows under Git Bash included, against a failure no real
    install path produces.
  - **What remains.** `tests/ai-cursor-banner.test.sh` runs the hook as `bash "$hook"`, so the
    exec-bit path the harness uses is covered by check 9, not by that suite. No
    `.ai/project.yml` key.

- **WB-D22 (`#230`) — a review step is derived from GitHub, so handoff skips the ledger PR
  that would only say "review PR N next".** *Step-1 half* (orchestrator plan v9 § 7.1 step 1,
  § 8.4b, § 8.4c). The loop half, for milestone 2, is added under this same number when that
  milestone starts. Today a work PR is usually followed by a second, docs-only cursor-sync PR
  whose only news is "review or merge PR N next", and the human reads and merges each one.
  Plan v9's exit metric for this step is fewer than 0.5 cursor PRs per work PR on
  devcontainers within a week, with zero relay PRs.
  - **The no-op handoff rule.** It applies when the only cursor change is that the anchored
    task's work now sits in an open PR awaiting review or merge. In that case
    `/way-of-working:handoff` writes `.ai/state.json` and nothing else:
    - It does not regenerate `.ai/next-steps.md`. A regenerated, uncommitted ledger would
      leave the tree dirty, and resume would wait.
    - It opens no ledger PR.
    - It ends with a synced switch to `{pr_base}` (amended by `#283`, below), not on the work
      branch.

    What it writes into `.ai/state.json`, in this order:
    - **The PR**, as `pointers.review_pr: {number, head_oid}`. `head_oid` is this
      checkout's own `git rev-parse HEAD`, and it must equal the PR's `headRefOid`. If they
      differ (unpushed local commits, or a remote commit not pulled), handoff opens the
      ledger PR instead. The pin binds the review to the commit this checkout holds, not to
      commits the owner wrote: a collaborator's commit the maintainer has pulled is pinned
      like any other.
    - **The `## Critic pass` section** (below) is written to the PR body before the anchor
      is re-taken. That way an edit that touches `#N`'s `updated_at` cannot fall after the
      anchor.
    - **`next_action`**, beginning `` review PR #M — `` when `review.ci_gate` is set, or
      `` merge PR #M — `` when it is `null`, followed by the task's usual `` task #N — ``
      token (or `` task {backlog.repo}#N — ``).
    - **The anchor**, re-taken with `task_issue: N`. This is handoff's existing mechanical
      re-anchor. A `drift`, an `unreadable` or a no-baseline result opens `hitl_gate`, and
      a gate change takes the ledger-PR route below. That is the main way a no-op falls
      back, visibly, to a ledger PR.
    - **`last_commit`** is the work branch's HEAD, as handoff writes it today. It equals the
      pin. (As first written this let `cursor-drift.sh` read `clean` on the work branch; see
      the `#283` amendment, below, for what replaces that.)
    - **`sprint_status` stays `implementing`.** It is not `awaiting_review`, which
      auto-start does not accept.
    - **With `review.ci_gate` set, `assigned_model` and `assigned_persona` become the
      architect values.** The review runs on the architect model (architect-review's
      step 1), and resume's model match must pass. This is part of the no-op, not the
      "model switch" that forces a ledger PR. A fix after the review is the human's call,
      made after reading it. The human starts a session on `{models.coder}` on the work
      branch and directs it. Resume there reports the mismatch against the architect
      assignment and waits, which is expected: the human's instruction is the override.
      Nothing auto-starts a fix.

    This **amends** two handoff rules for this shape:
    - the rule that an implementing cursor's `next_action` begins with `` task #N — `` as
      its very first characters;
    - the rule that an `architect-review` next action anchors `task_issue: null`. Under that
      rule the step could never pass resume's plan check.

    Every other `state.json` writer that sets pointers sets `review_pr` to `null`:
    archive-sprint, park-sprint, unpark-sprint, and handoff writing any other cursor.
    plan-sprint writes only `hitl_gate`, and `architect-review` only `next_action` (`#283`, below), so neither touches `review_pr`. A value left
    behind still has to match an open PR at its pinned head, so it fails closed. A missing
    field reads as `null`, so an older cursor never auto-starts a review step.

    The rule applies only under `planning.kind: github_milestones`, because the derivation
    below needs an anchored task issue. Every known adopter is on, or moving to, that kind,
    so `files` repos are not served.

    The ledger normally keeps two things no command re-derives: the cursor's own fields and
    the critic pass's record (round count, stopping condition, model provenance). The
    cursor's fields are in `state.json`. For the critic record, handoff writes a
    `## Critic pass` section into the work PR's body with `gh pr edit <M> --repo {repo}`. It
    replaces the first `## Critic pass` heading at the start of a line, outside a code fence,
    up to the next `## ` heading, or appends one if none exists. If the write fails, handoff
    opens the ledger PR as before. The next ordinary handoff reads the section back as data
    and carries it into the ledger. It reaches `main` only through that ledger PR, which the
    human merges.

    Rejected: making the record a precondition that `/way-of-working:ship` happened to meet.
    That would fire on habit and need a judgement call on free prose.

    Any other cursor change still gets the ledger PR: a gate, a sprint status, a new task,
    or a model change other than the architect assignment above.
  - **The derivation rule.** `/way-of-working:resume` derives the review step from GitHub
    state only, never from `next_action`. A PR qualifies when **all** of these hold:
    - it is open and same-repository (`isCrossRepository` false);
    - its author is the login from a fresh `gh api user` read made for this step, which the
      same-conversation shortcut never reuses;
    - its title or body names the anchored task issue. The match is `#N` or `{repo}#N` when
      `backlog.repo` is `repo`, else `{backlog.repo}#N`. In each case it is never preceded by
      a word character or `/` (outside the repo prefix itself), and never followed by a
      digit.

    The step it derives depends on `review.ci_gate`, and on `review.ci_gate.check` for the
    `success` read. Both are read from the same default-branch copy as `{models.architect}`
    (below), never the working tree. Otherwise a PR could blank the gate, or name a check
    that is always green, and resume would report an unreviewed PR as reviewed. The same
    read carries resume's `{repo}` cross-check: the repo `origin` names must equal
    `{repo}`, and `{backlog.repo}` is taken from that copy too. Any of these derives
    nothing and auto-starts nothing, and is never read as `null`:
    - a mismatch;
    - a failed fetch, `git show` or `yq`.

    Handoff picks the `review PR` or `merge PR` form from its own working-tree copy. If
    that disagrees with the default branch's, the token check fails and resume waits.
    - **Set, and the gate does not yet read `success` on the PR's head:** the step is
      `/way-of-working:architect-review <M>`.
    - **Set, and the gate already reads `success` on the head:** the step is "PR #M was
      reviewed at its head and awaits your merge, or a fix". It is a report, like the `null`
      case, so a reviewed PR is never offered for review again.
    - **`null`:** there is no review to run, so the step is "PR #M awaits your merge", a
      report with nothing to auto-start. It names `/way-of-working:pr-checks <M>` as a status
      read the human can ask for. Resume never merges a work PR.

    Two or more qualifying PRs show all of them and wait.

    Resume derives nothing when its running login equals `orchestration.loop_identity`
    (key added in `#234`, guard built in `#295`: `review-step.sh decide` takes `login` and
    `loop_identity` and prints `none`, ahead of every other verdict). The value comes from the
    default branch's copy, is folded as `plan-anchor.sh` folds it (case-insensitive, a trailing `[bot]` ignored on both sides), and
    `null` means no guard. This stops a session running as the loop's own
    identity. It does **not** close § 8.13d's stale-value case: a stale `loop_identity` by
    definition does not equal the running login. That case stays with the driver's
    preflight login-equality check (plan v9 § 7.3).

    Why the running login rather than a schema key: it is the identity that posts the
    review, so the PR's author and its reviewer cannot drift apart. A session under the
    wrong account finds no PR and waits.
    - Rejected: a `maintainer_login` key. It can go stale, and it would still have to equal
      the running login.
    - Rejected: `author_association`. It is wider (any collaborator's PR), and it is relative
      to who is looking (`WB-D20`).
  - **Auto-start needs two sources to agree, and a fresh session** (§ 8.4b). The derived
    step auto-starts only when **all** of these hold:
    - `.ai/state.json` exists.
    - `pointers.review_pr.number` is the derived PR, and `head_oid` is that PR's current
      head.
    - **The review-form token check passes.** It replaces the `task #N —` leading-token
      cross-check for this shape. `next_action` must begin `` review PR #M — `` and then the
      task token, with `M` equal to `review_pr.number` and `N` equal to
      `plan_anchor.task_issue`. The ledger's **Next:** is not compared, because during a
      review it still names the task by design (below).
    - **The checkout is the base, synced and clean** (amended by `#283`; first written as
      "the work branch at `head_oid`"). `branch` equals `pr_base`, `HEAD` equals
      `origin/{pr_base}` after a fetch, and the tree is clean. `pr_base` is the **default
      branch's** copy, for the same reason `{models.architect}` is: the working tree's could
      name the work branch itself. See *The reviewer session starts from the base*, below.
    - **The cursor's own two fields agree** (`#283`). `last_commit`, resolved to a full oid,
      equals `review_pr.head_oid`. This is the review shape's drift rule, in place of
      `cursor-drift.sh`.
    - **The model is the repo's architect.** `assigned_model` must equal
      `{models.architect}`, not merely match the running model, so a `state.json` naming
      another model cannot start the review on it. The value is read from the **default
      branch's** committed `.ai/project.yml`. The default branch is named from `origin` (not
      from any schema value), fetched, then read with `git show`. This is how resume's
      ruleset step reads `migration_base` and the ci_gate check name. It is never read from
      the working tree, which the PR under review can edit. It is never read from
      `origin/{pr_base}` either: `{pr_base}` itself comes from the working tree, and during
      a migration it names an integration branch whose copy "can't vouch for itself".
    - **No same-conversation shortcut is in effect.** A `/model` switch inside the
      conversation that wrote the PR is not a fresh session, and the gate's whole premise is
      a fresh one. architect-review's own *State the integrity precondition, then honor it*
      step stays as well. `--pin` (below) is never evidence of a fresh session.
    - **architect-review carries the pin, explicitly.** Resume invokes it as
      `/way-of-working:architect-review <M> --pin <head_oid>`, where the value is a full
      40-hex SHA compared byte for byte, never a prefix. A hand-started run with no `--pin`
      behaves as today. With `--pin`, architect-review:
      - stops at *Pin the target* if the SHA it pins differs;
      - stops at its *Check the other required checks first* step if the gate already
        reads `success` on the pin. The PR was already reviewed at that head, so a later
        session that finds the same `review_pr` never posts a second review.
      - re-reads `headRefOid` immediately before posting, and stops if that differs;
      - on step 8's poll, counts `success` only on the pinned SHA, never re-pins and
        reposts, and reports any head other than the pin as a stop;
      - ends **without** step 10's `/way-of-working:handoff` pointer. The cursor already
        records PR #M, and what comes next is the human's merge or the coder's fix. A
        handoff from the PR's base branch, where `review-base-anchor.sh` leaves the
        checkout, would fail the pin and open exactly the relay PR this rule removes. A later
        resume there never auto-starts a second review: the pinned `architect-review` run
        rewrites the cursor's `next_action` as soon as its post succeeds (`#283`), so `decide`
        prints `show … token`, or `reviewed` once the gate reads success. Before `#283` the base
        checkout read `drift`, which was what stopped a re-run; that stop is replaced, not
        lost.

      Today's step 8 polls the current head and accepts `success` there without comparing
      it to what was reviewed. That gap is closed for the pinned run only.
    - Every other auto-start condition in resume still holds unchanged, except the two the
      `#283` entry below replaces: the checkout condition above and resume's generic
      `cursor-drift.sh` `clean`/`cursor-sync` condition.

    What runs is built from the GitHub-derived number. `next_action`'s text is a vote that
    must match, never the command. Disagreement, a moved head, or a missing `state.json`
    shows the derived step and waits. This is fail-closed, like every other auto-start
    condition.
  - **The reviewer session starts from the base, not the PR's tree** (`#283`; the first
    residual of this decision). As first built, auto-start required `HEAD` to equal
    `review_pr.head_oid`, so the fresh reviewer session loaded `.claude/settings.json` hooks,
    `CLAUDE.md` and `.mcp.json` from the PR under review.
    - **What is new, and what is not.** Shell execution through a `SessionStart` hook is old:
      any session opened on the work branch runs it, including the coder fix session a
      no-op handoff points at, so auto-start added nothing there. The new harm is to the
      review's integrity: the author's `CLAUDE.md` is in the reviewer's context as authority,
      and it stays there after `review-base-anchor.sh` switches to the base. Whether a changed
      plugin `ref` in that tree substitutes the predicates is unverified.
    - **The review needs nothing from the PR's working tree.** `architect-review` syncs to
      the base, pins from GitHub, and executes PR code only in a `review-sandbox.sh` checkout.
    - **The change.** The no-op handoff ends with a synced switch to `{pr_base}`;
      `.ai/state.json` is git-ignored and carries the pin across it. Resume's auto-start
      checkout condition is "clean, on `{pr_base}` equal to `origin/{pr_base}`", plus the
      existing pin equal to the PR's `headRefOid`. `review-step.sh decide` takes `branch`,
      `base`, `base_head` and `last_commit` for it, and prints the new reason `last-commit`.
    - **The review-shape drift rule.** `last_commit` is the work branch's HEAD, so on the base
      `cursor-drift.sh` reads `drift` by construction (a fixture in
      `tests/cursor-drift.test.sh` pins that premise). It is therefore not consulted for this
      shape. Its job is to stop a `next_action` that a changed repo has invalidated from
      running unattended, and nothing here runs `next_action`: what starts is built from the
      derived PR. The replacement is the internal check that `last_commit` equals the pin, so a
      cursor whose two fields disagree shows the step and waits.
    - **The handoff block** tells the human to open a session on the work branch only when
      directing a fix.
    - **Rejected: a handoff-side denylist** of `.claude/`, `CLAUDE.md`, `.mcp.json` and
      `.claude-plugin/`. It is advisory (the human can start on the branch anyway) and
      open-ended (nested `CLAUDE.md`, base hooks calling scripts the PR edits).
    - **The pinned run consumes the vote.** With the base now the auto-start checkout, nothing
      but the gate would stop a later resume there from starting a second review on the same pin
      while the gate reads `pending`, `absent` or `failure`. So `architect-review` rewrites the
      git-ignored cursor's `next_action` (so it no longer begins `review PR #M — `) the moment
      its post succeeds, pinned or not, and before the gate poll, so an interrupted poll leaves
      no live vote. A failed post leaves it, so the run can be retried. It deliberately leaves
      `pointers.review_pr` intact: handoff finds the earlier critic record through that field,
      and nulling it would erase the record on the fix-and-repost loop and at the ledger carry.
    - **Residuals, stated plainly.**
      - The check runs when resume runs, not when the session loads its config. A session
        opened on the work branch has already loaded the PR's hooks, `CLAUDE.md` and
        `.mcp.json`; a hook there that switches the checkout to the base first would pass the
        predicate. The guard defends the honest path (the handoff block names the base), not a
        hostile branch author who also controls how the session is opened.
      - Ignored local files (`.claude/settings.local.json`, `CLAUDE.local.md`) survive the
        switch and are invisible to the clean-tree check. Anything that ran on the work branch,
        the coder session included, could have written them. That is the old host-execution
        risk, not a new one.
      - A human who opens the review session on the work branch anyway gets `show … checkout`
        and a "go" prompt, not an auto-start; nothing prevents the "go".
      - **Strict sync.** Any merge to `{pr_base}` between the handoff and the resume leaves
        `HEAD` behind `origin/{pr_base}` and shows `checkout`. That is fail-closed, not a bug:
        `git pull --ff-only origin {pr_base}` clears it. Likewise a local `{pr_base}` ahead of
        origin, or a dirty tree that stops the switch, shows `checkout`.
      - **Migration branches.** The handoff switches to its own working-tree `pr_base`, which
        on a migration's integration branch is that branch; resume compares against the
        default branch's copy. The two differ for the whole migration, so the review step shows
        `checkout` and waits, never auto-starts. Fail-closed; resolving the base from the PR's
        `baseRefName`, validated as `review-base-anchor.sh` does, is the follow-up if a
        migration adopts `review.ci_gate`.
  - **A fresh machine with no `state.json`** derives the step, shows it beside the ledger's
    **Next:**, says the ledger is behind by design, and waits. This is the existing rule
    that `next-steps.md` alone never auto-starts, applied to the new step. One "go" from the
    human runs the derived step. A machine whose `state.json` names a different PR or task is
    the disagreement case, not this one.
  - **When `review_pr` names no open PR** (merged or closed), resume reports which, says
    the cursor is stale, and waits. The next ordinary handoff, run by the human or by the
    session they start, picks the next task and writes the ledger PR. A PR that is still
    open but whose head moved (say, a fix pushed after a requested change) is the moved-head
    case above. It shows the step and waits, and a new no-op handoff from the fixed head
    re-pins it.
  - **What changes, and what it supersedes.** This is the cost of the rule.
    - **WB-D20's display property.** Under `WB-D20`, a cursor-sync merge made through
      resume's offer shows the human the `next_action` beside the ledger before approving
      it. A review-step `next_action` is never approved by anyone. The SessionStart banner
      injects it into the model's context, but that is not human approval. It also never
      reaches `main`, so between the no-op handoff and the work PR's merge, `main`'s
      **Next:** still names the task, not the PR.
    - **Why giving it up is acceptable.** The property is given up only for a `next_action`
      whose sole effect is a vote on a step derived elsewhere. The command is rebuilt from
      GitHub state, so a harmful `next_action` can at worst make auto-start wait. A
      free-prose `next_action` kept `WB-D20`'s display through the ledger PR. (`/resume`'s
      display of it was removed with the merge, `WB-D24`/`#385`.)
    - **The first unattended review post.** Until now an `architect-review` next action
      anchored `task_issue: null` and never auto-started. This makes it the first review
      the plugin posts without a human approving that step. Resume's *Why auto-start is not
      a lost approval* passage says auto-start "never crosses a merge or review boundary…
      nothing here posts a review". That passage is amended for this one derived step. The
      review is still never a merge, and the human still merges.
    - **Plan v9 § 7.1 step 3** says the fresh-session review "stays human-started, locally,
      as today", and then sets out what automating it in CI would require. This entry reads
      "human-started" as *the human starts the fresh session*. That stays true. What is
      dropped is the "go" inside the session, which § 8.4b's decision already allows.
    - **The ledger catches up** at the next ordinary handoff after the merge.
  - **Loop PRs never match. This is intended** (§ 8.13c, option A). The milestone-2 driver
    opens its PRs with the GitHub App's token, so their author is the App's bot account,
    never the login resume runs as. The one path that starts a review under the owner's
    identity therefore never derives a step from a loop-written PR. If the first wave's
    measurement of human minutes per work PR shows the PR list is not enough, a reminder
    written by the driver at the end of a wave (§ 8.13c, option C) is the next step. That
    reminder would never be a `next_action`.
  - **Rejected alternatives.**
    - **Derive the step from `next_action` alone.** The cursor would then carry an
      unreviewed command, which is exactly what `WB-D20`'s display existed to stop.
    - **Extend the derivation to `orchestration.loop_identity`** (§ 8.13c, option B). That
      widens the gate-minting path to loop-written PRs, and still has to refuse auto-start
      for them.
  - **What remains.**
    - "Pushed by the maintainer's login" (§ 7.1) is checked as **authored by**, plus the pin.
      GitHub's PR API records who opened a PR, not who pushed each commit, and commit
      metadata can be forged. Here is what the pin bounds:
      - Handoff pins only a head equal to its own local commit, so a push the checkout has
        not pulled sends it to the ledger PR. A pulled one is pinned.
      - Resume refuses a head that moved since.
      - A pinned architect-review refuses a head other than the pin, at its pin, before it
        posts, and on its poll.

      One window remains: a push landing between the pre-post read and the post itself.
      `gh pr review` attaches the review to whatever the head is then (a pinned run now posts
      against the pin instead: see the *Build* bullet, Known residual 2). The review body names
      the SHA it reviewed, and the poll then stops and reports, but the gate may already be
      green on the new head. Posting through `gh api …/pulls/<M>/reviews -f commit_id=<pin>`
      narrows this where the adopter's gate honours `commit_id`, and the build took it for
      pinned runs. A hand-started review carries a wider form of
      this race today: from its pin to its post, with a poll that accepts the new head. A
      fresh machine with no pin only shows the step.
      *Amended 2026-10-11 (#346):* every run, hand-started included, now posts through
      `…/pulls/<M>/reviews` with `commit_id` set to the reviewed SHA, which narrows the post half
      of that race for all runs where the adopter's gate honours `commit_id`. A head-keyed gate
      can still go green on a moved head, which only a pinned run's poll reports.
    - **Anyone with write access can edit a PR's title and body**, not only its author.
      Adding `#N` to an unrelated open PR of the maintainer's makes two PRs qualify, so
      resume waits. On a fresh machine, it shows the wrong PR for one "go". Auto-start itself
      is bound by `review_pr.number`.
    - **The same writers can edit the `## Critic pass` section.** GitHub keeps the body's edit
      history, but nothing here checks it. The record is as trustworthy as the PR body,
      which is less than a merged ledger commit.
    - **"GitHub state the session cannot shape" holds against the loop.** The loop session
      holds no GitHub token (§ 8.13a), and its PRs carry the App's author. It does **not**
      hold against an interactive session, which acts under the owner's own `gh` login and
      could open a qualifying PR itself. That session already holds the owner's credentials.
      The derived step is a review, never a merge, and the human still merges.
    - **Confirmed in the build: a PR mentioning `#N` does not bump the issue's `updated_at`.** The
      PR that carries this build (#284, "Closes #230") left `#230`'s `updated_at` at the anchored
      value. The no-op handoff still re-takes the anchor after the PR exists, as a precaution.
    - **`#209` and `#220` close with this WB-D's build**, so a sprint close is one PR. `#209`
      is the roadmap entry written before the close, and `#220` is a dirty ledger left by
      plan-sprint. They are build items, not decisions.
    - **No new `.ai/project.yml` key.** `pointers.review_pr` is a `state.json` field.
  - **Build (`#230`).** What landed, and the choices the build made inside this entry:
    - **`bin/review-step.sh`** is both halves as a pure, fixture-tested predicate: `derive`
      (the qualifying-PR rule, with `@tsv`'s escapes decoded before the word-character test) and
      `decide` (`auto | show <reasons> | merge | reviewed | many | none | unreadable`). The
      no-op handoff runs `derive` itself and requires `one <M> <oid>` with `<oid>` equal to its
      own `HEAD`, so handoff pins only a PR that resume would derive. `bin/critic-section.sh`
      is the fence-aware replace/read-back for the PR body's `## Critic pass` section.
    - **`#209`** is closed by option (b): `handoff` refuses to write `done` before the roadmap
      entry is on `origin/{pr_base}` and says the entry belongs in the sprint's last work PR.
      **`#220`** by option (a): `plan-sprint` offers "continue uncommitted" only when the
      cursor's `next_action` is or begins with `/way-of-working:handoff`.
    - **`next_action` is compared with its exact prefix**, `` review PR #M — task #N — ``, so
      `#12` cannot match `#123` and `task #230` cannot match `task #2301`.
    - **`derive` takes the `--limit` the caller gave `gh pr list` (200) and refuses, exit 2, a
      list of that many records or more.** A truncated list (newest first) could drop a
      qualifying PR and turn `many` into `one`, so it is never an answer.
    - **The `<repo>#N` form also rejects `-` and `.` before the owner**, since owner and repo
      names may contain them (`evil-owner/repo#N` is another repo).
    - **`reviewed` is honest only about the pin.** A green gate on a head `state.json` does not
      pin for that PR reads `show … head-moved` (a push landing in the post window).
    - **`fresh` means no assistant turn or work before the resume**; `/clear` and `/model` do
      not count, so the new-window, `/model`, resume sequence handoff prescribes is fresh.
    - **Known residuals, not closed by this build.** (1) *Closed by `#283`, which moved the checkout to the
      synced base; the text that follows is the record of what was open.* The pinned review
      session starts on the PR's tree (the checkout condition requires HEAD at the pin), so it
      takes its project settings from that tree. Two halves, one old and one new. *Shell execution* through a
      `SessionStart` hook is old: it happens in any session opened on the work branch, including
      the coder session the no-op handoff tells the human to open, so auto-start adds no
      capability there. *Review integrity* is what this entry introduces: the PR's `CLAUDE.md`
      and `.mcp.json` are loaded into the "fresh" reviewer as authority, and its project
      settings (session hooks, `permissions.allow`, `env` including `PATH`) stay active after
      `review-base-anchor.sh` switches to the base, so an author writes standing instructions
      and tooling for their own reviewer, and the skill's fixed `event=COMMENT` is a promise
      about the text, not about what runs in that session.
      Whether a changed plugin `ref` in that tree substitutes the predicates
      is unverified (a pin bump needs a marketplace re-add, not a session start). A handoff-side
      denylist of `.claude/`, `CLAUDE.md`, `.mcp.json` and `.claude-plugin/` was rejected: it is
      advisory (the human can start on the branch anyway) and open-ended (nested `CLAUDE.md`,
      base hooks calling scripts the PR edits). The structural fix is tracked as `#283`:
      start the pinned review from `{pr_base}`, carrying the pin in the git-ignored
      `state.json`, which amends the checkout condition above and needs its own drift rule. It
      must land before any adopter with `review.ci_gate` set bumps its plugin ref to a release
      containing this entry; the auto-start review path is not live in this repo, where the key
      is `null`. (2) A pinned `architect-review` posts through `…/pulls/<M>/reviews -f
      commit_id=<pin> -f event=COMMENT`, so the review attaches to the pin when a push lands
      after the pre-post re-read. A gate keyed on the review's `commit_id` then stays red on the
      pushed head, and one keyed on the PR's head can still go green there, which the poll
      reports. Not verified live (no gate here), and a harness denial of that `gh api` write is a
      stop, never a fall back. (3) The repo's own ledger PRs naming the task also qualify in
      `derive`, and fail closed to `show` or `many`. A draft work PR is pinned and auto-reviewed
      like any other.
    - **`derive` requires the PR's own `state` to read `OPEN`** besides being listed with
      `--state open`, so a merged or closed record can never qualify if a caller's filter slips.

- **WB-D23 (`#315`) — the orchestrator driver lives in `scripts/loop/`, not `bin/`.**
  Orchestrator plan v9 § 7.1 step 4 named it `bin/run-sprint.sh`; the maintainer chose a new
  directory under `scripts/` on 2026-10-06 (`docs/proposals/orchestrator-m2-decisions.md`,
  decision 5). The plan text now says `scripts/loop/`.
  - **The loop cannot edit its own driver.** `scripts/` is already in this repo's
    `orchestration.human_only_paths`, so a loop task whose diff touches the driver fails the
    post-exit human-only-path check. Under `bin/` the driver would sit beside the plugin's
    predicates, which a loop task may legitimately change.
  - **It gets the critic floor.** `scripts/` is already in `code_paths`, so every diff to the
    driver triggers `/way-of-working:critic-gate`'s critics, as `bin/` would.
  - **It is never shipped to adopters.** `bin/` here means `plugins/way-of-working/bin/`, which
    the plugin puts on every adopter's Bash tool `PATH` while it is enabled (`WB-D10`). The
    driver is host tooling for one maintainer's loop, not a predicate a skill calls, and has no
    business on that `PATH`. Repo-root `scripts/` is not in the plugin at all.
  - **It stays outside the coupling gate.** `scripts/coupling-check.sh` scans
    `plugins/*/` only, and the driver must name host- and repo-specific values (its own config
    path, the App's installation, the image digest) that `WB-D2` forbids in shared plugin code.
    Its repo-specific values still come from driver config, not literals, but that is the
    driver's own discipline, not a CI gate.
  - **The loop image's Dockerfile lives there too** (plan v9 § 7.3), for the same first reason:
    the image bakes in the managed settings that hold the session narrow, and the loop must not
    be able to change them.
  - **Cost.** Tests for the driver live under `tests/` like every other suite, and the driver
    is called by path, never by bare name. If the driver ever becomes something adopters run,
    this decision is reopened rather than the driver copied into `bin/`. No `.ai/project.yml`
    key.
- **WB-D24 (`#368`) — Claude stops acting as the maintainer; human code-owner approval,
  not the admin role, is the merge gate.** Decided by the maintainer on 2026-10-08. It
  **supersedes `WB-D20`**, **reverses** plan v9 § 8.5 option (a) (`restrict-updates-to-main`,
  chosen 2026-10-04 and confirmed by the 2026-10-05 test), and **amends** `WB-D22`,
  `WB-D13`, plan v9 principle 2, § 8.13c and decision 9 of
  `docs/proposals/orchestrator-m2-decisions.md` (the loop's `update`-rule precondition). It rolls out in sprints ("Identity M0…M8"). Until a repo's
  cutover task lands, that repo keeps today's model.
  - **Why.**
    - **Admin was the gate only because Claude pushes as the maintainer.** § 8.5 rejected a
      required approval because GitHub does not let authors approve their own PRs, and nearly
      every PR was authored by the maintainer's login (the rest were Dependabot's), which the agent held. That made "is an
      admin" the only gate left. It also meant every interactive session held an
      admin-capable, long-lived login while reading untrusted issue and PR text.
    - **The capability that justified it was barely used.** Measured over two months of
      transcripts and the merged-PR history of this repo and devcontainers:
      - the agent-run `--admin` cursor-sync merge (`WB-D20`) took effect **once in 219**
        cursor-sync PRs; the median time from open to merge is about three minutes
      - **30 of 341** GitHub-touching sessions ran admin-class commands of other kinds
      - devcontainers' command-text merge hook needed four non-converging review rounds,
        and stayed a tripwire, not a boundary
  - **The model.**
    1. **Agent identities are GitHub Apps, not the maintainer.** Each org gets three:
       - a *dev* App: Contents, Pull requests and Issues write; Checks, Actions and Commit
         statuses read; no Administration, Workflows, statuses write, Environments or
         Secrets
       - a *reviewer* App, which only posts the fresh-session COMMENT review: Pull requests
         write; Contents, Checks and Commit statuses read, so it can read the PR and its
         checks. Measured in #376 with CODEOWNERS covering `*`: its APPROVE does not
         satisfy the code-owner rule, and merge and push are refused. "Only posts" is
         intent, not capability: Pull requests write also reaches other review and PR
         metadata actions, which #435 measured (see the accepted residuals)
       - an *admin* App, used only in admin mode (item 5)

       They are kept separate from the loop Apps (`orchestration.loop_identity`). Tokens are
       one-hour installation tokens. The keys stay on the host and a host broker mints the
       tokens, so no key enters a container.
    2. **The merge gate is one approval from a human code owner, with no bypass actors.**
       - `CODEOWNERS` names both of the maintainer's accounts. Either one approves the
         other's PRs, and the maintainer's own pushes.
         **603-Identity amendment (2026-10-09, #377):** its repos run with one code owner,
         JaredGroves-603, and no second seat. A PR the maintainer authors, or a commit they
         push onto an agent's PR, cannot be approved by them, so human-wanted changes go
         through the dev App. Break glass is the org owner suspending the org ruleset in the
         browser, then re-enabling it; no bypass actor, and never an agent action. A
         repo-scoped admin token cannot edit the org ruleset (session 5, item 18).
       - Stale approvals are dismissed, and the last push must be approved by someone other
         than its pusher.
       - Required checks are pinned to their source app (`integration_id`). The pins were
         added to each repo's existing checks ruleset on 2026-10-08. At cutover, the checks
         move to a ruleset of their own with no bypass, apart from the approval rules.
       - GitHub's immutable-releases setting is turned on at each repo's cutover, for every
         repo that publishes releases (#439). It applies only to releases published after it
         is on, and it locks a published release's assets and tag. `release.yml` publishes in
         one call with no assets, so it keeps working.
       - `restrict-updates-to-main` is removed at each repo's cutover. 603-Identity, on the
         Team plan, carries the approval rules as an org ruleset with an explicit include
         list.
    3. **Merging is mechanical.** `ship` arms auto-merge (`--auto --squash
       --match-head-commit`) only where the repo allows it and the base requires a code-owner
       approval (`gh pr merge --auto` merges a mergeable PR at once, so elsewhere arming is an
       agent-run merge; #386). The approval is the control, the merge click is not, and
       "the human's merge is the approval" becomes "the human's code-owner approval is the
       approval". `/resume`'s agent-run merge is **removed**, not kept for cursor-sync PRs. A stalled auto-merge (armed, approved, `CLEAN`, approval on the current head) is reported by `pr-checks` with the pinned merge command, never merged by an agent: which App holds the token is not established, so an agent-run stall merge waits on a measured dev-App proof (#432, residual tracked separately).
       Routine cursor fields later move to an unprotected `ai/cursor` branch, while
       `plan_anchor` changes stay on `{pr_base}` through an approved PR.
    4. **Claude runs in per-repo dev containers.** They hold no human credential (no
       keyring, browser profile, GPG or `gh` login) and no cloud credential. There is no
       Docker socket. AWS work from a container goes through CI's read-only plan roles;
       applies run in CI behind an Environment, or by the maintainer on the host. "No GPG"
       includes a forwarded GPG agent: container commits are unsigned (`WB-D25`).
    5. **Admin mode is explicit and time-boxed.** On the host, the maintainer mints a
       one-hour admin-App token scoped to one repo and a subset of permissions, behind a
       passphrase. It reaches one container, and revoking it kills it server-side. While
       it is live, it elevates **everything** in that container. Cloud admin has no such
       mode: it stays on the host.
    6. **Trust is by declared identity, not `author_association`.** Read through an App
       token, association changes with the viewer: the maintainer's own issues read as
       `CONTRIBUTOR`. So trusted and untrusted identities are declared as `{login, id}`
       pairs in a new `identities` key, which reopens `WB-D22`'s rejection of a
       maintainer-login key. Unattended `/resume` auto-start also requires the
       maintainer's **reaction** on the exact spec comment, created after its last edit.
       An App can edit comments but cannot react as another user.
  - **Rejected.**
    - **Keeping `--admin` for cursor-sync only.** It needs a bypass-capable login in the
      agent's shell, which is the exposure itself.
    - **An admin bypass on the approval ruleset for the maintainer's own PRs.** The second
      code owner does the same job with no standing bypass.
    - **Reusing the loop Apps for interactive sessions.** That shares revocation and audit,
      and muddies the loop's "cannot do X" preflight.
    - **A machine user.** It needs a seat, a long-lived token and a mailbox.
    - **Docker-socket access for image builds.** The socket controls the VM that mounts
      the host's drives.
    - **A cloud admin mode.** No measured demand: zero cloud-touching commands from agent
      sessions in the transcript window. It has the highest blast radius, and AWS
      sessions cannot be revoked on demand.
  - **Accepted residuals.**
    - Arming (`ship`, #386) reads whether a code-owner approval rule exists, not whether the arming
      identity can bypass it. Before a repo's cutover its human login may be a bypass actor on that rule; after,
      the dev App has none. Whether GitHub completes an auto-merge using the enabler's bypass is
      unverified. It also reads the ruleset's code-owner flag, not whether `CODEOWNERS` covers the
      PR's paths: where it does not, GitHub asks only for the count, which any write-access
      approver can meet. Cutover has `CODEOWNERS` cover `*`.
    - The Claude login credential lives in each container's home volume.
    - Admin mode elevates the whole container.
    - The reviewer token exists for a few minutes after the review sandbox is destroyed.
    - Prefix deny rules stay a seatbelt.
    - The reviewer App's `pull_requests: write` reaches more than a COMMENT review (#435, item 4):
      it can dismiss a human approval, edit a PR's title, body and base, and close and reopen a
      PR. None is a merge path, but a dismissal stalls a merge and the edits can mislead a
      human reader. It cannot disable auto-merge. `dismissal_restriction` stays off.
    - An admin token scoped to one repo can still create new repositories in the org (#435,
      item 8); it cannot then read them.
    - With immutable releases on, the dev App can still edit a published release's notes and
      title, delete the release and create a draft release (#439, item 9). The tag, the code and
      any assets stay, the tag name cannot be reused, and tag creation and publishing stay
      refused by the ruleset. Nothing narrower exists: release writes ride on Contents write.
    - Auto-merge's `expectedHeadOid` is checked only when auto-merge is armed (#435, item 2);
      after a writer's push the approval requirement is the only guard.
    - Until each repo's cutover, its sessions run under the old login, so admin-class work
      happens in the browser.
  - **Amendment to `WB-D22` (`#381`).** `WB-D22` chose the running login over a schema key so the
    PR's author and its reviewer cannot drift apart. An installation token is refused `GET
    /user`, so under one the review step derives as the declared `identities.dev_app` instead
    (`review-step.sh login app`); a `null`, absent or malformed `dev_app` derives nothing. The
    drift that choice guarded against returns in App mode, because which App holds the token is
    unproven and the loop-identity guard then sees only the declared App. So App mode is capped
    at `show <M> app-mode`: it derives, it never reaches `auto`, and a human's "go" runs the
    review.
  - **Cost.**
    - Approve replaces Merge, and Dependabot PRs need an approval, with a `GITHUB_TOKEN`
      workflow arming their auto-merge.
    - Workflow-file changes need admin mode or a human push.
    - No extra GitHub Team seat: 603-Identity runs with a single code owner
      (amendment above).
    - New schema keys (`identities`, a `rulesets` list) and a dual-mode plugin release
      before any repo cuts over.

- **WB-D25 (`#522`) — commits made in a dev container are unsigned; what lands on `main` is
  signed by GitHub's squash merge.** Decided by the maintainer on 2026-10-13. It clarifies
  `WB-D24` item 4 and reverses the template's GPG-agent forwarding that #393 (PR #519) kept
  and recorded as a residual in `docs/identity/DEV-CONTAINER.md`.
  - **Why.**
    - **A forwarded agent is a signing oracle for the human.** While the passphrase is cached
      (the host's TTL is 4h, sliding), any process in the container signs commits, tags and
      detached signatures as the human with no prompt. Sessions read untrusted issue and PR
      text, so prompt injection reaches it. One agent holds both orgs' keys, so a glunk-works
      container could sign as JaredGroves-603. The pinentry prompt names the key, not what is
      signed, so it is not a presence check.
    - **The signature says the wrong thing.** A session-written commit shows Verified as the
      human (PR #519's own commit did). `WB-D20` already rejected a signature as evidence of
      authorship, and approval rules key on the pusher and the PR author, not the signer.
    - **Nothing here needs signed branch commits.** This repo is squash-only, no ruleset
      carries `required_signatures`, and the 12 most recent `main` commits were all verified,
      signed by GitHub on merge. No script, workflow or test reads a branch commit's signature,
      and the loop already commits unsigned.
  - **The rule.**
    - Inside a dev container, `commit.gpgsign` and `tag.gpgsign` are forced off, and the GPG
      tools are removed from the image. That removes the programs only. The capability is gone
      only if VS Code then forwards no agent socket, which the live check on #574 must show
      (see Residual).
    - Commits made on the host stay signed. `main` stays signed because every merge is a
      squash merge, which GitHub signs.
    - `reference/conventions.md`'s "Sign commits." is reworded to say this, since it ships to
      consumers.
    - The changes to `.devcontainer/` (a human-only path), `docs/identity/DEV-CONTAINER.md`
      and `conventions.md` land in a follow-up PR, after a live container confirms the agent
      socket is closed and the `GIT_CONFIG_COUNT` override wins over the identity file's
      `gpgsign = true`.
  - **Terraform repos (603-Identity).** No change until each repo's `WB-D24` cutover; until
    then they keep the template's forwarding and signed branch commits. At cutover, `main` is
    signed by rule, not habit: each repo is set to squash-merge only (terraform-cloudflare-dns
    allows merge and rebase commits today, which would put unsigned branch commits on `main`),
    and its ruleset gains `required_signatures` on `main` only, so unsigned container commits
    on PR branches still pass. Tested 2026-10-13 on `identity-ruleset-scratch` with an active
    `required_signatures` rule on its default branch: a squash merge of a PR whose branch
    commit was unsigned succeeded through the REST merge endpoint, and the resulting commit is
    committed by GitHub, has one parent and is `verified` (`valid`). A rebase merge was refused
    ("Rebase merges cannot be automatically signed by GitHub"). A merge-commit merge was refused
    with "Commits must have verified signatures" among its violations. `gh pr merge` was a poor
    instrument there: it refused on its own stale `BLOCKED` read before calling the API.
    Applied 2026-10-14, ahead of the `WB-D24` cutover, to `terraform-cloudflare-dns` and
    `terraform-microsoft365-entra`: squash-merge only, and a separate `wb-signatures` ruleset
    (`required_signatures` on the default branch, no bypass actors) beside each repo's existing
    rulesets, which are unchanged. Each repo then squash-merged an unsigned-branch PR through
    the REST endpoint (`terraform-cloudflare-dns` #72, `terraform-microsoft365-entra` #50): the
    merge commit is committed by GitHub, one parent, `verified` (`valid`). **Those merges went
    through the REST endpoint because the normal route refused them:** with `required_signatures`
    active, GitHub's merge box, `gh pr merge` and an armed auto-merge all block a PR whose branch
    commits are unsigned ("Commits must have verified signatures"), and the squash does not
    exempt it. The cleanup PR `terraform-cloudflare-dns` #73 showed it: blocked with an unsigned
    branch commit, then merged by its armed auto-merge once the maintainer re-pushed the commit
    signed with their host key, merge commit committed by GitHub and `verified`. So on a repo
    carrying `required_signatures`, an unsigned container commit cannot merge by the normal
    route: the rule above ("container commits are unsigned") and `required_signatures` on the
    same repo do not fit together. How container commits are signed or merged there is open;
    host-signed commits are unaffected. The workflows of neither repo hold a `git push` to
    `main`: in `terraform-microsoft365-entra` the two that run on a push to `main` are
    `contents: read`, and the only `contents: write` is the review gate's arming of squash
    auto-merge, which takes the normal route above. Each test added a `sigtest.txt` to `main`;
    both are gone (`terraform-cloudflare-dns` #73, `terraform-microsoft365-entra` #52), and the
    leftover `chore/remove-sigtest` branches were deleted 2026-10-14.
  - **Rejected.**
    - **Forwarding the GPG agent, with a longer cache.** The signing oracle above.
    - **A signing SSH key held in the container.** It is a long-lived human credential in the
      container, which `WB-D24` item 4 rules out, and an App cannot register a signing key.
  - **Deferred.**
    - **Commits created through the App API**, which GitHub signs as the bot.
    - **Authoring container commits as the dev App's `[bot]` noreply identity** instead of the
      human's `user.name`/`email`. They stay the human's, with the Co-Authored-By trailer.
    - **Signed branch commits on the terraform repos after cutover.** The only route is a
      forwarded agent, with the exposure above.
  - **Cost.** PR-branch commits show no signature, or "Unverified" if vigilant mode is on for
    the human's account.
  - **Residual, live check run 2026-10-13 (`#574`).** On the rebuilt container (image built
    from `7d1b677`), a VS Code-attached terminal showed: none of `gpg`, `gpg-agent`, `gpgconf`,
    `gpg-connect-agent`, `gpgsm` on PATH; `git` 2.53.0; `GIT_CONFIG_COUNT=2` forcing
    `commit.gpgsign` and `tag.gpgsign` to `false` over the identity file's `commit.gpgsign=true`;
    and a test commit carried no `gpgsig`. The `find` for `S.gpg-agent*` was **not empty**:
    `/home/app/.gnupg/S.gpg-agent` and `S.keyboxd` exist, but they predate the container's start,
    and a connect to either is refused. They are dead files left on the per-checkout home volume
    by the previous container, not a forwarded socket. Read the `find` result with that in mind:
    a socket that refuses a connection and is older than the container is stale; wipe the home
    volume to get a clean no-output pass. Vigilant mode is on for the maintainer account
    `Seuss27` and `JaredGroves-603`, the account that opens the terraform repos' PRs (the
    maintainer's report, 2026-10-14; it is a per-account setting the dev App cannot read).

- **WB-D26 (`#611`) — `/way-of-working:spec-task` drafts a task's spec comment and stops; the
  maintainer posts it and reacts.** Decided by the maintainer in the issue's design, and
  recorded with the spec comment on `#611`. It follows `WB-D24`'s rule that a spec comment
  auto-starts a build only when a declared maintainer wrote it and a declared maintainer reacted to it.
  - **Why.**
    - **A comment the agent posts has the wrong author.** After cutover the agent acts as the
      dev App, so `plan-anchor.sh verify` reads its comment as `untrusted` and `resume` waits.
      The spec has to be the maintainer's own comment.
    - **Posting makes approval a reflex.** The maintainer reading a draft before posting it is
      the review; a skill that posted and then asked for a reaction would turn that into a click.
    - **Planning time is too early.** A spec is checked against a tree, and the tree moves; the
      skill runs just in time, right before the task is next.
  - **The rule.**
    - The skill reads `#N` only when its author is trusted, by the same
      `gh-identity.sh author` test `resume` uses, from the default branch's `identities`.
      It reads no other issue's body and no comments, and treats the body as data.
    - It drafts in a fixed shape (goal, files touched, done when, tests, out of scope, restated
      from the issue body), checks every file, function and test it names on `origin/{pr_base}`
      or marks it **(new)**, and prints the draft only after `bin/spec-shape.sh` says `ok`.
    - It never posts, edits or reacts. `scripts/invariants-check.sh` check 18 fails the build if
      the skill's text carries a `gh issue`/`gh pr` write command, a `gh label` command, or a
      `gh api` call with a POST, PATCH, PUT or DELETE method or a field or input flag. It is a
      static check on the skill's prose, not a proof about a model's behaviour.
    - It reads the repo, backlog repo and base from the default branch's copy of `.ai/project.yml`, as
      `resume` does, and its closing message says to build in a fresh session: this one has read
      `#N`'s body, which the builder must not have in context under a map (`#496`).
    - It runs on the architect model (`models.architect`; Opus by default), with `spawn-model.sh` provenance when it is a subagent.
    - `resume` and `handoff` point at it and never invoke it. No new `.ai/project.yml` key: the
      shape is generic method, and the trusted ids and base come from `identities` and
      `pr_base`.
  - **Rejected.**
    - **Writing specs in `plan-sprint`.** That is planning time, when the tree has not yet moved
      past the spec, and it turns a triage pass into a drafting pass.
    - **Letting the skill post the comment.** The author and reflex problems above.
  - **Accepted residual.** The trust check is on the issue's author, not its last editor: an
    account with write access to the backlog (the dev App included) can edit a trusted
    author's body, and the edited text reaches the drafter. The draft is paraphrased, its last
    section lists what came from the body, and the maintainer reads it before posting.

## Status

All four of `WB-D1..D4` are implemented by this repo's existence and structure as of
`v0.1.0`. `WB-D2`'s schema (`reference/project-schema.md`), the full skill and agent
generalization against it, `WB-D5`, and the grep-based `coupling` CI job that enforces
`WB-D2` mechanically all land in `v0.2.0`. `WB-D6`'s dispositions — the Tier-3 coupling
patterns, the `/way-of-working:critic-gate` new-doc row, and the `/way-of-working:handoff` step-5 clarification — land in
`v0.4.0`; F1–F4 needed no plugin change (already fixed in `v0.2.0`).

`v0.5.0` lands `WB-D7` (superseding the `v0.4.0` range-based drift carve-out), `WB-D8`, and
`WB-D9`, plus the `invariants` CI job and `CHANGELOG.md`. It is **non-breaking** — every
existing `.ai/project.yml` stays valid untouched.

That last part was not the plan. `WB-D8` was scoped as a breaking change — `roadmap` and
`threat_model` converted to mappings behind a new required `schema_version` — until a review
pass observed that `backlog` was *already* a mapping, so the half that adopting repos were
actually blocked on needed no break at all. The breaking half is deferred until a consuming
repo demonstrates it needs one, which is also what supplies the evidence to design it
against. Worth recording because the cheaper answer was available from the start and was
found by asking "what does this actually cost the people adopting it," not by a new
requirement arriving.

`WB-D10`'s first landing (`bin/cursor-drift.sh`, #21) shipped in `v0.6.0` alongside #23's
push-identity fix; its second (`bin/entry-anchor.sh`, #66) and `WB-D11` shipped in `v0.7.0`.
`v0.8.0` (#92) lands `WB-D12` (#88) and `WB-D10`'s third landing, `bin/review-gate-state.sh`
(#91), with the park series and `/way-of-working:architect-review`. It is **non-breaking** —
no `.ai/project.yml` key added, removed, or renamed.

`v0.9.0` lands four `/way-of-working:architect-review`/`/way-of-working:pr-checks` fixes
(#97, #98, #99, #100) — no `.ai/project.yml` key touched. `v0.10.0` adds `planning.kind:
github_milestones` (#86) and its `archive-sprint` milestone-close wiring (#128), `bin/plan-
anchor.sh`; `models.second_opinion` (#72) and `bin/spawn-model.sh`; fixes 66 broken
"step N" cross-references to cite step names instead (#61) and qualifies the
absent-is-unreadable rule for the keys that already document their own absent-means-X
meaning (#127); and adds `migration_base`, the one breaking-shaped key it adds
(non-default-`pr_base` repos only — see the changelog migration note). Sprint 2 (milestone
2, all 6 issues closed) also lands this repo's own release-tag hardening (#104): `release.yml`
mints its write token from the `claude-workbench-release` GitHub App under a `main`-only,
human-reviewed `release` environment, and a new `release-tag-creation` ruleset (`creation`
only, the App as its sole bypass actor) closes the gap where any writer could hand-push a
`v*` tag past every check `release.yml` runs. Verified live, not just staged: the real
`v0.10.0` release minted its tag through the App, and both probes — a hand-pushed
`v0.0.0-probe` tag and a throwaway `on: push` workflow minting a tag via `GITHUB_TOKEN` —
were rejected (`GH013`/`422`), the second reproduced under an admin identity the ruleset
marks `current_user_can_bypass: never` to rule out a scope explanation. Sprint 2 closed at
`4bf7c7c` (the `v0.10.0` tag, PR #145), with this repo's own plugin pin bump to `v0.10.0`
(PR #147) as the sprint's last, non-blocking step.

`v0.11.0` is Sprint 3 (milestone 4, *harden architect-review's trust chain*, all 5 issues
closed) and adds no `.ai/project.yml` key. `WB-D10`'s fourth landing,
`bin/review-base-anchor.sh` (#126, PR #156), moves `/way-of-working:architect-review`'s
PR-base chain onto fixtures. `WB-D13` (#113, PR #160) replaces that skill's shared-`.git`
worktree execution with `bin/review-sandbox.sh`. This is accident containment, not isolation;
a full container is #158, in Sprint 5. `/way-of-working:resume` now verifies the default
branch's own protection while a `migration_base` is live (#125, PR #163). Two
`archive-sprint` fixes found at Sprint 2's close also land: precondition 3 gets a branch
procedure (#150, PR #165), and the milestone-close outcome gets a fixed ledger line checked
by `bin/milestone-close-line.sh` (#153, PR #167). Sprint 3 closed at `60fa315` (the `v0.11.0`
tag, PR #169), with this repo's own pin bump to `v0.11.0` (PR #170) as its last step.

`v0.12.0` closes Sprint 4 (milestone 3, *record the deferred decisions*, both issues closed)
and adds no `.ai/project.yml` key. `WB-D14` (#48, PR #174) keeps `TIER2` in
`scripts/coupling-check.sh` hand-maintained. `WB-D15` (#45, PR #176) adds a `zizmor` job to
`ci.yml`, verified live to fail on a finding. It does not enable CodeQL on
`bedrock-serverless-rag`: that toggle is a repo setting this harness cannot flip, and it is
tracked as `bedrock-serverless-rag#134`. `WB-D16` (#177, PR #178) was not a milestone item.
It raises `/way-of-working:critic-gate`'s round cap from 2 to 4, at the maintainer's
request. Sprint 4 closed at `bc4237a` (the `v0.12.0` tag, PR #179), with this repo's own pin
bump to `v0.12.0` (PR #180) as its last step.

`v0.13.0` carries Sprint 5's shipped work (milestone 5, *every config key is an explicit
decision*): `WB-D17` (#142, PR #185) makes every `.ai/project.yml` key required-present, with
`/way-of-working:resume` interviewing for a missing one through `bin/schema-complete.sh`, and
`WB-D18` (#152, PR #187) adds `/way-of-working:plan-sprint`. This repo's own pin bump to
`v0.13.0` is PR #191. The milestone's third issue, #158 (a container for architect-review's
PR execution), was designed through 13 decisions and then deferred, not built. `WB-D13`'s
amendment (PR #194) records why and when to revisit, and #158 and its follow-up #193 are
closed as not planned. PR #194 also runs `tests/review-sandbox.test.sh` in CI and marks three
`bin/` scripts executable; it landed after the tag and is unreleased. Sprint 5 closed at
`4784d2e` (PR #194), not at a release tag.

`v0.14.0` carries Sprint 7's shipped work (milestone 7, *the local green gate checks what it
claims, in reasonable time*): `WB-D19` (#197, PR #198) makes `/way-of-working:plan-sprint`
lead with a recommended placement and build order, `invariants-check.sh`'s
reach-precedes-ruleset check now matches the real `--paginate` call (#162, PR #202), and
`schema-complete.sh` reads each key table in one `yq` call, taking its fixture suite from
about 2m15s to about 15s on Git Bash (#189, PR #204). The release is PR #206 and this repo's
own pin bump to `v0.14.0` is PR #207. Sprint 7 closed at `4d63776` (PR #207).

`v0.16.0` carries most of Sprint 8's shipped work (milestone 8, *Security review phase 1:
plugin release*): `/way-of-working:resume`'s cursor-sync merge and
`/way-of-working:pr-checks`' verdict now work under a restrict-updates ruleset (#229, PR
#238; #224, PR #239), and the SessionStart hook script is stored executable behind a
fail-closed invariants check (#214, PR #240). The release is PR #241 and this repo's own
pin bump to `v0.16.0` is PR #242. Two tasks landed after the tag and are unreleased:
`/way-of-working:architect-review` and the `architect` and `security-critic` agents now
mark a PR body as data and call out bot-authored PRs, with an invariants check that keeps
the wording (#225, PR #251), and the repo is licensed Apache-2.0 (#226, PR #252). They
ship in the release the milestone 9 plan puts at that milestone's end. Sprint 8 closed at
`d4f82ac` (PR #252), not at a release tag.

Sprint 9 (milestone 11, *v0.16.0 follow-ups: merge-flow hardening*, all 7 issues closed)
adds no `.ai/project.yml` key and is unreleased; it ships in the milestone 9 release.
`/way-of-working:resume` offers the `--admin` cursor-sync merge only to an identity that can
bypass, and `pr-checks` names that identity in its admin-merge verdict (#250, PR #256).
`cursor-sync-pr.sh` requires every named required check to appear green (#245, PR #258).
`pr-checks`' blocked-state predicate reads rule parameters and answers could-not-tell for a
rule it cannot evaluate (#248, PR #260), with a stub-`gh` fixture for that block (#244, PR
#262). `invariants-check.sh` rejects `gh` output piped into a `bin/` predicate (#243, PR
#264). `ai-cursor-banner.sh` caps the length of each field it injects (#246, PR #266).
`WB-D21` keeps `hooks.json` invoking that hook directly (#247, PR #268). Sprint 9 closed at
`7be385a` (PR #268), not at a release tag.

Sprint 10 (milestone 12, *Session-start hardening: banner and branch prune*, both issues
closed) adds no `.ai/project.yml` key and is unreleased; it ships in the milestone 9 release.
`ai-cursor-banner.sh` strips control characters from each field it injects (#270, PR #275).
`/way-of-working:resume` and `/way-of-working:archive-sprint` prune a merged branch whose
local tip is the commit GitHub merged or an ancestor of it, through `bin/prune-verdict.sh`
(#271, PR #278). Sprint 10 closed at `542827e` (PR #278), not at a release tag.

Sprint 11 (milestone 9, *Sprint 8: orchestrator milestone 1*, all its issues closed) ships as
`v0.17.0`, released in #303 (PRs #305, #306). It adds the `orchestration.*` schema keys (#234),
a resume guard that refuses auto-start while the driver's lock file exists (#233), the
loop-identity name rule for `plan-anchor.sh` and `review-sandbox.sh` (#235) and for a review step
in resume (#295), the derived review step with the no-op handoff (#230, `WB-D22`), the pinned
review started from the base branch (#283), the `plan-sprint` `depends_on` marker (#232), the lean
resume path (#231), and the `archive-sprint` and `plan-sprint` fixes #209, #219, #220.
Hermetically verified, live smoke done: resume's `--admin` cursor-sync offer and `pr-checks`'
identity-naming READY (admin merge) verdict, run on 2026-10-06 against PRs #308 and #309 (#273),
and the loop host runs Claude Code 2.1.289, above the 2.1.259 floor (#236). Sprint 11 closed at
`edc21d0` (PR #306), the pin bump after the `v0.17.0` tag.

Sprint 13 (milestone 16, *Identity M1: Apps, token minting and scratch proof*, all its issues
closed) adds no `.ai/project.yml` key and is unreleased. It creates the dev, reviewer and admin
GitHub Apps (#372), `scripts/identity/mint.sh` for scoped installation tokens (#373, PR #423) and
the `wow-admin` and `wow-review-mint` host commands (#374, PR #426), recreates the scratch repo with the
target ruleset shape (#375, PR #428), and removes the unused GitHub MCP server entry (#371). The scratch
proofs of the App model are recorded in `docs/proposals/IDENTITY-SCRATCH-RESULTS.md`: sessions 1
and 2 (#376, PR #434), session 3 (#435, PR #438), session 4, immutable releases and the approval
edge cases (#439, PR #441), and session 5, the 603 org-ruleset proof (#377, PR #445). Host App
entries are keyed by role, not org (PR #444). Sprint 13 closed at `40fd3f8` (PR #445), not at a
release tag.

Sprint 14 (milestone 17, *Identity M2: dual-mode plugin v0.18.0*, all its issues closed) is
released as `v0.18.0` (PR #565) and adds one required `.ai/project.yml` key, `identities`
(`null` keeps the pre-cutover model), plus the optional `rulesets` list (#378). Every skill
now works under the maintainer's token or an App token and the agent-run `--admin` cursor-sync
merge is gone: `bin/gh-identity.sh` classifies the acting identity (#379), trust is by declared
identity and a maintainer's reaction on the spec comment (#382, #383, #548, #561), `pr-checks`
judges rulesets as a set and reports the code-owner approval gate (#384), `resume` no longer
merges (#385), `ship` arms auto-merge where an approval is required (#386), `architect-review`
posts every run through the REST reviews call, as a reviewer token under a map (#389, #502), and
`bin/hitl-gate-closed.sh` is the single predicate for a closed `hitl_gate` (#557, PR #563). The
`CHANGELOG.md` `[0.18.0]` entry carries the Migration line.

Hermetically verified; live checks deferred and tracked: the REST reviews post and the reviewer
flow have not yet posted on a gated repo, and are verified at claude-workbench's own cutover
(#458, #398); the host broker under its scheduled task is #515. Live today: `v0.18.0` is tagged,
installs at project scope and `/way-of-working:resume` runs under it in this repo. Sprint 14
closed at `cfc92be` (PR #568), the pin bump after the `v0.18.0` tag.

Sprint 15 (milestone 18, *Identity M3: host broker and dev container*, all its issues closed)
adds no `.ai/project.yml` key and is unreleased; this repo now declares its own `identities` map
(PR #583). The host token broker and its scheduled task (#392, PRs #509, #513), the
claude-workbench dev container (#393, PR #519) and `archive-sprint` reading a null
`backlog.repo` as the repo itself (#479, PR #533) shipped in `v0.18.0`. The broker was verified
live under its scheduled task against the real dev App (#515). Its registration no longer
throwing when `sh` is not on PATH (#578, PR #595) is hermetically verified; the live re-run is
deferred to #604. `WB-D25` (#522, PR #573) makes dev-container
commits unsigned, with `main` signed by GitHub's squash merge: the container drops GPG (#574,
PR #581), and the live checks and the terraform repos' signing rules are recorded (PRs #584,
#585, #587). One repo-wide `eol=lf` rule makes the container and a Windows checkout agree (#579,
PR #598), and the conventions clear the phantom `settings.json` diff after a pin bump (#570,
PR #576). The signing spike (#588) recommends REST git-data commits through the dev App; the
`bin/api-commit.sh` build is #601, in milestone 19. Sprint 15 closed at `41e8eb7` (PR #602), not
at a release tag.
