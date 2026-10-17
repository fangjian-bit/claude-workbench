# claude-workbench

This repo is the source of the `way-of-working` plugin — see [README.md](README.md) for
what it is and [docs/decisions.md](docs/decisions.md) (`WB-D*`) for why it's shaped this
way. It now consumes its own plugin (`.claude/settings.json`), parameterized by
[.ai/project.yml](.ai/project.yml) per
[reference/project-schema.md](plugins/way-of-working/reference/project-schema.md).

## How work happens here

No sprint cadence — small, single-task PRs via `/way-of-working:ship`, each closing (or
declining) one backlog issue. `/way-of-working:resume` at session start,
`/way-of-working:handoff` before switching model/session, `/way-of-working:critic-gate`
after the green gate and before handoff on any diff touching `code_paths`.

## The one rule that matters most here

**Shared plugin code in `plugins/way-of-working/` — every entry except `reference/`
and `.claude-plugin/` — may never name a repo-specific value.** Every literal removed
becomes a schema key
([project-schema.md](plugins/way-of-working/reference/project-schema.md)), enforced
mechanically by `scripts/coupling-check.sh` in CI — not by convention. See
[reference/conventions.md](plugins/way-of-working/reference/conventions.md) for the full
Global Conventions this plugin ships (commit grammar, branch names, label taxonomy,
Definition of Done) — they apply to this repo's own PRs too.

## Local green gate

```
bash scripts/lint.sh            # marketplace.json / plugin.json / SKILL.md frontmatter
bash scripts/coupling-check.sh  # no repo-specific literals in any plugins/*/ entry except reference/, .claude-plugin/, .git/
bash scripts/invariants-check.sh  # known-wrong forms haven't come back
sh tests/cursor-drift.test.sh   # bin/ script fixtures (not yet a required check)
sh tests/coupling-check.test.sh # coupling gate fixtures (not yet a required check)
sh tests/entry-anchor.test.sh   # ledger entry-anchor matcher fixtures (not yet required)
sh tests/review-gate-state.test.sh  # review-gate predicate fixtures, both surfaces (not yet required)
sh tests/ai-cursor-banner.test.sh  # SessionStart banner fixtures, incl. the Parked: line (not yet required)
sh tests/plan-anchor.test.sh    # planning.kind: github_milestones anchor predicate fixtures (not yet required)
sh tests/spawn-model.test.sh    # models.second_opinion provenance predicate fixtures (not yet required)
sh tests/review-base-anchor.test.sh  # architect-review's preflight-chain script fixtures (not yet required)
sh tests/review-sandbox.test.sh # architect-review's PR-execution sandbox fixtures (not yet required)
sh tests/review-token.test.sh   # review-token.sh request/discard fixtures (no skill calls it since #636; not yet required)
sh tests/review-poll.test.sh     # wow-review-poll launch decisions, exit-code policy, token revocation and cleanup vs stub gh and wow-review (not yet required)
sh tests/review-outbox.test.sh  # review-outbox.sh where/outcome/body/findings fixtures and launcher agreement (not yet required)
sh tests/milestone-close-line.test.sh  # archive-sprint's Milestone close: ledger-line predicate fixtures (not yet required)
sh tests/schema-complete.test.sh  # WB-D17 .ai/project.yml completeness-checker fixtures (not yet required)
sh tests/plan-gather.test.sh    # plan-sprint's read-only gather-step fixtures (not yet required)
sh tests/milestone-desc.test.sh  # milestone-desc.sh write: scratch-file, repository and read-back fixtures vs a stub gh (not yet required)
sh tests/spec-issue.test.sh     # spec-issue.sh fetch: argument, out-dir, trust and stop-word fixtures vs a stub gh (not yet required)
sh tests/plan-depends.test.sh   # plan-sprint's depends_on marker read-back, plus order, frame and items, fixtures (not yet required)
sh tests/invariants-reach-order.test.sh  # invariants-check.sh check 3 (reach precedes ruleset) fixtures (not yet required)
sh tests/invariants-null-repo.test.sh  # invariants-check.sh check 12 (null backlog.repo means {repo}) fixtures (not yet required)
sh tests/invariants-unpark-pfc.test.sh  # invariants-check.sh check 13 (unpark-sprint validates parked_from_commit) fixtures (not yet required)
sh tests/invariants-gate-reader.test.sh  # invariants-check.sh check 14 (three hitl_gate readers call the shared predicate) fixtures (not yet required)
sh tests/invariants-spec-body.test.sh  # invariants-check.sh check 15 (architect-review loads no issue body under an identities map) fixtures (not yet required)
sh tests/spec-reaction.test.sh  # spec-reaction.sh approved/unreacted/bad-argument fixtures (not yet required)
sh tests/invariants-spec-reaction.test.sh  # invariants-check.sh check 16 (one spec-reaction rule, plan-anchor.sh and architect-review call it) fixtures (not yet required)
sh tests/spec-comment.test.sh  # spec-comment.sh ok/moved/wrong-issue/untrusted/unreacted/unreadable/bad-argument fixtures (not yet required)
sh tests/invariants-spec-comment.test.sh  # invariants-check.sh check 17 (resume, coder and architect-review print the spec comment only via spec-comment.sh, name spec-find.sh, resume and coder also name spec-fresh.sh, which exists and makes no gh call, and carry no comment listing) fixtures (not yet required)
sh tests/spec-shape.test.sh    # spec-shape.sh ok/missing-section/wrong-order/empty-restated/unreadable/bad-argument fixtures (not yet required)
sh tests/invariants-spec-task-post.test.sh  # invariants-check.sh check 18 (the skill carries no posting form; spec-post.sh pins exactly two gh lines) fixtures (not yet required)
sh tests/spec-post.test.sh      # spec-post.sh post/hold/stop/response fixtures vs a stub gh (not yet required)
sh tests/spec-find.test.sh      # spec-find.sh projection fixtures (jq) and find/found/unreacted/none/ambiguous/moved/unreadable and pending fixtures vs a stub gh (not yet required)
sh tests/spec-fresh.test.sh     # spec-fresh.sh check/shape fixtures vs a scratch repo with a local bare origin; needs yq and git (not yet required)
sh tests/draft-identity.test.sh  # draft-identity.sh dev_app/not-dev-app/stored-login/unreadable fixtures vs a stub gh (not yet required)
sh tests/blocking-criteria.test.sh  # blocking-criteria.sh criterion projection, sanitizing, caps and the conventions.md worked example (not yet required)
sh tests/invariants-milestone-jq.test.sh  # invariants-check.sh check 19 (every milestone read projected, description reads go through blocking-criteria.sh) fixtures (not yet required)
sh tests/invariants-files-filter.test.sh  # invariants-check.sh check 20 (the pulls/<N>/files --jq filter reads a canned page of the endpoint) fixtures (not yet required)
sh tests/hitl-gate-closed.test.sh  # hitl-gate-closed.sh canonical closed form vs bare, OPEN, parked, appended clause, empty fixtures (not yet required)
sh tests/invariants-gh-pipe.test.sh  # invariants-check.sh check 11 (no gh output piped into a bin/ predicate) fixtures (not yet required)
sh tests/cursor-sync-pr.test.sh # resume's cursor-sync PR report predicate fixtures (not yet required)
sh tests/driver-lock.test.sh    # resume's driver-lock predicate fixtures (not yet required)
sh tests/gh-identity.test.sh    # gh-identity.sh user/App/unknown classification fixtures (not yet required)
sh tests/token-check.test.sh    # token-check.sh empty/expired/user/wrong-App/right-App token fixtures (not yet required)
sh tests/dev-token.test.sh      # .devcontainer/dev-token live/near-expiry/user/malformed token and credential-helper fixtures (not yet required)
sh tests/blocked-state.test.sh  # pr-checks' BLOCKED verdict predicate fixtures (lag, awaiting-approval, blocked) (not yet required)
sh tests/blocked-state-block.test.sh  # pr-checks' blocked-state and pinned-app shell blocks vs a stub gh (not yet required)
sh tests/prune-verdict.test.sh    # resume/archive-sprint prune: merged-tip-or-ancestor verdict fixtures (not yet required)
sh tests/auto-merge-arm.test.sh  # ship's auto-merge arm predicate fixtures (not yet required)
sh tests/app-push.test.sh      # app-push.sh App-mode pinned push and no-skill-pushes-unpinned fixtures (not yet required)
sh tests/stall-merge.test.sh    # pr-checks' stalled-auto-merge predicate fixtures (not yet required)
sh tests/review-step.test.sh    # review-step derive/decide predicate fixtures (not yet required)
sh tests/critic-section.test.sh  # critic-section PR-body section fixtures (not yet required)
sh tests/loop-baseline.test.sh  # scripts/loop/baseline.sh derivation fixtures on canned gh output (not yet required)
sh tests/loop-proxy.test.sh     # scripts/loop/proxy.py allow/deny fixtures (not yet required)
sh tests/loop-inject.test.sh    # scripts/loop/inject.py path and header fixtures (not yet required)
sh tests/loop-git-tools.test.sh # scripts/loop/git_tools.py fixed-tool fixtures, over MCP (not yet required)
sh tests/driver-core.test.sh   # scripts/loop/driver-core.sh tree copy, checks and commit, stub docker/gh (not yet required)
sh tests/loop-preflight.test.sh # scripts/loop/preflight.sh container and GitHub evaluator fixtures (not yet required)
sh tests/loop-critic.test.sh   # scripts/loop/critic.sh bundle, launch line and system/init check, stub claude (not yet required)
sh tests/identity-mint.test.sh  # scripts/identity/mint.sh JWT, request and failure fixtures, stub curl (not yet required)
sh tests/identity-wow.test.sh   # scripts/identity/wow-admin and wow-review-mint fixtures, stub curl (not yet required)
sh tests/identity-broker.test.sh  # scripts/identity/broker.ps1 dev-token rotation and install-host-tools.ps1 fixtures, stub minters; needs pwsh, skips without (not yet required)
sh tests/review-image.test.sh   # scripts/identity/review/ entrypoint, outbox-read, Dockerfile and build-context fixtures (not yet required)
sh tests/identity-review.test.sh  # scripts/identity/wow-review launcher fixtures vs stub docker, gh and wow-review-mint (not yet required)
```

`scripts/lint.sh` needs the `claude` CLI and `jq` on PATH. `scripts/invariants-check.sh` needs
`yq` (mikefarah v4) and `jq` on PATH too — it fails the gate, never skips it, when either is missing.
`tests/review-base-anchor.test.sh`, `tests/schema-complete.test.sh`, `tests/milestone-desc.test.sh`, `tests/spec-issue.test.sh`, `tests/spec-post.test.sh`, `tests/spec-fresh.test.sh` (which also needs `git`) and `tests/draft-identity.test.sh` need `yq` on PATH as
well (each skips itself, loudly, if absent). `tests/review-image.test.sh` needs `jq` and `yq`,
and skips itself loudly without them. `tests/invariants-files-filter.test.sh` needs `jq` on PATH
(the checker's check 20 does), and skips itself loudly without it.
