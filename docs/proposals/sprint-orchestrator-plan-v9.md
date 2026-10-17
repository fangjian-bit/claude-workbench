# Sprint orchestrator for `way-of-working` — plan v9, with its review history

**Status:** proposal, accepted for build on 2026-10-05; nothing built yet. Committed as a
docs-only PR with its inputs and the earlier drafts; not part of any release.
**Written:** 2026-10-04, by a Claude Code session running Fable 5.1, for the maintainer of
`glunk-works/claude-workbench` and for a *separate* Claude session that will review this
document for context and bias.
**Revised:** 2026-10-04 (v4), by a second Fable 5.1 session that reviewed v3 and applied the
corrections in § 6.3. **Revised again:** 2026-10-04 (v5), by a third Fable 5.1 session that
reviewed v4 against primary sources and applied the corrections in § 6.4. **Revised a third
time:** 2026-10-04 (v6), by an **Opus 5.5** session — the first reviewer from outside the
author's model family — that reviewed v5 against primary sources and applied the corrections in
§ 6.5. The maintainer also corrected one fact during that review: the host is an **always-on
desktop, not a laptop** (§ 4.5, § 6.2, § 8.2). **Revised a fourth time:** 2026-10-04 (v7), by
a second **Opus 5.5** session — cross-family to the author, **same family as v6** — that
reviewed v6 against primary sources and applied the corrections in § 6.6. **Revised a fifth
time:** 2026-10-04 (v8), by a fourth **Fable 5.1** session — same family as the author, v4 and
v5, cross-family to v6 and v7 — that reviewed v7 against primary sources and applied the
corrections in § 6.7. **The v8 reviser also recommended and recorded the six decisions taken
after its review (§ 8.7–8.10 and the notes under § 8.2, § 8.5, § 8.6).** The maintainer had
decided that a fresh session would write v8 (§ 8.10) and then asked the reviewing session to
do it instead, so this draft repeats the reviewer-then-editor pattern § 6.6's closing paragraph
warned about. **Revised a sixth time:** 2026-10-04/05 (v9), in three separate sessions. The
v9 **review** was a third **Opus 5.5** session (same family as v6 and v7, cross-family to v8
and the author); it recommended five decisions, the maintainer took them, and it wrote an
edit spec rather than the draft. **The three tests the plan had deferred (§ 8.5, § 8.7,
§ 8.8) were then run on this machine** by a separate Opus 5.5 session, which also evaluated
and tested a GitHub App as the loop identity; four more decisions followed from the results.
The **edit** was made by a **Fable 5.1** session (this one) that applied the spec and the
results and reviewed nothing. For the first time since v5 the reviewer did not write the
draft, and for the first time the results were executed rather than reasoned. No full
review round follows v9; the only check is a diff of v9 against `V9-EDIT-SPEC.md`,
`V9-TEST-RESULTS.md` and `GITHUB-APP-EVALUATION.md`.
**Supersedes:** plan v1–v8 (all summarised in § 6; none was filed).
**Decisions:** § 8.1–8.4 were **decided by the maintainer on 2026-10-04** after the v4
review, each marked *Decided* with the reasoning and the alternatives weighed. The v6 review
did **not** change any decision; where it found a decision inconsistent with the rest of the
plan it added a *v6 review note* under that decision, and it raised **two new open decisions**
(§ 8.5 merge restriction on GitHub, § 8.6 devcontainers' Docker-dependent gate) that the
maintainer has not yet answered. The v7 review changed no decision either. It rewrote § 8.5's
options (one was wrong, one was missing), added an option to § 8.6, and moved one v6
recommendation that had been written into principle 10 as a rule back to a recommendation.
**After the v7 review the maintainer decided six more items on 2026-10-04**, each taking the
v7 reviewer's recommendation: § 8.5 (option a on all four repos), § 8.6 (d, then e), the
§ 8.4a critic floor, the § 8.1 date question, the § 8.2 move trigger, and deferring § 7.4's
merge-triggered dispatch (recorded under § 8.3). The v8 review changed no decision. It found
two documented platform features both Opus passes had missed (Docker's `isolated` gateway mode
for `--internal` networks, § 4.5; Claude Code's `--restricted` flag, § 4.2), each of which
replaces an undocumented control in § 7.3, and it found § 8.5's `--admin` claim and § 8.2's
"routine" wording untestable as written. **After the v8 review the maintainer decided six more
items on 2026-10-04**, each taking the v8 reviewer's recommendation: the egress mechanism
(§ 8.7), the settings-loading form (§ 8.8), the meaning of "routine" in § 8.2's trigger, the
scope of § 8.5's scratch test, the host's plain-file secrets (§ 8.9), and the editorial
corrections and who applies them (§ 8.10). **After the v9 review the maintainer decided five
more items on 2026-10-04**, each taking the v9 reviewer's recommendation: the driver spawns
the critics (§ 8.4a), the scratch test runs checks 1–3 now (§ 8.5), private repos may run on
this host under two conditions (§ 8.2), the plain-file secrets are host hygiene (§ 8.9), and a
fresh session writes v9 after the tests run (§ 8.11). **After the tests, four more on
2026-10-04/05:** the loop container runs without Claude Code's sandbox (§ 8.8), the critic
launch line names the agent's tools (§ 8.4a), the per-PR merge check drops
`viewerCanMergeAsAdmin` (§ 8.5), and the loop identity is a GitHub App, not a machine user
(§ 8.12). **After the edit, four more on 2026-10-05** (§ 8.13), recommended by the editor in
conversation and taken by the maintainer: the driver pushes after exit and the session holds
no GitHub token; loop-spawned critics get no Bash; loop PRs stay outside resume's derived
step; the § 8.1 name rule is implemented in milestone 1. What remains open is in § 9.
**Synced 2026-10-07 (#315)** to the decisions in `orchestrator-m2-decisions.md`: § 7.1 steps
4–6 cut into three milestones, the driver in `scripts/loop/` (WB-D23), and the loop image's
base named in § 7.3 and § 8.2. No review round; not a v10.

---

## 0. How to review this document

You are reading this because the maintainer wants an independent check. The authoring
session had these properties, which a reviewer should treat as potential bias:

- It ran on **Fable 5.1**. Its eight critic and research subagents ran on Fable 5.1 (2), Opus 5.5 (2),
  the `claude-code-guide` agent (3), and a general web-research agent (1). No human reviewed
  any intermediate finding. Same-family judges are known to inflate agreement.
- It **selected which critic claims to verify**. Claims marked *verified by author* below were
  checked by the authoring session against the file or URL named. Claims marked *reported by
  subagent* were not independently re-read. Everything else is the author's own reasoning.
- The measured data (§ 3) comes from **local transcripts on one machine** and from GitHub PR
  metadata. The transcript scan de-duplicated one mirrored project directory; it did not
  reconcile against Anthropic's own usage accounting, which is not exposed to tools.
- The author produced v1, then argued against parts of v1 in v2 and v3. Watch for
  over-correction in both directions: v3 was more conservative than the evidence required in
  places; v4 swung back on one point (§ 8.3) further than the evidence allows; v5 reversed it.
- The author never ran a headless `claude -p` session, never ran a GitHub Action with the
  plugin, and never tested a hook under `--permission-prompts none`. **Neither did the v3 or
  v4 reviewer.** All feasibility claims about those paths are from documentation, and § 4
  treats the documentation as stable when it is not (see the `--bare` note in § 4.1 and § 9).
- **v4 and v5 are same-family revisions.** The v3 reviewer re-verified every § 2 row, re-ran
  `pr_analysis.py` and `daily_usage.py`, and fetched the § 4 URLs; its corrections are in § 6.3
  and its claims are marked **[R]** in § 4. The v4 reviewer did the same again, read the raw
  hooks.md, settings.md, permissions.md and Microsoft's wsl-config page, and checked the
  consuming repos for `.husky/`, `package.json` and `.gitmodules`; its corrections are in § 6.4
  and its claims are marked **[V]**. Where v5 disagrees with v4's framing (§ 6.1 note, § 8.3),
  that is one reviewer's reading against another's, and § 6.4 gives the evidence for each.
- **v6 is the first cross-family revision** (Opus 5.5). It wrote a first-pass verdict on v5
  before opening v4 or v3, then verified against the raw hooks.md, settings.md, permissions.md,
  headless.md and the mods admin page, the three consumers' live rulesets, devcontainers'
  `.ai/project.yml`, and re-ran `pr_analysis.py` (devcontainers). Its claims are marked **[O]**
  in § 4. It did not open `analysis/session-export/`. Its own likely biases: it reads the
  plan as a security reviewer first (most of its findings are in § 7.3 and § 8.2), it is the
  same family as the plan's three Opus critics, and it found what it predicted in its first
  pass, which is either confirmation or confirmation bias. It did **not** execute anything
  either: no container was built, no ruleset was changed, no `claude -p` was run.
- **v7 is a second Opus 5.5 pass**, so it is cross-family to the author but **same family as
  v6**. It wrote a first-pass verdict on v6 before opening v5, then verified against: the
  raw settings, settings-reference, permissions, hooks, sandboxing, skills, sub-agents,
  memory, network-config and mods admin pages; docs.github.com (rulesets, bypass, approvals,
  forks, the compare API); docs.docker.com (`--internal`, seccomp, WSL file sharing, Enhanced
  Container Isolation); all four live rulesets, read with both gh accounts; who authored and
  merged the last 100 merged PRs in each repo; devcontainers' `gates.green`, its CI workflows
  and image Dockerfiles; critic-gate's table; resume's merge command and devcontainers'
  `merge-guard.sh`. It re-ran `pr_analysis.py` (claude-workbench). Its claims are marked
  **[O2]** in § 4. Two research subagents (Opus) fetched the docs; v7 re-read the two quotes
  its § 8.5 rewrite rests on from the raw GitHub page itself, and marks the rest as reported by
  subagent where it did not. It did not open `analysis/session-export/`, v4 or v3. Its own
  likely biases: **the same security-first reading as v6** (most of its findings are again in
  § 7.3 and § 8.5), the same reliance on documentation for behaviour nobody ran, and a
  same-family tendency to agree with v6's structure while correcting its details. It executed
  nothing either.
- **v8 is a fourth Fable 5.1 pass**, same family as the author, v4 and v5, cross-family to
  v6 and v7. It wrote a first-pass verdict on v7 before opening v6, then verified against: the
  raw settings, settings-reference, permissions, hooks, sandboxing, cli-reference, headless,
  skills, sub-agents, memory, network-config, managed-settings, permission-modes and mods
  admin pages, plus the Claude directory reference; docs.github.com (available rules,
  creating rulesets, approving, fork approvals, events, OIDC reference, the compare API);
  docs.docker.com as markdown (`network create`, bridge driver, port publishing and gateway
  modes, iptables, seccomp, WSL backend, Desktop settings, Enhanced Container Isolation and
  its limitations); gh's own `pr merge` source (`pkg/cmd/pr/merge/merge.go`, `http.go`); all
  four live rulesets with both gh accounts; the § 2.2 authorship row; devcontainers'
  `gates.green`, `build.yml`, `image-scope.sh`, `build-and-test.sh`, `lint.yml`,
  `verify-selftest.yml`, `architect-review-gate.yml`, base Dockerfile and `merge-guard.sh`;
  bounty-infra's `gates.green`, `plan-infra.yml` and `ci.yml`; this repo's `ci.yml`,
  `critic-gate/SKILL.md`, `resume/SKILL.md` and WB-D20. It re-ran `pr_analysis.py`
  (infrastructure-core). Its claims are marked **[F8]** in § 4. It did not open
  `analysis/session-export/`, v4 or v3. It executed nothing either. **The auto-mode
  classifier refused its check for plain-file credentials on this host** (existence only,
  not contents), so § 4.5's WSL-distro line is an inference the maintainer verifies
  (§ 8.9). Its own likely biases: same family as the author, so a pull back toward v3–v5's
  positions (it reverted none of v6's or v7's structure, and sided with v5 against v6 in
  one place while finding v7's version of that verdict overstated too); the same reliance on
  documentation as every pass before it; and, having found two documented features by
  searching outside the previous passes' vocabulary, a tendency to over-trust documentation
  it found itself. It also recommended and recorded the decisions taken after its review.

- **v9 is a third Opus 5.5 review, with the edit made elsewhere.** The reviewer is same
  family as v6 and v7, cross-family to v8 and the author. It wrote a first-pass verdict on
  v8 before opening v7, then verified against: the raw cli-reference, headless, permissions,
  permission-modes, sandboxing, settings-reference, tools-reference and authentication pages;
  docs.github.com (merge queues, rulesets); gh's `merge.go`; the GraphQL schema by
  introspection; all four repos' rulesets with both accounts, including the tag and push
  rulesets v8 omitted; the three consumers' workflows for `merge_group` triggers;
  devcontainers' `build.yml` and the jobs API on its last six PR runs; bounty-infra's
  `plan-infra.yml`; this repo's WB-D20, critic-gate and resume lines. It re-ran
  `pr_analysis.py` (bounty-infra, the one repo nobody had run). Its claims are marked
  **[O3]** in § 4. It did not open `analysis/session-export/`, v4 or v3; v6 and v5 only at
  the lines § 6.7 cites. It executed nothing and changed no GitHub setting. It did **not**
  edit the plan: it wrote `V9-EDIT-SPEC.md` (five decisions, a nine-item editorial bundle,
  the § 6.8 text) for a separate session to apply. Its own likely biases (§ 6.8): same
  family as v7, so its verdict on § 6.6 item 9 sides with its own family and should be
  weighed by the quoted lines; the security-first reading of v6 and v7; and the over-trust
  of its own finds that it named in v8.
- **The tests were run by a fourth session, also Opus 5.5**, on this machine on
  2026-10-04/05 (`V9-TEST-RESULTS.md`): the `isolated` gateway probe (§ 8.7), the
  `--restricted` launch form as amended by D1 (§ 8.8), and § 8.5's checks 1–3 on a scratch
  repo with a machine user; then the GitHub App evaluation and its scratch-repo test
  (`GITHUB-APP-EVALUATION.md`). Its claims are marked **[T]** in § 4. Its own bias note,
  carried into § 6.8: the session that recommended D1–D5 was the same family, and two of
  the tests check those decisions' premises; its verdicts rest on the init events, tool
  calls, server responses and rule-suite logs it quotes, not on interpretation. One result
  went against D2's chosen signal and the maintainer changed it (§ 8.5).
- **v9's editor is a Fable 5.1 session (this one).** It applied the spec and the results
  file, reopened no decision, re-verified no evidence and reviewed nothing. Where the
  results contradicted the spec it applied the results, as the spec instructs, and listed
  each case in its hand-back. It did not open `analysis/session-export/`. **After the
  edit it also recommended the four decisions in § 8.13**, one at a time, with options and
  costs, and the maintainer took each; so the editor, like every reviser before it, has
  now both recorded and recommended. A read-only Opus 5.5 session then reviewed § 8.13
  against § 7.2 and § 7.3 (recorded under § 8.13); its findings are applied.

Suggested checks (v9; the v8 list is superseded and kept below for the record):
1. **Diff-check v9 against `V9-EDIT-SPEC.md`, `V9-TEST-RESULTS.md` and
   `GITHUB-APP-EVALUATION.md`.** Every decision, correction and test result in those three
   files should appear here once, in the section it names, and nothing else should have
   changed. That is the only review v9 gets.
2. After that, the next work is what the tests left open (§ 9, "Open after v9"), then the
   driver, starting with the full § 7.3 container assembled as one piece.

Suggested checks for the reviewer (v8; superseded, kept for the record):
1. Re-derive the § 3 PR counts for **bounty-infra**, the one repo nobody has re-run. The
   § 3.1 table has no row for it; add one if the numbers are worth recording.
2. The two documented features v8 introduced, from the raw pages: Docker's
   `com.docker.network.bridge.gateway_mode_ipv4=isolated` (docs.docker.com, port publishing,
   Gateway modes) and Claude Code's `--restricted` (cli-reference.md:123). Does each do what
   § 7.3 now relies on? Does `--tools Bash` under `--restricted` restore Bash with the
   sandbox, and do `--plugin-dir` skills still load? Does `isolated` mode work on Docker
   Desktop's WSL2 backend, and is the proxy container still reachable by container IP?
3. § 8.5's scratch test as rewritten (§ 8.5, decided after v8): five checks, and the
   `--admin` question reframed as "does GitHub report `mergeStateStatus: BLOCKED` to a
   bypass-eligible viewer". Is that the right question? Read gh's `merge.go` yourself.
4. § 8.2's trigger as re-keyed (per-sitting away-blocks on the Docker Desktop host, an
   `orchestration.placement` key the governor reads). Is it consistent with § 7.4 as
   rewritten, and does it close the "routine" ambiguity or move it?
5. § 6.7's verdicts on § 6.6 items 7 and 9, where a Fable pass judges one Opus pass's
   reading of another Opus pass and of a Fable pass. Read v6 principle 3 (L511–512), v6
   § 8.4a (L1193–1195), v5 § 3.1 (L207), v5 § 8.3 (L861) and v5 § 6.4 (L652) yourself.
6. Whether § 7.3 is now simpler than v7's, or only differently complicated. v8 removed the
   host-side gateway rule, the `project`-only fallback and `--disallowedTools` as a layer;
   name anything it should have removed and did not, and anything it removed that mattered.
7. The six decisions taken after the v8 review (§ 6.7's last paragraph): can the plan carry
   each out, and does anything in § 4–§ 7 contradict it? The reviewer that recommended
   them also recorded them.
8. Read § 7.3 as an attacker again. v4 found the watcher; v6 the config-dir unlink, the
   `permissions.allow` merge and git config execution; v7 the live-reloaded helpers and the
   `--internal` gateway; v8 found nothing new and says so. Look for the next.

---

## 1. The request and the constraint

**Request (2026-10-04).** The maintainer is the bottleneck for getting sprint work done
across several repos that consume the `way-of-working` plugin. They asked whether a
Fable-driven sprint/milestone orchestrator could direct subagent-based task execution to the
same quality bar without them dispatching each item, acknowledging it would change merge
rules and more. They then added two requirements and asked for repeated critical review:

- **Context management and token spend control are first-class design requirements.**
- **Everything must run on the maintainer's Claude subscription.** No API-key billing, no
  purchased usage credits.

**What the maintainer did NOT ask for.** Nothing here was approved. Every "decision" in § 8 is
theirs to make. The maintainer has not said whether a dedicated Linux host is acceptable.

---

## 2. Repo context and the trust rules the plan must hold

Source repo: `glunk-works/claude-workbench` (public). Consumers read in this analysis:
`603-Identity/devcontainers` (public, GitHub Team org), `603-Identity/infrastructure-core`
(private, Team org), `glunk-works/bounty-infra` (public, free org). Both orgs are visible to
the `JaredGroves-603` gh account; the `Seuss27` account cannot see 603-Identity private repos.
Pins on 2026-10-04: devcontainers and bounty-infra at `v0.15.0`, infrastructure-core at
`v0.14.0`. *Verified by v4 reviewer.*

### 2.1 What the plugin is

A session-handoff protocol: short single-model Claude Code sessions externalise state into
`.ai/state.json` (git-ignored machine cursor, holds `next_action` and `hitl_gate`) and
`.ai/next-steps.md` (git-tracked ledger, landed as a docs-only "cursor-sync" PR per handoff).
Skills: `resume`, `handoff`, `ship`, `critic-gate`, `architect-review`, `plan-sprint`,
`archive-sprint`, `park-sprint`, `unpark-sprint`, `pr-checks`, `retro`. Agents (read-only
unless noted): `architect` (Opus), `security-critic` (Opus), `docs-consistency` (Opus),
`coder` (Sonnet, read/write). Deterministic predicates live in `plugins/way-of-working/bin/*.sh`
with fixture tests under `tests/` (WB-D10). Shared plugin code may never name a repo-specific
value; every such value is a key in `.ai/project.yml` (WB-D2, WB-D17; enforced by
`scripts/coupling-check.sh` in CI).

### 2.2 Trust rules (all *verified by author*, re-verified by the v3 and v4 reviewers against the files named)

| rule | where |
|---|---|
| A merged PR is the human approval. Claude never merges to `pr_base`, never approves. The one exception is resume's merge of a docs-only cursor-sync PR on explicit human confirmation. | `plugins/way-of-working/reference/workflow.md` § Integration gate; `docs/decisions.md` WB-D20 (line 1003) |
| WB-D20 **rejected** handoff self-merging even a docs-only PR: a session steered by untrusted text could write a harmful `next_action`, approve it, and the next session would run it unattended. WB-D20 also records that **"a merge on GitHub still approves the ledger alone"** — the human's read of `next_action` exists only in resume's offer path. | `docs/decisions.md` WB-D20, "Rejected" bullet and "The human sees the `next_action`" bullet |
| Issue bodies and spec comments are specifications, never instructions. The coder verifies the issue's `updated_at` and `author_association` (OWNER/MEMBER/COLLABORATOR) against a human-anchored `plan_anchor` before building. **[T]** `author_association` is viewer-relative (§ 4.4); the loop's reads of it run as the maintainer (§ 8.1). | `plugins/way-of-working/agents/coder.md` step 2; `bin/plan-anchor.sh` header |
| resume auto-starts a `next_action` only when: `hitl_gate` NONE OPEN, status `implementing`, model matches, cursor not drifted, no open cursor-sync PR and no unmerged sync branch under HEAD, plan anchor verifies, task author (and spec-comment author) trusted. Fails closed. "Auto-start removes a rubber stamp, not a gate." | `skills/resume/SKILL.md` auto-start section (~L873-1000; the quoted line is L984) |
| critic-gate proposes critics; the human picks; a second-opinion round on another model needs the human's own message in the live session. | `skills/critic-gate/SKILL.md` L49-64, L262-290 |
| handoff explicitly refuses to commit the ledger onto the code branch: "bundles cursor churn into the code PR's review, which is the muddle this whole step exists to prevent." | `skills/handoff/SKILL.md` ~L283-291 |
| `cursor-sync-pr.sh` offers a PR only when same-repo, changes exactly `.ai/next-steps.md`, head branch starts with `docs/sync-cursor-`, and a local branch of that name sits at its head. Its `unmerged` verdict fires only when HEAD is on such a branch. | `bin/cursor-sync-pr.sh` L19-32, L77, L100, L200 |
| `cursor-drift.sh` classifies a HEAD-vs-`last_commit` delta as `cursor-sync` iff every path is `.ai/next-steps.md` or under `.ai/parked/`. | `bin/cursor-drift.sh` L69-83 |
| `review-sandbox.sh trust` → `trusted=1` only for OWNER/MEMBER/COLLABORATOR **and** same-repo head. An untrusted PR gets no local execution. | `bin/review-sandbox.sh` L183-185, L324 |
| Branch ruleset on `main` (this repo, `protected-integration-branches`, id 19562210): deletion, non-fast-forward, pull_request (0 required reviewers), required checks `lint`, `coupling`, `invariants`. No bypass actors. | `gh api repos/glunk-works/claude-workbench/rulesets/19562210` |
| **All four repos require 0 approving reviews** (`required_approving_review_count: 0`, no bypass actors) on `main`: claude-workbench (above), devcontainers (id 24183176), bounty-infra (id 19438326), infrastructure-core (id 20586659, which also requires `architect-review`). Each also has `require_extra_approval_for_unattributed_changes: true`. v7 looked it up: it is the "additional approval for unattributed **Copilot** pull requests" setting, and "has no effect if the ruleset requires zero approvals". Consequence: any identity with Contents write can merge a PR whose required checks are green. Principle 2 depends on this (§ 6.5 item 1, § 8.5). *[O], read live 2026-10-04; [O2] re-read with both gh accounts. `bypass_actors` reads `null` on the glunk-works repos to the account without admin, and `[]` to the owner.* **[F8]** re-read all four on 2026-10-04, same result. Only claude-workbench's and bounty-infra's rulesets carry `deletion` and `non_fast_forward`; the 603-Identity rulesets carry `pull_request` and `required_status_checks` only. **[O3]** v8 offered infrastructure-core's second active ruleset, `block-secret-bearing-files` (24418824), as precedent for § 8.5 (a)'s separate-ruleset layering; it is `target: push` (`file_extension_restriction`, `file_path_restriction`, `conditions: null`), not a branch ruleset, so it is not. The real precedent is devcontainers' `release-tags` (24335229): a separate ruleset on tags `v*` and `devc-automerge-*`, bypass actor `RepositoryRole` 5 (admin) with `bypass_mode: always`, carrying `creation`, `update`, `deletion` and `non_fast_forward` (**[T]** read live 2026-10-04; the spec said `update` alone). Other live rulesets v8 omitted: claude-workbench `protected-release-tags` (20554576) and `release-tag-creation` (23936220, Integration bypass); infrastructure-core's disabled Copilot review ruleset (19359056). | `gh api …/rulesets/…`; https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets |
| **The maintainer's account authors and merges almost every PR.** In the last 100 merged PRs per repo: claude-workbench 100/100 and bounty-infra 70/75 authored and merged by Seuss27 (the rest dependabot); devcontainers 100/100 and infrastructure-core 97/100 by JaredGroves-603. The interactive Claude sessions push under the maintainer's own login, so "the human's PR" is in practice a Claude-written PR the human merges. GitHub: "Pull request authors cannot approve their own pull requests." This decides § 8.5 option (b). *[O2]; [F8] reproduced exactly on 2026-10-04 with both accounts (the remainder is `app/dependabot`: 5 on bounty-infra, 3 on infrastructure-core).* | `gh pr list --state merged --limit 100 --json author,mergedBy`; docs.github.com, approving a pull request with required reviews |

### 2.3 devcontainers specifics (the consumer with the fresh-session review gate)

*Verified by author* and re-verified by both reviewers unless noted.

- `review.ci_gate.check: architect-review` is a **required status**. The gate workflow
  (`.github/workflows/architect-review-gate.yml`) counts a review comment only when its
  author's numeric user ID is in `REVIEWER_IDS: "281693088"` (the owner), and posts the status
  against the PR head SHA. It is an **existence** gate, not a verdict gate: it checks that a
  review was posted, not what it concluded. Triggers: `pull_request` (opened/synchronize/
  reopened), `issue_comment`, `pull_request_review`. Its own header notes that `pull_request*`
  runs use the PR's **own copy** of the workflow (issue #93), while `issue_comment` runs use
  the default branch's copy.
- Open decisions on that gate: **#93** (a same-repo PR can edit the gate it is checked by) and
  **#122** (review-gate trust model, F9b: any writer can mint the status from their own PR
  workflow; decide before auto-merge is turned on). devcontainers' own ledger (L21-22) commits
  the owner to deciding both by **2026-10-17**; on GitHub both sit in the milestone *Repo
  hardening: review gate and CI*, due **2026-12-15**. The earlier date is a ledger promise, not
  a GitHub deadline. **#139** (turn on auto-merge for verified image bumps, milestone *P2:
  adoption waves*, due 2027-01-29) names #122 as its prerequisite in its body; v9 adds an
  auto-merge-under-restrict-updates check as a second precondition (§ 8.5, § 8.6).
- `.ai/project.yml` `code_paths` includes `images/`, `template/`, `tests/`, `tools/`,
  `.github/`, `.trivyignore.yaml`, `.gitattributes`, `.ai/project.yml`, `.claude/` — with
  comments saying an edit weakening any of them must route to review.
- `gates.green` is eight shell commands. Three of them execute **tree-resident scripts**:
  `bash tools/tests/run-gate-tests.sh`, `bash .github/scripts/build-and-test.sh local`,
  `bash tests/template-proof.sh`. This matters for § 6.1 and § 8.3. *Verified by v4 reviewer.*
  **Five of the eight need a Docker daemon** (v6): hadolint, Trivy and zizmor via
  `docker run`, `build-and-test.sh local` (builds all three images and smoke-tests them) and
  `template-proof.sh` (brings up the template with the devcontainer CLI). The file's own
  comment says "Needs Docker, git, jq, Go 1.26.3, node with npm". The remaining three are
  shellcheck, `go test` and `run-gate-tests.sh`. This matters for § 8.2 and § 8.6: the
  session cannot run devcontainers' gate inside a container without Docker access. *[O]*
  **v7:** of the five, only two need a daemon by nature. hadolint, Trivy and zizmor are
  linters run through `docker run` for version pinning; zizmor is already installed in the
  base image (`images/base/Dockerfile` L23), and hadolint and Trivy ship as single static
  binaries. `build-and-test.sh local` and `template-proof.sh` genuinely build and run
  containers. **CI already runs all five on every PR** that touches anything image-shaping:
  `lint.yml` runs hadolint, Trivy, shellcheck and zizmor; `build.yml`'s required job "Build and
  smoke-test (no push)" runs `build-and-test.sh local` and `template-proof.sh` unless
  `.github/scripts/image-scope.sh` finds a docs-only diff (`build.yml` L56-72); and
  `verify-selftest.yml` runs `go test` and `run-gate-tests.sh`. *[O2]* **[F8]:** image-scope
  gives `build=1` only for `images/*`, `template/*`, `tests/*`, `.github/scripts/*`,
  `.github/workflows/build.yml`, `.trivyignore.yaml` and `.gitattributes`, read with
  `--no-renames` so a move out of scope still builds, and it fails closed on an empty diff.
  The image-shaping tool manifests live under `images/base/tools/` (base Dockerfile L117), so
  the list covers what shapes an image. A PR touching only `tools/devc-verify`, `.claude/` or
  `.ai/` gets no image build in CI, by design; `lint.yml` and `verify-selftest.yml` have no
  path filter and always run. This bears on § 8.6 (e): the two deferred steps run in CI only
  when image-scope says so, and the digest must record which it was.
- `.claude/settings.json`: deny rules cover only `git push --force*`,
  `git push --force-with-lease*`, `git push -f`, `git commit --no-verify`, `-n`,
  `git push --no-verify` (Bash and PowerShell forms). One PreToolUse hook:
  `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/merge-guard.sh"` on Bash|PowerShell.
- `merge-guard.sh` blocks command segments starting with `gh pr merge` except resume's exact
  cursor-sync shape; its own comments list residuals: `python -c`, `xargs`, and "if this script
  cannot run at all (no bash), the call is not blocked. The main ruleset still requires every
  check." A merge via `gh api -X PUT repos/…/pulls/N/merge` is **not** matched. Its header
  also records the platform rule this plan leans on in § 7.3: "a deny rule wins over every
  allow rule and hook."
- Ruleset `main-required-checks` (id 24183176): pull_request + required_status_checks. Required
  checks: `hadolint (Dockerfiles)`, `Trivy misconfiguration (Dockerfiles)`,
  `shellcheck (scripts)`, `zizmor (workflow security)`, `Build and smoke-test (no push)`,
  `architect-review`, `selftest`.
- None of the four repos (this one and the three consumers) has `.husky/`, `package.json`, or
  `.gitmodules`. *Verified by v4 reviewer via `gh api …/contents/…` (404 on each).*

---

## 3. The measured problem

### 3.1 Where the human's time goes (GitHub PR metadata, *verified by author*, reproduced by both reviewers)

Classification by PR title prefix: `docs(cursor)`/`docs: sync cursor`/park/anchor → **cursor**;
`docs: mark`/`docs(roadmap|sprint|decisions|ledger)`/`chore(release|claude|ai)` → **record**;
dependabot; everything else → **work**. Script: `pr_analysis.py` (see § 10).

| repo | window | work PRs | cursor PRs | record PRs | cursor per work | median open→merge (work) | median work PR size |
|---|---|---|---|---|---|---|---|
| devcontainers | 2026-09-28 → 10-04 | 55 (53 merged) | 81 (68 merged) | 7 | **1.53** | 15 min | 64 lines |
| infrastructure-core | 2026-08-14 → 10-01 | 84 | 48 | 63 | 0.57 | 11 min | 166 lines |
| claude-workbench | 2026-07-22 → 10-02 | 71 | 52 | 31 | 0.73 | 12 min | 129 lines |
| bounty-infra, by title (v9) | 2026-06-26 → 10-02 | 69 (66 merged) | 2 | 2 | **0.03** | 4 min | 89 lines |
| bounty-infra, by files or "sync cursor" title (v9) | same | 33 merged | 22 (21 merged) | — | **≈ 0.67** | 3 min | 69 lines |

Busiest day, devcontainers (2026-10-02): **31 merges over 11.3 h, median 9 min between
merges**, 13 of them work. The merges run from 12:22 to 23:37 UTC, with at least one merge
in every hour but 17:00: **the human was present for the whole window.** infrastructure-core
2026-09-07: 29 merges over 22.8 h. **bounty-infra (v9, [O3]):** `pr_analysis.py` run
2026-10-04 with the Seuss27 account: 86 PRs, 13 dependabot. **The title classifier misses
bounty-infra's grammar** (`docs(SE): sync cursor …`), which is why the by-title row reads
0.03; classifying by files (a PR touching only `.ai/next-steps.md`) or a "sync cursor" title
gives 22 cursor PRs (21 merged) against 33 merged work PRs, ≈ 0.67. Busiest day 2026-07-23:
15 merges over 21.5 h, median gap 31 min. § 10 notes the classifier is tuned to the other
repos' titles.

One issue end to end (devcontainers #160, a +4/−1 fix): PR 237 cursor → PR 238 code →
PR 239 cursor "shipped; architect review next" → PR 241 cursor "reviewed and merged". Three
PRs, three sessions (coder, handoff, fresh-session reviewer), ~9 human touches, 25 minutes.
**14 cursor PRs in the last 200 exist only to say "architect review next"** (title match on
"review next"; v3 said 16 without a reproducible rule).

Sprint 7 on this repo (PRs #200–#208): 9 PRs for 2 issues (#162, #189), 7 of them ceremony.
v3 said 11; the extra two were sprint-06 close-out PRs.

Decision backlog the loop cannot clear: devcontainers' ledger lists 4 owner-owned items;
infrastructure-core has 15 open issues labelled `status/needs-human` (13) or `decision` (8),
counted 2026-10-04 (v3 said 10).

Where the human-time baseline actually sits: today's flow is already **one task per human
merge**, with 9–15 minutes between merges on a busy day, and dependent tasks already wait on
that merge. **But today the human is present while that happens**, so a chain of dependent
tasks advances at the human's pace and a four-task chain finishes in an afternoon. Any design
that keeps the human merge as the approval inherits the one-task-per-merge rule; what changes
is *when* the merges happen. A loop that runs while the human is away (§ 7.4's dispatch window)
advances a chain by one task per sitting, and sittings are daily, not every nine minutes.
§ 8.3 states that trade-off. Neither the cursor-PR count nor the touch count measures reading
time; nothing in this document does.

**v6:** the ceiling comes from § 7.4's *away-only* dispatch window, not from principle 1.
The loop adds to the daytime flow rather than replacing it: the human can still work a chain
interactively at today's pace. What the loop cannot do under the current window is advance a
chain past its first link. A dispatch triggered by the human's merge *during* a sitting would
let a chain advance without the human dispatching each item (the original
complaint, § 1), at the cost of loop sessions drawing on the usage window while the human
works. § 7.4 lists it as an option. **Nothing in § 3 measures how much of past sprint work
was dependent**; the § 8.3 measurement is the first time anyone will know.
**v7:** the pace is one *task session* per link (a capped coder session plus up to three
critics × `round_cap`), not the nine-minute review cadence above, so "at review cadence"
overstated it. And v5 had already put the ceiling on the away-only window (v5 § 3.1: "A loop
that runs while the human is away (§ 7.4's dispatch window) advances a chain by one task per
sitting"); v6's real addition was the merge-triggered option, not a different cause.

Host friction recorded in devcontainers' own ledger (L35-37): `GH_TOKEN` per repo (two gh
accounts), commits from Windows but tests in WSL, "WSL's `gh` is Seuss27, no push", auto mode
blocks ruleset edits, host GPG cache TTL for long sessions.

### 3.2 Where the tokens go (local transcripts, *verified by author*, scripts in § 10)

`~/.claude/projects/<proj>/*.jsonl`; each `assistant` line carries `message.usage`.
Subagent transcripts live under `<proj>/<session>/subagents/`. The
`personal-claude-workbench` directory mirrors the `glunk-works-claude-workbench` one
(identical session files) and was excluded.

Since 2026-09-01 (272 main sessions, 848 subagent files):

| measure | value |
|---|---|
| cache-read tokens, main sessions | ≈ 2.3 B |
| cache-read tokens, subagents (critics) | ≈ 0.6 B, almost all Opus (654 of 848 files Opus 5.5, 156 Opus 5) |
| cache writes + output, all | < 0.13 B |
| median peak context per session | 138 k |
| sessions whose peak context passed 150 k | 142 of 325 |
| share of all cache reads on turns above 150 k context | **79 %** |
| five largest sessions | claude-workbench coder sessions 2026-09-23..25, 200–480 turns, 350–505 k median context, Sonnet 5 (1 M window) |
| plugin prose loaded per session (resume+handoff+ship+critic-gate+conventions) | ≈ 169 KB ≈ 42 k tokens |

Daily envelope, last 14 days (de-duplicated; reproduced by the v3 and v4 reviewers on
2026-10-04): mean **≈ 195 M cache-read/day**, 0.9 M output/day, ≈ 52 sessions/day (incl.
≈ 34 Opus critic subagents/day). Opus ≈ 60 M/day of cache reads, Sonnet ≈ 124 M, Fable ≈ 11 M.
Per-session medians: main Sonnet 5.1 M cache-read / 49 turns (p90 47.5 M); main Opus 2.6 M /
29 turns; Opus critic subagent 0.2 M / 10 turns.

Reading: spend is dominated by re-reading large contexts; four-fifths of it happens in
sessions past 150 k. A capped task session (≈100 k context, ≤60 turns) is about one of today's
median Sonnet sessions, so a wave of four tasks ≈ one current afternoon.

**These are API-token figures used as a proxy.** Under the subscription constraint the binding
quantity is consumption of the 5-hour and weekly windows, which Anthropic does not expose as a
number. Cache-read tokens track that consumption in direction (a long-context turn costs more
of the window than a short one) but not in units, and `--max-budget-usd` is a list-price
estimate of the same proxy. The governor in § 7.4 is sized on the proxy and must be re-sized
from observed limit errors once anything runs.

---

## 4. Platform facts the plan depends on

Legend: **[A]** verified by author from the URL on 2026-10-04; **[S]** reported by a subagent
with the URL, not re-read by the author; **[R]** re-verified by the v3 reviewer from the URL
on 2026-10-04; **[V]** re-verified by the v4 reviewer from the URL on 2026-10-04 (raw page
where noted, not a summary); **[O]** verified by the v6 (Opus) reviewer from the raw page on
2026-10-04; **[O2]** verified by the v7 (second Opus) reviewer on 2026-10-04: from the raw
page by a research subagent whose quotes v7 relays with line numbers, or by v7 itself where
marked *[O2, re-read]*; **[F8]** verified by the v8 (fourth Fable) reviewer from the raw page
itself on 2026-10-04, no subagent; **[O3]** verified by the v9 (third Opus) reviewer from the
raw page or live API on 2026-10-04; **[T]** tested on this machine on 2026-10-04/05
(`V9-TEST-RESULTS.md`, `GITHUB-APP-EVALUATION.md`). Every [O2] line number v8 re-read matched within two lines
(settings-reference.md:1385-1395, :2113-2114, :2903-2905; sandboxing.md:40-43, :523,
:531-536, :850; skills.md:233, :299; sub-agents.md:250; memory.md:60; network-config.md:
215-233; admin.md:267; headless.md:311).

### 4.1 Headless and budgets (`claude -p`)
- `--max-budget-usd` exists, print mode only, subagent spend counts, spawning stops at the cap;
  it is a **client-side list-price estimate**. [A][R][V] https://code.claude.com/docs/en/cli-reference.md
- `--max-turns` (exits with error at the limit), `--json-schema` (structured output in
  `structured_output`), `--autocompact <100k..1M>` (per-launch auto-compact window, capped at
  the model's window), `--fork-session`, `--forward-subagent-text`, `--plugin-dir`,
  `--exclude-dynamic-system-prompt-sections`, `--restricted`, `--setting-sources`,
  `--settings`, `--strict-mcp-config`, `--append-subagent-system-prompt`. [A][V] same URL
- `--permission-prompts none` removes tools that need a person (AskUserQuestion) and denies
  anything that would prompt **"unless a `PermissionRequest` hook allows it"**. **Requires
  v2.1.259+.** `dontAsk` mode also denies AskUserQuestion. [A][R][V] https://code.claude.com/docs/en/headless.md
- **Installed CLI on the maintainer's machine is 2.1.228** (`claude --version`). The version
  floor comes from headless.md, not from `--help`: cli-reference.md says `--help` does not list
  every flag, so a flag's absence there proves nothing. [A][R][V] **[T]** the test container
  ran **2.1.289** (npm latest on 2026-10-04); every § 8.8 result is from that version.
- `--bare` skips hooks/skills/plugins/CLAUDE.md **and never reads OAuth credentials or
  `CLAUDE_CODE_OAUTH_TOKEN`**; it needs `ANTHROPIC_API_KEY`. So bare mode is out under the
  subscription constraint. [A][R][V] headless.md; authentication.md
  **headless.md also says `--bare` "is the recommended mode for scripted and SDK calls, and
  will become the default for `-p` in a future release."** When that lands, plain `-p` on a
  subscription login needs an explicit opt-out that is not documented today. The plan's
  launch line (§ 7.3) depends on that opt-out existing. [V]
- Plain `-p` without `--bare` runs the project's hooks and connects its `.mcp.json` servers
  "even in a folder you've never trusted", with no trust dialog. [A][R][V] headless.md
- `--setting-sources user` makes Claude Code read "neither the project's settings files nor
  its `.mcp.json`". The page says nothing about project `CLAUDE.md`, so that effect stays
  unverified. [V] https://code.claude.com/docs/en/permissions.md § What runs before you trust a folder
- `--output-format json` includes `total_cost_usd`, per-model usage, `permission_denials`. [A][V]
- Background subagents hold a `-p` process open up to 10 min idle by default
  (`CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS`). [A][V]

### 4.2 Subagents, hooks, settings
- Subagents **can** spawn subagents, default 3 levels (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`).
  `isolation: worktree` is a documented frontmatter field. Subagent requests count toward the
  same usage limits. [A][R][V] https://code.claude.com/docs/en/sub-agents.md
  → The sentence "a subagent cannot spawn subagents" at `reference/workflow.md` L140 is
  **stale**. [A][R][V] It is not in `skills/critic-gate/SKILL.md` (no "spawn/nest/sibling"
  phrasing in the nesting sense there). [R][V]
- **Settings files are watched and reloaded live.** settings.md: "Claude Code watches your
  settings files and reloads them when they change, so it applies most edits to the running
  session without a restart, including edits to `permissions`, `hooks`, and credential helpers
  … The reload covers user, project, local, and managed settings." A missing/non-executable
  hook, a timed-out hook, and any exit code other than 0 or 2 are **non-blocking: the action
  proceeds** ("for most hook events"). Managed-settings hooks cannot be disabled from
  user/project/local settings; `allowManagedHooksOnly` in managed settings blocks user,
  project, local and plugin hooks entirely. [A][R][V] https://code.claude.com/docs/en/hooks.md ;
  https://code.claude.com/docs/en/settings.md (raw)
- **`PermissionRequest` hooks are an allow path under `--permission-prompts none`, and the
  path is bounded.** hooks.md (raw): "PermissionRequest hooks run only when Claude Code is
  about to ask you for permission, or when it would otherwise auto-deny a call that can't
  prompt"; "if no hook returns a decision, it denies the tool call." Exit code 2 is not
  honoured for this event; the decision goes through the `decision` object. A hook's allow
  does not override a deny rule: hooks.md's PermissionRequest decision table says "Deny and ask
  rules are still evaluated, so a hook returning `"allow"` doesn't override a matching deny
  rule" [O]. (v5 cited the `PermissionDenied` section for this; that event fires "when auto
  mode denies a tool call" and is not the evidence. Corrected in v6.) A hook's `allow` may also
  carry `updatedPermissions` entries (`addRules`, `removeRules`, `replaceRules`, `setMode`)
  with a `destination` of `session`, `localSettings`, `projectSettings` or `userSettings`, so
  a hook can **persist** an allow rule, or remove a deny rule, in any non-managed source [O].
  Only managed deny rules are out of its reach. **Consequence for § 7.3:** a hook in any loaded
  settings source can widen the session from "denied because nobody can answer" to "allowed",
  for every call the driver did not explicitly deny. So the driver must (a) own every settings
  source the session loads, (b) keep them unwritable by the session for the session's
  lifetime, because the watcher applies edits live, and (c) enumerate the dangerous surface in
  deny rules rather than lean on `dontAsk`'s default. v3 had this inverted ("can deny, not
  allow"); v4 fixed the direction; v5 adds the bound and the watcher. [R][V] v6 sharpens (a)
  and (b): the dependable way to own them is to make non-managed sources *irrelevant*
  (`allowManagedHooksOnly`, `allowManagedPermissionRulesOnly`, deny rules in managed settings
  only), because (b) cannot be met by file permissions in a directory the session must write
  (next bullets). [O]
- Deny rules win over allow rules and over `bypassPermissions`. [S] permissions.md; the same
  rule is stated in devcontainers' `merge-guard.sh` header. [V] permissions.md (raw): "Rules
  are evaluated in order: deny, then ask, then allow"; "a managed settings deny can't be
  overridden by `--allowedTools`". [O]
- **Allow rules merge across scopes.** settings.md: Claude Code "merges `permissions.allow`
  across scopes, unless your organization sets `allowManagedPermissionRulesOnly`." So a
  writable user `settings.json` widens the session through `permissions.allow` alone, with no
  hook involved, and `allowManagedHooksOnly` does not stop that. [O]
  **What `allowManagedPermissionRulesOnly` does (v7).** settings-reference.md:1387: "Claude
  Code then ignores `allow`, `ask`, and `deny` rules in user, project, local, and `--settings`
  files, ignores `--allowedTools`, hides the always-allow choices in permission prompts, and
  stops saving new rules." `--disallowedTools` and the session's deny and ask rules still
  apply (:1391). From v2.1.282 it also ignores skill and command `allowed-tools` from
  non-managed sources (:1395-1402). It does not cover MCP; that needs
  `allowManagedMcpServersOnly` (:1416). **Consequence:** with this key set, every allow rule
  the session needs must live in managed settings, and the plan's `--allowedTools` list does
  nothing. [O2]
- **`--settings` precedence.** settings.md:566: "Claude Code applies it above your user,
  project, and local files and below managed settings. It can set any key your user settings
  file can set." [O2]
- **`--setting-sources` can leave out `user`.** cli-reference.md:127: "Comma-separated list
  of setting sources to load (`user`, `project`, `local`)"; skills.md:233 refers to a list
  "that leaves out `user`". Whether managed settings and the `--settings` file still load
  under the CLI is not stated (only the Agent SDK's equivalent is documented to keep
  managed settings, managed-settings.md:84). What the session loads when the list is empty
  is not stated either. [O2]
  **`--restricted` is the documented form of "load nothing writable" (v8).** cli-reference.md:
  123: "Start in restricted mode. Use it when an evaluation harness drives `claude` on a
  shared machine and Claude Code must not run commands or read that machine's user and
  project settings. Claude Code removes the built-in tools that run commands or code, and
  WebFetch, unless you name them individually in `--tools`, not through the `default` preset.
  It also confines the built-in file tools to the working directories, loads only managed
  settings and `--settings`, refuses `bypassPermissions`, and refuses to create cloud
  sessions … Requires Claude Code v2.1.248 or later." permission-modes.md:625 adds that under
  it the auto-mode classifier cannot approve protected-path writes. [F8] **Tested (§ 8.8)
  [T]:** `--tools Bash` restores Bash (the `system/init` event lists it; with `--tools
  "Read"` there is none). The working directories under `--restricted` are **the work clone
  alone**: `/tmp` is not one until the launch line adds `--add-dir /tmp`. A plugin agent
  loads under `--restricted --agent <plugin>:<agent> --plugin-dir`, with its frontmatter
  `model` applied, but its tools are the **intersection** with `--tools`, so a critic line
  must name the agent's tools (§ 8.4a). Loading is observable from the stream-json
  `system/init` event (`plugins`, `agents`, `tools`, `model`); in 2.1.289 the
  `--output-format json` result has no `plugins` or `plugin_errors` key. `--restricted`
  excluded a user and a project `settings.json` that a control without it loaded. Four
  builtin plugins (`cc-plugin-sec-default`, `-agents-md`, `-telemetry`,
  `-plugin-authoring`) load under it, and the config dir collects `remote-settings.json`
  and `policy-limits.json` from the server. The skills a `--plugin-dir` exposes are listed
  but inert when `--tools` names no `Skill` tool: `--tools` gives only "the ones you list"
  (cli-reference.md:136) and `Skill` is a separate tool (tools-reference.md:52) **[O3]**.
- **Project settings also carry `env` and helpers, and apply in `-p` with no trust dialog**
  (v8). settings-reference.md:2905: `env` "from project and local settings: after you trust
  the workspace, or at startup in `-p` mode, which never shows the trust dialog". permissions.md:
  726 (on `--bare`): "The project's `env` block and helpers such as `awsAuthRefresh` in its
  settings files still apply, and Claude Code reads `apiKeyHelper` only from `--settings`."
  So v7's `project`-only fallback would have loaded a file whose `env` and helper keys the
  session can write, and needed three controls to keep it inert; § 8.8 drops it. [F8]
- **Protected paths: the sandbox's list and the permission system's are different lists**
  (v9, **[O3]**; v8 conflated them). sandboxing.md:531-536 gives the sandbox's groups: in the
  working directory, "the `.claude` settings files, the `.claude/skills`, `.claude/agents`,
  `.claude/commands`, and `.claude/hooks` directories, `.mcp.json`"; "in `~/.claude`, or the
  directory `CLAUDE_CONFIG_DIR` points to: most of its contents, plus `~/.claude.json` and
  the `.credentials.json` credential store"; "There is no way to exempt one of these paths."
  The `--plugin-dir` entry v8 added to that list belongs to the **permission system's**
  protected list (permission-modes.md:646); sandboxing.md's Protected paths section says
  "The permission system has its own protected paths … the sandbox's list applies to a
  command that is already running", and its groups contain no plugin dir. The sandbox
  covers Bash only (:42); the managed denies cover Edit and Write. **Tested (§ 8.8) [T]:**
  in the § 7.3 container the sandbox cannot start at all. bubblewrap fails at namespace
  creation under Docker's **default seccomp profile** (`bwrap: No permissions to create new
  namespace`, although the kernel allows user namespaces), a step before the `/proc` mount
  that `enableWeakerNestedSandbox` addresses, and it fails closed, so no command runs. Under
  `seccomp=unconfined` (diagnostic only) it enforces as documented: EROFS outside the write
  allowlist, a proxy 403 with a `sandbox_violations` record, no permission rule involved.
  *Decided after the tests (§ 8.8):* the loop container runs with `sandbox.enabled: false`.
- **Two more instruction paths load from the work clone** (v8): `.claude/rules/*.md`, where a
  rule with `paths:` frontmatter "loads only when Claude reads" a matching file (Claude
  directory reference, project tab, rules entry), and subdirectory `CLAUDE.md` files, which
  "are included when Claude reads files in those subdirectories" (memory.md:146). Both are
  self-injection inside a clone that lives for one task, so they add no capability the
  session lacks and do not persist; the restore step covers them because `.claude/` and
  `CLAUDE.md` are restored whole, and `.claude/rules/` is now named in § 7.3's list. [F8]
- **Writable user settings still widen the session through helpers and `env`** (v7). These
  keys may sit in any settings file, user settings included: `apiKeyHelper` (run "through the
  system shell"), `awsAuthRefresh`, `awsCredentialExport`, `gcpAuthRefresh`,
  `otelHeadersHelper` ("at startup and periodically"), plus `statusLine`,
  `subagentStatusLine` and `fileSuggestion` (settings-reference.md, around :5531). They are
  reloaded live: "including edits to `permissions`, `hooks`, and credential helpers such as
  `apiKeyHelper`" (settings.md:584). They run **outside the sandbox**: "helper commands such as
  your status line command and `apiKeyHelper` run with your full access" (sandboxing.md:43).
  `allowManagedHooksOnly` narrows only `statusLine`, `fileSuggestion` and
  `subagentStatusLine` to managed settings; no `allowManaged*` key is documented to restrict
  the other helpers. `env` is re-read live "from user settings, `--settings`, and managed
  settings" when a saved change alters the merged `env` (settings-reference.md:2905). So a
  session that can write a loaded user `settings.json` can get a command run by the `claude`
  process itself, outside any Bash sandbox, or change its own environment mid-run. [O2]
- **The user config dir also holds instructions and code that load on the next session.**
  `~/.claude/CLAUDE.md` (memory.md:60), user agents in `~/.claude/agents/` (watched live,
  sub-agents.md:251), user skills in `~/.claude/skills/` (SKILL.md text hot-reloaded in the
  current session, skills.md:299). If `CLAUDE_CONFIG_DIR` persists between tasks, a session
  can leave instructions for the next task's session. `strictPluginOnlyCustomization`
  (managed) blocks "skills, agents, hooks, and MCP servers from user and project sources".
  Whether leaving `user` out of `--setting-sources` also drops user CLAUDE.md, agents and
  skills is not stated. [O2]
- **The watcher also loads new files.** settings.md: "Claude Code also loads a settings file
  you create mid-session if its folder existed when the session started." [O]
- **`CLAUDE_CONFIG_DIR` holds writable state.** settings.md: with it set, "Claude Code then
  stores your settings, session history, and plugins there", and `.claude.json` (sign-in
  session, per-project state) is a file Claude Code "writes for itself". So the config dir
  cannot be read-only to the session user, and a root-owned file in a directory the session
  user can write can be unlinked and recreated (POSIX directory semantics). [O]
- **Bash deny rules are not a boundary.** permissions.md: a Bash rule "covers the invocation
  Claude usually produces and isn't a security boundary around the program"; "For filesystem
  and network enforcement that doesn't depend on the command text, use sandboxing." Claude
  Code's sandbox applies OS-level filesystem and network limits to Bash, PowerShell and
  Monitor commands and their children. [O] permissions.md § How permissions interact with
  sandboxing.
  **v7, sandbox in a container.** The Linux backend is bubblewrap (sandboxing.md:623). "In an
  unprivileged container, bubblewrap can't mount a fresh `/proc` … Set
  `enableWeakerNestedSandbox` to `true` … Only use this setting when the outer container
  already provides the isolation boundary you need" (:850); settings-reference.md:2114 adds
  "This reduces security." Docker's default seccomp profile denies `mount` and `pivot_root`
  (docs.docker.com/engine/security/seccomp). The sandbox covers Bash only: "tools such as Read,
  Edit, Write, WebFetch, and WebSearch follow permission rules instead" (:42). It blocks
  writes to the config dir, `~/.claude.json` and `.credentials.json` (:536), but **reads of
  credential files are allowed by default**: "This default still allows reading credential
  files, so protect credentials" (:523). [O2] **[T]** the weaker nested mode is not enough:
  Docker's default seccomp profile stops bubblewrap one step earlier (above).
- **Mods** (plugins that run code inside Claude Code; on by default from v2.1.287) are a
  second widening path parallel to hooks: with no managed policy, a mod "that Claude writes
  during a session" loads, and a mod can approve a call an `ask` rule would prompt for.
  Where managed settings exist, deny rules hold over mods; `allowManagedHooksOnly` stops
  user-installed mods from loading. [O] https://code.claude.com/docs/en/plugins/mods/admin.md
  **v7:** a plugin Claude Code copies into its cache "counts as a user's, even when managed
  `enabledPlugins` enables it … it doesn't load under `allowManagedModsOnly` or
  `allowManagedHooksOnly`" (admin.md:268). Under the plan's managed settings, then, the
  plugin's own hooks do not run. Today that is only the SessionStart cursor banner
  (`plugins/way-of-working/hooks/hooks.json`), which a headless task session does not need.
  The installed CLI (2.1.228) predates both mods (2.1.287) and the skill `allowed-tools`
  handling above (2.1.282). [O2]
- **Hosts Claude Code itself needs** (network-config.md:215-233): `api.anthropic.com`;
  `claude.ai`, `claude.com`, `platform.claude.com` (OAuth refresh); `mcp-proxy.anthropic.com`;
  `downloads.claude.ai`, `storage.googleapis.com`, `registry.npmjs.org` (updates);
  `github.com`, `raw.githubusercontent.com`; Datadog intake hosts (optional). The update
  hosts can stay off the proxy's list if auto-update is disabled in the image. [O2]

### 4.3 Subscription authentication and limits
- `claude setup-token` mints a **one-year** OAuth token, subscription-billed, Pro/Max/Team/
  Enterprise, "can only make model requests" (no Remote Control, no claude.ai connectors). No
  revocation procedure is documented. Deleting a GitHub Actions secret does not invalidate the
  credential it held ("If you delete a secret, the credential it held stays valid").
  [A][R][V] https://code.claude.com/docs/en/authentication.md ;
  https://code.claude.com/docs/en/github-actions.md (Uninstall)
- `CLAUDE_CONFIG_DIR` gives each login its own credentials/settings directory; on Linux the
  credential file is `.credentials.json` under that directory, mode 0600. [A][R][V] authentication.md
- Subscription usage: rolling **5-hour** window plus a **weekly** window, shared across all
  models (plus model-specific Opus/Sonnet limits). Subagents, background sessions, routines,
  `-p` runs and `/insights` all draw from the same pool. Without usage credits, further runs
  are rejected until the window resets. `autoContinueAtUsageLimit` exists for interactive
  sessions. [A][R][V] https://code.claude.com/docs/en/costs.md
- Prompt cache TTL: **1 h** for the main conversation on subscription within plan usage,
  **5 min** on usage credits [A][V] costs.md; 5 min for subagents/workflows by default [S]
  prompt-caching.md. `/usage` shows hit ratio (main conversation only). [A][V]
- `/usage` plan breakdown attributes usage to skills, subagents, plugins, MCP servers, and
  flags long-context/cache-miss behaviours ≥10 %. Computed from local history. [A][V] costs.md
- A `-p` run that hits the limit exits with an error. [S] errors.md, headless.md
- **Agent SDK is API-key only**: "Unless previously approved, Anthropic does not allow third
  party developers to offer claude.ai login or rate limits for their products, including agents
  built on the Claude Agent SDK." [S][R][V] https://code.claude.com/docs/en/agent-sdk/overview.md
- Auto mode is available on subscription, in `-p`, on Sonnet 5.5 / Opus 5.5 / Fable 5.1 /
  Opus 4.7+. [S] auto-mode-config.md
- No documented terms statement restricting subscription use to interactive sessions; the
  reviewer should check https://www.anthropic.com/legal/commercial-terms. [S]

### 4.4 GitHub Action, routines, merge queue
- `anthropics/claude-code-action`: accepts `claude_code_oauth_token`; automation mode runs on
  any event when `prompt` is set; on issue/PR events the triggering user must have write
  access; bot actors rejected unless `allowed_bots`; **commits pushed with `GITHUB_TOKEN` do
  not trigger CI**; inputs `plugins`, `plugin_marketplaces`, `claude_args`, `settings`.
  [A][R][V] https://code.claude.com/docs/en/github-actions.md
  The docs do **not** say the Action cannot merge or approve (v3 claimed that). The Claude
  GitHub App's installed permission set is: Actions RW, Checks RW, **Contents RW**, Discussions
  RW, Issues RW, Members R, Metadata R, **Pull requests RW**, Repository hooks RW,
  **Statuses R**, **Workflows RW**. Contents + Pull requests write is enough to merge through
  the API; only the tool allowlist in `claude_args` prevents it. Workflows RW means an
  Action-placed loop could edit the gate workflow (#93's exact gap) unless the allowlist
  forbids it. Statuses R means the App itself cannot mint a commit status. GitHub does not let
  an installer accept a subset; a custom App with Contents/Issues/Pull requests only is the
  documented alternative. Treat "cannot merge" as a configuration property, never an identity
  property. [R][V]
- Its security doc restores a **fixed list** from the PR base branch before running:
  `.claude/`, `.mcp.json`, `.claude.json`, `.gitmodules`, `.ripgreprc`, `CLAUDE.md`,
  `CLAUDE.local.md`, `.husky/`; base-absent paths are removed and PR versions kept under
  `.claude-pr/`. It sanitises HTML comments, invisible characters, image alt text, hidden
  attributes and entities; scrubs Anthropic/cloud/GitHub secrets from subprocess env (best
  effort; bubblewrap PID isolation on Linux); warns "Do not check out an untrusted ref into
  the workspace root" and "Do not use a personal access token". [S][R][V]
  https://github.com/anthropics/claude-code-action/blob/main/docs/security.md
- Routines: research preview; subscription usage; commits and PRs **carry the maintainer's
  GitHub user**; push to `claude/` branches; GitHub triggers cover **pull_request and release
  only** (not issues); API trigger exists; hourly caps (100 scheduled/h per account, 30/h per
  routine shared by Run-now and API fires). [A][R][V] https://code.claude.com/docs/en/routines.md
- Merge queue: public org repos, or private repos on Enterprise Cloud; **not** private repos
  on Team. [S] docs.github.com + community discussion; the cited page contains no
  availability statement (v3, v4). **[O3] No repo in this plan has one:** no live ruleset on
  the four repos has a merge-queue rule; no workflow in devcontainers, bounty-infra or
  claude-workbench has a `merge_group` trigger, and required checks do not run in the queue
  without one (docs.github.com, managing a merge queue, L32); all four `main` rulesets have
  `strict_required_status_checks_policy: false`, so a wave merges serially with no re-run
  between merges. Auto-merge is devcontainers' #139 only. § 8.5 turns the queue and
  auto-merge checks into preconditions.
- 603-Identity is on GitHub **Team**; glunk-works has no paid plan. [A][R][V] `gh api orgs/…`
- **Ruleset mechanics that bear on § 8.5** (v7; docs.github.com, reported by subagent unless
  marked):
  - Restrict updates: "only users with bypass permissions can push to branches or tags whose
    name matches the pattern." The docs do not say in so many words that this blocks a PR
    merge by a non-bypass user. *[O2, re-read: the section exists, L17 of the raw page.]*
  - Bypass is granted **per ruleset**; nothing splits it per rule. With
    `bypass_mode: pull_request`, "the actor can then choose to bypass any branch protections
    and merge that pull request", so bypass is an explicit choice at merge time. `gh pr merge
    --admin`: "Use administrator privileges to merge a pull request that does not meet
    requirements." The UI offers repository roles, teams, apps and Dependabot as bypass
    actors, not individual users; the REST enum has a `User` type. **[F8]:** creating-rulesets
    L62-65 names the eligible bypass actors: "Repository admins, organization owners, and
    enterprise owners; the maintain or write role, or custom repository roles based on the
    write role", plus teams and apps. **What `--admin` actually does (v8):** in gh's source,
    `--admin` only changes the client-side check. `merge.go` L255-275 refuses a PR whose
    `mergeStateStatus` is `BLOCKED` unless `UseAdmin` is set (`blockedReason`, L779-800:
    "the base branch policy prohibits the merge"); the GraphQL `mergePullRequest` input it
    then sends (`http.go` L48-80) has no admin field. GitHub applies bypass on the server
    regardless. **Tested 2026-10-05 (§ 8.5) [T]:** GitHub reports `BLOCKED` to the admin on
    a green PR whose only unmet rule is the restriction, gh refuses it client-side, and the
    admin's plain REST merge succeeds with the rule suite logged `bypass`. So resume's merge
    needs `--admin`, and the server applies an eligible bypass whatever the client sends.
    **[O3]** `--admin` is *not only* client-side once a merge queue is enabled: gh then
    merges directly instead of enqueueing (`merge.go` L549-551, `shouldAddToMergeQueue`
    returns false under `UseAdmin`; L298-304). Moot while no repo has a queue; it matters
    for § 8.5's check-4 precondition. **`viewerCanMergeAsAdmin` does not reflect ruleset
    bypass [T]:** it read `false` for the admin on two green PRs the admin then merged, one
    with no admin flag at all. What tells accounts apart is the ruleset API's
    `current_user_can_bypass`, read as each account: on the scratch restrict-updates ruleset
    it read `pull_requests_only` for the admin and `never` for the machine user and for the
    App. https://raw.githubusercontent.com/cli/cli/trunk/pkg/cmd/pr/merge/merge.go
  - Rulesets have no priority; "the most restrictive version of the rule applies".
  - "Pull request authors cannot approve their own pull requests."
  - Forks: secrets other than `GITHUB_TOKEN` "are not passed to the runner when a workflow is
    triggered from a forked repository", and `GITHUB_TOKEN` is read-only there. *[F8,
    re-read: events-that-trigger-workflows L587.]* **Consequence for OIDC (v8):** a fork PR's
    read-only token cannot carry `id-token: write` (**[O3]** an inference from events L587
    plus OIDC reference L494, not a quote), and "without `id-token: write`, the OIDC JWT ID
    token cannot be requested" (OIDC reference L494). That, not the subject string, is
    why bounty-infra's `tofu-plan` cannot run from a fork; the `repo:…:pull_request` subject
    would be identical on a fork PR. § 8.5's evidence line is corrected to say so. "By default,
    all first-time contributors require approval" to run workflows. New organizations
    "disallow the forking of private repositories" by default. A read collaborator's
    `author_association` is still COLLABORATOR (GitHub's schema; the docs do not say).
  - Compare API: the changed-file list "includes up to 300 changed files for the entire
    comparison", shown on the first page only; renamed files carry `previous_filename`.
- **`author_association` is viewer-relative [T].** Issue glunk-works/claude-workbench#220,
  opened by the maintainer, reads `MEMBER` to the maintainer's account and `CONTRIBUTOR` to
  both the test App and the machine user. A trust check run with the loop's own credential
  would class the maintainer's issues as untrusted; the driver reads it as the maintainer
  (§ 8.1). The App's own PR read `NONE` to every viewer. Public issues and comments are
  readable with no Issues permission, even outside the installation.
- **A GitHub App as an identity** (v9; docs.github.com quoted in `GITHUB-APP-EVALUATION.md`,
  then tested on the scratch repo **[T]**). Installation tokens "expire one hour from the
  time you create them"; each is minted for a subset of the installation's repositories and
  permissions (a repo outside the installation or a permission the App lacks → `422`); a
  private App "can only be installed on the account that owns the app", so one App per org;
  "a GitHub App does not consume a GitHub seat"; private keys "do not expire" and are
  revoked by hand. A permission change takes effect only after an owner re-approves it at
  each installation. Tested: the restrict-updates rule blocks the App's REST merge and its
  `--admin` merge (`405`, rule suite `fail`); a workflow-file push without the Workflows
  permission is refused server-side; its `pull_request` CI run needs no approval; its
  commits over git are unsigned; under its token `gh api user` returns `403` and
  `repos/{repo}` `.permissions` reads all `false`, so the plugin's reach checks fail closed
  on it (§ 7.2); `current_user_can_bypass` reads `never` with its token.

### 4.5 WSL2 defaults (added in v5; bears on § 6.2 and § 8.2)
From https://learn.microsoft.com/en-us/windows/wsl/wsl-config, per-distro `/etc/wsl.conf`
defaults. [V]
- `[automount] enabled = true`: fixed Windows drives are mounted under `/mnt`, so a process in
  the distro can read `/mnt/c/Users/<user>/.config/gh/hosts.yml`, `.gnupg/`,
  `.claude/.credentials.json` and every repo checkout. (v7: on this machine gh stores its
  tokens in the Windows keyring, so `hosts.yml` holds no token; the other paths stand.)
- `[interop] enabled = true` and `appendWindowsPath = true`: the distro can launch Windows
  executables and the Windows `PATH` is appended, so `gh` or `git` can resolve to the Windows
  binaries carrying the maintainer's authentication and signing identity.
- `[user] default` = the first user created, which on the stock Ubuntu image has passwordless
  `sudo`; `wsl.exe --user root` also exists from the Windows side.
- `[wsl2] firewall = true` (Windows 11 22H2+) lets Windows Firewall and Hyper-V firewall
  rules filter WSL traffic; without those rules egress is unrestricted NAT.
- The distro's filesystem is reachable from Windows at `\\wsl.localhost\<distro>\…`, so a
  file inside the distro is readable by any Windows process running as the maintainer.
- **Docker Desktop on this machine uses the WSL2 backend** (`docker info` on 2026-10-04:
  server 29.5.3, kernel `6.18.33.1-microsoft-standard-WSL2`, distros `Ubuntu` and
  `docker-desktop`). A container therefore runs inside the `docker-desktop` distro: it has
  no `/mnt/c`, no Windows interop and no Windows `PATH` unless a bind mount supplies them, its
  volumes live in that distro's disk image (reachable from Windows as above), and the Docker
  socket is root-equivalent for the Windows user who runs Docker Desktop. [V] `docker info`,
  `wsl -l -v`; architecture per Docker Desktop's documentation, not re-fetched.
- **v6 additions** (from Docker Desktop's documented behaviour, not re-fetched, and not
  executed on this machine):
  - Docker Desktop shares Windows drives with the engine for bind mounts. Any process that
    can reach the Docker socket can `docker run -v C:\Users\<user>:/x …` and read the
    maintainer's gh, GPG and Claude credentials. "No `/mnt/c` by construction" holds only for
    a container that has **no** socket access. A container given the socket (for example to
    run devcontainers' gate, § 2.3) has every credential § 4.5 lists, as root.
    **v7 correction:** "every credential" overstated it, and the drive-sharing behaviour is
    not stated in Docker's documentation. On the WSL2 backend the docs list no file-share
    setting at all (the settings page's File sharing table names Mac, Linux and Hyper-V
    only); that Windows paths can be bind-mounted is implied only by a performance warning
    against `docker run -v /mnt/c/users:/users` in the WSL best-practices page. And gh on
    this machine keeps its tokens in the **Windows keyring** (`gh auth status`: "(keyring)"),
    not in `hosts.yml`, so they are not files a bind mount can read. The residual is still
    severe, but it is **write-then-execute**, not read: socket access is root on the
    `docker-desktop` VM with read *and write* access to the maintainer's files, so it can
    read file-based secrets (repo checkouts, `.claude/.credentials.json`, GPG key files,
    which are passphrase-protected) and plant something that later runs as the maintainer
    on Windows (a Startup-folder entry, a repo's git config), which then reaches the keyring.
    Docker's own limitations page says: "On WSL, users can access Docker Engine directly or
    bypass Docker Desktop security settings." Enhanced Container Isolation, which blocks
    socket mounts by default, needs a Docker Business subscription. [O2] **[F8, re-read:**
    ECI page header "Subscription: Business"; "By default, ECI blocks bind mounting the Docker
    Engine socket (/var/run/docker.sock)"; the File sharing table on the Desktop settings page
    names Mac, Linux and Windows Hyper-V only; the WSL best-practices page's `/mnt/c` warning
    is at L23. The "access Docker Engine directly or bypass" sentence is on ECI's
    *limitations* page, which adds: "Direct VM access: Users can bypass Docker Desktop
    security by accessing the VM directly: `wsl -d docker-desktop`. This gives users root
    access", and "Shared kernel vulnerability: All WSL 2 distributions share the same Linux
    kernel instance."**]**
    **v9 (§ 8.9, decided: host hygiene, not a blocker).** devcontainers' ledger (L35-37,
    § 3.1) names a second gh inside the Ubuntu distro. gh's own help says that where no
    credential store is found it "will fallback to writing the token to a plain text file",
    so a plain token there is likely; and the Windows file is documented, not inferred: "On
    Windows, credentials are stored in `%USERPROFILE%\.claude\.credentials.json`"
    (authentication.md:206) **[O3]**. Neither changes a control in § 7: the loop container
    is never given the socket, and anything that holds the socket already runs as the
    maintainer on Windows and can read both files without Docker (`\\wsl.localhost\Ubuntu\…`,
    above). Logging the WSL gh out is optional hygiene; its ledger entry already says it
    cannot push.
  - `host.docker.internal` reaches services listening on the Windows host (**[T]** from
    the default bridge Docker Desktop forwards it to Windows' loopback), and the bridge
    gateway reaches whatever listens on the bridge address, which on this backend is the
    VM, not Windows ([T], below). An egress allowlist must cover them, not only the public
    internet.
    **v7:** an `--internal` network does not block this. docs.docker.com, `docker network
    create --internal`: "Communication with the gateway IP address (and thus appropriately
    configured host services) is possible, and the host may communicate with any container
    IP directly." So the session container itself reaches host services on the gateway,
    without going through the proxy; a proxy rule cannot stop it. It needs a block on the
    host side or inside the container's own network namespace (see § 7.3). [O2, reported by
    subagent; v7's own grep of the rendered page did not match the sentence, so re-read it.]
    **[F8, re-read from the markdown source:** the sentence is at
    docs.docker.com/reference/cli/docker/network/create.md L197-203, under "Network internal
    mode". The premise holds.**] But Docker documents the fix at its own layer (v8).** The
    bridge driver's `com.docker.network.bridge.gateway_mode_ipv4` and `_ipv6` options take
    `nat`, `nat-unprotected`, `routed` or `isolated`. docs.docker.com/engine/network/
    port-publishing/, Gateway modes: "Mode `isolated` can only be used when the network is
    also created with CLI flag `--internal`, or equivalent. An address is normally assigned to
    the bridge device in an internal network. So, processes on the Docker host can access the
    network, and containers in the network can access host services listening on that bridge
    address (including services listening on 'any' host address, 0.0.0.0 or ::). No address
    is assigned to the bridge when the network is created with gateway mode `isolated`." With
    no bridge address there is nothing on the host side for the session to reach, and no
    firewall rule to keep alive across Docker Desktop restarts. Docker's iptables page also
    says "you should not modify the rules created by Docker", which counts against v7's
    host-side rule on its own. **Decided after v8 (§ 8.7): `isolated` mode replaces the
    host-side rule.** [F8] **[O3]** the same page says `--internal` containers "may
    communicate between each other" (network create.md L197), which is what keeps the proxy
    reachable; and Docker Desktop's networking page puts the bridge **inside the VM**, so on
    this host a plain `--internal` gateway reaches the VM's services, not Windows'. (v8's
    "the option landed in Engine 28" was not on the cited page; deleted.) **Tested
    2026-10-04 (§ 8.7) [T]:** on a control `--internal` network the gateway reached a
    listener in the VM's namespace, while a Windows listener (bound to `127.0.0.1`; an
    all-interfaces bind was not tested), `host.docker.internal` and every other VM address
    were unreachable; on the `isolated` network IPAM shows **no Gateway**, the bridge has no
    address, nothing outside the network answered, and the proxy stand-in answered by IP
    and by name. Two details for the preflight: `host.docker.internal` does not resolve on
    either internal network (probe its address, `192.168.65.254` here, read from a
    non-internal network), and with no gateway Docker hands the subnet's `.1` to a
    container, so a probe that derives the gateway as `.1` hits a peer, possibly the proxy.
  - **The host is an always-on desktop, not a laptop** (maintainer, 2026-10-04). Sleep is
    not a constraint. Docker Desktop still runs under the maintainer's Windows login, so after
    a reboot (for example a Windows Update restart) nothing dispatches until someone logs in,
    unless Docker Desktop is configured to start without one.

---

## 5. Design principles (unchanged from v3)

1. **The orchestrator never merges to `pr_base`.** Every approval that lands on main is a
   human merge of a task-sized PR. No sprint branch, no driver merges anywhere.
2. **The human's merge is the only approval, as a property of credentials and repository
   rules, not prose.** The loop's GitHub identity cannot merge, cannot post commit statuses,
   cannot push to `main`, has no admin. Hooks and deny rules are defence in depth, never the
   control. **v6:** a PAT with Contents write can merge a green PR on a ruleset that requires
   0 approvals (§ 2.2), which all three first-wave repos do today. So "cannot merge" is not a
   credential property on its own; it needs a **ruleset change** (§ 8.5) before step 4 runs.
   Until then the principle is false and the plan must say so. **v7:** or a loop identity
   with no write access at all, pushing from a fork (§ 8.5 option e); then "cannot merge" is
   a credential property after all. *Decided after v7:* § 8.5 option (a), a separate
   restrict-updates ruleset on every repo. **Tested 2026-10-05 [T]:** the rule blocks a
   non-bypass machine user's PR merge and a GitHub App's, and the admin still needs every
   check; (e), the fallback, is not triggered, and the loop identity is now an App
   (§ 8.12), which cannot fork. **v9, after the edit (§ 8.13):** the session holds no
   GitHub credential at all; the driver pushes after exit. "Cannot push" is a credential
   property again; "cannot merge" stays a ruleset property.
3. **Deterministic driver** (fixture-tested `bin/` scripts, WB-D10). LLM judgment only in
   **two named slots**, each with `--json-schema` output: (a) **critic selection** — which
   critics the diff warrants, using critic-gate's own table, filtered by the
   `orchestration.critics` allowlist (§ 8.4a); (b) **stop classification**. Nothing else.
   (v3–v4 named only slot b; the maintainer added slot a in § 8.4a.) **The deterministic
   floor (decided, § 8.4a):** the driver computes, without a model, `code_paths` touched →
   **at least one of** architect or security-critic (the table's row says "and/or",
   `skills/critic-gate/SKILL.md` L71); `load_bearing_docs` touched → docs-consistency. Slot
   (a) chooses which code critic, whether both, the new-doc row (L82) and repo-local critics,
   and may only **add** to the floor, never remove from it, because its input is a diff
   written by a session that read issue text. A floor critic missing from
   `orchestration.critics` stops the dispatch. **The driver computes the floor and spawns
   it** (D1, decided after the v9 review, § 8.4a): every critic, floor or slot-(a) addition,
   runs as its own capped session started by the driver, under its own frontmatter model
   and tools; the coder session has no `Agent` tool and loads no plugin. (History: v6
   recommended a floor and wrote it here as both code critics plus the new-doc row; v7
   re-keyed it to the table; the maintainer adopted v7's form after the v7 review; v8
   rewrote this paragraph to state the rule once, § 6.7; v9 named the spawner, § 6.8.)
4. **One fresh capped session per task.** `claude -p` on the subscription login with
   `--max-turns`, `--max-budget-usd` (as a proxy), `--autocompact ≤ 100k`,
   `--permission-prompts none`, a narrow allowlist. Justified by § 3.2 (context
   spend), *not* by subagent nesting. (v7: the allowlist lives in **managed settings**,
   because `allowManagedPermissionRulesOnly` makes Claude Code ignore `--allowedTools`, § 4.2.)
5. **Policy resolved before the session, by the driver, from existing predicates**
   (`plan-anchor.sh` per task at dispatch, `review-base-anchor.sh`, `spawn-model.sh`,
   `cursor-drift.sh`). The interactive skills stay interactive; the session gets a narrow task
   prompt. One WB-D names which human authorizations become plan-time policy.
6. **The session's own configuration is driver-owned and unwritable by the session.** Config
   dir, `--settings`, `--plugin-dir` (pinned copy), managed-settings hooks on the host; config
   paths restored from `origin/{pr_base}` before every launch; every control that must hold
   lives in **managed settings** on a read-only path (`allowManagedHooksOnly`,
   `allowManagedPermissionRulesOnly`, the deny rules), so whatever the session writes into
   its own writable config dir cannot widen it (v6; v5 relied on read-only files in a
   writable directory, § 6.5 item 3); hashes recorded after exit. **v7:** "irrelevant" must
   cover more than hooks and permissions. Writable user settings can also set live-reloaded
   credential helpers and `env` (§ 4.2), so the session does **not** load user settings at
   all, and its `CLAUDE_CONFIG_DIR` is fresh per task. **v8:** the documented way to load
   only managed settings and the driver's `--settings` file is `--restricted` (§ 4.2, § 8.8),
   **tested in v9 [T]**. **v9:** `--settings` is then the only non-managed source left; its
   `env` is re-applied live and `apiKeyHelper` is read only from it, so it is passed as
   **inline JSON** or as a root-owned file on the read-only root filesystem, never a path the
   session can write (v7 said so; v8 dropped it, § 6.8). The controls do not count Claude
   Code's sandbox, which cannot start in the container (§ 8.8).
7. **Plan-then-execute.** The step set and writable locations are fixed before any session
   reads issue text. Only human-anchored issues by trusted authors are dispatched (existing
   stop). *Amended by `WB-D32`: the task must still be human-anchored and its spec
   maintainer-approved, but its author may be the declared dev or reviewer App.* No quarantined-extraction layer (see § 7).
8. **Human-only paths** are a schema key (`orchestration.human_only_paths`, WB-D17 style:
   present, explicit). Enforced twice: in-session deny rules supplied by the driver, and a
   post-exit `git diff --name-only origin/{pr_base}...head` check. Either failing stops the
   wave.
9. **Author ≠ approver ≠ gate-minter.** No identity the loop controls is ever in a review
   gate's reviewer allowlist.
10. **Budgets are subscription-usage budgets**, sized from § 3.2 and enforced by the driver:
    per-day session cap, human-hours window, per-model daily caps (Opus, Fable), model routing
    taken from the repo's existing `models` map and each agent's frontmatter with **no loop
    default** (§ 8.4a), transcript-metered token ceiling, stop on any limit error. A per-model
    cap that trips mid-task (for example the Opus cap after the coder finished but before its
    critics ran) **stops the task without opening a PR**, rather than ship with fewer critics
    than the floor or than slot (a) selected (§ 8.4a). (History: v6 wrote the floor here as
    a rule before it was decided; v7 restored it to a recommendation; the maintainer adopted
    it after the v7 review; v8 states it once.)
    (v3–v4 said "Sonnet critics by default"; the loop now imposes no model of its own.)
11. **Evidence over assertion.** Digest derived mechanically by the driver (files, tests
    added, critic rounds and stop reason, usage, hook denials), mirrored into the PR body by the
    driver's identity. Per-task audit line in an append-only log outside any worktree.
12. **Fixture on `bin/` change.** A task touching `plugins/*/bin` or `scripts/` must add or
    change a fixture; the driver checks the diff.

v5 reworded three principles. Principle 6 gained "unwritable by the session", forced by the
settings watcher (§ 4.2). Principles 3 and 10 changed at the maintainer's decision in § 8.4a:
critic selection became a second judgment slot, and the loop stopped carrying a model default
of its own; routing comes from the repo's `models` map and agent frontmatter, inside per-model
daily caps. The section title keeps "unchanged from v3" for the other nine.

v6 amended principle 2 (repository rules, not credentials alone, § 8.5) and annotated
principle 3 with a recommended deterministic floor that the maintainer has not confirmed.
Principle 6's "unwritable by the session" is now met by making non-managed settings sources
**irrelevant** rather than unwritable (§ 7.3), because the config directory must stay
writable (§ 4.2).

v7 amended principle 2 (the fork alternative), principle 4 (the allowlist moves into managed
settings), principle 6 (no user settings source, fresh config dir per task) and principle 10
(removed v6's floor-as-rule wording), and re-keyed principle 3's recommended floor to
critic-gate's own table. No decision changed.

v8 rewrote principles 3 and 10 to state the adopted floor once, without the "not yet
confirmed" history in the running text, and added `--restricted` to principle 6. No
decision changed.

v9 amended principle 2 (the App identity; the ruleset tested), principle 3 (the driver
spawns the critics) and principle 6 (`--settings` unwritable; no sandbox). No decision
reversed.

---

## 6. Review history (what was wrong with v1–v8, and what survived)

### 6.1 v1 (first draft) — key shape and why it fell
Phases: sprint-branch mode (task PRs merged by a session into an unprotected `sprint/NN`
branch, one human merge per sprint) → headless-safe skills (declared headless outcome per
AskUserQuestion site, whole-build-order anchor, bot identity) → `bin/run-sprint.sh` → move
off the Windows host.

Findings against it (three of four v1 reviewers converged, per the author; the v3 and v4
reviewers did not open their reports and re-verified the facts instead):
- **Sprint branch re-opens WB-D20 through config, not the cursor.** Task 2 boots from the
  tree task 1 wrote; on devcontainers that tree includes `.ai/project.yml` (`gates.green` is
  arbitrary shell), `.claude/`, the merge-guard hook, `CLAUDE.md`, the gate workflow. The human
  read moved to the end of the batch. *Verified by author and by both reviewers* that
  devcontainers lists those paths in `code_paths` for exactly this reason.
  **v4 note, amended in v5:** § 7.3's per-launch restore of configuration from the *protected*
  branch **partially** answers this objection for a sprint branch, if the restore source is
  `origin/main` rather than the sprint branch. It closes the config-file vector: `.claude/`,
  `CLAUDE.md`, `.ai/project.yml` and the Action's list come from `main`. It does **not** close
  the code-the-config-points-to vector: `gates.green` on devcontainers runs
  `tools/tests/run-gate-tests.sh`, `.github/scripts/build-and-test.sh` and
  `tests/template-proof.sh` from the working tree (§ 2.3), none of which is restored, so task
  2's gate run executes task 1's unreviewed edits to those paths. With both tasks on the same
  credentials the attacker's gain is persistence across the batch rather than new capability,
  which is exactly what v1's own "Known risks" listed (lines 110-113 of
  `analysis/orchestrator-plan-v1.md`: "a bad task 1 shapes tasks 2–4 before the human sees
  any of it"; "prompt-injection persistence inside a batch"). What survives against the sprint
  branch after a `main`-sourced restore: (a) **review granularity** — one fresh-session review
  of a sprint-sized diff instead of 64-line PRs, on a repo whose gate counts per-PR reviews on
  `main`; (b) **task N builds on task N−1's unreviewed code**, including the gate scripts it
  will run; (c) a driver that merges anywhere violates principle 1 by letter. These are costs
  of *review quality and in-batch persistence*, not a WB-D20 breach in the cursor sense. The
  v1 verdict stands on evidence; v3's "killed it" overstated it; v4's "answers this objection"
  overstated the other way.
  **v6 note:** for a *task PR to `pr_base`* the tree-script residual is nil. The session
  already has Bash, CI runs the PR's own copy of those scripts anyway, and the human reviews
  the diff. For a *sprint branch* it is persistence across the batch. On devcontainers it
  would also be persistence **with Docker access**, because `build-and-test.sh` and
  `template-proof.sh` drive the Docker daemon (§ 2.3), which is root-equivalent on the host
  (§ 4.5). That strengthens the case against re-opening the sprint branch on devcontainers.
- **Driver-dispatched coder + reviewer empties the fresh-session gate.** The gate counts the
  owner's ID; a headless reviewer under the owner's login mints it by construction. Per-task
  reviews into an unprotected branch satisfy nothing on main. *Verified by author.*
- **Bot identity breaks the plugin's trust predicates** (OWNER/MEMBER/COLLABORATOR allowlist)
  or becomes a trusted writer — the #122 question. *Verified by author.*
- **"Declared headless outcome per ask site" converts human authorizations into config.**
- **Whole-build-order anchor = batch-wide stall** on any issue comment. *Verified by author.*
- **Stale premises:** subagents can nest; budget flags already exist. *Verified by author.*
- Nothing on crash/resume, concurrency with the one live cursor, kill switch, audit.

Survived into v2: deterministic driver, fresh capped session per task, policy before session,
anchor per task, human-only paths, derived digest, usage governor, eval set, context diet.

### 6.2 v2 — key shape and why it was reshaped again
Steps: ledger written into the open task PR → close-time fixes → event-dispatched fresh review
under a non-counting identity → context diet → headless coder loop after #93/#122 → ops.

Findings (three reviewers; each marked with what the author verified):
1. **Ledger-in-task-PR re-opens the WB-D20 gap wider.** `cursor-sync-pr.sh` is blind to a
   task branch (prefix filter), so resume sees `cursor-sync` drift, "none" for sync PRs, gate
   NONE OPEN → **auto-start of a `next_action` nobody merged**. The human merging on GitHub
   approves the ledger's **Next:**, never the git-ignored `next_action`; WB-D20's only display
   of `next_action` is resume's offer path, which this makes dead. handoff's prose explicitly
   rejects the shape. *All verified by author* (§ 2.2 rows 6–8).
2. **Event-dispatched review cannot satisfy the gate and leaks the token.** A bot's review is
   skipped by `REVIEWER_IDS`; a routine runs as the owner and *would* count, violating
   principle 9. `ready_for_review`/`labeled` are `pull_request` activity types that run the
   PR's own workflow copy **with repository secrets**, so a task PR can edit the workflow and
   print `CLAUDE_CODE_OAUTH_TOKEN`. *Gate allowlist and workflow-copy note verified by
   author; secrets-on-same-repo-PR is GitHub semantics (reported).*
3. **Session config comes from the task branch's working tree**, and hooks reload live and
   fail open. Driver-side "read from origin/pr_base" does not reach the session. *Verified by
   author* (§ 4.2).
4. **Hooks are tripwires.** Deny rules and merge-guard do not see `gh api … /merge`,
   `python -c`, aliases. *Verified by author* (§ 2.3).
5. **Budgets unbounded on subscription.** `--max-budget-usd` is a list-price estimate blind
   to the pool. No pre-dispatch usage read is documented beyond status-line fields. *Verified
   by author.*
6. **Throughput honesty.** Dependent tasks wait on the human's merge to main, so v2 runs one
   task (or one independent wave) per sitting. v1 bought N tasks per sitting at the cost of a
   sprint-sized PR and the config gap above.
7. **Acceptance-test-first and quarantined extraction are theatre for this repo class**
   (median PR edits SKILL.md prose; the anchored trusted-author issue already is the boundary).
8. **Human-only path set incomplete** (misses `tests/`, `.gitattributes`, `.trivyignore.yaml`,
   `scripts/`, `plugins/*/{bin,hooks}`). *Verified against devcontainers' `code_paths`.*
9. Housekeeping: CLI is 2.1.228 (flag needs 2.1.259); stale nesting sentence at
   `workflow.md` L140; merge queue only on the public repos.

Placement analysis under the subscription constraint (security reviewer, author agrees; the
WSL2 row was added in v4 without a security reviewer and amended in v5 from § 4.5):

| placement | model auth | GitHub identity | secret at rest | assessment |
|---|---|---|---|---|
| local Windows host | maintainer's login | maintainer's admin `gh`, cached GPG | none new | worst: owner credentials for two orgs, hooks fail open, MSYS quirks |
| cloud routine | subscription | **the maintainer** | none | acts as the owner, so it can mint the gate; PR/release triggers only |
| GitHub Action | `setup-token` secret | Claude App (short-lived token; Contents RW, Pull requests RW, **Workflows RW**, Statuses R) | one-year OAuth token | only placement with a separate GitHub identity; a leak costs usage for a year, not repos; same-repo PR triggers expose the secret; Workflows RW must be denied by allowlist or a custom App |
| dedicated Linux host / VM running the devcontainers image | `setup-token` in its own `CLAUDE_CONFIG_DIR` | an App installation token per task (§ 7.2), non-owner, one repo, no admin/statuses | token on a host the maintainer controls | best for the coder loop: root-owned managed hooks the branch cannot disable; no GPG; egress limited |
| **hardened container on Docker Desktop (WSL2 backend) on the existing always-on desktop** (added in v5 after the maintainer asked; **chosen in § 8.2**; reviewed for the first time in v6, from documentation and config only — nothing was built) | the `setup-token` credential in the container (env or `.credentials.json`) | none in the container (§ 8.13): the driver mints a one-hour, one-repo GitHub App installation token after the session exits and pushes itself, from a private key that stays on the host (§ 7.2, § 8.12; v5–v8 said a machine user's PAT) | token in a Docker volume inside the `docker-desktop` distro's disk image, **readable from Windows as the maintainer**; also readable by anyone who can reach the Docker socket; **and readable by the session itself** (same user), which could send it out only inside content the driver pushes, since under § 8.13a the session has no GitHub egress or token; the driver greps the tree and commit message for the token prefix before pushing (§ 7.3) | **only while the container has no Docker socket:** no `/mnt/c`, no Windows interop, no Windows `PATH`, no GPG. Managed settings baked into a read-only `/etc` make the controls physical; the session's writable config dir does not (§ 7.3, v6). Egress through an `--internal` network and a dual-homed proxy (v5's `--network none` + sidecar cannot work as written, § 6.5 item 4), **with the network created in `isolated` gateway mode**, because an `--internal` network with a bridge address still reaches host services there (§ 4.5, v7; v7's host-side block replaced by the Docker option in v8, § 8.7, **tested in v9 [T]**). **Residuals:** the Docker socket is a root door (`docker exec -u root`, `docker cp`, `docker run -v C:\…`) for any process running as the maintainer on Windows, **including the maintainer's own interactive Claude Code sessions**; shared kernel with every other container on the machine; **devcontainers' gate needs Docker (§ 2.3), and giving the container the socket removes every property in this cell (§ 8.6)**; OAuth token exfiltration over the allowed egress (one-year token, no documented revocation, § 4.3); **the per-command network allowlist and the credential `denyRead` that Claude Code's sandbox would have added are lost, because the sandbox cannot start here (§ 8.8), so the proxy and the managed `Read` deny carry them alone (v9)**; Docker Desktop runs under the maintainer's Windows login, so a reboot pauses dispatch until login. v5 listed "laptop sleep"; the host is an always-on desktop, so that residual is withdrawn. **v9:** the private repo is no longer excluded from this host (§ 8.2, D3); its residuals are the same as any repo's, and the standing-window move trigger applies to every repo. When the image should move to a VM or separate box is § 8.2's decision; v6's view that the security residuals, not availability, should trigger it is a review note there, not a fact of this row (v7) |
| **WSL2 distro on the existing machine** (added in v4; amended in v5; **dominated by the container row** — same kernel and machine, but the isolation has to be configured instead of coming for free) | `setup-token` in its own `CLAUDE_CONFIG_DIR` inside the distro | machine user's PAT in its own `GH_CONFIG_DIR` | token on the maintainer's laptop, inside the distro, **readable from Windows via `\\wsl.localhost\`** | reaches most of the Linux-host row's properties **only with all of**: a **new** distro (the existing one carries the maintainer's `gh` identity, § 3.1), `automount.enabled=false`, `interop.enabled=false`, `appendWindowsPath=false`, a loop user **without sudo**, `[wsl2] firewall=true` plus Hyper-V firewall rules for egress. Without those, the session can read the maintainer's `gh`, GPG and Claude credentials from `/mnt/c`, can run the Windows `gh.exe`, and can `sudo` past root-owned managed settings. Residual even then: shared kernel host, a reboot pauses runs until login, `wsl --user root` from Windows, same physical machine as the admin credentials |

### 6.3 v3 — what the v3 review corrected (applied in v4)

The v3 reviewer (a second Fable 5.1 session, 2026-10-04) verified against the repo, the
consuming repos over read-only `gh api`, the cited URLs, and re-ran `pr_analysis.py` and
`daily_usage.py`. Every § 2.2 row, § 2.3 fact, § 3 number marked *verified by author*, and
§ 4 claim marked [A] reproduced, except the items below. The reviewer did not open
`analysis/session-export/`.

Wrong in v3, fixed in v4:
1. § 4.2 said `PermissionRequest` hooks "can deny, not allow" under `--permission-prompts
   none`. headless.md says the opposite. Fixed in § 4.2; consequence added to § 7.3.
2. § 7.3 called `.claude CLAUDE.md .mcp.json .ai/project.yml` "the Action's restore list". The
   Action's list also has `.husky/`, `.gitmodules`, `.claude.json`, `.ripgreprc`,
   `CLAUDE.local.md`. Fixed in § 7.3. *(v5: the list correction stands; the reason v4 gave for
   `.husky/` — "git hooks that execute on the loop host's own commit" — does not; see § 6.4
   item 2.)*
3. § 4.2 and step 2 said the stale nesting sentence is also in `critic-gate/SKILL.md`. It is
   only in `workflow.md` L140. Fixed in both places.

Overstated or unsupported in v3, corrected in v4 (all re-verified in v5):
4. "16 cursor PRs … architect review next" → 14 by a stated rule (§ 3.1).
5. "Sprint 7: 11 PRs for 2 issues" → 9 PRs, #200–#208 (§ 3.1).
6. infrastructure-core "10" decision issues → 15 on 2026-10-04 (§ 3.1).
7. "#93/#122 due 2026-10-17" is a ledger promise; the GitHub milestone is due 2026-12-15 (§ 2.3, § 8.1).
8. "No merge/approve capability" for the Action is not in the docs and is false as an identity
   property (§ 4.4).
9. Merge-queue plan availability is unverified from the cited page (§ 4.4).
10. The `--help` grep was not evidence for the `--permission-prompts` version floor (§ 4.1).

Framing the v3 reviewer disputed, reworded in v4 (v5 verdict on each in § 6.4):
11. § 6.1's "killed it" overstated the sprint-branch case once § 7.3's restore existed (note
    added in § 6.1).
12. § 8.3 presented one-wave-per-sitting as a ceiling to "accept"; it is today's cadence
    (§ 3.1 baseline paragraph, § 8.3 rewritten).
13. Step 1's trust surface was "none"; it changes what the merged ledger records, so the WB-D
    now covers step 1 as well as step 4 (§ 7.1).
14. § 8.2 offered only host-or-nothing; a WSL2 row was added to the placement table and § 8.2.
15. § 8.5 re-opened the maintainer's stated hard constraint; moved to § 9 as a note.
16. § 3.2's token figures were not named as a proxy for window consumption; paragraph added.
17. Step 4 assumed "independent tasks" are derivable from plan-sprint's build order; plan-sprint
    emits a numbered sequence with no independence marker (`skills/plan-sprint/SKILL.md`
    L303). Dependency added to step 4 and § 7.3.

Biases the v3 reviewer named that v3 had not declared: API-token cost framing under a
subscription constraint; exit metrics that count touches, not reading time; a security posture
tuned to prompt injection over review-load; "trust surface: none" on the author's own
ceremony fix.

### 6.4 v4 — what the v4 review corrected (applied in v5)

The v4 reviewer (a third Fable 5.1 session, 2026-10-04) wrote a first-pass verdict on v4
before opening v3, then verified against the repo, the consuming repos over read-only
`gh api`, the raw text of hooks.md, settings.md and permissions.md, the other § 4 URLs, and
Microsoft's wsl-config page; re-ran `pr_analysis.py` (devcontainers) and `daily_usage.py 14`
and reproduced § 3 exactly. It did not open `analysis/session-export/`. Every § 6.3 factual
correction (items 1–10) reproduced.

Its first-pass verdict, before opening v3, was: v4 holds as a plan; steps 1–2 cheap and well
evidenced; step 4 correctly gated on § 8; three reviser judgements look wrong or half right
from the text alone (§ 8.3 conflates merge cadence with chain throughput; § 7.3's
`core.hooksPath` line is mechanically confused and the loop user's own settings file is
writable; § 6.1's note treats the restore as a full answer); step 1's WB-D looks right; the
WSL2 row is under-assessed. Verification against primary sources confirmed each of those and
added items 4, 7 and 8 below.

Wrong or overstated in v4, fixed in v5:
1. **§ 6.3 item 2's rationale for `.husky/`.** Husky hooks execute only when `core.hooksPath`
   points at `.husky`, which husky's npm `prepare` script writes into the untracked
   `.git/config`; a fresh clone never has it. No consumer has `.husky/` or `package.json`
   (§ 2.3). Restoring the Action's full list is harmless and kept; the reason is corrected.
2. **§ 7.3's `core.hooksPath` line** said `git -c core.hooksPath=/dev/null` stops ".husky/ or
   a task-branch `.git/hooks` write" executing "on commit". `git -c` binds only the driver's
   own git invocations, not the session's `git commit` in Bash, and a hook firing inside the
   session gains nothing the session's Bash tool does not already have. "A task-branch
   `.git/hooks` write" cannot exist: `.git/hooks` is untracked, and the per-task clone discards
   whatever the session wrote there. The only real exposure is driver-run git inside a clone
   the session has already touched (the post-exit `git diff` runs no hooks; a later
   `git checkout` would). Rewritten in § 7.3 as a driver-side rule with its real scope.
3. **§ 7.3 missed a live widening path.** The loop user's own `settings.json` in
   `CLAUDE_CONFIG_DIR` is writable by the session process (same user), and the settings
   watcher applies edits to `hooks` and `permissions` live (§ 4.2). A session that writes a
   `PermissionRequest` allow-hook into its own user settings widens itself mid-run; the
   post-exit hash only records it afterwards. Fixed in § 7.3 (files read-only to the session
   user; managed deny on writes under the config dir) and principle 6.
4. **§ 7.3's pre-launch hash compare** ran immediately after restoring from the same ref, so it
   checked nothing. Moved to post-exit, where it detects what the session changed.
5. **§ 6.1's v4 note** said the restore "answers this objection". It answers the config-file
   half; `gates.green` executes tree-resident scripts the restore does not touch (§ 2.3).
   Amended to "partially answers", with v1's Known risks cited.
6. **§ 8.3 / item 12: reversed.** "One wave per sitting is today's cadence" conflates the
   interval between merges with the throughput of a dependent chain. Today the human is
   present during the merge window (§ 3.1: 12:22–23:37 UTC on the busiest day), so a chain
   advances every nine minutes. The loop exists to run while they are away (§ 7.4's window),
   so a chain advances once per sitting, which is once a day. That is a real ceiling for
   dependent work. v3's "accept" framing was right; v4 was wrong to remove it. § 8.3 rewritten
   again; v4's reframing of the *real* decision as "re-open the sprint branch or not" is kept,
   because it is the right question.
7. **§ 4.4's App permissions** named only Contents and Pull requests. The installed set also
   includes Workflows RW (the #93 gap for an Action-placed loop) and Statuses R. Added.
8. **§ 4.1 / § 9 missed a platform-churn risk.** headless.md says `--bare` will become the
   default for `-p`. The subscription path depends on plain `-p`; no opt-out is documented
   yet. Added to § 4.1 and § 9.

v5 verdict on v4's judgement calls (§ 6.3 items 11–17):
- 11 (soften "killed it"): **kept, amended** — the restore is partial (item 5 above).
- 12 (§ 8.3 "nothing to accept"): **reversed** (item 6 above).
- 13 (step 1 needs the WB-D): **kept**. WB-D20's own text says a GitHub merge approves the
  ledger alone; step 1 removes that read for one step type. Small, non-zero, and it changes a
  recorded decision's property, which is what a WB-D is for. v5 adds the sharper angle neither
  v3 nor v4 named: the derived step is a fresh-session review that mints the gate under the
  owner's ID, so the PR it targets must be derived from GitHub state the session cannot shape
  (same-repo head, maintainer-authored), never from `state.json`. Written into step 1.
- 14 (WSL2 row): **kept as an option, amended** with § 4.5's preconditions. As written in v4
  it would have placed the loop on a distro that can read every credential it was meant to be
  isolated from.
- 15 (§ 8.5 → § 9 note): **kept**. A stated hard constraint is not an open decision.
- 16 (proxy paragraph): **kept**. The most useful addition in v4.
- 17 (independence marker): **kept, verified**. plan-sprint treats dependency only as a
  placement *reason* (L169, L176); the emitted build order (L303) carries no marker.

Biases the v4 reviewer named that v3 and v4 had not declared:
- Both sessions treat code.claude.com as ground truth for behaviour nobody executed, and as
  stable when it is not (`--bare` default change announced; routines in research preview;
  `--permission-prompts` 31 builds old).
- The v4 reviser showed convenience bias toward the maintainer's existing machine: it added
  and ranked second a placement it had not threat-modelled, on the host the ledger says
  already carries the maintainer's identity.
- The v4 reviser moved every disputed point toward the middle (softened v1, hardened step 1,
  added a middle placement), which reads as judgement but is also what a same-family second
  opinion tends to produce.
- The v4 reviser's § 8.3 argument committed the count-what-is-countable bias it named in the
  author: merge gaps measure the human's presence, not chain latency.

### 6.5 v5 — what the v6 (Opus 5.5, cross-family) review corrected (applied in v6)

The v6 reviewer wrote a first-pass verdict on v5 before opening v4 or v3. It then verified
against: the raw hooks.md, settings.md, permissions.md and headless.md; the mods admin page;
the live rulesets of claude-workbench, devcontainers and bounty-infra; devcontainers'
`.ai/project.yml`; and the plugin files cited in § 2. It re-ran `pr_analysis.py`
(devcontainers) and reproduced § 3.1 exactly (one more cursor PR had merged since: 69 where
v5 printed 68). It did not open `analysis/session-export/`.

Its first-pass verdict, before opening v4 or v3: v5 holds as a sequencing plan. Steps 1–2
are cheap and well evidenced, step 3 is correctly blocked, and § 8.4b is the best addition.
Step 4's security story is weaker than it reads: principle 2 contradicts § 7.2's PAT scope;
the container hardening contradicts itself (`--network none` plus a sidecar; a read-only
rootfs while the config dir has to be writable; `allowManagedHooksOnly` doesn't stop
`permissions.allow`); devcontainers' gate needs Docker; the driver git rule misses
config-driven execution; the OAuth token can leave over the allowed egress. On § 8.3, v5's
logic is sound, but the ceiling limits what the loop adds rather than being a regression,
and nothing measures how much work is dependent. Verification confirmed all of these except
the git point, which it narrowed (item 6).

Wrong or overstated in v5, fixed in v6:
1. **Principle 2 is false on all three first-wave repos today.** § 4.4 already said Contents
   + Pull requests write "is enough to merge through the API", and § 7.2 grants the loop
   exactly that. Every ruleset requires 0 approvals (§ 2.2). On claude-workbench and
   bounty-infra the loop can merge its own green PR. On devcontainers it can merge in the
   window between the owner's review minting `architect-review` and the human's merge. Only
   deny rules stop it, and § 6.2 item 4 calls those tripwires. Principle 2 amended; new open
   decision § 8.5.
2. **The chosen placement cannot run devcontainers' gate.** Five of eight `gates.green`
   steps need Docker (§ 2.3). Inside the § 7.3 container the session either skips the gate
   or is given the socket. The socket is root on the `docker-desktop` VM, and through Docker
   Desktop's drive sharing it reaches every Windows credential (§ 4.5, v6 additions; v7:
   overstated, § 6.6 item 5). No
   earlier pass checked the motivating repo's gate against the placement. New open decision
   § 8.6.
3. **§ 6.4 item 3's fix (read-only settings files plus a managed Bash deny on the config
   dir) was half overbuilt and half underbuilt.**
   - Overbuilt: `allowManagedHooksOnly` alone closes the hook path, including mods the session
     writes.
   - Underbuilt: (a) `permissions.allow` from user settings still merges in, and only
     `allowManagedPermissionRulesOnly` stops that. (b) `CLAUDE_CONFIG_DIR` must be writable
     (session history, `.claude.json`), so a root-owned 0644 file in it can be unlinked and
     recreated. (c) A Bash deny "isn't a security boundary" per permissions.md.
   - § 7.3 rewritten so non-managed sources are irrelevant rather than unwritable.
4. **The egress design could not work as written.** With `--network none` the container has
   only loopback and cannot reach a sidecar. Sharing the sidecar's network namespace gives the
   session the proxy's unrestricted egress. Replaced with an `--internal` network and a
   dual-homed proxy, and the preflight check changed to match. Separately, github.com is
   allowed and three of the repos are public, so the session can exfiltrate the one-year
   OAuth token it can read; the Action scrubs env for this reason. Added as a residual with
   mitigations in § 7.2 and § 7.3.
5. **§ 4.2 cited the wrong evidence for the bound.** `PermissionDenied` is an auto-mode
   event. The bound itself holds, on hooks.md's PermissionRequest decision table. Also added:
   a hook's `updatedPermissions` can persist or remove rules in any non-managed source.
6. **§ 7.3's driver-side git rule was still too narrow.** v5 was right against v4: `git -c`
   in the driver does not bind the session, and husky needs `core.hooksPath` from npm's
   `prepare`. But `core.hooksPath=/dev/null` does not neutralise a `.git/config` the session
   wrote: `core.fsmonitor`, `credential.helper`, `core.sshCommand` and `url.<x>.insteadOf` run
   or redirect on the "later … fetch" v5 still allowed. If the driver runs outside the
   container, that is a way out of the container. Rewritten: the driver takes the post-exit
   diff from the GitHub compare API and never runs git in a clone the session touched.
7. **Smaller inconsistencies.**
   - The launch line hard-coded `--model sonnet` against § 8.4a's "no loop default". It now
     reads `models.coder`.
   - § 8.1 said #93 is mitigated "by PAT scope alone". A PAT without the Workflows permission
     still edits `.github/scripts/*`, which the PR's own CI runs; the mitigation is that plus
     `human_only_paths` covering `.github/`. Note added.
   - § 8.1 said steps 4–6 wait on #93/#122, while its decision makes the loop independent of
     #122. Note added.
   - § 8.4a's unattended critic selection changes critic-gate's own contract ("spawn NOTHING
     yet… the human confirms or trims the list", `skills/critic-gate/SKILL.md` L47–51), not
     only principle 3. The WB-D must amend the skill. Note added.
8. **The host is an always-on desktop**, not a laptop (maintainer correction). The "laptop
   awake" residual is withdrawn, and § 8.2's condition for moving the image is restated in
   terms of security rather than availability.

v6 verdict on § 6.3 items 11–17 and § 6.4's verdicts on them:
- 11: **v5 right** (the restore is partial). For a task PR the residual is nil; for a sprint
  branch it is persistence, and on devcontainers persistence with Docker access (§ 6.1 v6
  note).
- 12 / § 6.4 item 6: **v5 right on direction, wrong on cause.** v4's "nothing to accept"
  fails, because the loop adds nothing to a chain past its first link. But v5 compared the
  loop with a human who is present, as if the loop replaced daytime work. The ceiling comes
  from § 7.4's away-only window, not from principle 1, and merge-triggered dispatch during a
  sitting (§ 7.4) was offered by neither reviser. § 3.1 does not measure dependency share.
  (v7: v5 had already named the away-only window as the cause; see § 6.6 item 9.)
- 13: v5 right; § 8.4b is the right strengthening.
- 14: v5 right against v4, but v5 then repeated v4's error with the container row (item 2).
- 15, 16, 17: both right; 17 re-verified (`skills/plan-sprint/SKILL.md` L303).

Biases the v6 reviewer named that none of the earlier passes declared:
- **Tool-centric framing.** All three Fable passes tried to make principle 2 true inside
  Claude Code configuration. None read the GitHub rulesets, which is where principle 2
  actually lives.
- **Accretion.** Each revision added mitigations. None asked whether devcontainers, the repo
  whose 1.53 cursor ratio motivates the work, can host the loop at all.
- **Convenience bias, repeated.** v5 named it in v4's WSL2 row, then wrote "principle 6
  physical" for the container row from one `docker info`.

### 6.6 v6 — what the v7 (second Opus 5.5) review corrected (applied in v7)

The v7 reviewer wrote a first-pass verdict on v6 before opening v5, then verified against the
sources listed in § 0. It re-ran `pr_analysis.py` for claude-workbench and reproduced § 3.1's
row exactly (71 work / 52 cursor / 31 record, 0.73, median 12 min, median 129 lines). It did
not open `analysis/session-export/`, v4 or v3.

Its first-pass verdict, before opening v5: v6 holds as a sequencing plan, and its § 6.5
findings are mostly the right kind (repo-side controls over tool configuration). The weakest
parts are the new § 8.5 and § 8.6 option sets, which look incomplete, and two places where a
"note" leaks into a principle. Predicted: item 1 right unless
`require_extra_approval_for_unattributed_changes` changes it; § 8.5 misses a fork option, and
(b)'s "one extra click" is wrong because the human authors most PRs; (a)'s bypass may need
`--admin`, which merge-guard refuses; § 8.6 misses native linters; writable user settings
matter beyond hooks and permissions; the sandbox needs a weaker nested mode; the git rule is
right; "review cadence" overstates; principle 10 states the floor as a rule. Verification
confirmed all of these except one prediction, that bypass might skip required checks, which
reduced to a layering detail (item 1).

Wrong or overstated in v6, fixed in v7:
1. **§ 8.5's options.**
   - (b) is not "one extra click per PR". The maintainer's account authored nearly every PR
     in all four repos (§ 2.2), and GitHub does not let a PR's author approve it. (b) blocks
     every PR the maintainer opens, including resume's cursor-sync merge, unless a second
     person approves or the maintainer bypasses.
   - A fork-based option was missing: a read-only machine user can push only to its own fork
     and cannot merge at all.
   - (a) has two mechanics v6 did not state. Bypass is granted per ruleset, so the
     restriction belongs in a **separate** ruleset if the existing one's required checks are
     to keep binding the human. And a bypass merge is an explicit choice (`gh pr merge
     --admin` from the CLI), which resume's merge command (`skills/resume/SKILL.md` L350) and
     devcontainers' merge-guard (its exact-shape regex, `merge-guard.sh` L166) both refuse.
   - v6's caveat about `require_extra_approval_for_unattributed_changes` is resolved: it
     applies only to Copilot PRs opened under Copilot's own identity, and "has no effect if
     the ruleset requires zero approvals". Item 1 stands.
   § 8.5 rewritten.
2. **§ 7.3's "nothing it writes is consulted" held only for hooks and permissions.** The
   launch line kept `--setting-sources user`, so the session's own writable user
   `settings.json` was still loaded. Credential helpers (`apiKeyHelper`, `otelHeadersHelper`,
   `awsAuthRefresh`, …) and `env` may sit there, are reloaded live, and the helpers run
   outside the sandbox (§ 4.2). A persistent config dir also carries user CLAUDE.md, agents
   and skills into the next task's session. Fixed in § 7.3 and principle 6: drop `user`
   from `--setting-sources`, use a fresh `CLAUDE_CONFIG_DIR` per task, and set
   `strictPluginOnlyCustomization`.
3. **`allowManagedPermissionRulesOnly` answered.** It ignores `--allowedTools` and allow
   rules in `--settings` files. Principle 4's and § 7.2's `--allowedTools` list did nothing
   once the key was set. The allowlist moves into managed settings; `--disallowedTools` still
   applies and is kept as a second layer.
4. **The `--internal` network still reaches the host's gateway** (Docker's own description
   of `--internal`), so "the proxy denies `host.docker.internal`" blocks at the wrong layer.
   Fixed in § 7.3 and § 6.2: block host and gateway addresses on the host side.
5. **The Docker-socket residual was overstated in one direction.** "Reaches every Windows
   credential" is not in Docker's documentation, and gh's tokens are in the Windows keyring
   here, not in a file. The residual is still severe but works by write-then-execute (§ 4.5).
6. **The sandbox in a container** needs `enableWeakerNestedSandbox`, which "reduces
   security", covers Bash only, and allows reading credential files by default. v6's "put the
   credential outside the sandbox's readable set" needs an explicit `denyRead` (§ 4.2, § 7.2,
   § 7.3).
7. **Principle 10 stated the unconfirmed floor as a rule** ("never ships with fewer critics
   than the floor"), while § 8.4a called it a recommendation. Restored. **The floor itself
   went past critic-gate's table:** row 1 is "security-critic and/or architect", and the skill
   lets the human pick one or skip the new-doc row (`skills/critic-gate/SKILL.md` L71, L82,
   L95). Re-keyed to "at least one of" in principle 3 and § 8.4a.
   **v8, amended in v9:** half right. v6's *principle 3* (v6 L511-512) did write
   "`code_paths` → architect and security-critic; … newly added doc → docs-consistency", so
   the re-keying was needed there. But v6's *§ 8.4a note* (v6 L1193-1195) left "the
   table's 'and/or' choices" and the new-doc security-critic call to the LLM slot, so v6
   was internally inconsistent rather than past the table throughout. v8 also rebutted the
   word "smuggled"; that is withdrawn, because v7 never used it (no match in v7): it is
   v6's own check 7 (v6 L82). v7 was right about principle 10.
8. **§ 8.6 was incomplete.** Three of the five Docker steps are linters that can run natively
   (zizmor is already in the base image). CI already runs all five as required checks on
   every image-shaping PR (§ 2.3), so option (a) keeps the merge-time bar. Its real cost is
   that critics review a diff whose build is unproven, and red PRs reach the human. Option
   (e) added; (a)'s cost stated.
9. **§ 6.5's verdict on item 12 ("v5 wrong on cause") was a strawman.** v5 had already put
   the ceiling on the away-only window. "At review cadence" (§ 3.1, § 7.4) overstated the
   merge-triggered option's pace, which is one task session per link. And it left out two
   costs: § 7.5's lock file blocks the human's own resume auto-start during the sitting, and
   loop sessions draw on the same 5-hour usage window the human is using. § 3.1 and § 7.4
   amended.
   **v8, reverted in v9:** v8 read v5 § 8.3's opening sentence (v5 L861, "Keeping the human
   merge as the only approval means a dependent chain advances one task per sitting") as
   attributing the ceiling to principle 1, and called v5 inconsistent. The same paragraph
   names the away-window two lines later: "under the loop, which runs while they are away,
   it advances once a day" (v5 L863). v5 was not inconsistent; v6 read one sentence; v7's
   substance was right, and "strawman" is strong wording rather than wrong substance. The
   v9 reviewer is the same family as v7, so weigh this verdict by the quoted lines, not the
   reviewer. The three costs v7 added hold: the lock file is § 7.5's own design, the 5-hour
   window is costs.md, and the task-session pace follows from § 7.4's cap.
10. **Smaller.**
    - § 6.2's container row stated as fact that moving the image is "justified by the
      security residuals", which is v6's note on § 8.2's decision; moved back to the note.
    - The compare API lists at most 300 changed files and reports renames through
      `previous_filename`; § 7.3's post-exit check must fail closed at the cap and test both
      names.
    - infrastructure-core also requires `architect-review` (§ 2.2).

v7 verdict on § 6.3 items 11–17 and § 6.5's verdicts on them:
- 11, 13, 14, 15, 16, 17: § 6.5 right (17's L303 not re-read).
- 12: § 6.5 right on direction, wrong to say v5 mistook the cause (item 9 above).

v7 verdict on § 6.5 items 1–8: 1 right, with its § 8.5 option set wrong or incomplete (item
1 above); 2 right that the gate as written needs Docker, overstated on credentials (items 5,
8); 3 right in direction, incomplete (items 2, 3); 4 right about `--network none`, but its
replacement had the gateway hole (item 4); 5 not re-read by v7; 6 right (v5's "the post-exit
`git diff` runs no hooks" was itself wrong: `core.fsmonitor`, `diff.external` and textconv
drivers run on diff); 7 right (v5 L742 `--model sonnet`, v5 L845 "PAT scope alone"); 8 right.

Biases the v7 reviewer named that no earlier pass declared:
- **"The human's PR" is a Claude-written PR.** Every pass treated the maintainer as the
  author of the PRs they merge. In fact the interactive Claude sessions open them under the
  maintainer's login (§ 2.2). That is why (b) looked cheap. It also means WB-D20's "a merged
  PR is the human approval" already rests on the human reading a Claude-written diff, which
  is the same act the loop asks for. The plan should not present the loop's PRs as a new
  kind of trust.
- **Identity-centric framing in v6.** It fixed principle 2 with rulesets but never asked
  whether the loop needs write access at all.
- **"Same quality bar" read as local-gate parity.** Every pass read the maintainer's phrase as
  "the session runs the whole local gate". On devcontainers the merge-time bar lives in CI's
  required checks, which run every Docker step.
- **Shared with v6 (and present in v7):** security-first reading, and treating documentation
  as ground truth for behaviour nobody ran. Every v7 finding in § 7.3 is unexecuted.

**Decisions taken after the v7 review.** The v7 reviewer then presented the six items still
open or pending (§ 8.5, § 8.6, the § 8.4a floor, the § 8.1 date, the § 8.2 move trigger and
§ 7.4's merge-triggered dispatch) with options, pros and cons, and a recommendation for each.
Before that, it read claude-workbench's and bounty-infra's CI workflows, which ruled out the
fork option for bounty-infra and changed its own § 8.5 recommendation from per-repo to
option (a) everywhere. The maintainer took every recommendation on 2026-10-04, adding that
they are "not terribly worried about the integrity of this host". Each decision is recorded
under its § 8 item. Because the reviewer that recommended them also edited the plan, the next
reviewer should check that the recorded decisions match what the plan now does, not only
that they read well.

### 6.7 v7 — what the v8 (fourth Fable 5.1) review corrected (applied in v8)

The v8 reviewer wrote a first-pass verdict on v7 before opening v6, then verified against the
sources listed in § 0. It re-ran `pr_analysis.py` for infrastructure-core and reproduced
§ 3.1's row exactly (84 work / 48 cursor / 63 record, 0.57, median 11 min, median 166 lines,
29 merges over 22.8 h on 2026-09-07). It did not open `analysis/session-export/`, v4 or v3.

Its first-pass verdict, before opening v6: v7 holds as a sequencing plan. Predicted from the
text alone: "bypass merge needs `--admin`" was asserted from gh's flag text, not gh's
behaviour; the bounty-infra OIDC blocker is the fork token, not the subject string;
`--setting-sources ""` is probably under-documented for the CLI; `--disallowedTools` and the
settings hashes are redundant; Docker may document a gateway mode that replaces the host-side
rule; v7 looked only at Windows-side secret files; § 8.2's "routine nights" clashes with
§ 7.4's night window; principle 3 carries stale "not yet confirmed" text; § 6.6 item 9 turns
on v5's exact words. Verification confirmed each, and added the `--restricted` flag, which
the first pass had not predicted.

Reproduced exactly: the § 2.2 authorship row; all four rulesets with both accounts; every
§ 4.2 line-number quote re-read (§ 4 legend); the `--internal` gateway sentence (network
create.md L197-203); ECI's subscription and socket statements; the File sharing table; the
restrict-updates, self-approval, fork-secrets and compare-cap statements on docs.github.com;
bounty-infra `plan-infra.yml` L14-25 and `ci.yml` L178; critic-gate L71, L82, L95; resume
L350; merge-guard L166.

Wrong, overstated or incomplete in v7, fixed in v8:
1. **§ 7.3's host-side gateway rule was the wrong layer.** Docker documents
   `gateway_mode_ipv4=isolated` for `--internal` networks: no address is assigned to the
   bridge (§ 4.5). It is set at `docker network create`, persists like any network, and is
   readable by the preflight. v7's rule worked against rules Docker says not to modify and
   had unverified persistence. Replaced (§ 7.3, § 8.7); the in-container probe stays.
2. **§ 7.3's settings-loading forms were both undocumented when a documented one exists.**
   `--restricted` "loads only managed settings and `--settings`" (§ 4.2). The empty
   `--setting-sources` list becomes the contingency; the `project`-only fallback is dropped,
   because project settings carry `env` and helpers that apply in `-p` at startup (§ 4.2)
   and it needed three controls to keep one unneeded file inert. § 7.3 and § 8.8.
3. **"A bypass merge is `gh pr merge --admin`" was asserted, not read.** `--admin` only
   skips gh's own client-side refusal of a `BLOCKED` PR; the server applies bypass regardless
   (§ 4.4). The test question is whether GitHub reports `BLOCKED` to a bypass-eligible
   viewer. § 8.5's scratch test is rewritten around it, and resume's `--admin` change waits
   for the answer. Two interactions were missing from the test: GitHub's merge queue (§ 7.1
   step 4) and devcontainers' planned auto-merge (#139) both merge as GitHub, not as a
   bypass actor. Added. The plan's own contingency ("the other three need a different
   answer") named nothing; it now names (e) plus fork-safe required checks.
4. **§ 8.5's bounty-infra evidence named the wrong mechanism.** The OIDC subject is the same
   on a fork PR; the blocker is the read-only `GITHUB_TOKEN`, which cannot carry
   `id-token: write` (§ 4.4). Conclusion unchanged. And "claude-workbench's `ci.yml` uses no
   secrets" holds for the three required checks only: its `zizmor` job needs
   `security-events: write` (ci.yml L120-122) and would fail from a fork. Noted.
5. **§ 8.2's trigger used a word the governor cannot read.** "Runs unattended nights as a
   matter of routine" names the thing § 7.4's designed window does on its first night.
   Re-keyed to a placement key and per-sitting away-blocks (§ 8.2 decided after v8, § 7.4).
6. **§ 4.5's narrowing looked only at Windows-side files.** The Ubuntu distro's gh, which
   devcontainers' ledger names, stores its token in a plain file unless a secret service is
   configured, and the distro is reachable from the Docker socket. Recorded as an inference
   for the maintainer to verify (§ 8.9); v8's own check was refused by the auto-mode
   classifier.
7. **§ 6.6 item 7 and item 9 each overstated the pass they corrected** (v8 notes under
   them). Item 7 was right about v6's principle 3 and principle 10 and wrong about v6's
   § 8.4a note; "smuggled" does not fit a reviser that flagged its own note for checking.
   Item 9's "strawman" does not fit a v5 that attributed the ceiling to principle 1 in
   § 8.3 and to the window in § 3.1.
8. **Smaller.**
   - `--disallowedTools` as a "second layer" duplicates the managed deny rules it repeats
     (settings-reference.md:1391 says both apply, so it was inert, not harmful). Removed from
     the launch line.
   - The post-exit settings hash is forensics once nothing writable is consulted; relabelled.
   - `.claude/rules/` joins the restore list (§ 4.2).
   - § 8.6's CI-wait rule now reads image-scope's verdict and records "build skipped
     (build=0)" rather than implying CI ran the deferred steps (§ 2.3).
   - Principles 3 and 10 state the adopted floor once (§ 5).
   - infrastructure-core's second ruleset and the 603-Identity rulesets' rule set are
     recorded in § 2.2.

v8 verdict on § 6.6 items 1–10: 1 right, with item 3 above; 2 right, and § 4.2 adds that
project settings carry the same keys; 3 right; 4 right on premise, wrong on remedy (item 1);
5 right on gh, incomplete (item 6); 6 right; 7 half right (item 7); 8 right, with the
image-scope detail in § 2.3; 9 overstated (item 7); 10 right (v6 L664 did state it as fact).

v8 verdict on § 6.6's verdicts on § 6.3 items 11–17 and § 6.5 items 1–8: not re-derived
beyond what the items above touch. v8 read v6 only where § 6.6 adjudicated it and v5 only at
the lines item 9 turns on.

Biases the v8 reviewer named that no earlier pass declared:
- **Search by inheritance.** Each pass grepped the previous pass's vocabulary
  (`--setting-sources`, `--internal`, `allowManaged*`) and so found refinements of the
  previous answer, not the documented features beside it. Both v8 additions came from reading
  the flag table and the Docker page index whole rather than searching for a term.
- **Compensating adjudication.** v7, judging v5 against its own family's v6, sided with v5
  and overstated the case (item 9). A same-family pass correcting for family loyalty can
  overshoot the other way.
- **Shared with every pass, and present in v8:** documentation as ground truth for behaviour
  nobody ran. The two features v8 added are documented and untested here, like everything in
  § 7.3.

**Decisions taken after the v8 review.** The v8 reviewer presented six items, one at a time,
with options, pros, cons and a recommendation; the maintainer took every recommendation on
2026-10-04. They are recorded under § 8.7 (egress mechanism), § 8.8 (settings-loading form),
§ 8.2 (the meaning of "routine"), § 8.5 (the scratch test's scope and contingency), § 8.9
(the host's plain-file secrets) and § 8.10 (the editorial corrections and who applies them).
The maintainer first decided under § 8.10 that a fresh session would write v8, then asked
the reviewing session to do it; v8 records that reversal so the next reviewer reads § 7
against § 8 with the same suspicion the v7 brief asked for.

### 6.8 v8 — what the v9 (third Opus 5.5) review corrected (applied in v9)

The v9 reviewer wrote a first-pass verdict on v8 before opening v7, then verified against
the sources listed in § 0. It re-ran `pr_analysis.py` for bounty-infra (§ 3.1, the row
nobody had produced) and found the title classifier misses that repo's cursor grammar. It
did not open `analysis/session-export/`, v4 or v3; v6 and v5 only at the lines § 6.7
cites. It executed nothing and changed no GitHub setting. It did not edit the plan
(§ 8.11): it wrote `V9-EDIT-SPEC.md`, and a separate session applied it after the tests
ran.

Its first-pass verdict, before opening v7: v8 holds as a sequencing plan; its best change
is procedural (tests before the driver). Ten predictions from the text alone. Verification
confirmed six (`Skill` missing from `--tools`; "moot under `--restricted`" unsupported; the
sandbox's and the permission system's protected paths conflated; `viewerCanMergeAsAdmin`
exists and no merge queue is configured anywhere; the jobs API exposes step conclusions;
24418824 is a push ruleset), partly confirmed three (`isolated` silent on Desktop;
placement self-declared and public-only unenforced; § 7.3 differently complicated rather
than simpler) and **refuted one**: it had predicted that v8's verdict on § 6.6 item 9 was
fair.

Verified as v8 states: the `--restricted` quote (cli-reference.md:123); the `isolated`
quote (port publishing, Gateway modes); `merge.go` L255-275 and L779-800 and `http.go`
L48-80 (no admin field); WB-D20 at L1003; critic-gate L67-95; resume L350; `ci.yml` zizmor
L118-122; `plan-infra.yml` L20-25; `ci.yml` L178; all four repos' rulesets with both
accounts; image-scope's path list.

Wrong, overstated or incomplete in v8, fixed in v9 (the spec's editorial bundle):
1. **`--settings` must be unwritable: a v8 regression.** v7 put the driver file "outside
   every writable path" (v7 L1274); v8's launch paragraph dropped it. Under `--restricted`
   it is the only non-managed source left, its `env` is re-applied live
   (settings-reference.md, "When Claude Code applies `env` values") and `apiKeyHelper` is
   read only from it (permissions.md:726), with helpers running outside the sandbox
   (sandboxing.md:43). Now inline JSON or a root-owned file on the read-only rootfs
   (§ 7.3, principle 6). A v8 edit outside § 8 changed a decision's effect without saying
   so.
2. **Sandbox protected paths.** § 4.2 and § 7.3 said the sandbox denies Bash writes to the
   `--plugin-dir` copy. That entry is the permission system's (permission-modes.md:646);
   the sandbox's groups contain no plugin dir, and sandboxing.md says the two lists are
   separate. Corrected in both places. The spec restated the sandbox's remaining reasons;
   the tests then found it cannot start in the container, and the maintainer dropped it
   (§ 8.8), so that restatement is superseded.
3. **"Moot under `--restricted`"** for user CLAUDE.md, agents and skills (§ 9) was
   unsupported: cli-reference.md:123 speaks only of settings. What makes them moot is the
   fresh `CLAUDE_CONFIG_DIR` per task. Reworded.
4. **§ 8.6's CI-wait rule** can read the verdict from outside: the jobs API
   (`GET /repos/{repo}/actions/runs/{run}/jobs`) gives each step's `conclusion`, and on the
   last six devcontainers PR runs "Build and test all images" and "Prove the template" read
   `skipped`, guarded by `if: steps.scope.outputs.build == '1'` (`build.yml` L64, L71).
   Replaces "step outputs or summary"; the § 9 item is closed. v8's § 2.3 claim that
   image-scope's path list covers image-shaping files holds (build context is
   `images/<flavor>`, so `COPY tools/…` is `images/base/tools/`).
5. **§ 2.2's layering precedent** was a push ruleset. The real precedent is devcontainers'
   `release-tags`; the other rulesets v8 omitted are listed (§ 2.2).
6. **§ 7.3 egress.** The proxy is dual-homed and its external network still reaches its own
   gateway, so the proxy's allowlist refuses IP literals and `host.docker.internal`. Docker
   Desktop's networking page puts the bridge inside the VM, so the `--internal` gateway
   reaches the VM's services, not Windows' (the test then confirmed it, § 8.7). "The option
   landed in Engine 28" (§ 4.5) was not on the cited page; deleted. `--internal` containers
   "may communicate between each other" (network create.md L197) is the cited support for
   proxy reachability.
7. **§ 6.6 items 7 and 9.** Under item 9, v8's "v5 inconsistent" is reverted: v5 L863 names
   the away-window two lines after the sentence v8 quoted. Under item 7, v8's point about
   v6's principle 3 and § 8.4a note stands, but its rebuttal of "smuggled" is deleted: v7
   never used the word; it is v6's own check 7. The reviewer is v7's family; weigh by the
   quoted lines.
8. **§ 3.1 bounty-infra row** added, with both classifier results and the rule.
9. **§ 4.4's OIDC correction** kept, with the "cannot carry `id-token: write`" step marked
   as an inference from two pages, not a quote.

Verdicts on § 6.7 items 1–8: 1 right; 2 right on the flag, wrong in effects (items 1–3
above); 3 mostly right (the `--admin`/queue note and `viewerCanMergeAsAdmin`, § 8.5, D2);
4 right (item 9); 5 partly right (D3: re-keyed to a word the governor can read, but
public-only protected little); 6 sound on gh (D4); 7 half right on § 6.6 item 7, wrong on
item 9 (item 7 above); 8 right except the CI-wait route and the § 2.2 precedent (items 4,
5). On § 6.7's verdicts on § 6.6 items 1–10: agree on 1–6, 8, 10; agree on 7 that v7
overreached on the § 8.4a note; disagree on 9.

Biases, declared and undeclared:
- v6 and v7, same family: v7 kept v6's security-first structure; v8's "search by
  inheritance" claim holds.
- v8: over-trust of its own finds shows in items 1–3 above and in its claim that § 7.3 got
  simpler. Its item 9 verdict split the difference against the text, the "compensating
  adjudication" it named in v7.
- v9 reviewer: its item 9 verdict sides with its own family; weigh it by the quoted line.
  Security-first, like v6 and v7.
- **Undeclared by every pass before v9:** eight passes refined the Docker-socket residual
  although the loop container never gets the socket (§ 8.9); "merge queue where available"
  was carried from v3 without anyone checking that a queue was configured (none is, § 4.4);
  nobody counted the document's own size (2,338 lines at v8) as a review cost; and every
  pass after v7 treated "public repos only" as protecting the admin credentials, which it
  does not (§ 8.2, D3).

**Decisions taken after the v9 review.** The reviewer presented five items with options,
pros, cons and a recommendation; the maintainer took each on 2026-10-04: the driver spawns
the critics (§ 8.4a, D1); § 8.5's scratch test runs checks 1–3 now and turns 4–5 into
preconditions (§ 8.5, D2); private repos may run on this host under two conditions, with
placement moved to the driver's host config (§ 8.2, D3); § 8.9 is host hygiene (D4); a
fresh session writes v9 after the three tests run (§ 8.11, D5). The reviewer did not edit
the plan.

**The tests (2026-10-04/05) and what they changed.** A separate Opus 5.5 session ran
§ 8.7's probe (PASS); § 8.8's launch form as amended by D1 (Bash restored; the sandbox
cannot start in the container; plugin agents load, but `--restricted` strips tools not
named in `--tools`; `--restricted` loads only managed settings and `--settings`); and
§ 8.5's checks 1–3 (all three answered; `viewerCanMergeAsAdmin` read `false` for an admin
who then merged). Its setup found that an outside-collaborator machine user cannot mint a
per-repo token, which D3's condition (1) requires; it then evaluated and tested a GitHub
App on the same scratch repo. Four decisions followed, each the recommendation, taken by
the maintainer without further reasoning: no Claude Code sandbox in the loop container
(§ 8.8); the critic line names the agent's tools and the driver reads the init event
(§ 8.4a); the per-PR check reads `current_user_can_bypass` and `mergeStateStatus`
(§ 8.5); the loop identity is a GitHub App "unless/until there is a reason to switch"
(§ 8.12). **The tests' own bias note, carried here:** the testing session is the same
family as the reviewer that recommended D1–D5, and two of the tests check those decisions'
premises; its verdicts rest on the quoted init events, tool calls, server responses and
rule-suite logs, and one of them went against D2's chosen signal. Where the results
contradicted the spec, the results were applied (the spec says they win); the editor's
hand-back lists each case.

---

## 7. The plan (v9)

### 7.1 Steps

| # | change | trust surface | exit metric |
|---|---|---|---|
| 1 | **No-op handoff rule.** When the only cursor change is "review or merge PR N next", handoff writes `.ai/state.json` and skips the ledger PR; resume derives that step **from GitHub state only** (an open same-repo PR whose head was pushed by the maintainer's login and whose title or body names the anchored task issue), never from `state.json`'s `next_action`. (v9: loop PRs are pushed by the App and never match; **intended**, § 8.13.) Milestone 1 also implements § 8.1's name rule (§ 8.13). Fix #209 (roadmap entry written before close) and #220 (dirty ledger) so a sprint close is one PR. | **small, and it needs the WB-D**: `main`'s ledger stops being the complete record during a review (WB-D20's display property), and resume gains a GitHub-derived step. Because that step is a fresh-session review that mints the gate under the owner's ID, the derivation must be from GitHub state the session cannot shape. The WB-D must say what a fresh machine with no `state.json` does, and must state the derivation rule. | cursor PRs per work PR < 0.5 on devcontainers within one week; relay PRs = 0; plus **minutes the human spends per work PR**, measured from merge timestamps, so reading load is visible |
| 2 | Fix the stale nesting sentence (`workflow.md` L140 only). Split `resume` into a lean auto-start path plus on-demand appendices (target < 20 k tokens of plugin prose per task session). Update the CLI to ≥ 2.1.259 on the host that will run anything headless. | none | prose loaded per task session measured from transcripts |
| 3 | **Fresh-session review stays human-started**, locally, as today (after step 1 it costs one session and zero PRs). Automating it is **blocked on #122 and #93**. If and when they are decided: `workflow_dispatch` from the driver only, no `pull_request*` trigger, no PR checkout, the OAuth secret in a GitHub Environment with required reviewers, tools limited to read + inline-comment, `--max-turns`, `timeout-minutes`, concurrency group. Posted under an identity **not** in any reviewer allowlist. | blocked | n/a |
| 4 | **Headless coder loop** (the driver in `scripts/loop/`, fixture-tested; not `bin/`, WB-D23) running as a **hardened container built from `ghcr.io/603-identity/devcontainer-base` plus a loop layer** (§ 7.3), hosted on Docker Desktop on the maintainer's always-on desktop to start (§ 8.2; the image is unchanged if it later moves to a VM or box). Details in 7.2–7.5. **Two further prerequisites (v6), both now decided:** a separate restrict-updates ruleset on each repo, tested first on a scratch repo, so the loop identity cannot merge (§ 8.5); and devcontainers excluded from the first proving round, then run with native linters and CI as the gate of record for the image build and template proof (§ 8.6). Step 4 does **not** wait for 2026-10-17 (§ 8.1). **Three tests preceded v9 [T]:** the `--restricted` launch form (§ 8.8), the `isolated` gateway probe (§ 8.7) and § 8.5's checks 1–3, all run on 2026-10-04/05, plus the GitHub App test (§ 8.12); the first build step is the full § 7.3 container assembled as one piece, without the sandbox. Waves of **independent** tasks; task PRs to `pr_base`; the human merges the wave **serially** in one sitting (no repo has a merge queue, and strict status checks are off on every repo, so there are no CI re-runs between merges, § 4.4). On the Docker Desktop host the loop dispatches only into one-shot away-blocks the human marks per sitting; the host's `placement` lives in the driver's own config, not in any repo (§ 8.2, D3). | **the same WB-D** (which human authorizations become plan-time policy, including the critic allowlist and the critic-selection judgment slot; the loop identity's trust class; the human-only path key; the independence marker — all decided in § 8.4) | a 3–4 task wave completes with no session above the context cap and spend under the ceiling; zero human touches between dispatch and the merge sitting; **and** human minutes per work PR not above the step-1 baseline |
| 5 | **Usage governor and operations** (7.4, 7.5). | none | no "hit your limit" error during the maintainer's declared hours over two weeks |
| 6 | **Eval set**: 20–50 real past tasks (from merged PRs), code-graded first, re-run per driver release; read the transcripts. | none | pass^k stable release over release |

Steps 1–2 are one milestone (five issues, the stale-sentence fix, and the WB-D's step-1 half).
Steps 4–6 are three milestones, cut by what each proves (confirmed by the maintainer on
2026-10-06; `docs/proposals/orchestrator-m2-decisions.md` has the decisions and data):
- **M2a, loop container proven** (milestone 13). The whole § 7.3 container assembled as one
  piece and attacked; § 9's open live items closed; the driver core built hermetic, with stub
  `docker` and `gh`, beside the container proof; the minimal per-task limits, kill file and
  recovery the first dispatch needs (taken forward from step 5, § 7.4–7.5); `--model fable`
  smoke-tested headless; the baseline script.
- **M2b, first waves on claude-workbench** (milestone 14). Live App preflight, one task per
  away-block, then a small wave; the batch-merge helper; merge-triggered dispatch, opt-in.
  Carries step 4's exit metric.
- **M2c, governor and eval** (milestone 15). The rest of step 5 (day caps, window and
  away-block, reserve, the scoped-lock decision) and step 6's eval set, plus the
  subscription-vs-key and Fable-vs-Opus comparisons.

### 7.2 Step 4 — identities and credentials
- Model auth: `claude setup-token` minted by the maintainer, stored only on the loop host in
  its own `CLAUDE_CONFIG_DIR`. Rotate yearly; record the mint date. The token is still the
  maintainer's subscription: a leak anywhere spends their pool for up to a year, and no
  revocation procedure is documented (§ 4.3). **v6:** the session runs as the same user that
  holds the credential, so it can read it. Mitigations: pass it only to the `claude`
  process, never exported into the session's Bash environment (as the Action scrubs
  subprocess env), and deny `Read` on the credential path in managed settings. **v7** added
  a sandbox `denyRead` beside that; **v9:** the sandbox is off in the loop container
  (§ 8.8), so the managed `Read` deny carries it alone. **[T]** with the sandbox running,
  the token was absent from Bash's environment (`printenv … | wc -c` → 0); without the
  sandbox this is untested (§ 9). The residual is recorded in § 6.2. **#345 (after v9):**
  the session no longer holds the credential at all: it carries a placeholder and
  `ANTHROPIC_BASE_URL`, and a credential-injecting proxy in its own container
  (`scripts/loop/inject.py`) adds the real one. The mitigations above are superseded for the
  loop container; a `setup-token` credential works through the proxy **[T]** (2026-10-07).
- GitHub: a **GitHub App**, not a machine user (*decided 2026-10-05, after the App test*,
  § 8.12; the maintainer: "unless/until there is a reason to switch"). One private App per
  org (glunk-works, 603-Identity), plus a dedicated App for infrastructure-core, so that no
  single private key can mint a token covering a private and a public repo. Each is
  installed on "Only select repositories" with **Contents write and Pull requests write
  only**: no Workflows (a workflow-file push is then refused server-side, **[T]**); no
  Issues (§ 8.12 allowed Issues read on the private repo "only if the session reads its
  spec comment itself"; under § 8.13a the session reads nothing from GitHub, and the driver
  reads issue and spec-comment text with the maintainer's view, § 8.1, passing only the
  extracted fields in the task prompt, § 7.3). The **private key stays on the host**,
  readable by the driver only, never in a container. **No GitHub token enters the
  container** (*decided 2026-10-05, after the edit*, § 8.13): the session commits locally
  only; after it exits the driver mints a JWT (RS256, at most ten minutes) and then **one
  installation token for the dispatched repo and those two permissions**, pushes the
  branch and opens the PR itself (§ 7.3), and the token is used for seconds. The one-hour
  expiry therefore bounds nothing; the turn and budget caps bound the task. `orchestration.
  loop_identity` names the App's bot login (`<slug>[bot]`; `glunk-loop-test[bot]` on the
  test App). Its PRs read `author_association: NONE` to every viewer **[T]**, outside the
  plugin's OWNER/MEMBER/COLLABORATOR allowlists, so § 8.1's untrusted-by-name rule is a
  backstop rather than the only control. `603-gh-loop`, the machine user created for
  § 8.5's test, stays as an unused fallback.
- **Nothing that loads the plugin runs under the App token [T]:** `gh api user` returns
  `403 Resource not accessible by integration`, and `repos/{repo}` `.permissions` reads all
  `false`, so the plugin's identity and reach checks fail closed on it. Under D1 the coder
  loads no plugin; the critics, which do, need no GitHub write and get no App token (a
  read-only token at most). The driver's author-trust reads (§ 8.1) use the maintainer's
  view, never the App token, because `author_association` is viewer-relative (§ 4.4).
- **The token's permissions do not stop a merge** (v6). Contents write is required to push a
  branch and is also sufficient to merge a green PR on a 0-approval ruleset (§ 2.2). The
  control that makes "cannot merge" true is on the repository side (§ 8.5), **tested [T]:**
  the restrict-updates ruleset blocked the machine user's REST merge and the App's REST and
  `--admin` merges (`405`, rule suite `fail`). The permissions and the deny rules are
  defence in depth. v7's option (e) (a fork, read access only) was the fallback if that
  test failed; it did not, and an App cannot fork.
- Allowed git/gh surface for the session: local `git` only (`add`, `commit`, `diff`,
  `log`, `status`; **#345:** as five fixed tools of a managed `loopgit` MCP server, not
  `Bash(git …)` allows); no `push`, no `gh`, no remote (v5–v9 before § 8.13 allowed `git push
  origin task/*` and `gh pr create`). Everything else denied. The allowlist and the deny
  rules both live in managed
  settings, because `allowManagedPermissionRulesOnly` makes Claude Code ignore
  `--allowedTools` (§ 4.2); v8 dropped v7's `--disallowedTools` "second layer" as inert.
- Commits: the App's commits over git are **unsigned [T]** (`verified=false`); no ruleset
  here requires signatures, and one that did would block the loop's pushes. Never the
  maintainer's GPG key (WB-D20: signature is not an authorship signal; a distinguishable
  committer is).
- Egress on the host limited to Anthropic and GitHub.

### 7.3 Step 4 — session configuration
- Own clone per task (never the maintainer's checkout; WB-D12 single live cursor holds).
- Before each launch, restore from `origin/{pr_base}` **the Action's full list plus this
  plugin's own config**: `.claude/ .mcp.json .claude.json .gitmodules .ripgreprc CLAUDE.md
  CLAUDE.local.md .husky/ .ai/project.yml`, which includes `.claude/rules/` (path-scoped
  instructions, § 4.2); remove any of them the base lacks (as the Action
  does). This closes the config-file vector only; the gate's tree-resident scripts
  (§ 2.3) still run from the task branch, which is acceptable for a task PR to `pr_base`
  (the human reviews that diff) and is the residual cost named in § 6.1 for a sprint branch.
- **Driver-side git rule (rewritten in v6).** The driver runs **no git command at all** in a
  clone the session has touched. The session can write that clone's `.git/config`, and
  `core.hooksPath=/dev/null` does not neutralise `core.fsmonitor`, `credential.helper`,
  `core.sshCommand` or `url.<x>.insteadOf`, which run or redirect on status, checkout and
  fetch. The post-exit human-only-path and fixture checks read the diff from GitHub instead
  (`gh api repos/{repo}/compare/{base}...{head}` on the pushed head), or from a fresh clone
  the driver makes after exit. The session's own git calls are out of scope: anything a
  hook or config entry runs inside the session has the session's existing Bash capability
  and nothing more. (v5 was right that v4's `git -c` line could not bind the session.)
  **v7:** the compare API lists at most 300 changed files, on the first page only (§ 4.4).
  The check **fails closed** when the list has 300 entries or the comparison is truncated,
  and tests both `filename` and `previous_filename` on renames, so a move *out of* a
  human-only path is caught. The fresh-clone form has neither limit and is preferred where
  the driver host can clone. **v9, after the edit (§ 8.13): the driver pushes, so the
  checks run before anything reaches GitHub.** After the session exits, the driver copies
  the session's working tree (files only, never its `.git`) into a fresh clone of
  `origin/{pr_base}` it made itself, runs the human-only-path and fixture checks on that
  tree, commits with the message from the session's structured output, mints the App token,
  pushes `task/*` and opens the PR with the digest. The compare-API form becomes the
  post-push forensic check. The session's own `.git` is never read by the driver.
  **How the copy is made safe** (Opus review of § 8.13, 2026-10-05): the tree is
  session-authored bytes moving onto the host that holds the App key, so: copy only after
  every session process is dead, with a non-dereferencing archive (`tar` without `-h`),
  from a clone that lives on a volume, not a tmpfs that vanishes with the container;
  exclude `.git` **at any depth** (a nested `.git` directory or `gitdir:` file would become
  a gitlink); mirror deletions, since a plain copy keeps files the session removed; reject
  any symlink whose target leaves the tree; run the driver's git on Linux (a driver
  container, never the Windows host's git with its `core.autocrlf` and
  `core.symlinks=false`) with `GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1`, an
  explicit bot author and committer and `commit.gpgsign=false`, so the maintainer's
  identity, GPG key and global config never touch a loop commit (§ 7.2's "unsigned [T]"
  was observed for in-container commits only); validate the structured-output commit
  message against the commit grammar and strip closing keywords and trailers; and grep the
  tree and the message for the OAuth token prefix before pushing, because under § 8.13a
  the only exfiltration channel through GitHub is content the driver pushes. A fix session
  under `round_cap` gets its clone seeded from the driver's committed clone (it cannot
  fetch a private repo with no token) and is always a **new** session: the previous one's
  `CLAUDE_CONFIG_DIR` was discarded at exit.
- **Launch, coder session (v9; #345 drops `Bash` from `--tools` and `--strict-mcp-config`,
  which claude refuses beside a managed MCP config; see `scripts/loop/README.md`):** `claude -p --restricted --tools "Bash,Read,Edit,Write,Glob,Grep"
  --add-dir /tmp --model <models.coder> --max-turns N --max-budget-usd X --autocompact 100k
  --permission-mode dontAsk --permission-prompts none --settings '<inline JSON>'
  --strict-mcp-config --output-format json --json-schema <stop-schema> "<task prompt>"`.
  No `Agent` tool and no `--plugin-dir`: the coder spawns nothing and loads no plugin (D1,
  § 8.4a).
  **Launch, each critic (v9; D1 as amended after the tests and § 8.13):** `claude -p
  --restricted --agent <plugin>:<critic> --plugin-dir <pinned copy> --tools "Read,Grep,Glob"
  --model <frontmatter model> --add-dir <staged bundle> --append-system-prompt "<staged
  mode>" --max-turns N --max-budget-usd X --permission-mode dontAsk --permission-prompts
  none --settings '<inline JSON>' --strict-mcp-config --output-format stream-json --verbose
  --json-schema <findings-schema> "<task>"`, one session per critic, started by the driver.
  **Critics get no Bash** (§ 8.13): the driver stages what the agents would have run git or
  gh for, as files in a read-only bundle: the diff against `pr_base`, a bounded `git log`,
  the base-branch copies of every touched file, the gate and fixture output, the CI job
  conclusions, the live ruleset JSON (the preflight already reads it) and the state of every
  issue or PR id the diff and the touched `load_bearing_docs` cite. Critics run **after the
  push**, in the driver's committed clone, never the session's. The gate and fixture output
  in the bundle was produced by the session and is labelled untrusted. The addendum tells
  the agent it is in staged mode and that an id the bundle does not carry means "could not
  look", never "dangling" (docs-consistency's own most trust-destroying false finding).
  `--tools` must still be explicit: `--restricted` gives an agent the intersection with
  `--tools`, and results decision 2 showed the frontmatter's Bash is restored only when
  named **[T]**; `Read, Grep, Glob` is what B3a ran, which tested loading only, not a
  bundle or an addendum (§ 9). The driver checks loading from the
  stream-json `system/init` event (`plugins` lists the pinned copy, `agents` the critic,
  `tools` and `model` the frontmatter values); the json result carries no `plugins` key in
  2.1.289 **[T]**. (v6's line had `--allowedTools` and `--setting-sources user`; v7's
  `--disallowedTools` and an undocumented `--setting-sources` form; v8's put `Agent` in
  `--tools` and a file path in `--settings`. § 6.5–6.8 explain each.)
  **`--restricted`: load no file the session can write** (decided after v8, § 8.8; **tested
  [T]**). It "loads only managed settings and `--settings`" (§ 4.2): with a user and a
  project `settings.json` planted, only the `--settings` value reached the session, and a
  control without the flag loaded all three. It refuses `bypassPermissions` and cloud
  sessions, and confines the file tools to the working directories, which under it are
  **the work clone alone**: `/tmp` needs `--add-dir /tmp` (v8 said "the work clone and
  `/tmp`"). It removes the command-running tools "unless you name them individually in
  `--tools`", hence the explicit lists above. Two things the test found that v8's account
  of what loads did not cover: four builtin plugins load under it, and the config dir
  collects `remote-settings.json` and `policy-limits.json` from the server. And under
  `dontAsk` a managed `Bash(echo *)` allow did **not** cover `echo "$FOO"`, nor
  `Bash(cat *)` a path outside the working directories, so the allowlist for each repo's
  gate commands has to be tested in this exact form, not assumed. v7's contingency (an
  empty `--setting-sources` list) is no longer needed and is dropped, as the `project`-only
  form already was. `.mcp.json` is ignored (`--strict-mcp-config`). Whether any form
  suppresses project `CLAUDE.md` is **unverified**; the restore step covers it either way.
  **`--settings` is passed as inline JSON**, or as a root-owned file on the read-only root
  filesystem, never a path the session can write: under `--restricted` it is the only
  non-managed source left, its `env` is re-applied live and `apiKeyHelper` is read only
  from it, with helpers running outside any sandbox (§ 4.2; v9, § 6.8 item 1). **Watch the
  `--bare` default change** (§ 4.1): when it lands, this line needs whatever opt-out ships
  with it, or the session will have no OAuth credential.
- **Every settings source the session loads is driver-owned and unwritable by the session**
  (principle 6). The reason is two documented facts together: a `PermissionRequest` hook in
  any loaded source can *allow* what `--permission-prompts none` would otherwise deny
  (§ 4.2), and the settings watcher applies edits to `hooks` and `permissions` live, in user
  and managed settings alike (§ 4.2).
  **v6 mechanism.** v5 made the user `settings.json` read-only and added a managed Bash deny
  on writes under the config dir. That does not hold: the config dir must be writable
  (session history, `.claude.json`), so a root-owned file in it can be unlinked and
  recreated; Bash deny rules are not a boundary; and `permissions.allow` widens without any
  hook (§ 4.2). The control is instead to make every non-managed source **irrelevant**:
  - `allowManagedHooksOnly: true` in managed settings: no user, project, local or plugin
    hook runs, and no user-installed or session-written mod loads.
  - `allowManagedPermissionRulesOnly: true` in managed settings: Claude Code ignores allow,
    ask and deny rules from user, project, local and `--settings` files, and ignores
    `--allowedTools` (v7, § 4.2). So the session's allowlist lives in managed settings, and
    the `--settings` file carries only non-permission keys. (v8: under `--restricted` the
    user, project and local files are not loaded at all, so this key's job shrinks to
    ignoring allow rules in the `--settings` file; it stays as the documented backstop for
    the contingency form.)
  - `strictPluginOnlyCustomization` and `allowManagedMcpServersOnly` in managed settings
    (v7): no skills, agents, hooks or MCP servers from user or project sources;
    `allowManagedPermissionRulesOnly` does not cover MCP (§ 4.2).
  - **No user, project or local settings source, and a fresh `CLAUDE_CONFIG_DIR` per task**
    (v7, sharpened in v8 by `--restricted`, tested in v9 **[T]**; launch line above). A loaded user `settings.json` can set credential helpers that Claude Code runs
    outside the sandbox, and `env` that it re-reads live, and no `allowManaged*` key covers
    those (§ 4.2). A config dir that persists between tasks also carries a user `CLAUDE.md`,
    agents and skills from one task's session into the next. The driver creates the dir on
    a per-task tmpfs, copies in the credential, and discards the dir after the post-exit
    checks.
  - Every deny rule lives in managed settings, so neither a hook's `updatedPermissions` nor a
    rewritten user file can remove it (§ 4.2). Deny rules still **enumerate** the dangerous
    surface (merge, status, workflow-file, human-only paths, `Read` on the credential path)
    rather than lean on `dontAsk`'s default.
  - **Claude Code's sandbox is off in the loop container** (`sandbox.enabled: false` in
    managed settings; *decided 2026-10-04, after the tests*, § 8.8). v7 planned it as a
    second layer with `enableWeakerNestedSandbox`; the test found bubblewrap cannot start
    under Docker's default seccomp profile at all, a step before the `/proc` mount that key
    addresses, and it fails closed (§ 4.2). Relaxing seccomp (a custom profile, or
    `unconfined`, the only form tested) would weaken the container, which is the boundary,
    to rescue the inner layer. Lost with it, and carried by other controls: the per-command
    network allowlist (the proxy covers the whole container); the credential `denyRead`
    (the managed `Read` deny remains; whether Bash can read the token without the sandbox
    is open, § 9); and the in-container write allowlist (the read-only rootfs and the tmpfs
    mounts bound writes instead). v8's second reason for keeping it, that the sandbox
    protects the `--plugin-dir` copy, was wrong anyway: that path is the permission
    system's (§ 4.2), and under D1 the coder has no plugin dir.
  - The restore step still neutralises `.claude/` before launch.
  Under these keys, with the `--restricted` form confirmed by test **[T]**, nothing the
  session writes into its config dir or work clone is consulted for hooks, permissions,
  helpers, `env`, skills, agents or MCP servers. What a write into the config dir
  (`.claude.json`, `remote-settings.json`, `policy-limits.json`) could change for the
  running session is the one untested piece (§ 9), bounded to one task by the fresh dir. v6
  said the session "may then write whatever it likes into its own config dir"; that held
  only for hooks and permissions while the user source was still loaded.
- **Post-exit, not pre-launch:** hash every settings file, hook script and the plugin copy and
  compare with the pre-launch hashes the driver recorded; any difference fails the task and
  stops the wave. (v4 ran the compare before launch, right after restoring from the same ref,
  where it could not fail.) **v8:** this is **forensics, not a control**. Once nothing
  writable is consulted, a changed hash tells you the session tried, which is worth a stopped
  wave and a look at the transcript, but it is not what keeps the session narrow.
- Host-level, as a container (§ 8.2):
  - **The image** (named 2026-10-07, #315). `603-Identity/devcontainers` publishes three
    images, `devcontainer-base`, `-tofu` (base + OpenTofu + tflint) and `-node` (base +
    Node.js + npm), and none ships the `claude` CLI, so "the devcontainers image" alone
    named nothing buildable. The loop image is built `FROM
    ghcr.io/603-identity/devcontainer-base`, pinned by tag **and** digest and verified against
    that repo's `build.yml` provenance (`gh attestation verify`, as its consumers' `verify`
    check does). Base already runs as a non-root uid 1000 with no sudo, strips every setuid
    bit and is built for a read-only root. The **loop layer**, a Dockerfile in `scripts/loop/`
    (WB-D23), adds `claude` in `/usr/local/bin`, pinned by version and checksum, with
    auto-update off: the native installer's per-user location would put the binary on
    writable state, where the session could replace it, and an updater needs the update hosts on the proxy list (§ 4.2). It also
    bakes in the managed settings below. **One loop image per toolchain, not one image:**
    claude-workbench's gate needs only what base carries plus `claude`; bounty-infra, when it
    joins, gets a second loop image `FROM devcontainer-tofu` plus `claude` and `hatch`. No
    new variant is published from devcontainers for now: one consumer does not justify it,
    and devcontainers is outside the first proving round (§ 8.6). Revisit when it joins.
  - Root-owned `/etc/claude-code/managed-settings.json` carrying the keys above,
    `sandbox.enabled: false`, the deny rules and the PreToolUse guards is **baked into the
    image**; the `--settings` value is inline JSON or a second root-owned file beside it.
  - The container runs as a non-root `USER` with a **read-only root filesystem**, so
    `/etc` and the managed settings cannot change.
  - Writable state lives only on a tmpfs or volume holding the work clone, `/tmp` and
    `CLAUDE_CONFIG_DIR`. v5 said the read-only rootfs meant "the session cannot write any
    settings file at all"; that was wrong, because the config dir is writable. The managed
    keys above are what make that safe.
  - **No Docker socket** mounted or reachable, and no bind mount under `/mnt` or a Windows
    drive.
  - **Egress** through a user-defined `--internal` Docker network whose only other member is
    a proxy container, which is also attached to an external network. The proxy allows only
    the hosts Claude Code needs (v7, from network-config.md: `api.anthropic.com`,
    `claude.ai`, `claude.com`, `platform.claude.com`; not the update hosts, since auto-update
    is off in the image, above and § 4.2). **github.com and api.github.com are off the coder's
    list** (§ 8.13a): the session has no remote and no token, so for it those hosts would
    be an exfiltration route only, and a repo whose gate fetches from GitHub names them in
    its own `orchestration.*` list.
    **v7: the proxy cannot deny the host gateway for the session**, because an `--internal`
    network still lets the session container reach the gateway IP directly (§ 4.5). **v8,
    decided (§ 8.7): the network is created with
    `-o com.docker.network.bridge.gateway_mode_ipv4=isolated` (and the `_ipv6` twin if IPv6
    is enabled), under which Docker assigns no address to the bridge, so there is no gateway
    for the session to reach and no firewall rule to keep alive** (§ 4.5). v7's host-side
    rule inside the `docker-desktop` VM is withdrawn: Docker says not to modify its rules,
    and its persistence across Docker Desktop restarts was unverified. The proxy container is
    reached by its own container IP or name on the same network (`--internal` containers
    "may communicate between each other", network create.md L197 **[O3]**; the stand-in
    answered by both **[T]**); the driver reaches the session by `docker exec` and logs,
    never by IP. **Tested on this backend (§ 8.7) [T]:** the `isolated` network had no
    gateway and reached nothing outside itself, and the proxy stayed reachable. On this host
    a plain `--internal` gateway would reach the VM's listeners, not Windows' **[T]**. The
    proxy's own allowlist refuses IP literals and `host.docker.internal`, because the
    proxy's external network still reaches its own gateway (v9). The gate's own fetches
    widen the list per repo (bounty-infra's `hatch` and `tofu init` need PyPI and the OpenTofu registry, § 8.6).
    That list is repo-specific, so it belongs in `orchestration.*`, not in the plugin
    (WB-D2), and every host on it is another exfiltration channel. v5's `--network none` plus
    a sidecar could
    not work: `none` leaves only loopback, and sharing the sidecar's namespace gives the
    session the proxy's own unrestricted egress.
  - **The driver's preflight checks all of these from outside the container** (`docker
    inspect`: `User` non-root, `ReadonlyRootfs`, no `/mnt` or drive-letter `Mounts`, no
    `docker.sock` mount, `NetworkMode` is the internal network, proxy up; `docker network
    inspect` shows `Internal: true`, the `gateway_mode_ipv4=isolated` option **and no
    `Gateway` in IPAM** (v9: an isolated network has no gateway, and Docker gives the
    subnet's `.1` to a container, once the proxy **[T]**, so the probe must never derive
    one); plus in-container probes **by IP** that a non-allowlisted public host, the VM's
    addresses and `host.docker.internal`'s address (read from a non-internal network; the
    name does not resolve on internal networks **[T]**) are all unreachable) and refuses to
    dispatch when any fails.
  - **GitHub preflight (v9; § 8.5 decision 3, § 8.12, § 8.13).** In two parts, because
    under § 8.13a no App token exists until the push. **At dispatch, with the maintainer's
    read-only view:** the `update` rule is present on `pr_base`; the App appears in no
    applicable ruleset's `bypass_actors`; the task issue's and spec comment's
    `author_association` are trusted (§ 8.1), never read as the loop. **Immediately before
    the push, with the token just minted:** `GET /installation/repositories` is exactly the
    dispatched repo; every ruleset that `GET /repos/{repo}/rules/branches/{pr_base}` names
    reads `current_user_can_bypass: never`; and the App's bot login (from the installation)
    equals `orchestration.loop_identity`, compared case-insensitively, so a stale value
    cannot leave the name rule (§ 8.13d) pointing at nobody. Per PR, once its checks are
    green, `mergeStateStatus` read as the loop identity must be `BLOCKED`; anything else
    stops the wave.
  - Residuals on the Docker Desktop host are listed in § 6.2's container row.
  - **devcontainers is excluded from the first proving round** (§ 8.6, decided: d then e),
    because five of its eight gate steps need the Docker daemon as written (two by nature,
    § 2.3). It joins under option (e) once the loop has proved itself elsewhere.
  - **Private repos may run on this host under two conditions** (§ 8.2, D3, as met by
    § 8.12): (1) one credential per repo, never one covering a private and a public repo,
    met by the per-task, one-repo App token and the dedicated infrastructure-core App, and
    enforced by the preflight's `GET /installation/repositories` check; (2) the private
    repo's clone holds **no live secrets**, checked before infrastructure-core's first
    dispatch (its history has not been checked, § 9). The move to a VM or box is still
    required before any standing window, for every repo.
- Wave composition comes from the plan, not from the driver's guess: a task is dispatched in
  the same wave as another only when the human-confirmed plan marks neither as depending on
  the other (step 4's prerequisite). Absent the marker, one task per sitting.
- Task prompt: the anchored issue number, the spec comment id, acceptance criteria, target
  files, the gate command list from `origin/{pr_base}`'s `.ai/project.yml`. Never raw issue
  text beyond that.

### 7.4 Step 4/5 — the usage governor
Implementable from docs: per-task `--max-turns`, `--max-budget-usd` (proxy), `--autocompact`;
`--model` for the **coder session** taken from the repo's `models.coder`; the two judgment
slots on `models.architect`; **critics** each as their own driver-started session on their
frontmatter `model:` and `tools:` (§ 8.4a, D1), under their own `--max-turns` and
`--max-budget-usd`, with the `round_cap` fix loop handing findings to a **new** coder
session seeded from the driver's clone (§ 7.3); every model's usage counted against that model's per-day cap below; `timeout` around
every session; parse `permission_denials`, `total_cost_usd`, `is_error` from the result JSON
and, for critics, the stream-json `system/init` event; stop on any "hit your limit" result. Sizing note from § 3.2: today's flow already runs ≈ 34 Opus critic
subagents a day at ≈ 0.2 M cache-read each and ≈ 5 M per median Sonnet coder session, so each
per-model cap should start near today's observed load for that model, not below it.

Driver-side rules (sized from § 3.2):
- per-day session cap and per-day Opus/Fable session cap;
- dispatch only inside a declared window (e.g. 00:00–07:00 local) plus marked away-blocks,
  **and only while the Docker daemon answers and the § 7.3 preflight passes**. **v8,
  decided (§ 8.2 after v8; re-homed by D3 after v9):** the standing window is legal only
  when the host's `placement`, a value in **the driver's own config on the loop host**
  (beside the kill file and lock, § 7.5; one value per host, never in a repo's
  `.ai/project.yml`, § 8.4d), is a VM or separate box. While it reads `docker-desktop`,
  the governor dispatches **only into away-blocks the human marks per sitting**: an
  away-block is a one-shot record with an end time and a maximum length, consumed by the
  driver when the block ends and written to the audit log. The governor cannot prove a
  block was written by the human; one-shot consumption makes automating it a deliberate
  act, and the audit log makes a nightly pattern visible (D3). "Unattended as a matter of
  routine" is thereby
  a predicate, not a judgment: on this host every unattended run is one the human opted into
  that day. The host is an
  always-on desktop (§ 4.5), but Docker Desktop runs under the maintainer's login, so after
  a reboot the daemon is down until login. The governor checks Docker, not just the clock,
  and records every window it could not use;
- **option, not decided (v6): merge-triggered dispatch during a sitting.** When the human
  merges task N of a dependent chain, the driver dispatches N+1 at once rather than waiting
  for the night window, so a chain advances while the human is present without them
  dispatching each item. It keeps principle 1 intact and touches no § 2.2 trust rule: N+1
  comes from the human-confirmed plan, builds on the `main` the human just merged, and
  never reads `next_action`. This is the option § 8.3's "ceiling" leaves out. **v7, its
  costs:**
  - The pace is one task session per link (a capped coder session plus critics), not the
    nine-minute review cadence, so expect a few links per sitting, not a whole chain.
  - Loop sessions draw on the same 5-hour usage window the human is working in. The 50 %
    reserve below is weekly and does not protect the 5-hour window.
  - § 7.5's lock file makes resume refuse auto-start while the loop runs, so it blocks the
    human's own resume in that repo during the sitting. Either the lock is scoped to the
    loop's clone and task, or this option is limited to repos the human is not working in.
  *Deferred by the maintainer (2026-10-04, after v7):* decide after the § 8.3 measurement of
  the dependent share; if adopted, scope the lock and limit it to repos the human is not
  working in;
- reserve ≥ 50 % of the measured weekly envelope for the maintainer's interactive work;
- transcript-metered token ceiling per task and per day (sum `cache_read` + `output`);
- liveness: transcript mtime; a session silent > N minutes is killed and recorded;
- backoff and stop after the first limit error; never auto-continue.

Not implementable from docs: a reliable pre-dispatch read of remaining plan usage.

### 7.5 Step 5 — state, recovery, audit
- Driver state: append-only JSONL **outside any worktree**, owned by the driver user. GitHub
  is the source of truth, reconciled at each step (`git ls-remote` for the branch, `gh pr list
  --head` for the PR, digest marker in the PR body).
- Recovery: exited-but-not-copied → copy and check (the clone is on a volume, § 7.3);
  committed-but-not-pushed → mint and push; pushed-but-no-PR → create the PR without
  re-running; PR-but-no-digest → write it from the log.
- Kill file outside any worktree, checked before each dispatch and polled during a run (kill
  the process group). Lock file in the driver directory; `resume` refuses auto-start while
  present (needs a small plugin change). The driver directory also holds the host's
  `placement` value and the current away-block (§ 7.4), and the App private keys, readable
  by the driver user only (§ 7.2).
- Per-task audit line: issue number + `updated_at` at dispatch, anchor SHA, `origin/{pr_base}`
  SHA, head SHA, PR number, session id, models used, turns, usage, cost estimate, stop reason,
  `permission_denials`, pre- and post-exit hook/settings/plugin hashes, human-only-path check
  result, fixture check result. Mirrored into the PR body by the driver's identity with the
  log line's hash.

### 7.6 Stays human
Sprint scope and spec approval (plan-sprint), every `hitl_gate`, every merge to `pr_base`,
the release tag, the decision backlog, resolving #93/#122, registering the Apps and rotating
their private keys, marking away-blocks, deciding `orchestration.*` policy per repo.

---

## 8. Decisions only the maintainer can make

Items 1–4 were decided by the maintainer on 2026-10-04, one at a time, after the v4 review
and before the v5 review. Each entry keeps the options that were weighed so the next reviewer
can judge the choice, then states the decision. The v6 review added *review notes* under
items 1–4 without changing any decision, and raised items 5 and 6, which are **open**. The
v7 review changed no decision. It corrected v6's floor recommendation under 4a, rewrote
item 5's options and added one to item 6. **After the v7 review the maintainer decided
items 5 and 6 and the four pending notes** (the 4a floor, the 8.1 date, the 8.2 move
trigger, and the 7.4 option under 8.3), each marked *Decided (2026-10-04, after the v7
review)*. **After the v8 review the maintainer decided six more items**, marked *Decided
(2026-10-04, after the v8 review)*: notes under 8.2, 8.5 and 8.6, and new items 8.7–8.10;
the v8 reviewer recommended and recorded all six. **After the v9 review, five more**, marked
*Decided (2026-10-04, after the v9 review)*: notes under 8.4a, 8.5, 8.2 and 8.9, and 8.11,
recommended by the v9 reviewer and recorded by a separate editor. **After the tests, four
more**, marked *after the tests* or *after the App test* with their own dates: under 8.8,
8.4a and 8.5, and 8.12, recommended by the testing session. **After the edit, four more**
(§ 8.13, *Decided (2026-10-05, after the edit)*), recommended by the editor in conversation,
each taken by the maintainer. § 9 lists what is still unbuilt; no decision is open.

1. **#93 and #122 on devcontainers.** The ledger promises them by 2026-10-17; the GitHub
   milestone says 2026-12-15. Step 3 and the loop identity's trust class both wait on them.
   Nothing in this plan can decide them; the decision here is only **which date governs**,
   because steps 1–2 can ship on either and steps 4–6 cannot start before them.
   *Decided (2026-10-04):* **the ledger date, 2026-10-17, governs**, and **the loop identity
   is untrusted by name regardless of #122's outcome**: `orchestration.loop_identity` names
   the loop identity (the App's bot login since § 8.12; v8 said the machine user), and
   `review-sandbox.sh trust` and `plan-anchor.sh` return untrusted for
   that login whatever its `author_association` says, so nothing the loop writes is ever
   executed locally at review or anchored as a plan without a human in between. This is the
   loop's answer to #122 for its own identity only; #122's general answer is still the
   devcontainers owner's. #93 is mitigated for the loop by PAT scope alone: a fine-grained PAT
   without the Workflows permission cannot push a change under `.github/workflows/`.
   *v6 review note (not a change to the decision):*
   - "By PAT scope alone" overstates it. A PAT without Workflows still pushes edits to
     `.github/scripts/*` and anything else a workflow runs from the PR's tree, and
     `pull_request` runs use the PR's copy with the repository's secrets. The loop's
     mitigation for #93 is the PAT scope **plus** `human_only_paths` covering `.github/`
     (principle 8: in-session deny plus the post-exit diff check).
   - This decision makes the loop independent of #122, so the opening sentence's "steps 4–6
     cannot start before them" now holds for step 3 and for #93's general fix, not for the
     loop's own trust class. The maintainer may want to say whether step 4 still waits on
     2026-10-17.
   *Decided (2026-10-04, after the v7 review):* **step 4 is decoupled from the date.** It waits on milestone 1, the § 8.5
   scratch-repo test and the § 8.6 answer, not on 2026-10-17. Step 3 still waits on #93 and
   #122. The reason: § 8.1's own decision already makes the loop independent of #122, and the
   loop's #93 mitigation (no workflow permission, `.github/` in `human_only_paths`) does not
   depend on #93's general fix.
   *v9 note [T] (not a change to the decision):* `author_association` is **viewer-relative**:
   the maintainer's own issue reads `CONTRIBUTOR` to the loop's credential, App or machine
   user, so the driver's author-trust reads use the maintainer's view, never the loop token
   (§ 4.4, § 7.3). The App's PRs read `NONE` to every viewer, outside every allowlist, so
   the name rule above is a backstop. It was a **decision not yet implemented**:
   `plan-anchor.sh` checks no author today. *Decided (2026-10-05, after the edit, § 8.13):*
   implemented in milestone 1. And "PAT scope" now reads "App permissions": a workflow-file
   push by an App without the Workflows permission is refused server-side.
2. **Where the loop runs.** The runtime unit is a **container built from the devcontainers
   image** in every option; the decision is what hosts the Docker daemon. Options weighed:
   Docker Desktop on the existing laptop (WSL2 backend), hardened per § 7.3; the same
   container on a VM or small Linux box; a bare WSL2 distro (now dominated, § 6.2); the
   Windows host as-is (ranked last by every reviewer; not offered). Steps 1–2 pay on any host.
   *Decided (2026-10-04):* **a hardened container on Docker Desktop on the laptop, to build and
   prove step 4.** Non-negotiable: the driver's preflight (§ 7.3) runs before every dispatch
   and refuses when the container is not non-root, read-only, bind-mount-free under `/mnt` and
   drive letters, and behind the egress sidecar. Accepted residuals, recorded in § 6.2: the
   Docker socket is a root door for anything running as the maintainer on Windows; the token
   volume is readable from Windows; shared kernel with the maintainer's other containers; the
   dispatch window exists only while the laptop is awake and logged in. The image moves to a
   VM or always-on box unchanged when the `depends_on` measurement (§ 8.3) shows the loop
   earns one. No security reviewer has looked at this placement; § 9 records that.
   *Named (2026-10-07, maintainer, #315):* "the devcontainers image" is
   `devcontainer-base` plus a loop layer, one loop image per toolchain (§ 7.3).
   *v6 review note (not a change to the decision):*
   - The host is an **always-on desktop**, not a laptop (maintainer, 2026-10-04). The "awake
     and logged in" residual reduces to "logged in after a reboot". The machine is already
     always on, so the condition for moving the image should be the **security** residuals
     (socket, shared kernel, admin credentials on the same machine), not the `depends_on`
     measurement.
   - As written, the decision cannot serve devcontainers. Five of eight gate steps need
     Docker (§ 2.3), and giving the container the socket removes every property the
     decision's non-negotiables rely on (§ 4.5). That is now open decision § 8.6.
   - The non-negotiable "behind the egress sidecar" is replaced by "on an internal network
     behind a proxy" (§ 7.3), because the sidecar design could not work.
   *Decided (2026-10-04, after the v7 review):* **the move trigger is security, not the `depends_on`
   measurement.** Docker Desktop on this desktop stays the proving host: claude-workbench
   first, then bounty-infra once § 8.5 lands (v7 wrote "for public repos only"; struck by
   D3 below). The loop moves to a separate box or a VM **before** any standing window, for
   every repo (v7 wrote "before it runs against infrastructure-core (private) or runs
   unattended nights as a matter of routine"; the first half is struck by D3, the second
   re-keyed by the decision after v8). The maintainer's words, recorded for the next
   reviewer: **"I am not terribly worried about the integrity of this host."** So the
   residual the trigger protects is not the desktop itself; it is the private repo and the
   maintainer's admin credentials for two orgs, which sit on the same machine. Two facts for
   whoever plans the move: this machine runs **Windows 11 Home, which has no Hyper-V**, so a
   VM on the same desktop means VirtualBox or VMware Workstation. (v7 added that the host-side
   gateway block "is easier to keep on a host the loop owns"; v8 struck it, since § 8.7
   replaces that block with a Docker network option that needs no host-side rule anywhere.)
   *Decided (2026-10-04, after the v8 review):* **"routine" is a key, not a word.** As v7
   wrote it, "runs unattended nights as a matter of routine" names what § 7.4's designed
   00:00–07:00 window does on its first night, and the governor cannot test "routine".
   Options weighed: (A) no standing window on the Docker Desktop host, dispatch only into
   away-blocks the human marks per sitting, each with an end time, with the standing window
   refused until an `orchestration.placement` key says the loop runs on a VM or box; (B) a
   count, such as "the standing window may run for two sprints, then the move is due"; (C)
   leave the wording. (B) is arbitrary and passes silently, and two sprints of unattended
   nights beside the org admin credentials is what the trigger exists to prevent; (C) leaves
   the first reviewer after the first night asking the same question. **(A) is decided.**
   Cost: one action per night during proving, the same order of effort as merging the wave
   the next morning. The maintainer's own words still govern what the trigger protects: not
   the host, but the credentials and the private repo on it, and an opt-in block is the
   smallest unit of exposure that can be granted them. § 7.1 step 4 and § 7.4 say so.
   *Decided (2026-10-04, after the v9 review):* **"public repos only on this host" is
   dropped.** Private repos (infrastructure-core) may run on the Docker Desktop host under
   two conditions: (1) **one credential per repo**, never one token covering both a private
   and a public repo (written as "one machine-user PAT per repo"; the tests then found an
   outside-collaborator machine user cannot mint one, and § 8.12 meets the condition with a
   per-task, one-repo App token instead); (2) the private repo's clone holds **no live
   secrets**, checked before infrastructure-core's first dispatch. `placement` moves out of
   the repos' `.ai/project.yml` into the **driver's own config on the loop host** (beside
   the kill file and lock, § 7.5), one value per host, because it is a host fact: four
   repos could hold four different claims about one machine, and the governor would trust
   whichever repo it was dispatching. An **away-block** is a one-shot record with an end
   time and a maximum length, consumed by the driver when the block ends and written to the
   audit log. Its honest limit: the governor cannot prove a block was written by the human,
   and a nightly scheduled block would be a standing window it cannot tell apart; one-shot
   consumption makes automating it a deliberate act, and the log makes a nightly pattern
   visible. The move to a VM or box is still required before any **standing window**, for
   every repo.
   The maintainer's question, recorded verbatim because it changed the decision: **"what is
   the major risk with the private repo on docker desktop? I am already working within
   docker with the private repos on this desktop."** The reviewer's answer, accepted:
   - the admin credentials are reachable from the loop container only by escaping it
     (shared kernel → Docker VM → Windows files), identically for a public or a private
     repo, so public-only did not reduce that risk;
   - the private repo's integrity is protected by the same controls as any repo: the loop
     cannot merge (§ 8.5), the human reviews every PR;
   - what is private-specific is **confidentiality** of its source via a prompt-injected
     session, and its channels are narrow: egress is Anthropic (which already receives the
     code from interactive sessions), GitHub and the gate's registries, and on GitHub the
     session can write only where its token can, so a token scoped to the private repo
     alone has nowhere public to push; injection is also less likely there, since only org
     members can file issues on a private repo;
   - what really differs from the maintainer's current work is that the loop runs
     **unattended**, holds the one-year OAuth token and reads issue text with no one
     watching; that applies to every repo and is what the standing-window trigger is about;
   - infrastructure-core's `block-secret-bearing-files` push ruleset (`*.tfvars`,
     `*.tfstate`, `*.pem`, `*.key`, …) suggests secrets are already kept out; its history
     was not checked (§ 9).
   Options weighed: (A) keep public-only and enforce it in the preflight (visibility read
   live), which enforces a rule that protects little; (B) a visibility check only, placement
   per repo, the block mechanism left to driver design; (C) as v8 wrote it, public-only
   unenforced, prose only. § 7.3, § 7.4 and § 8.4d say so.
3. **Wave granularity.** Keeping the human merge as the only approval means a dependent chain
   advances one task per sitting. Today, with the human present, a chain advances every nine
   minutes (§ 3.1); under the loop, which runs while they are away, it advances once a day.
   For *independent* tasks the wave model is strictly better than today. So the decision is:
   **accept one dependent task per sitting**, and let plan-sprint's `depends_on` marker
   (step 4's prerequisite) maximise the independent share of each sprint; or **re-open v1's
   sprint branch** for N dependent tasks per sitting, at the cost § 6.1's amended note
   describes (review granularity, in-batch persistence through the gate's tree-resident
   scripts, a driver that merges somewhere). If the sprint branch is re-opened, the minimum
   protections are § 7.3's config restore from `origin/main` per session, a batch of two,
   per-task digests in the sprint PR, a fresh-session review of the sprint PR as a whole, and
   the gate scripts for task N run from `origin/main`'s copy rather than the sprint branch.
   *Decided (2026-10-04):* **accept the ceiling; add a human-confirmed `depends_on` marker to
   plan-sprint.** Principle 1 stands as written. The driver dispatches waves of tasks the plan
   marks independent and one task per sitting otherwise. Over the first two or three sprints
   the driver records what share of dispatched tasks were independent; the sprint branch is
   re-opened only if that share turns out low, and then with every protection listed above.
   *v6 review note (not a change to the decision):* the decision is consistent with
   principle 1.
   - The ceiling it accepts comes from § 7.4's away-only dispatch window, not from
     principle 1. Merge-triggered dispatch during a sitting (§ 7.4 option) would advance
     chains (v7: at one task session per link, not review cadence, § 7.4) with principle 1
     untouched, and should be weighed **before**
     the sprint branch is re-opened.
   - On devcontainers, re-opening the sprint branch would also carry task N−1's edits to
     Docker-driving gate scripts into task N's gate run (§ 6.1 v6 note).
   *Decided (2026-10-04, after the v7 review):* **merge-triggered dispatch (§ 7.4) is deferred** until the
   measurement above reports the dependent share. If that share is high, merge-triggered
   dispatch, with a scoped lock and only in repos the human is not working in, is tried
   **before** the sprint branch is re-opened.
4. **Which human authorizations become plan-time policy** and what step 1's no-op handoff rule
   records on `main` and derives from GitHub — the content of the one WB-D.
   *Decided (2026-10-04), in four parts:*
   - **4a. Policy set, model routing and judgment slots.** `orchestration.*` in each consuming
     repo's `.ai/project.yml` carries: `critics` (an **allowlist** of critic agents the loop
     *may* spawn, not a fixed must-spawn list), `round_cap` (critic re-run rounds before a task
     stops as non-converged; 2), `human_only_paths`, `loop_identity`, and plan-sprint's
     `depends_on` marker per issue. **There is no loop-specific model key and no loop
     default.** Model routing is the plugin's existing doctrine, unchanged: the coder session
     runs on `models.coder`, the two judgment slots run on `models.architect`, and each critic
     runs on its own frontmatter `model:` (the thing that already sets what a critic runs as;
     this plugin's three pin `opus`, a consuming repo's custom critic may pin anything). The
     maintainer's instruction, recorded for the next reviewer: **"the most appropriate model
     for the task and purpose"**, not Opus by default and not Sonnet by default; the `models`
     map and the agent frontmatter are where "appropriate" is decided, per repo, by a human,
     and the governor's per-model caps (§ 7.4) bound whatever that routing costs.
     **Critic selection is a named LLM judgment slot:** the loop runs critic-gate's existing
     proposal logic (which critics the diff warrants, from the skill's table) unattended and
     spawns the result, filtered by the allowlist. Principles 3 and 10 are amended to say so.
     The second-opinion round on another model stays human-only and is unavailable to the loop.
     The maintainer's reason, also recorded: "LLM judgement is part of what I am looking for
     here to produce quality code at times where I am not here to babysit."
     *v6 review note — recommendation awaiting the maintainer, not a change to the decision:*
     - critic-gate's table is keyed on paths for its first two rows (`code_paths`,
       `load_bearing_docs`) and on a mechanical `--diff-filter=A` for the third
       (`skills/critic-gate/SKILL.md` L69–73). The driver can compute those rows without a
       model.
     - The judgment slot's input is a diff written by a session that read issue text. As
       recorded, it can be steered to select **no** critics, and nothing catches that.
     - Recommended: the path-keyed rows form a deterministic **floor**, and the LLM slot may
       only **add** critics within the allowlist (the table's "and/or" choices, repo-local
       critics, the security-critic call on a new doc). That keeps LLM judgment where the
       maintainer wants it and keeps principle 3's driver deterministic where an injection
       could otherwise reduce review.
     - **v7 correction to the recommendation:** the floor must not be stricter than the
       table it is computed from. Row 1 reads "security-critic and/or architect" (L71), and
       the skill says the human can "pick one rather than both when a light look is enough"
       (L95) and can skip the new-doc row "for a trivial addition" (L82). So the floor is:
       `code_paths` touched → **at least one of** architect or security-critic;
       `load_bearing_docs` touched → docs-consistency. Which code critic, whether both, and
       the new-doc row stay with slot (a). A floor of both code critics on every task would
       re-decide the skill's "and/or" and double the Opus cost of every code task. The
       floor remains a **recommendation**; v6 had also written it into principle 10 as a
       rule, which v7 removed.
     *Decided (2026-10-04, after the v7 review):* **v7's floor is adopted.** The driver computes it without a
     model: `code_paths` touched → at least one of architect or security-critic;
     `load_bearing_docs` touched → docs-consistency. Slot (a) chooses which code critic,
     whether both, the new-doc row and repo-local critics, and may only add to the floor.
     A floor critic missing from `orchestration.critics` is a configuration error that
     stops the dispatch. Principles 3 and 10 say so; the WB-D's loop half records it.
     - Running critic-gate's proposal unattended also changes that skill's contract ("spawn
       NOTHING yet… the human confirms or trims the list", L47–51), so the WB-D's loop half
       must amend the skill as well as principles 3 and 10.
     - Cost: every task now carries at least one Opus judgment session plus up to three Opus
       critics × `round_cap` 2. § 5 principle 10 now says what happens when the Opus cap
       trips mid-task: stop, no PR.
     *Decided (2026-10-04, after the v9 review):* **the driver spawns the critics.** Each
     critic, floor or slot-(a) addition, runs as **its own capped session started by the
     driver** (`claude -p --restricted --agent <critic> --plugin-dir <pinned copy> --model
     <frontmatter model> --max-turns N --max-budget-usd X --json-schema <findings-schema>
     …`) against the pushed diff; the coder session gets **no `Agent` tool and no
     `--plugin-dir`**. Why: the plan never said which process spawns critics (v8 said only
     "the loop … spawns the result"), and v8's launch line put `Agent` in `--tools`, so the
     coder would have spawned its own reviewers. The floor exists because that session read
     issue text and can be steered; if it spawns the critics, it decides whether the floor
     runs. Driver-spawned critics make the floor mechanical, put each critic under its own
     model, turn cap and budget (what § 7.4's per-model caps assume), and give critics a
     fresh view of the diff. Costs: more sessions per task with no shared cache (some extra
     Opus spend, bounded by the caps); the `round_cap` fix loop needs the driver to hand
     findings to a new or resumed coder session; more driver code. Options weighed: (B) the
     coder spawns in-session and the driver audits the transcript afterwards, after the
     fact, on evidence the session wrote; (C) leave it unspecified, so § 8.8's test would
     be built around the wrong question. Principle 3, § 7.3, § 7.4 and § 8.8 say so.
     *Decided (2026-10-04, after the tests):* **the critic line gains `--tools "<the agent's
     frontmatter tools>"`, and the driver verifies loading from the stream-json
     `system/init` event.** The test (§ 8.8) found the agent loads, on its own model, but
     `--restricted` strips any tool `--tools` does not name: D1's line as written ran the
     architect with `Read, Grep, Glob` and no Bash. Options: (A) as decided, tested, runs
     the agent as designed, at the cost that a critic's Bash now runs unsandboxed (§ 8.8)
     while it reads an untrusted diff; (B) critics get no Bash (`--tools "Read,Grep,Glob"`,
     the driver stages the diff), which diverges from the frontmatter and the architect's
     git/gh instructions; (C) revisit D1, which nothing in the result argued for. The bias
     flag given to the maintainer: (A) and (B) both keep D1, and the testing session is the
     same family that recommended it; the result is a pass on D1's premise. *Decided
     (2026-10-05, after the edit, § 8.13):* **(B)**, critics get no Bash and the driver
     stages their inputs; § 7.3's critic line says so.
   - **4b. Step 1 on a fresh machine, or on disagreement.** resume derives the review step
     from GitHub state only (open same-repo PR, head pushed by the maintainer's login, names
     the anchored task issue) and **auto-starts it only when `state.json` exists and names the
     same PR**. With no `state.json`, or when the two disagree, resume shows the derived step
     and waits. Two independent sources must agree before a step that mints the gate under the
     owner's ID runs unattended. Fails closed, like every other auto-start condition.
     (v9: loop PRs are pushed by the App, so they never match "the maintainer's login" and
     never become a derived review step. *Decided (2026-10-05, after the edit, § 8.13):*
     intended.)
   - **4c. Shape.** One WB-D number, written in two halves on the step-1 / step-4 boundary;
     the step-1 half lands with milestone 1, the loop half is added when milestone 2 starts.
   - **4d. Where policy lives.** In each consuming repo's `.ai/project.yml` under
     `orchestration.*`, WB-D17 style: every key present and explicit; `schema-complete`
     refuses a loop dispatch when any is absent, so the repo's own record says what the loop
     may do to it. **One value is not there (D3, after the v9 review):** the host's
     `placement` lives in the driver's own config, because it is a fact about the machine,
     not the repo; four repos could hold four different claims about one host, and the
     governor would trust whichever repo it was dispatching (§ 8.2, § 7.4).
5. **Decided after the v7 review (raised by v6; options rewritten in v7): how the loop
   identity is stopped from merging.** Every ruleset requires 0 approvals (§ 2.2), so a
   Contents-write PAT can merge a green PR. Principle 2 is false until one of these lands.
   `require_extra_approval_for_unattributed_changes` does not help: it covers Copilot PRs only
   and "has no effect if the ruleset requires zero approvals" (§ 2.2, v7). Options:
   - **(a) Restrict updates to `main` to bypass actors**, in a **new, separate ruleset**
     whose only bypass actor is the repository admin role (the machine user has no admin;
     the UI does not offer individual users), with `bypass_mode: pull_request`. The existing
     ruleset, with no bypass actors, keeps requiring every check of everyone: rulesets
     aggregate, and the most restrictive rule applies (§ 4.4). Putting the restriction in the
     existing ruleset instead would let the admin bypass its required checks too, because
     bypass is granted per ruleset.
     **Cost (v7):** every merge to `main`, the human's included, becomes an explicit bypass
     (the UI's bypass choice, `gh pr merge --admin` from the CLI). resume's cursor-sync merge
     (`gh pr merge <N> --repo {repo} --squash --match-head-commit <oid>`,
     `skills/resume/SKILL.md` L350) has no `--admin`, and devcontainers' `merge-guard.sh`
     admits only that exact shape (L166), so both need amending, and the amended guard must
     still refuse `--admin` on anything but a cursor-sync PR. Whether the restriction blocks
     a non-bypass user's PR *merge*, as opposed to a direct push, is implied but not stated
     in GitHub's docs; test it with the machine user on a scratch repo before relying on it.
   - **(b) Require one approving review.** **Not usable as v6 described it** (v7). The
     maintainer's account authors nearly every PR in all four repos (§ 2.2), and GitHub does
     not let a PR's author approve it. (b) would block every PR the maintainer opens,
     cursor-sync PRs included, unless a second person approves or the maintainer bypasses,
     which reduces (b) to (a) plus an approval click on the loop's PRs. Kept for
     completeness.
   - **(c) A required check that fails when the PR's author is `orchestration.loop_identity`
     and the merger is not the owner.** GitHub does not expose the merger to a check before
     the merge, so this is likely not implementable. Listed for completeness.
   - **(d) Accept deny rules as the control** and amend principle 2 to say so. That
     contradicts § 6.2 item 4.
   - **(e) No write access: the loop opens PRs from a fork** (added in v7). The machine user
     gets **read** on the upstream and pushes to its own fork; its PAT needs Contents write
     on the fork only. It cannot merge, push to `main` or post statuses upstream, by
     credential, with no ruleset change and no change to the human's merge or to resume.
     Costs, per GitHub's docs (§ 4.4):
     - Fork-triggered workflows get no secrets and a read-only `GITHUB_TOKEN`. A required
       check that needs a secret or a write token fails or cannot report: possibly
       bounty-infra's `tofu-plan` (**not checked**), and devcontainers' architect-review gate,
       whose `pull_request` run posts a status (its `issue_comment` run uses the default
       branch's copy and may still post).
     - First-time contributors need a human to approve each workflow run until their first
       merge.
     - infrastructure-core is private, and new orgs disallow forking private repos by default,
       so (e) there needs an org policy change.
     - The machine user is still COLLABORATOR by `author_association` (read access), so § 8.1's
       untrusted-by-name rule is still needed. `review-sandbox.sh trust` already refuses a
       fork head (§ 2.2), which agrees with § 8.1. `cursor-sync-pr.sh` is unaffected: loop PRs
       are never cursor-sync PRs.
   *v6 recommendation:* (a) or (b), decided per repo, recorded in `orchestration.*` and checked
   by the driver's preflight via `gh api` before any dispatch.
   *v7 recommendation, for the maintainer to decide per repo:*
   - claude-workbench: **(e)**. Its required checks (`lint`, `coupling`, `invariants`)
     appear to need no secrets; confirm on one fork PR.
   - bounty-infra: (e) if `tofu-plan` and the other required checks run without secrets on a
     fork PR, otherwise (a).
   - devcontainers: **(a)**, because the architect-review gate's status path is built around
     same-repo PRs (#93, #122).
   - infrastructure-core: **(a)**; it is private and also requires `architect-review`.
   - (b) nowhere. Whichever option is chosen, record it in `orchestration.*` and have the
     preflight check it via `gh api` (the ruleset, or the PAT's lack of upstream write).
   **Checked after the v7 review** (read live, 2026-10-04): claude-workbench's `ci.yml` uses
   no secrets, so (e) would work there. bounty-infra cannot use (e): `tofu-plan` authenticates
   to AWS by OIDC with a subject bound to `repo:glunk-works/bounty-infra:pull_request`
   (`plan-infra.yml` L14-25), and `secrets-scan` needs the `GITLEAKS_LICENSE` secret
   (`ci.yml` L178); fork PRs get neither. That leaves claude-workbench as the only repo where
   (e) fits. **v8 corrections:** the subject string is not the blocker (it would be the same
   on a fork PR); the blocker is that a fork PR's read-only `GITHUB_TOKEN` cannot carry the
   `id-token: write` permission `plan-infra.yml` L24 declares, so no OIDC token can be
   requested (§ 4.4). The conclusion stands. And "uses no secrets" holds for claude-workbench's
   three *required* checks; its `zizmor` job needs `security-events: write` (`ci.yml`
   L120-122) and would fail from a fork, but it is not required.
   *Decided (2026-10-04, after the v7 review):* **option (a) on all four repos.** One mechanism in the driver
   rather than two, and the plugin change it needs (resume's cursor-sync merge with
   `--admin`) is needed for the other three repos anyway. Conditions:
   - **Test first** on a scratch repo with the machine user: restrict-updates blocks its PR
     merge, the admin can still merge with every check required, and `gh pr merge --admin`
     on a cursor-sync PR works. If the restriction does not block a PR merge, claude-workbench
     falls back to (e), and the other three need a different answer. (Run 2026-10-05, below.)
   - The restriction lives in a **new ruleset** whose only bypass actor is the repository
     admin role, `bypass_mode: pull_request`; the existing rulesets keep their checks and no
     bypass actors.
   - resume's cursor-sync merge gains `--admin` (a plugin change under the step-4 WB-D), and
     devcontainers' `merge-guard.sh` admits that shape and still refuses `--admin` on any
     other PR.
   - The repo's choice is recorded in `orchestration.*`, and the driver's preflight reads the
     ruleset via `gh api` and refuses to dispatch if it is missing or changed.
   - The ruleset changes are the maintainer's to make; the harness refuses `gh api` writes to
     these orgs.
   *Decided (2026-10-04, after the v8 review):* **the scratch test grows to five checks, the
   `--admin` question is reframed, and the contingency is named.** v8 found that gh's
   `--admin` only skips the client's own refusal of a `BLOCKED` PR and that the server
   applies bypass regardless (§ 4.4), and that two merges in this plan are made by GitHub
   itself, not by a bypass actor: the merge queue (§ 7.1 step 4) and devcontainers' planned
   auto-merge (#139). Options weighed: (A) extend the test now and defer the contingency to
   its result, naming the candidate; (B) keep v7's three checks; (C) decide the full
   contingency now. (B) would meet the merge queue at the first wave instead of on the
   scratch repo; (C) is a large redesign for an outcome v8 does not expect, since a PR merge
   updates the ref the rule protects. **(A) is decided.** The five checks, with the machine
   user and the admin on a scratch repo carrying both rulesets:
   1. the machine user's PR merge is blocked;
   2. the admin's merge still needs every check of the no-bypass ruleset;
   3. whether GitHub reports `mergeStateStatus: BLOCKED` to the admin on a green PR whose
      only unmet rule is the restriction (this, not "does `--admin` work", decides whether
      resume's merge needs `--admin`; the plugin change and the merge-guard amendment
      **wait for this answer**);
   4. a merge-queue merge under the rule;
   5. an auto-merge under the rule.
   If check 1 fails, claude-workbench falls back to (e) as already decided, and the named
   candidate for the other three is **(e) plus making each required check fork-safe**
   (`tofu-plan` and `secrets-scan` on bounty-infra; the same-repo assumption in
   devcontainers' and infrastructure-core's `architect-review` gates), since (b), (c) and (d)
   were ruled out on their merits and that does not change with the test. Check 4's answer
   also decides whether step 4's "merge queue where available" survives.
   *Decided (2026-10-04, after the v9 review):* **the proving round runs checks 1–3 now.**
   Check 4 becomes a **precondition for ever enabling a merge queue**, check 5 a
   **precondition for devcontainers' #139**, run when devcontainers joins under § 8.6 (e).
   Why: no live ruleset on the four repos has a merge-queue rule; no workflow in
   devcontainers, bounty-infra or claude-workbench has a `merge_group` trigger, and required
   checks do not run in the queue without one; all four `main` rulesets have
   `strict_required_status_checks_policy: false`, so a wave merges serially with no re-run
   between merges (§ 4.4, [O3]). Auto-merge is #139 only, and devcontainers is excluded
   from the first round. Options weighed: (B) keep five checks and build queue and
   auto-merge scaffolding on the scratch repo, answering questions about features no repo
   uses; (C) drop 4–5 entirely, losing the record of why they are needed. Two corrections
   with it: `--admin` is not only client-side once a queue exists (gh merges directly
   instead of enqueueing, § 4.4), which matters for the check-4 precondition; and the
   contingency's cost, stated honestly: making bounty-infra's `tofu-plan` fork-safe cuts
   against `plan-infra.yml` L11-18, which scopes its read-only credentials to the
   `pull_request` OIDC subject on purpose, so it is a CI trust-model redesign, not a toggle.
   § 7.1 step 4 drops "merge queue where available"; § 9 carries the two preconditions. As
   written, check 3 read `mergeStateStatus` **and `viewerCanMergeAsAdmin`** (GraphQL
   `PullRequest`: "Indicates whether the viewer can bypass branch protections and merge the
   pull request immediately", read by schema introspection), as the admin and as the
   machine user, with the driver re-reading both per loop PR; the test replaced that signal
   (below).
   **Tested (2026-10-05, on `glunk-works/wb-ruleset-scratch` carrying both rulesets, with
   the admin and the machine user `603-gh-loop`) [T]:**
   1. **PASS.** The machine user's green PR: `gh pr merge` refused client-side; the REST
      merge returned `405 Repository rule violations found / Cannot update this protected
      ref`, rule suite `fail`. Restrict-updates blocks a non-bypass user's PR merge, not only
      a direct push. **Option (a) stands; (e) is not triggered.** The same held for the
      GitHub App (§ 8.12).
   2. **PASS.** The admin's `--admin` merge of a red PR: "Required status check "ci" is
      failing", rule suite `fail`. The admin's bypass of the restrict ruleset does not carry
      over to the no-bypass ruleset.
   3. **Answered: the admin sees `BLOCKED`** on a green PR whose only unmet rule is the
      restriction, and gh refuses it client-side; the admin's plain REST merge succeeded,
      rule suite `bypass`, and `--admin` succeeded. So **resume's cursor-sync merge needs
      `--admin`**; the plugin change and devcontainers' `merge-guard.sh` amendment are
      unblocked. The server applies an eligible bypass whatever the client sends (§ 4.4,
      now [T]).
   `viewerCanMergeAsAdmin` read **`false` for the admin** on both green PRs, which the admin
   then merged, so it does not reflect ruleset bypass; `mergeStateStatus` read `BLOCKED` for
   both accounts on all four PRs; the ruleset API's `current_user_can_bypass` read
   `pull_requests_only` for the admin and `never` for the machine user on the restrict
   ruleset, and `never` for both on the other.
   *Decided (2026-10-05, after Test C):* **`viewerCanMergeAsAdmin` is dropped.** Before each
   dispatch, with the loop's token, every ruleset that
   `GET /repos/{repo}/rules/branches/{pr_base}` names must read `current_user_can_bypass:
   never`, and the `update` rule must be present. Per PR, once its checks are green,
   `mergeStateStatus` as the loop identity must be `BLOCKED`; anything else stops the wave.
   Options: (A) as decided; both signals behaved correctly in the test, at the cost of two
   reads, and `BLOCKED` means something only after the checks are green; (B) keep D2 and
   note the field is inert for rulesets, a check that cannot fail when it should; (C) the
   dispatch-time ruleset read only, one source of truth but no live per-PR check, so a
   ruleset change mid-wave goes unseen until the next dispatch. The bias flag given to the
   maintainer: (A) keeps D2's structure after D2's chosen field failed; (C) is the option
   that does not. The maintainer chose (A) without further reasoning. § 7.3's preflight says
   so.
6. **Decided after the v7 review (raised by v6; option added in v7): devcontainers'
   Docker-dependent gate.** Five of eight `gates.green` steps need the Docker daemon as
   written; two of them need it by nature (§ 2.3). Options:
   - **(a)** The session runs only the non-Docker gate steps (shellcheck, `go test`,
     `run-gate-tests.sh`), and CI's required checks (which already run the Docker steps on
     every PR) are the gate of record. The digest states which local steps ran. This changes
     "same quality bar" for devcontainers to "same bar, enforced in CI".
     **v7:** the merge-time bar is intact: all five Docker steps are required checks, run
     from the PR's own tree on every image-shaping PR (§ 2.3). What it lowers is the
     *pre-PR* bar the Definition of Done sets (local green gate, then critics): critics would
     review a diff whose images have not been built, and Docker-step failures reach the
     human's queue as red PRs. The driver should wait for CI on the pushed head before it
     counts the task done, and on red either re-dispatch a fix session within `round_cap` or
     stop the task with the PR marked draft.
   - **(b)** Rootless Docker-in-Docker or a separate builder VM reachable only from the
     container. More isolation work; untested here.
   - **(c)** Mount the host socket. **Not recommended:** it is root on the `docker-desktop`
     VM with read and write access to the maintainer's files (§ 4.5; v7 narrowed v6's "every
     Windows credential" to write-then-execute), which voids § 8.2's non-negotiables.
   - **(d)** Exclude devcontainers from the loop and start with claude-workbench and
     bounty-infra, whose gates need no Docker daemon in the session. bounty-infra's gate is
     `hatch run lint:check`, `hatch run test:run`, `tofu fmt` and
     `tofu init -backend=false && tofu validate` (read 2026-10-04). It needs PyPI and the
     OpenTofu provider registry through the proxy (§ 7.3). The repo whose cursor
     ratio motivated the plan would then be the last to benefit.
   - **(e) Native linters plus (a)** (added in v7). Install hadolint and Trivy in the loop
     image at the pinned versions the gate uses (zizmor is already in the base image), so
     the session runs six of the eight steps locally. Only `build-and-test.sh local` and
     `template-proof.sh` are left to CI. This needs the native and `docker run` forms of each
     linter to be the same version and to give the same result, which the schema marker
     below would have to express.
   *v6 recommendation:* (a), with `gates.green` gaining a schema-level marker for which steps
   need Docker, so the driver selects the steps without naming a repo-specific value
   (WB-D2). Run (d) as the first proving ground either way.
   *v7 recommendation:* (e), which is (a) with fewer steps deferred, plus the CI-wait rule
   above. Run (d) first either way.
   *Decided (2026-10-04, after the v7 review):* **(d), then (e).** The loop proves itself on claude-workbench and
   bounty-infra with devcontainers excluded. devcontainers joins afterwards under (e): the
   loop image carries hadolint and Trivy at the gate's pinned versions (zizmor is already in
   the base image), the session runs six of the eight steps, `gates.green` gains a
   schema-level marker for the steps that need a Docker daemon (WB-D2), and the driver waits
   for CI on the pushed head before it counts the task done. On red it re-dispatches a fix
   within `round_cap` or leaves the PR as a draft. Under § 8.2's decision devcontainers is
   public, so it may run on the Docker Desktop host.
   *v8 note (part of § 8.10, not a change to the decision):* the two deferred steps run in CI
   only when `image-scope.sh` reports `build=1` (§ 2.3). The CI-wait rule therefore reads
   that verdict from the jobs API (`GET /repos/{repo}/actions/runs/{run}/jobs`), which gives
   each step's `conclusion`: on the last six devcontainers PR runs, "Build and test all
   images" and "Prove the template" read `skipped`, guarded by `if:
   steps.scope.outputs.build == '1'` (`build.yml` L64, L71) **[O3]** (v8 said "step outputs
   or summary"), and the digest records one of "image build and template proof: passed in CI", "failed in CI",
   or "skipped by image-scope (build=0): no image-shaping path changed". It never says CI ran
   them when it did not. The native hadolint and Trivy must match the gate's pins (v2.15.1
   and 0.74.0 on 2026-10-04, devcontainers `.ai/project.yml` L71-72). **v9 (D2):** an
   auto-merge under the restrict-updates rule (§ 8.5's former check 5) is a precondition
   for #139, run when devcontainers joins under (e).
7. **Decided after the v8 review: how the `--internal` gateway hole is closed (§ 7.3
   egress).** v7's premise holds (§ 4.5): an `--internal` network still reaches the gateway
   IP and so the Windows host's services. v7's remedy was an iptables rule inside the
   `docker-desktop` VM with unverified persistence; Docker's own iptables page says not to
   modify its rules. Docker documents a network option v7 did not find:
   `com.docker.network.bridge.gateway_mode_ipv4=isolated`, usable only with `--internal`,
   under which no address is assigned to the bridge (§ 4.5). Options weighed:
   - **(A) `isolated` gateway mode on the internal network, host-side rule dropped.** Pros:
     documented; set once at `docker network create` and persists like any network; visible
     to the preflight through `docker network inspect`; the proxy stays reachable by container
     IP. Cons: untested on Docker Desktop's WSL2 backend; the host loses direct IP access to
     the container, which the driver never used.
   - **(B) Keep v7's host-side rule.** Cons: persistence unverified; a shell into the VM after
     every Docker Desktop restart until proven otherwise; against Docker's guidance.
   - **(C) Both.** Cons: carries (B)'s maintenance for no property (A) lacks; the accretion
     pattern v6 named.
   *Decided (2026-10-04, after the v8 review):* **(A)**, keeping v7's in-container preflight
   probe that the gateway IP and `host.docker.internal` are unreachable, because the probe is
   what proves the property on this backend. The sentence in § 8.2's decision that called the
   host-side block an argument for the move is struck; § 8.2's trigger rests on the socket,
   the shared kernel and the admin credentials, unchanged.
   **Tested (2026-10-04; Docker Desktop 4.79.0, engine 29.5.3, WSL2 kernel 6.18.33) [T]:
   PASS.** The control `--internal` network reached a VM-namespace listener through its
   gateway `172.18.0.1`; the `isolated` network (`172.19.0.0/16`, IPAM with **no Gateway**,
   bridge up with no IPv4 address) reached nothing outside itself: not the VM's addresses,
   not `host.docker.internal`'s address (`192.168.65.254`, which from the default bridge
   does forward to Windows' loopback), not the public internet; the proxy stand-in on it
   answered by IP and by name. `--internal` networks carry no default route at all. Three
   things differed from what v8 and the spec assumed, and § 7.3's preflight is rewritten
   for them: the plain `--internal` gateway reaches **the VM, not Windows** (spec bundle 6
   confirmed; v8's § 4.5 and this item's premise narrowed); on an isolated network there is
   **no gateway IP** to probe, and Docker handed the subnet's `.1` to the first container
   attached, once the proxy, so a probe that derives ".1" would hit a peer; and
   `host.docker.internal` does not resolve on either internal network, so a probe by name
   proves nothing. The preflight now asserts "no Gateway" from `docker network inspect`,
   then probes the VM's addresses and `host.docker.internal`'s address by IP. IPv6 was off
   on both networks, so the `_ipv6` twin was not tested; a Windows service bound to all
   interfaces was not tested either (§ 9).
8. **Decided after the v8 review: which settings-loading form the launch line uses (§ 7.3).**
   v7 offered an empty `--setting-sources` list, undocumented, with a `project`-only fallback
   plus write-denies. The CLI documents `--restricted`: "loads only managed settings and
   `--settings`", confines the file tools to the working directories, refuses bypass mode,
   removes the command-running tools "unless you name them individually in `--tools`",
   v2.1.248+ (§ 4.2). Project settings' `env` and helpers apply at startup in `-p`
   (§ 4.2), so the fallback would have protected an unneeded file with three controls.
   Options weighed:
   - **(A) `--restricted --tools …` as the launch form, tested first.** Pros: documented to
     do what principle 6 asks; its side effects cost the loop nothing. Cons: a mode built for
     evaluation harnesses, so two details need a test: `--tools Bash` under the sandbox, and
     `--plugin-dir` skills loading.
   - **(B) v7's empty `--setting-sources` list.** Cons: undocumented in both directions.
   - **(C) v7's `project`-only fallback.** Cons: loads a file carrying `env` and helper keys
     and then needs restore, managed deny and sandbox `denyWrite` to keep it inert.
   *Decided (2026-10-04, after the v8 review):* **(A)** as the launch form and first test,
   **(B)** as the contingency if (A) fails either detail, **(C) dropped**. The plan names one
   form as the design and one as the contingency rather than two undocumented forms as
   equals. § 9 lists (A)'s two unknowns in place of (B)'s.
   *Amended (2026-10-04, after the v9 review, D1):* the two unknowns become (1) `--tools
   Bash` restores Bash and it runs under the sandbox; (2) **plugin agents load** under
   `--restricted --agent --plugin-dir`. "Whether `--plugin-dir` skills load" is deleted: the
   v8 line had no `Skill` tool, and under D1 the coder loads no plugin. The spec placed the
   loading check in the result JSON's `plugins` and `plugin_errors` fields (headless.md:244);
   the test found those keys absent from the json result in 2.1.289 and `plugins` present in
   the stream-json `system/init` event, which the driver reads instead.
   **Tested (2026-10-04, in a `node:lts-bookworm-slim` container with Claude Code 2.1.289,
   a `claude setup-token` credential passed by `--env-file`, managed settings mounted
   read-only, a fresh tmpfs `CLAUDE_CONFIG_DIR`, uid 1000, Docker's default seccomp
   profile; 15 runs, ≈ $0.29) [T]:**
   - **B1, `--tools "Bash,Read"`: Bash comes back** (the init event lists it; with `--tools
     "Read"` there is none). The stated task did not complete, for two reasons that are not
     `--restricted`'s tool restoration: the sandbox could not start (B2), and `/tmp` is not
     a working directory under `--restricted` (Read refused `/tmp/b1.txt` as outside
     `/work`; `cat /tmp/b1.txt` was permission-denied under `dontAsk` despite a managed
     `Bash(cat *)` allow). With `--add-dir /tmp` and the sandbox off, all three steps
     succeed.
   - **B2, the sandbox: FAIL in the § 7.3 container.** Every command failed with `bwrap: No
     permissions to create new namespace`; the same `bwrap` fails outside Claude in that
     container and succeeds under `seccomp=unconfined`, and the kernel allows user
     namespaces, so Docker's default seccomp profile blocks namespace creation, before the
     `/proc` step `enableWeakerNestedSandbox` addresses. `allowUnsandboxedCommands: false`
     held when the model retried with `dangerouslyDisableSandbox`. Under `unconfined`
     (diagnostic only) it enforced as documented.
   - **B3, plugin agents: PASS on loading, FAIL on "its own tools".** `--restricted --agent
     way-of-working:architect --plugin-dir /plugins/way-of-working` loaded the pinned 0.15.0
     copy (init event: `way-of-working@inline`, the four agents, eleven skills) on
     `claude-opus-5-5` from the frontmatter, with tools `Read, Grep, Glob`: the frontmatter's
     Bash was stripped until `--tools "Bash,Read,Grep,Glob"` was added. Four builtin plugins
     load too.
   - **B4, settings: PASS, with a control.** With `--settings '{"env":{"FOO":…}}'` inline and
     `BAR`/`BAZ` planted in the config dir's and the clone's `settings.json`, `printenv`
     saw `FOO` only; without `--restricted` it saw all three. (Observable only with the
     sandbox off.) A first attempt with `echo "$FOO"` was permission-denied under `dontAsk`
     despite a managed `Bash(echo *)` allow.
   So (A) holds as the launch form, contingency (B) is not needed, and § 8.8's own failure
   case did not occur: what failed is the sandbox, decided next.
   *Decided (2026-10-04, after the tests):* **the loop container runs without Claude Code's
   sandbox** (`sandbox.enabled: false`). Options: (A) a custom seccomp profile adding
   user-namespace creation, untested, which gives the session's code user namespaces, a
   known kernel attack surface, on the shared Docker Desktop kernel; (B)
   `seccomp=unconfined`, tested, but it removes all syscall filtering from the container
   the plan calls the boundary; (C) as decided, the controls being the container, the
   read-only rootfs, the egress proxy, managed permission rules and `--restricted`, losing
   the per-command network allowlist (the proxy still covers the container), the
   credential `denyRead` and the in-container write allowlist; (D) defer to a test of (A)
   in the full container, leaving § 7.3 undecided. v8 already said the container, not the
   sandbox, is the boundary, and B4 showed `--restricted` alone ignores the user and project
   files that were the sandbox's second reason; (A) and (B) weaken the container to rescue
   the inner layer. For v9: § 7.3 drops "enable it anyway as a second layer"; principle 6's
   controls do not count the sandbox; § 6.2 lists the lost allowlist and `denyRead` as
   residuals; § 9 gains two open items: whether Bash can read the OAuth token without the
   sandbox (`env`, `/proc/<claude pid>/environ`; with the sandbox the count was 0), and
   whether Bash writes into the writable config dir (`.claude.json`,
   `remote-settings.json`, `policy-limits.json`) change anything the session or the next
   one loads, bounded to one task by the fresh `CLAUDE_CONFIG_DIR`.
9. **Decided after the v8 review: the plain-file secrets v7 did not look at.** v7 narrowed
   the Docker-socket residual to write-then-execute because the Windows gh keeps its tokens
   in the keyring. devcontainers' ledger records a second gh in the Ubuntu distro; gh on
   Linux without a secret service stores its token in `~/.config/gh/hosts.yml` in plain
   text; the distro shares the kernel with `docker-desktop` and is reachable through the
   socket (§ 4.5). The Windows-side `~/.claude/.credentials.json` v7 lists raises the same
   question. v8 tried to check whether the files exist, not their contents, and the auto-mode
   classifier refused it as credential exploration. Options weighed: (A) the maintainer
   checks both files and the plan records what holds, with a preference for logging the WSL
   gh out if its token is plain, since the ledger says that gh cannot push anyway; (B) record
   the residual unverified; (C) treat it as out of scope because the host is not the concern.
   (B) adds a third unverified line about this machine's credentials; (C) misreads the
   maintainer's words, since the residual is a credential, not the host.
   *Decided (2026-10-04, after the v8 review):* **(A).** The maintainer checks both files
   and § 4.5 records what holds.
   *Decided (2026-10-04, after the v9 review):* **demoted to host hygiene; not a blocker.**
   § 4.5 now records what is documented rather than inferred: the Windows file's path
   (authentication.md:206); gh's own fallback to a plain-text token where no credential
   store exists, so a plain token in the Ubuntu distro is likely; and that the socket
   residual **does not apply to the loop container**, which is never given the socket,
   while anything that holds the socket already runs as the maintainer on Windows and can
   read both files without Docker (`\\wsl.localhost\Ubuntu\…`). Whether § 4.5 says
   "write-then-execute" or "direct read" changes no control in § 7. Logging the WSL gh out
   is optional hygiene. Options weighed: (B) keep the maintainer's check, costing their
   time for an answer that changes no control; (C) drop the paragraph, losing a true, cheap
   hygiene point. § 9 drops the item.
10. **Decided after the v8 review: the editorial corrections, and who applies them.** The
    rest of v8's findings change no decision and need no test: the OIDC mechanism and the
    `zizmor` caveat under § 8.5; § 6.6 items 7 and 9 reworded as "v6 inconsistent" and "v5
    inconsistent"; principles 3 and 10 stating the floor once; `--disallowedTools` dropped as
    inert; the post-exit hash relabelled forensics; `.claude/rules/` in the restore list; and
    § 8.6's CI-wait reading image-scope's verdict (the one item that changes behaviour, in
    what the digest says). Options weighed: (A) a fresh session applies all of them as v8 and
    records the six decisions under § 8, so the recorder is not the reviewer; (B) apply only
    the correctness items; (C) leave v7 and carry the corrections in the conversation. (B)
    keeps the accretion two passes named; (C) makes the plan unreadable without a transcript.
    *Decided (2026-10-04, after the v8 review):* **(A)**, then amended by the maintainer in
    the same sitting: **the reviewing session writes v8.** v8 records that reversal in its
    header and § 6.7 so the next reviewer applies the same check the v7 brief asked for:
    does what § 7 now does match what § 8 records. The three tests (§ 8.5, § 8.7, § 8.8) run
    against v8, and the first thing anyone builds is a test, not the driver.
11. **Decided after the v9 review: who writes v9, and that the tests run first.** v8
    repeated the reviewer-then-editor pattern (§ 8.10). Options weighed: (A) a fresh
    session applies an edit spec, with only a diff check of v9 afterwards; (B) the
    reviewing session writes v9, the pattern a fifth time, by a reviewer that recommended
    all five decisions and revised one in conversation; (C) an addendum only, which § 7 and
    § 8 would contradict. *Decided (2026-10-04, after the v9 review):* **(A).** *Amended by
    the maintainer the same day:* **the three tests run first**, in their own session, so
    their results inform v9 rather than being bolted on after it, and any decision a result
    forces is taken before v9 is written. As run: the v9 reviewer (Opus 5.5) wrote
    `V9-EDIT-SPEC.md`; a separate Opus 5.5 session ran the tests and the App evaluation and
    wrote `V9-TEST-RESULTS.md` and `GITHUB-APP-EVALUATION.md`, with four decisions; a Fable
    5.1 session (the editor) applied all three, reopening nothing. The only review after v9
    is a diff check against those files.
12. **Decided after the App test: the loop identity is a GitHub App, not a machine user.**
    Setting up § 8.5's test (2026-10-05) showed that a machine user invited as an outside
    collaborator cannot mint a fine-grained token for an org's repo: GitHub's dialog offers
    only orgs the user belongs to as resource owners, so its only token is a classic one,
    scoped by visibility (`public_repo`) or to everything (`repo`), never to one repo. That
    fails D3's condition (1). The alternatives: org membership (a paid seat on 603-Identity,
    and `author_association` becomes MEMBER, against § 8.1's untrusted-by-name rule); a
    classic `repo` token (violates D3 outright); or a **GitHub App** installed per repo. The
    App was evaluated against docs.github.com and then tested on the scratch repo
    (`GITHUB-APP-EVALUATION.md`; App `glunk-loop-test`, since deleted): every check passed
    (§ 4.4: one-repo, two-permission, one-hour tokens; `422` on a repo or permission
    outside the installation; the restrict-updates rule blocks its merge, `405` and rule
    suite `fail`; its PR reads `author_association: NONE` to every viewer; a workflow-file
    push without the Workflows permission is refused server-side; CI runs on its PR without
    approval; `current_user_can_bypass` reads `never` with its token). Costs: the private
    key never expires and mints tokens for every repo its App is installed on until
    revoked, so it lives on the host, driver-readable only, with per-org and per-repo Apps
    bounding what one leaked key reaches; the driver grows JWT signing, token minting and
    refresh handling; an org owner must register and install two or three Apps; a
    permission change takes effect only after the owner re-approves each installation.
    *Decided (2026-10-05, after the App test):* **a GitHub App is the loop identity.** The
    maintainer's words: **"Lets go with the app unless/until there is a reason to
    switch."** A default, revisitable if a reason appears, not a permanent commitment. For
    v9: one private App per org plus a dedicated App for infrastructure-core; each installed
    on "Only select repositories"; Contents write and Pull requests write only, no
    Workflows, Issues read only for the private repo and only if the session reads its spec
    comment itself; the private key on the host, never in a container; one token per task,
    minted for the dispatched repo and those permissions; the preflight refuses to dispatch
    if `GET /installation/repositories` is not exactly the dispatched repo, if the App
    appears in any applicable ruleset's `bypass_actors` (read as the admin), or if
    `current_user_can_bypass` (read with the App token) is not `never`; the driver's § 8.1
    author-trust reads use the maintainer's view, never the App token; nothing that loads
    the plugin runs under the App token (its reach checks fail closed, § 7.2). `603-gh-loop`
    stays as an unused fallback; delete it if no reason to switch appears. The question
    the evaluation left open, how a task longer than the one-hour token pushes its work, is
    § 8.13's first decision. § 7.2, § 7.3, § 6.2 and D3's condition (1) are written to this.
    **Done (2026-10-05), read back live [T]:** the three Apps are registered and installed
    with Contents write, Pull requests write, Metadata read, no webhook: `glunk-loop`
    (glunk-works; App ID 5199187, installation 168191169; claude-workbench and
    bounty-infra), `identity-loop` (603-Identity; App ID 5199280, installation 168193109;
    devcontainers) and `infra-core-loop` (603-Identity; App ID 5199302, installation
    168193813; infrastructure-core). Keys are under the driver directory on the host. The
    `restrict-updates-to-main` ruleset (`update` rule, bypass `RepositoryRole` 5
    `pull_request`, no other actor) is active on all four repos: 24515052, 24515053,
    24515056, 24515057. Every pre-existing branch ruleset still has no bypass actors and
    strict checks off; no App is a bypass actor on any of them. glunk-works also carries an
    older App with Contents write on selected repos, `claude-workbench-release` (5051322),
    the Integration bypass on `release-tag-creation`; it is not on any `main` ruleset, and
    the preflight would refuse if it were added. The Test B setup-token and `603-gh-loop`'s
    classic token are revoked (maintainer, 2026-10-05; not verifiable from here). All three
    installations' repo selections were confirmed from the installation pages (screenshots;
    the gh token cannot list an installation's repositories).
13. **Decided after the edit (2026-10-05): the four items the tests left to a decision.**
    Recommended by the v9 editor (Fable 5.1) in conversation, one at a time with options
    and costs, and taken by the maintainer; so the editor has now also recommended, which
    § 0 records. Each is small, and none reopens an earlier decision.
    - **13a. How a task's work reaches GitHub, given the one-hour token.** Options: (A) fit
      the task inside the hour (token minted at launch, session pushes itself, a ~50-minute
      timeout), which caps tasks by the clock and keeps a pushing credential in the
      container for the whole hour; (B) the session never gets a GitHub token and the
      driver pushes after exit (tree copy into a fresh clone, checks, commit, mint, push, PR
      create), which removes the question and the credential together, moves the
      human-only-path check to pre-push, respects § 7.3's no-git-in-a-touched-clone rule
      by reading files rather than `.git`, and costs one more fixture-tested `bin/` script;
      (C) refresh a token file a credential helper reads every ~50 minutes, the most moving
      parts and the residual extended to the task's whole length. *Decided:* **(B).**
      "Cannot push" is a credential property again (principle 2); § 7.2 and § 7.3 say so.
    - **13b. Critics' Bash, now unsandboxed on an untrusted diff.** What the agents use
      Bash for, from their own files: `git diff`, `git log`, `git show` to establish the
      diff and `grep` for guarding tests and call sites (architect, security-critic); the
      same plus live `gh issue view`, `gh api … .permissions` and the ruleset
      (docs-consistency), which also says "prefer running the guarding test" (L144).
      Options: (A) keep the frontmatter tools,
      which gives a session reading attacker-influenced text command execution and runs
      git in the clone the coder touched; (B) `Read, Grep, Glob` only, the driver staging
      the diff, a bounded log, base copies, gate and fixture output, CI conclusions, the
      ruleset JSON and cited-issue states, with a staged-mode addendum; (C) Bash in a
      throwaway container, which isolates from the host but not from the diff. Costs of
      (B), stated: ad-hoc history exploration and running a fixture to confirm a hunch are
      lost; docs-consistency's live-state checks reach only what the driver staged. The
      floor still runs, the human-started fresh-session review and the interactive
      critic-gate keep full tools, and B3a ran with `Read, Grep, Glob` (loading only; the
      bundle and addendum are untested, § 9). *Decided:* **(B).**
    - **13c. Loop PRs never match resume's derived review step.** Options: (A) intended,
      record it; (B) extend the derivation to `orchestration.loop_identity`, which widens
      the one path that mints the gate under the owner's ID to loop-written PRs and would
      still have to refuse auto-start for them; (C) intended, plus a driver-written
      end-of-wave reminder that is never a `next_action`. *Decided:* **(A)** now; (C) if
      the first wave's human-minutes measurement shows the PR list is not enough.
    - **13d. The § 8.1 name rule, decided in v5 and never implemented.** Options: (A)
      implement in milestone 1: `review-sandbox.sh trust` and `plan-anchor.sh` read
      `orchestration.loop_identity` and return untrusted for it before any association
      check, with a fixture for the fail-open case; it also gives `plan-anchor.sh` the
      author check it lacks for everyone, and it survives a switch back to a machine user,
      which § 8.12 leaves open; (B) leave it as a documented backstop,
      a decision with no code behind it; (C) drop it and rely on `author_association`,
      which makes the trust class depend on GitHub's view of the identity rather than a
      repo-controlled value. *Decided:* **(A).** *Corrected by the Opus review (below):*
      the fail-open case that matters is not a `NONE` author, which `review-sandbox.sh`
      already refuses (L324), but a **stale `loop_identity` while the loop is a machine
      user** whose MEMBER or COLLABORATOR association passes; the preflight's
      login-equality check (§ 7.3) closes it. `plan-anchor.sh` has no association check to
      fall through to (that check lives in resume's prose, SKILL.md L943) and forbids `yq`
      (L50), so the login arrives as an argument, `verify` gains an `untrusted` verdict
      beside `match|drift|unreadable`, and its callers (handoff, archive-sprint) learn it.
      `orchestration.loop_identity` is not in `project-schema.md` yet; milestone 1 adds it
      as optional, before § 8.4d's "every key present" applies to a loop dispatch.
    **Reviewed (2026-10-05) by a read-only Opus 5.5 session**, at the maintainer's request,
    on § 8.13 against § 7.2 and § 7.3 only. Six findings, four confirmed against the files
    named, all applied above and in § 7.2, § 7.3, § 7.5, § 6.2 and § 9; none reopened a
    decision. The substantive ones: 13a moves session-authored bytes onto the host that
    holds the App key, and the copy had no stated safety rules (now § 7.3); three § 7.2/7.3
    lines were stale under 13a (the session's Issues read, GitHub egress, preflight
    timing); 13d named the harmless fail-open case. Its bias note on the editor: 13a's
    "removes the question and the credential together … one more fixture-tested script"
    was the convenient framing, omitting host-side git on session content beside the key;
    13d's `NONE` case was the convenient one too. 13c it found clean.

---

## 9. Known gaps, unverified claims, and places the author may be biased

- **Never executed:** a hook deny under `dontAsk` (v9 saw permission-rule denials under it,
  never a hook's); `--setting-sources user` effect on project `CLAUDE.md`;
  `--max-budget-usd` *tripping* on subscription auth (v9's runs passed it on an OAuth token
  without error but never reached it); what a `-p` run reports at a usage limit
  (reported: error exit); whether `--autocompact 100k` degrades task quality; whether the
  settings watcher honours file ownership (§ 7.3 assumes a read-only file simply cannot be
  edited, which is a filesystem fact, not a Claude Code one; v6 replaced that reliance, § 7.3);
  `allowManagedHooksOnly` on the chosen host.
- **Added in v6 and v7, answered since** (moved out of the open lists in v9): what
  `allowManagedPermissionRulesOnly` does to `--allowedTools` and `--settings` allow rules
  (v7, § 4.2); what `require_extra_approval_for_unattributed_changes` does (v7, § 2.2);
  which hosts Claude Code itself needs (v7, § 4.2); whether the sandbox runs in an
  unprivileged container (v9: tested, it cannot start under Docker's default seccomp
  profile; dropped, § 8.8); whether § 8.5 (a) needs `--admin` from resume (v9: tested, the
  admin sees `BLOCKED`, § 8.5); whether restrict-updates blocks a non-bypass PR merge (v9:
  tested for the machine user and the App, § 8.5); whether required checks run from a fork
  PR (moot: (e) is not triggered and an App cannot fork); the empty `--setting-sources`
  contingency (moot: `--restricted` loaded only managed settings and `--settings` in the
  test, § 8.8); whether leaving out `user` drops user CLAUDE.md, agents and skills (moot
  because the `CLAUDE_CONFIG_DIR` is fresh per task, so there is nothing there to load;
  v8's "moot under `--restricted`" was unsupported, since cli-reference.md:123 speaks only
  of settings); the host-side gateway block's persistence (withdrawn with the rule, § 8.7);
  Docker Desktop's drive sharing on WSL2 (not tested; under § 8.9 the socket residual does
  not apply to the loop container, so nothing in § 7 turns on it).
- **Still open from v7:** whether the native hadolint and Trivy give the same results as
  the gate's pinned `docker run` forms (§ 8.6 e).
- **Added in v8, all answered in v9:** the `--restricted` details (§ 8.8, tested);
  `isolated` mode on this backend (§ 8.7, tested); `BLOCKED` to a bypass-eligible viewer
  (§ 8.5, tested); the plain-file secrets (§ 8.9, demoted to hygiene); image-scope's verdict
  from outside (§ 8.6, the jobs API). The merge-queue and auto-merge questions are now
  preconditions, below.
- **Answered by the #318 attack pass** (2026-10-07, against the assembled container, `launch.sh` with
  `LOOP_ATTACK=1`, `scripts/loop/attack.sh`, claude 2.1.289; moved out of the open list below):
  - *Whether Bash can read the OAuth token without the sandbox:* **no, and there is nothing to read.**
    Since #345 the session holds only a placeholder. `env`, `/proc/*/environ`, `/proc/*/cmdline` and
    every file on `/home/app`, `/run/loop`, `/work` and `/tmp` held the real credential 0 times (a
    host-side search of the dumped text). Under the managed rules, Bash with no allow rule was denied
    `env`, `printenv`, `cat /proc/self/environ` and `ls /proc/1`. The credential remains *usable*
    through the injecting proxy, for ordinary `POST /v1/messages` and `count_tokens` bodies and
    `GET /v1/models` (the accepted residual, `#345`).
  - *Server-side tools through that credential:* **found and fixed.** The proxy forwarded any body, so
    the session could ask the API for `web_fetch`, `web_search`, `code_execution`, `mcp_servers` or a
    `container`, which act on Anthropic's side and reach any URL; the critic pass then found the same reach through a `url` or `file_id` source on an image or document block. `inject.py` now refuses a POST body
    that names `mcp_servers` or `container`, a `tools` entry whose `type` is not `custom`, a content block of a type Claude Code does not send or whose `source` is not inline base64 or text, a non-UTF-8 or BOM body, `NaN`, a `Content-Encoding`, a non-JSON `Content-Type`, a repeated
    key (parsers disagree on which wins) or non-JSON. Left open: the query string and the `anthropic-beta` header are forwarded as the session wrote them (no known server-side feature needs only those). Claude Code's own requests pass (the trivial
    task and every live probe ran through it). Fixtures: `tests/loop-inject.test.sh`.
  - *Writes into the config dir:* **pass.** With `settings.json`, `settings.local.json`,
    `remote-settings.json`, `.claude.json` (user and project `mcpServers`, `allowedTools`),
    `policy-limits.json` and a `hooks/` file seeded in `CLAUDE_CONFIG_DIR`, a live session ran no hook
    and no MCP server, and Write to `scripts/` stayed denied. `--restricted` loads only managed
    settings, and the config dir is a tmpfs per task, so nothing outlives the container.
  - *A Windows listener on all interfaces, and the `_ipv6` twin:* **pass.** A listener on `0.0.0.0` and
    one on `[::]` were not reachable from the session's `isolated` network (IPv4 only) or from an
    IPv6-enabled `gateway_mode_ipv6=isolated` twin, on every host address, the bridge gateways and
    `host.docker.internal`. The injecting proxy's external-network address does not answer the
    Windows host, and no container publishes a port. One quirk: the WSL adapter's `172.18.0.1` can
    equal a container address on the isolated subnet, so a probe of it hits the proxy, not the host.
  - *The git tools and the protected paths:* **pass.** Outside a repository the five fixed tools only
    report an error (no implicit `--no-index`; no file content read). A live Write was denied for
    `.git/config`, `.git/hooks/pre-commit`, a symlink to `.git`, a symlink to the config dir,
    `.mcp.json`, `CLAUDE.md`, `.github/`, `.claude/`, `/home/app` and `/run/loop`; Edit of `.mcp.json`
    was denied; a path through a symlink is denied by its resolved target.
  - *The managed `Bash(...)` rules, in the `--restricted --permission-mode dontAsk` form:* with
    `Bash(bash scripts/lint.sh)`, `Bash(bash scripts/coupling-check.sh)`,
    `Bash(bash scripts/invariants-check.sh)` and `Bash(sh tests/*.test.sh)`, **allowed:** the command
    exactly, with `2>&1`, after `cd /work &&`, and before `&& echo done`. **Denied:** `./scripts/…`,
    an absolute path, `scripts/../scripts/…`, an extra argument, `$HOME` or `$PWD` expansion,
    `$(…)`, an `X=1` prefix, `bash -c '…'`, a pipe to `tee`, and `; curl …` (each subcommand is
    checked). **Two cautions:** the `*` in `Bash(sh tests/*.test.sh)` also matched
    `tests/../x.test.sh`, so a glob rule is a path-traversal hole; use one exact rule per script.
    And Claude Code allows a small read-only set with **no rule at all**: `echo`, `id`, `ps aux`,
    `git status`, `git log`, `git show <rev>:<path>`, `git ls-files` (and `docker ps` passed the
    permission check). `git diff --no-index`, `git diff <path>`, `--output=`, `-c`, `git config`,
    `git branch -D`, `git grep`, `cat`, `head`, `sort`, `find`, `curl` and every write were denied.
  - *`--append-system-prompt` with an `--agent` main thread:* **pass.** With `--agents` inline and
    `--agent probe`, the appended instruction was followed (`ZEBRA-4417` in the reply) and absent
    without the flag. Not tested: a critic with a bundle and addendum against B3a.
  - *The full container as one piece, and a deliberate breakout:* **pass, with one residual.** Writes
    to `/`, `/etc`, `/usr/local/bin`, `/opt/loop`, `/etc/claude-code` and `/proc/sys` were refused;
    `CapEff` and `CapBnd` are 0 and `NoNewPrivs` is 1; `unshare -U` and `mount` were refused; no Docker
    socket and no host mount; no setuid file. 22 CONNECT and absolute-URI forms against the
    allowlisting proxy (case, trailing dot, port, userinfo, fragment, NUL, suffix, IP literals in
    hex, decimal and IPv6, the injecting proxy's name) tunnelled only `api.anthropic.com:443`. The
    **residual** is the allowlist itself: a tunnel to `api.anthropic.com`, `claude.ai`, `claude.com` or
    `platform.claude.com` reaches whatever those hosts serve.
- **Open after v9 (never executed or looked up; added in v9):**
  - the driver's tree-copy, commit and push path (§ 8.13a, with § 7.3's safety rules) and
    the critic staging bundle (§ 8.13b): new driver code, fixture-tested, never run;
  - whether a critic with a bundle and addendum behaves as B3a did with neither (the flag
    itself reaches an `--agent` main thread, answered above);
  - infrastructure-core's history for live secrets (§ 8.2, D3 condition 2);
  - the § 8.1 name rule is written (#235, #295): `plan-anchor.sh` and resume refuse the loop identity;
  - whether `viewerCanMergeAsAdmin` tracks only legacy branch protection is an inference
    from one reading, not tested; the field is no longer used (§ 8.5).
  - **Preconditions, not open questions (§ 8.5, D2):** a merge-queue merge under the
    restrict-updates rule, before any repo enables a queue; an auto-merge under it, before
    devcontainers' #139.
- **Security-reviewed once, on paper:** the container placement chosen in § 8.2 and its
  hardening list in § 7.3 were written by the v4 reviewer from Docker Desktop's architecture
  and one `docker info`. The v6 (Opus) reviewer attacked them from documentation and config
  and found the problems in § 6.5 items 2–4; the v7 (Opus) reviewer did the same and found
  § 6.6 items 2–6. v9's tests built its pieces separately (§ 8.7, § 8.8) and found one of
  them, the sandbox, cannot start. The whole container was assembled in #317 and attacked in
  #318 (the answered bullet above): one hole found and fixed, no breakout found, one residual
  (the proxy allowlist's hosts). That is one pass by one author on one host, not a guarantee.
- **Platform churn:** `--bare` is announced as the future default for `-p` (§ 4.1); routines
  are in research preview; `--permission-prompts` landed 31 builds after the installed CLI
  (the tests ran 2.1.289 in the container). Every § 4 fact has a date and should be
  re-fetched before anything is built.
- **Reported, not re-read by author:** Agent SDK auth statement (re-read by both reviewers);
  merge-queue plan availability (page has no statement); auto-mode availability; errors.md
  limit behaviour; prompt-caching.md subagent TTL; the Flatt write-up of an issue-body
  injection exfiltrating a token from a Claude Action run
  (https://flatt.tech/research/posts/poisoning-claude-code-one-github-issue-to-break-the-supply-chain/).
- **Data limits:** transcript scan de-duplicated by `message.id`; one mirrored directory
  excluded; no reconciliation with Anthropic's accounting; "peak context" is input+cache
  tokens on the largest turn, not the API's own measure.
- **Possible over-correction:** the plan forbids any driver merge anywhere. A narrowly-scoped
  merge into a *throwaway integration branch whose config and gate scripts both come from
  `origin/main`* might be defensible; § 6.1's note and § 8.3 now say so, but nobody has
  designed it.
- **Possible under-correction:** the no-op handoff rule (step 1) leaves `main`'s ledger one
  step stale during a review; a fresh machine with no `state.json` resumes from `main`. The
  author believes resume's GitHub-derived step covers it; not proven. v4 moved this into the
  WB-D; v5 added the derivation rule to step 1.
- **Fable preference:** the maintainer routes architect work to Fable (memory note) while the
  repo's `models.architect` says `opus`. The loop takes the map literally (§ 8.4a), so under
  the loop the judgment slots run on Opus unless the map changes; a reviewer may think that is
  too little Fable or too much.
- **Three Fable revisions, two Opus revisions, a Fable revision, then a split v9.** v4 and
  v5 were each produced by a Fable 5.1 session acting as reviewer and then as editor. v6
  and v7 were each produced by an Opus 5.5 session doing the same. v8 was produced by a
  Fable 5.1 session doing the same again, after the maintainer had first decided a fresh
  session would do it (§ 8.10). v8 is same-family to the author, v4 and v5, so where § 6.7
  sided with v5 against v6 (item 7, on § 6.6 item 9) that was a same-family verdict. v9
  broke the pattern: an Opus 5.5 session reviewed v8 and wrote a spec (same family as v6
  and v7, so its reversal of that verdict is itself a same-family one, offset only by the
  quoted lines, § 6.8); a second Opus 5.5 session ran the tests, the same family as the
  reviewer whose decisions two of them check, and said so; a Fable 5.1 session edited and
  reviewed nothing. No full review follows; the only check is a diff against the three
  input files (§ 0).
- **Host:** the maintainer corrected v5's "laptop" to an always-on desktop during the v6
  review. Any remaining availability argument in this plan should be read with that in mind.
- **Note, not a decision (moved from v3's § 8.5):** the subscription-only constraint is the
  maintainer's stated requirement and the plan honours it. For the record, the constraint is
  what forces plain `-p` (hooks and plugins load) over `--bare`, and makes `--max-budget-usd` a
  proxy rather than a cap; an API key for the loop host alone would remove both. The plan does
  not ask for that; it records the cost.
- **The author did not read** bounty-infra's or infrastructure-core's threat models in full,
  nor devcontainers' `docs/threat_model.md` beyond grep hits. Neither did the v3, v4 or v6
  reviewer.

---

## 10. Appendix — artefacts and how to regenerate the numbers

Analysis scripts and the v1–v8 drafts are beside this file in `docs/proposals/analysis/`
(originals in the authoring session's scratchpad):
`C:\Users\SR116\AppData\Local\Temp\claude\c--Users-SR116-projects-glunk-works-claude-workbench\d2bb1d4a-393d-4799-95ed-47e30db7c48c\scratchpad\`
- `pr_analysis.py <repo>-prs.json …` — PR classification, open→merge timing, cadence.
  Input: `gh pr list -R <repo> --state all --limit 200 --json number,title,createdAt,mergedAt,state,additions,deletions,changedFiles,files`.
- `usage_analysis.py <since>` — per-project/model/session usage from `~/.claude/projects`.
- `peak_ctx.py <since>` — per-session peak context; subagent totals.
- `daily_usage.py <days>` — daily envelope, de-duplicated; per-session medians by kind/model.
- `orchestrator-plan-v1.md` … `orchestrator-plan-v8.md` — the earlier drafts as reviewed.
  v3 is the document § 6.3 was run against; v4 is the document § 6.4 was run against; v5 is
  the document § 6.5 was run against; v6 is the document § 6.6 was run against; v7 is the
  document § 6.7 was run against; v8 is the document § 6.8 was run against.
- `V9-EDIT-SPEC.md`, `V9-TEST-RESULTS.md` and `GITHUB-APP-EVALUATION.md` (beside this file
  in `docs/proposals/`) are the three inputs v9 was written from and the only things it is
  checked against (§ 0). The test session's scripts and raw outputs (`testA/`–`testD/`) are
  in its own scratchpad, not in this repo.

The v3 reviewer re-ran `pr_analysis.py` (devcontainers, claude-workbench) and
`daily_usage.py 14` on 2026-10-04 and reproduced § 3 within one PR. The v4 reviewer re-ran
`pr_analysis.py` (devcontainers) and `daily_usage.py 14` on 2026-10-04 and reproduced § 3
exactly (Fable cache reads 11 M/day where v4 printed 10). The relay-PR count in both used
`'review next' in title.lower()` over the same 200-PR pull. The v6 reviewer re-ran
`pr_analysis.py` (devcontainers) on 2026-10-04 and reproduced § 3.1 (cursor PRs merged 69
where v5 printed 68, one later merge); it did not re-run `daily_usage.py`. The v7 reviewer
re-ran `pr_analysis.py` (claude-workbench, pulled with the Seuss27 account) on 2026-10-04 and
reproduced § 3.1's row exactly; it did not re-run `daily_usage.py`. The v8 reviewer re-ran
`pr_analysis.py` (infrastructure-core, pulled with the JaredGroves-603 account) on
2026-10-04 and reproduced § 3.1's row exactly (median gap on 2026-09-07: 16 min, not in the
table); it did not re-run `daily_usage.py`. The v9 reviewer re-ran `pr_analysis.py`
(bounty-infra, pulled with the Seuss27 account) on 2026-10-04: 86 PRs. **The title
classifier is tuned to the other repos' titles** and misses bounty-infra's `docs(SE): sync
cursor …` grammar, so § 3.1 carries both the by-title and the by-files figures for that
repo; it did not re-run `daily_usage.py`.

Memory note written by the authoring session: `token-spend-data-lives-in-transcript-usage-fields.md`
(where usage data lives; the mirrored directory).

The eight subagent reports and the authoring session's transcript are exported under
`docs/proposals/analysis/session-export/` (git-ignored). Its README says **do not read unless
required**: it is context for the maintainer, not review input. § 6 condenses the reports.
No review session's transcript (v3 to v9) is exported; their reasoning exists only as
§ 6.3 to § 6.8 and, for v9, the three input files above. Each reviewer's first-pass verdict, written before it opened the
previous draft, is summarised at the top of its section.
