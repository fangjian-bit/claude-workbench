# Dev-workflow protocol: model routing + session handoff

This workflow runs on two models, split to keep each session lean and single-model
(the fix for hitting session limits — long Opus sessions accumulate huge context).
Work is externalized into `.ai/` so a fresh session can rehydrate cheaply instead of
inheriting a bloated context window.

## The two state layers (do not conflate)

- **`.ai/`** — *this* dev-workflow's state (how Claude Code sessions hand off).
  - `.ai/next-steps.md` (git-tracked) — the human-readable cursor: current phase/sprint, status, next action, which model to use, HITL Gate state. A **thin pointer** into the roadmap + the active sprint plan (a file, or — under `planning.kind: github_milestones` — a GitHub milestone); not a second copy of them.
  - `.ai/state.json` (git-ignored) — the machine cursor (`current_phase`, `current_sprint_id`, `sprint_status`, `assigned_model`, `assigned_persona`, `last_commit`, `next_action`, `hitl_gate`, `pointers`, `lanes`). `lanes` is the live-lane array handoff derives with `lane-state.sh` (`null` when the repo declares none, when the lane state could not be read, or on a cursor an unpark just restored, until the next handoff); resume compares it with the live state and never acts on it.
  - `.ai/context/` (git-tracked) — heavy reference loaded on demand, where a repo keeps any.
  - `.ai/archive/` (git-ignored) — retired sprint snapshots. Disposable: a retired sprint's
    durable record is in `{roadmap}` and the merged PRs.
  - `.ai/parked/` (**git-tracked**) — `<id>-state.json` + `<id>-next-steps.md` for a sprint
    set aside mid-flight (`/way-of-working:park-sprint`). Tracked, unlike its sibling,
    because a parked cursor is the *only* copy of in-flight state — nothing else records
    where that sprint stopped.
- **A repo's own products' agent state** (an orchestrator's runtime files, another tool's memory) — written when that product runs. Nothing in the dev workflow writes it.

The deep, authoritative history stays in the repo's own docs — `{roadmap}` and whatever
archive files it retires content into; `.ai/` never duplicates it, only points at the
current cursor within it.

### Two sprints, one cursor

There is exactly one live cursor. When a sprint has to be set aside mid-flight — blocked
on an outside decision while another sprint needs to run — the answer is not a second
cursor or a multi-sprint `state.json`: `/way-of-working:park-sprint <next-id>` snapshots
the live pair into `.ai/parked/<id>-*`, re-seeds the live cursor for the next sprint, and
opens the docs-only cursor-sync PR. `/way-of-working:unpark-sprint <id>` restores it
behind a `hitl_gate` naming what merged in between, because the parked `next_action` was
written against an older HEAD and must never auto-start. Swapping two sprints is a park
whose `<next-id>` is already parked: park hands straight to unpark and one PR carries
both. The directory is the authority for what is parked: the session banner derives its
`Parked:` line from it, and the ledger records each park as a **Just done** event rather
than restating the list. Both skills are
mechanical; any model may run them. `/way-of-working:resume`'s *Check reality vs. the cursor* step admits the parked
delta as `cursor-sync`, so parking costs the next session nothing.

## Model routing

- **Architect = Opus.** Decide *what* to build or *whether* a diff is correct: architecture, design, sprint/phase planning (one question at a time, HITL Gates), Architect Review of a coding diff, boundary calls, non-trivial debugging, roadmap/memory updates.
- **Coder = Sonnet.** Execute an already-defined spec: implement a sprint task, write/adjust tests, mechanical refactors, run the green gate (`gates.green` in `.ai/project.yml`), fix lint.

Which concrete model fills each role is per-repo configuration — the `models` key in
`.ai/project.yml`; Opus and Sonnet are the defaults this doc's diagrams use. (`models`
governs *sessions* by default, not subagent spawns — the plugin's agents each fix their own
default model via frontmatter, with one narrow exception: `models.second_opinion`, a
human-authorized, spawn-time override for a single late `/way-of-working:critic-gate` round
on a different model, plus its one delta-scoped re-run; see `project-schema.md` § `agents`,
`models`.) Routing is
**manual and persona-driven** — the human picks the model. Automated routing (a
proxy/router) is explicitly out of scope.

## Switch points across a sprint

**Under `planning.kind: github_milestones`, `/way-of-working:plan-sprint` runs *before* the
`OPUS (plan)` box below, not inside it.** It turns `/way-of-working:archive-sprint`'s seeded
"no milestone picked yet" into a concrete milestone placement for the human to pick up — the
backlog-triage altitude, across every open issue and milestone, not the single sprint's own
design that the `OPUS (plan)` box's milestone-description-plus-spec-comment work is about.
Its recommendation is a checkable proposal the human decides on, not a design, so it is not
drawn as its own model box in the diagram below (any model).

```
OPUS (plan)    design/plan the sprint -> write sprint_plan.md + roadmap -> /way-of-working:handoff
   |           (or, under planning.kind: github_milestones, the milestone description +      |
   |            an approved spec comment on the task issue -- project-schema.md § `planning`) |
   v   (fresh session, /model sonnet)                                         |
SONNET (code)  /way-of-working:resume -> branch sprint/NN-slug -> implement + tests -> green
   |           gate -> /way-of-working:critic-gate -> commit, push, open PR                  |
   |           -> /way-of-working:handoff                                                    |
   |                                                                          |
   v   *** NEW SESSION (context empty), then /model opus ***                  |
   |   /model alone does NOT clear context — a reviewer holding the authoring |
   |   context proofreads its own reasoning instead of re-deriving it.        |
OPUS (review)  /way-of-working:resume -> /way-of-working:architect-review <PR> -> file findings
   |           -> /way-of-working:handoff -> STOP                             |
   |                                                                          |
   v                                                                          |
HUMAN          review the PR -> approval (code-owner where required) -> merge (auto-merge where armed) -> /way-of-working:archive-sprint, plan next
```

Each box is its own **short, single-model session**. The expensive planning context
never carries into the coding session, and vice-versa — that is the token saving.

- **Primary path: session handoff** (above). Use it at every sprint boundary.
- **Secondary path: in-session subagent.** For a small, well-scoped coding task that
  doesn't warrant a full session switch, an Opus session may dispatch the Sonnet
  **`coder`** subagent (shipped in the plugin's `agents/`) via the Agent tool. The subagent's
  result returns into the Opus context, so prefer the handoff path for anything large.

## Integration gate: every sprint lands via a pull request

**A human approval gates every merge.** Nothing reaches the integration branch
without it. Claude commits and pushes freely on a sprint branch, opens the PR, and
**never merges** it directly (where the repo allows it and the base requires a code-owner approval, `ship` arms auto-merge, which waits for that approval; `pr-checks` reports an armed, approved, clean PR whose auto-merge has stalled, and merges nothing). `/way-of-working:resume` only reports a forgotten docs-only
cursor-sync PR; it merges nothing (`WB-D24`).

- **Branch per sprint:** `sprint/NN-slug`, cut from `pr_base` (`.ai/project.yml`).
- **PR base is `pr_base`.** Every sprint PR merges into that branch — normally the repo's
  default branch, but the schema key exists because it does not have to be: a repo mid a
  large, multi-sprint migration may stage work on a long-lived integration branch instead,
  with that branch's own `pr_base` pointing at itself for the duration and the default
  branch naming it as `migration_base` (`project-schema.md` § `repo`, `pr_base`,
  `migration_base`). When the migration closes, each key is reset on the branch that set
  it, and the migration lands as **one deliberate merge commit** (never a squash —
  squashing would collapse the whole migration's history into one). That is a repo-local event with its own
  local record; this doc states the rule, not the war story.
- **CI runs on the PR.** The CI workflow triggers on `pull_request:` with no branch filter
  — so a sprint branch pushed *without* a PR gets **no CI at all**. The PR is what turns the
  green gate on for sprint work; the local `gates.green` gate (`.ai/project.yml`) is a
  pre-check, not the gate of record. (A repo running a long-lived
  integration branch per the note above will also need `push:` on that branch while it's
  active, stripped once the branch retires — repo-local CI config, not this doc's concern.)
- **Claude does not merge, and does not force-push a pushed branch** without asking.
- A PR gates *integration*, not *committing* — local commits on a sprint branch are
  still free and expected.
- **A squash-merged branch is dead — never push to it again.** The squash puts a *new*
  commit on the base with the same content, so the branch's original commits are still
  "unmerged" and re-applying them conflicts. Start a fresh branch off the updated base
  and cherry-pick anything that didn't land. This bites hard because of the next rule.
- **A conflicted PR runs no CI, silently.** GitHub cannot build the `refs/pull/N/merge`
  ref when a PR is not mergeable, so `pull_request` workflows never start — and *zero
  checks* is visually almost identical to *checks still queuing*. If a PR shows no
  checks after a minute, check `mergeable` before assuming CI is slow:
  `gh api repos/<owner>/<repo>/pulls/<N> -q '.mergeable_state'`.

### The QA-critic pass runs Coder-side, before the Architect review (`/way-of-working:critic-gate`)

After the green gate and before `/way-of-working:handoff`, the implementation session runs **`/way-of-working:critic-gate`**:
a read-only critic pass over the diff that catches the cheap, mechanical, boundary-shaped
defects Sonnet-side, so the fresh-session Opus review spends its attention on judgment — and
so nothing ships with *no* critic having looked — a fully green PR with an incomplete fix
and no review having caught it is exactly the gap one standing critic pass exists to close
(the load-bearing incident behind `review.ci_gate` below). The session orchestrates it: it spawns coder and
critics itself, as siblings, so each result comes straight back to the session rather than
through a parent subagent (a subagent can spawn its own subagents only if it holds the `Agent`
tool; none of this plugin's agents does, so nothing here nests).

**The gate proposes; the human picks — it does not auto-fan-out.** Each critic is real spend
(mostly Opus subagents) and `architect`/`security-critic` overlap, so `/way-of-working:critic-gate` works out
which critics a diff *warrants* from the table below, presents that list with a reason each,
and spawns **only** what the human confirms (or the critics named explicitly in the call). A
light change may want one critic; a trust-boundary change may want the full set. That is the
diff mode. Its spec mode, which `/way-of-working:spec-task` runs on every draft, selects the
critics by rule from the files the spec lists and runs unattended under the same cap.

> **`/way-of-working:critic-gate` is defense-in-depth that runs EARLIER — it is NOT the
> fresh-session review gate (`review.ci_gate`) and never satisfies it.** Where a repo wires
> that gate, the fresh-session Architect review still happens after
> `/way-of-working:handoff`, unchanged (next section). Two properties keep the pass honest: the critics are
> **separate subagents** (fresh context — not `/model`-switching and self-reviewing), and
> they are **read-only** (they *find*; the coder *fixes* — so a critic can't wave its own
> problem through).

Propose by what the diff touches — don't offer critics that have nothing to look at:

| Diff touches… | propose |
| --- | --- |
| anything in `code_paths` | **`security-critic`** (taint / trust-boundary) **and/or `architect`** (correctness pre-review) |
| anything in `load_bearing_docs` | **`docs-consistency`** (prose-vs-code drift) |
| a repo-local agent's own trigger | that agent, proposed the same way (its definition says when it applies) |

(`/way-of-working:critic-gate`'s own SKILL carries the authoritative table, including the
newly-added-doc row; this is the overview.)

#### The agent catalog (spawn via the Agent tool by `subagent_type`)

The plugin ships five, in its own `agents/`; `agents.enabled` in `.ai/project.yml` picks
which of the review and implementation agents a repo uses, and `/way-of-working:critic-gate` proposes from that list only.

- **`coder`** (Sonnet by default, read/write) — implement one defined sprint task; the
  secondary in-session path when a full handoff is overkill.
- **`architect`** (Opus by default, read-only) — correctness + structural-invariant review;
  the `/way-of-working:critic-gate` pre-review and a `/code-review` fan-out target. **Not**
  the fresh-session review gate — `/way-of-working:architect-review` is.
- **`security-critic`** (Opus by default, read-only) — threat-model taint-flow on a
  `code_paths` diff.
- **`docs-consistency`** (Opus by default, read-only) — cross-check load-bearing prose
  against ground truth; run before a roadmap-heavy PR or at archive time.
- **`transcript-reader`** (Sonnet by default, read-only by tool surface: `Read`, `Grep`, `Glob`)
  — reads transcript text `/way-of-working:retro` has staged; spawned only by that skill,
  never a critic.

  Three of the first four are `/way-of-working:critic-gate`'s critics (`coder` implements, it is
  never proposed as one); each pins its default in its own frontmatter, and
  `models.second_opinion` is the one spawn-time override on it (`project-schema.md` §
  `agents`, `models`).

A repo may define **additional** agents locally in `.claude/agents/` (a guard-surface
auditor, a mutation-triage shard runner, a live-verification runner are shapes that have
worked) and add them to `agents.enabled`; `/way-of-working:critic-gate` then proposes them
when their own definition says they apply.

### The Architect Review is a posted GitHub review, not just prose

> **Vocabulary (two distinct checkpoints — do not use them interchangeably):**
> - **Architect Review** — the fresh-session Opus review of a coding diff, posted onto the PR.
>   Enforced by the `review.ci_gate.check` CI check, where a repo configures one. *Claude
>   does this one.*
> - **HITL Gate** — the human's approval. In practice: **the code-owner approval** (the human's merge where the base requires none). *Only the owner does this one.*
>
> An Architect Review going green does **not** pass the HITL Gate; it only unblocks it. The
> older term "HITL review" meant the first of these and is retired.

**Where `review.ci_gate` is configured, it is a CI gate**: any PR touching `code_paths`
(or the gate's own `triggers_on`) fails the `review.ci_gate.check` check until a review
carrying the configured header + attestation is posted **against that PR's current head
commit**. Docs / sprint-plan / `.ai/`-cursor PRs are exempt (no runtime behavior to get
wrong). A review of an *earlier* commit does not count — push first, then review the final
diff. Under an identities map, a host launcher at or after `WB-D38` can carry a
`Review verdict:` line on the review it posts, and a gate that reads it (`WB-D38`) fails on
`changes-needed`.

This is a check rather than a convention because the convention failed once, in the repo
this plugin was extracted from: a fully
green PR shipped a fix that covered one call site and silently left several sibling paths
still broken, the suite and CI both passed, and the review that would have caught it simply
never ran — it was only caught by a review done *after* the merge. A rule that lives only in
prose is a rule that gets skipped, which is why `review.ci_gate` exists as a schema key
rather than a paragraph: where a repo configures it, CI enforces the review; where it is
`null` (no fresh-session review gate defined for the repo), every skill that would
otherwise reference this gate must take that branch cleanly instead of asserting a
requirement that isn't wired up.

#### The review runs in a FRESH session — this is the point, not a detail

> **`/model opus` mid-session is NOT a review session.** Switching model does not clear
> context. The reviewer still holds every assumption the author made, so it re-reads its own
> reasoning and agrees with it. That is not a review; it is a proofread.

The required sequence — the same `/way-of-working:handoff` boundary the model split already uses:

```
SONNET (code)   implement -> green gate -> /way-of-working:critic-gate -> push -> open PR -> /way-of-working:handoff
                                   ↓
                        *** NEW SESSION. Context empty. ***
                                   ↓
OPUS (review)   /way-of-working:resume -> /way-of-working:architect-review <PR> -> HITL Gate
```

`/way-of-working:resume` rehydrates from `.ai/` — the externalized cursor — **not** from a memory of having
written the code. That is exactly what makes the review adversarial: the reviewer must
re-derive intent from the sprint plan and the diff, the way a stranger would, and a claim the
author found obvious has to survive being read cold.

This failed twice in practice before the attestation existed: one review was done by
`/model opus` inside the authoring session, and another was authored by Opus and would have
been self-reviewed. The gate now requires the reviewer to attest, and the check matches the
header and the attestation by literal `contains()`. CI cannot observe a session boundary; the
attestation does not prove one — it makes reviewing your own work a *knowing false statement*
rather than something that quietly happens. That is as far as a check can go; real
attribution needs a separate machine identity.

**The procedure is `/way-of-working:architect-review <PR>`, and only that.** It pins the head
SHA, checks the exemption, reviews a trusted PR by execution in an isolated sandbox
(`bin/review-sandbox.sh`, no link to the reviewer's own `.git` and no credential *handle* in
its environment — accident containment, not a container; see the script's own header for
what it does and does not close) and an untrusted
one from the required checks' own witness alone, with no local execution at all, pastes the header and
attestation out of `.ai/project.yml` (why those two strings are frozen and must never be
retyped is stated once, in `reference/project-schema.md` § `review.ci_gate`), posts it as
`POST …/reviews` with `event=COMMENT` and `commit_id` set to the reviewed SHA — never `event=APPROVE`: the approval is the human's (a code-owner approval where the base requires one), and a
Claude-issued approval would be a gate approving itself — then verifies the check went green
on the head (a pinned run: on the pin) on **both** surfaces a gate can post to, and files the non-blocking findings as
backlog items rather than into the cursor. The posted review is a timestamped, threadable
event distinct from the PR *description*: an audit record that survives edits to the
description and cannot be mistaken for the human's approval.

## The skills

- **`/way-of-working:critic-gate`** — run in the implementation session **after the green gate, before
  `/way-of-working:handoff`**. Proposes which read-only critics the diff warrants (the table above) and
  spawns only what you confirm — no auto-fan-out — then aggregates findings for the coder to
  fix, then re-runs the critics on the fixed tree and iterates under its stopping rule —
  never "until the critics are clean," which on a dense diff may never terminate.
  Defense-in-depth that runs *earlier* — **not** the `review.ci_gate` review, which still
  runs fresh after handoff where a repo wires one. Its **spec mode** is the unattended variant
  `/way-of-working:spec-task` runs on a drafted spec: critics chosen by rule, ending in a
  critic line or an escalation, never a question.
- **`/way-of-working:resume`** — run at the **start** of a session. Reads `.ai/state.json` +
  `.ai/next-steps.md` + the pointed sprint plan (a `sprint_plan.md` file, or — under
  `planning.kind: github_milestones` — the pointed milestone's description and open issues,
  `project-schema.md` § `planning`) + roadmap NEXT ACTION, states the exact
  pick-up point, and adopts the assigned persona/model.
  **It may then start the `next_action` unattended** — but only on a clean, unambiguous
  cursor: `hitl_gate` reading `closed` to `bin/hitl-gate-closed.sh` (its header defines the form), `sprint_status` `implementing`, the model
  matching `assigned_model`, no cursor/HEAD drift, no open cursor-sync PR and no unmerged
  sync branch under HEAD, and —
  under `github_milestones` — the plan anchor verified and the task issue's author trusted (or, under a map, the declared dev or reviewer App, `WB-D32`)
  (the skill's own *Auto-start* rule is the complete list). Before reading the cursor it
  reports a forgotten handoff cursor-sync PR, which it never merges (`WB-D24`).
  Anything else — a `planning`
  status, an open gate, an unreadable one, a wrong model, a dirty tree — and it states the
  pick-up point and waits. The one exception is under an `identities` map, as the declared dev
  App only: when every auto-start condition but the plan verification holds and the finder finds
  no spec comment by a declared author, or when a build it auto-started finds the approved spec
  stale against the base and no newer draft is waiting, it may instead draft one spec comment
  (posted, or held for a human) and end without building (`WB-D31`). The rule **fails closed**: not being able to tell whether a
  gate is open counts as open. The approval that carries signal is the `hitl_gate`, which
  is unchanged and still enforced; what auto-start removes is the content-free "go" that
  re-approved a `next_action` the human already approved by merging its cursor-sync PR (a
  merge on GitHub approves the ledger's **Next:**, which `next_action` should match but
  which nothing compares).
  After a **no-op handoff** (below) it also derives a review or merge step from GitHub state
  alone — never from `next_action` — and auto-starts
  `/way-of-working:architect-review <M> --pin <oid>` only when `state.json` agrees on the PR,
  its head and the task token, from a fresh session on the synced base (`WB-D22`, `#283`) — the
  no-op handoff ends there, so the reviewer never loads the PR's own hooks or `CLAUDE.md`.
- **`/way-of-working:handoff`** — run **before** switching model/session. Checks the QA-critic pass ran
  on any `code_paths` diff (a prompt, not a block — nothing else in the pipeline points at
  `/way-of-working:critic-gate`, so `/way-of-working:handoff` is where a forgotten pass gets caught). Serializes the
  current cursor to `.ai/state.json` — **including `hitl_gate`, always, even when nothing
  is open**, since `/way-of-working:resume`'s auto-start reads it — regenerates `.ai/next-steps.md` (what
  was done, what's next, which model next), and reminds you to commit if the tree is
  dirty. Does **not** archive. Because `/way-of-working:resume` may execute the `next_action` unattended,
  write it as a bounded imperative you would be content to see carried out without you; if
  it genuinely needs a decision, open a `hitl_gate` instead.
  **When the only cursor change is "review or merge PR #M next"** it is a *no-op handoff*:
  it writes `.ai/state.json` with `pointers.review_pr`, puts the critic record in the work
  PR's `## Critic pass` section, opens no ledger PR, and ends with a synced switch to `{pr_base}`
  (`WB-D22`, `#283`; `github_milestones` only).
- **`/way-of-working:architect-review <PR>`** — run in the **fresh** session after
  `/way-of-working:handoff`, where a repo wires `review.ci_gate`. Posts the review that
  satisfies the gate, verifies it went green on the head SHA on both surfaces a gate can
  post to, and files the non-blocking findings as backlog items. The only skill that
  posts a review; never approves.
- **`/way-of-working:archive-sprint`** — run **only** when a sprint has passed its HITL Gate **and** is committed.
  Moves its `next-steps.md` snapshot into `.ai/archive/`, compacts the deep record
  (completed narrative, and items closed during the sprint — resolved *and* declined —
  move to archive files: move, don't rewrite, on its own PR), closes the sprint's GitHub
  milestone under `planning.kind: github_milestones` (an open true issue is listed for a
  human call and blocks the close; an already-closed milestone or a failed read is just
  reported; otherwise a `plan-anchor.sh verify --plan match` on a known-usable anchor is
  required, or the close is staged for the human instead), advances `.ai/state.json` to
  the next sprint, and seeds a fresh
  `.ai/next-steps.md`.
- **`/way-of-working:plan-sprint`** — run under `planning.kind: github_milestones` to triage
  the backlog: unmilestoned issues, and open milestones, exist and need sorting into a
  sequence. A `sprint_status: planning` cursor whose `pointers.sprint_plan` is the "no
  milestone picked yet" state `archive-sprint` seeds is one common trigger for it, not the
  only one — backlog triage is independent of what the live sprint is doing, and this skill
  never picks which milestone becomes `pointers.sprint_plan` itself (a separate human call,
  followed by `/way-of-working:handoff`). Gathers the open issues with no milestone and the
  open milestones in due-date order (read-only), reads each issue's body and each
  milestone's description, then leads with one recommendation table — per issue, an
  existing milestone, a new one (with a drafted description), or leaving it unmilestoned on
  purpose, with a build-order position, a reason, and the evidence it cites — which the
  human accepts whole or adjusts one issue at a time; writes only what the human confirms,
  stages the milestone writes the calling environment's own write policy refuses, and posts
  a dated triage comment recording each decision. Recommends but never decides, never
  creates or closes a milestone the human hasn't named, and
  edits a build order live through `milestone-desc.sh`, the anchored milestone included,
  after the human confirms the diff. It stages the edit when the live write does not go
  through, and records the old and new order in a triage comment. Grounded triage, not
  design; any model.
- **`/way-of-working:spec-task <N>`** — the spec-comment half of the Opus planning role. Under
  an `identities` map it may be run ahead for any task whose `depends_on` is met, since the build
  re-checks the paths the spec lists and refuses a stale one (`WB-D31`); on an `identities: null`
  repo no build re-checks the paths a spec lists against the base (no `spec-fresh.sh check`), so
  drafting ahead has no such backstop there. It reads the issue only when its author is
  trusted (or, under a map, an App-filed issue a maintainer reacted to, `WB-D32`), drafts the spec comment in the fixed shape against the PR base's tree, then **posts it as the dev App or holds it for a human to post, and stops
  (`bin/spec-post.sh`)**. A declared maintainer reacts on GitHub, and once they have,
  under a map, the readers find it. Critic-gates every draft first (critic-gate's spec mode, unattended, by rule), then posts it, or
  posts it as an escalation with its open findings when the gate hits the cap or stops converging.
  Under a map, a declared maintainer's `spec-task-answer:` comment on the newest escalated comment steers a redraft of it on a later run (`WB-D39`).
  Never edits, deletes or reacts (`WB-D29`); its one label write is the escalation's. Runs on `models.architect`.
- **`/way-of-working:park-sprint <next-id>`** — set the live sprint aside mid-flight:
  snapshot its cursor into tracked `.ai/parked/<id>-*`, seed the live cursor for the next
  sprint, and open the docs-only cursor-sync PR. Mechanical; any model.
- **`/way-of-working:unpark-sprint <id>`** — restore a parked sprint to the live cursor
  behind a `hitl_gate` that names what merged since it was parked. Never leaves a cursor
  that can auto-start. Mechanical; any model.
- **`/way-of-working:ship`** — run when a task is done. Commits with a conventions-correct
  message, pushes to a branch cut from `pr_base` (never the base itself), and opens a PR
  with a length-checked title, arms auto-merge where the repo allows it and the base requires a code-owner approval (`WB-D24`), then
  **stops**; the approval the base requires is the gate, never an agent's merge.
- **`/way-of-working:pr-checks`** — report a PR's required checks and an explicit
  merge-ready verdict **without merging**; decodes the skipped/blocked/conflict traps.
- **`/way-of-working:retro`** — a session-end look at *how the session worked*, and at the
  repo's other recent sessions (lane, spec, earlier driver ones): friction
  that recurred or cost rework, each finding routed to its existing home (a backlog item,
  a memory, a small doc edit). Not for code diffs, and never a new parallel doc.
