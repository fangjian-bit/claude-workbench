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
On a PR touching `code_paths`, after `/way-of-working:ship`, the maintainer runs `wow-review`
on the host; a passing review from the reviewer App turns the `architect-review` status green, and until the follow-up so does one with no verdict line
(`.github/workflows/architect-review-gate.yml`, `WB-D37`). A PR touching nothing under `code_paths` is not gated.

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
bash scripts/test-all.sh        # every tests/*.test.sh, in parallel; its header carries the tool notes
```

`scripts/lint.sh` needs the `claude` CLI and `jq`. `scripts/invariants-check.sh` needs
`yq` (mikefarah v4) and `jq` on PATH — it fails the gate, never skips it, when either is missing.
