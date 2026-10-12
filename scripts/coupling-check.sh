#!/usr/bin/env bash
# The DRY gate: shared plugin code may never name a repo-specific value.
#
# Every literal shared plugin code needs is either a key in .ai/project.yml (see
# plugins/*/reference/project-schema.md) or it does not belong in the plugin at all.
# This check is the mechanical half of that rule -- it cannot prove a body is portable,
# but it catches the way portability actually rots: someone pastes a working command,
# a check name, or a repo name in from the repo they happen to be sitting in.
#
# Scope is every entry under plugins/*/ EXCEPT reference/, .claude-plugin/, and .git/ --
# a denylist, not an allowlist, so this loop fails closed for its one job: a new component
# (commands/, templates/, a root .mcp.json, whatever comes next) is scanned automatically
# the moment it exists, with no separate edit to this script required first.
# #49 was the allowlist version of this exact bug: hooks/ shipped and ran in every
# consuming repo for weeks, across several releases, before this check ever looked at it,
# because the loop only knew names that had been added to it by hand -- `skills agents`
# as first written, plus `bin` hand-added later in #21.
# `dotglob` is on below so the glob itself yields dot-directories -- without it,
# .claude-plugin/ would be skipped by the glob, not by the `case` arm that documents the
# skip, and the same silent gap would apply to any future dot-directory. reference/ is
# documentation about the contract and necessarily quotes concrete values --
# project-schema.md's worked examples are the whole point of it. Widening this to
# reference/ would make the schema doc unwritable. .claude-plugin/ is excluded for a
# different reason: it is plugin *metadata*, not executed code, and plugin.json's author
# field legitimately carries the org name that TIER2 matches -- scanning it would
# false-positive on correct content. .git/ is excluded so a plugin ever vendored as a
# nested clone doesn't fail on its own remote URL, which is exactly this kind of match on
# a directory that isn't plugin content at all. (It is defensive only: git refuses to
# commit any path with a .git component, so in CI this arm is unreachable. A *submodule*
# is not the case it covers -- a submodule's .git is a file, not a directory.)
#
# What this does NOT cover -- stated in full, because a gate's honest scope is part of
# the gate, and "everything else is handled" is the claim that stops people looking:
#   1. A file sitting directly in plugins/, outside any plugin directory (none today).
#   2. A symlink BELOW a component directory. `grep -r` follows a symlink only when it is
#      a command-line argument, so a symlinked SKILL.md at depth >= 2 is not read, while
#      Claude Code loading that skill would follow it. `-R` would close this; it is not
#      made here because it could not be verified on the authoring machine (no symlink
#      support) and an unverified change to a control is worse than a stated gap.
#   3. A plugin-root symlink to a directory, named like an exclusion. `[ -d ]` resolves
#      the link, so it takes the exclusion arm even though a symlink is not the
#      documentation/metadata/git directory the exclusion is justified by. `[ ! -L ]`
#      would close it, and is left unmade for the same reason as case 2.
#   4. An empty directory satisfies the per-plugin counter below without any content
#      being read -- git cannot commit one, but an unfetched submodule appears as one.
# What DOES fail closed: a plugin whose every entry is excluded, a plugins/ tree that is
# empty or missing, a wrong cwd, and a grep that errors rather than answering -- each
# fails the gate rather than reporting a pass over a tree this script did not read.
set -euo pipefail

# Tier 1 -- the sprint's acceptance pattern (SW Task 3). These are the specific literals
# the 7 skills and 4 agents actually carried before they were generalized.
#
# `architect-review` was a consuming repo's CHECK NAME, and since #90 it is also the name
# of a skill this plugin ships, so the bare token can no longer be the pattern: the
# invocation `way-of-working:architect-review`, the skills/architect-review/ path, and
# that skill's frontmatter `name: architect-review` are all legitimate. The pattern below
# matches the token unless the two characters before it are `:` + space (the frontmatter,
# and with it any `key: token` -- a YAML scalar, a pasted workflow step's `name:`, or prose
# ending in a colon) or the one before it is `:` or `/` -- and with `/` goes any path or
# URL whose last segment is the token, a consuming repo's `.github/workflows/<name>.yml`
# included. Those are the whole miss set, measured by running every 0-, 1- and
# 2-character printable prefix through the pattern.
# Everything else is caught: bare in prose, a shell argument
# (`review-gate-state.sh architect-review`), a jq expression, a `- ` list item, quotes,
# backticks, a derived job name, any indentation. Consequence to know: in plugin code the
# skill is written `/way-of-working:architect-review`, as every skill name is; the bare
# token in backticks reads as a check name to this gate, by design. Pinned by
# tests/coupling-check.test.sh, the `key: token` gap included.
CHECK_NAME="[^:/ ]architect-review|(^|[^:]) architect-review|^architect-review"
TIER1='hatch run|migration_roadmap|'"$CHECK_NAME"'|loop-orchestrator'

# Tier 2 -- every repo in the org, plus any emitter name the reference docs use as a worked
# example. A skill that names one of these is the same defect as tier 1, caught before it
# ships rather than after. `loop-orchestrator` is also matched by TIER1 (it predates this
# tier), but is listed here too so this tier's own membership rule is literally true on its
# own and doesn't silently depend on TIER1 never being pruned. Hand-maintained: WB-D14
# (docs/decisions.md) records the derive-vs-hand-maintain call; keep this list in sync
# with `gh repo list glunk-works`. Matched case-insensitively, in the TIER4 pass below.
TIER2='bounty-infra|global-bootstrap|scope-core|glunk-works|claude-workbench|bedrock-serverless-rag|pm-agent-loop|appsec-triage-agent|loop-engine|loop-orchestrator'

# Tier 3 -- structural literal SHAPES, not exact strings. SW Task 5 found that tiers 1-2
# match repo/org names and a curated string list but were blind to a hardcoded *path* that
# is not a repo name: the v0.1.0 skeleton carried `docs/migration_roadmap.md` and three
# `.ai/context/*.md` files, and "zero hits" proved only that no repo NAME leaked, not that
# the skills were portable. These patterns catch the shape of the two path literals that
# always have a schema-key home: a roadmap path is `{roadmap}`; a specific
# `.ai/context/<file>` either moved into this plugin's own reference/ or is the consuming
# repo's local truth, which a skill references as the bare directory, never a named file.
# A bare `.ai/context/` with no filename is a legitimate generic reference and is
# deliberately NOT matched.
#
# Check *names* are intentionally absent here. They appear legitimately in illustrative
# example output (see pr-checks' "Report shape" block, whose own prose says the real names
# come from {ruleset.required_checks}), so grepping them would false-positive on the
# examples. Check-name coupling is caught by a different mechanism instead: /way-of-working:resume and
# /way-of-working:pr-checks read {ruleset.required_checks} and report *inconclusive* on a mismatch rather
# than trusting a hardcoded list.
TIER3='docs/[A-Za-z_]+roadmap\.md|\.ai/context/[A-Za-z_]+\.(md|json)'

# Tier 4 -- the App identities of the orgs this repo is worked from, and the 603 org name.
# TIER2 names `glunk-works` (the org) but not the `glunk-<role>[bot]` logins of its GitHub
# Apps (`glunk-dev[bot]`, `glunk-review[bot]`): a critic on #476's PR (#528) found both in shared skill
# prose while this gate passed. The 603 Apps are `603id-<role>[bot]`, which shares no prefix
# with their org `603-Identity`, so the prefix and the org name are listed separately. A
# consuming repo's App logins live in .ai/project.yml (`identities`, and `orchestration.loop_identity` for the loop; null where unused),
# never in plugin code. A prefix, not a list of roles, so a newly minted App is covered
# without an edit; it is the orgs' own brand, which no portable plugin text has reason to
# carry. See #530.
#
# Matched case-INSENSITIVELY, in its own grep pass below, together with TIER2 and the
# maintainer's login: GitHub logins, org and repo names are case-insensitive and GHCR forces
# image paths lowercase, so `ghcr.io/603-identity/...` or `seuss27` pasted from a working
# command is the realistic leak. TIER1 and TIER3 stay case-sensitive (the tuned CHECK_NAME
# and path shapes would grow false positives). `603-?id(entity)?` covers `603id-<role>`, the
# org `603-Identity` and repos such as `603identity-site`. Not covered, stated: numeric App,
# client and installation ids, user logins (beyond the maintainer's, below), and separator or Unicode lookalikes (none is a
# real login, so only a deliberate evader writes one).
TIER4='glunk-[a-z0-9-]+|603-?id(entity)?'
LOGINS='Seuss27'

PATTERN_CS="${TIER1}|${TIER3}"
PATTERN_CI="${TIER2}|${TIER4}|${LOGINS}"

fail=0
scanned=0
plugins=0
shopt -s nullglob dotglob
for plugin_dir in plugins/*/; do
  # `.` and `..` only appear here on bash < 5.2, which has no `globskipdots`. Left
  # unhandled they would send `grep -r` up into the whole repo -- fail-closed, but it
  # would make the local run in CLAUDE.md permanently red on macOS's bash 3.2, and a
  # contributor debugging that is on the shortest path to "simplifying" this loop away.
  plugin_name="${plugin_dir%/}"
  case "${plugin_name##*/}" in .|..) continue ;; esac
  plugins=$((plugins + 1))
  plugin_scanned=0
  # `*`, not `*/`: files at a plugin's root are plugin content too. .mcp.json lives
  # there and carries MCP server commands, args and URLs -- exactly the "someone pastes
  # a working command in from the repo they happen to be sitting in" rot this gate
  # exists for. (hooks.json is NOT such a file: in this layout it sits inside hooks/,
  # which is scanned as a component directory.) `grep -r` takes a file argument as
  # happily as a directory one.
  for target in "${plugin_dir}"*; do
    # NOT `$(basename ...)`: command substitution strips trailing newlines, so a
    # directory whose name is "reference" followed by a newline would compare equal to
    # plain reference and be skipped -- the value checked would not be the value used.
    # A newline is a legal path character in git, so that is a committable gate bypass,
    # not a hypothetical.
    component="${target##*/}"
    # Excluded by name AND type. Each exclusion is justified by what the entry
    # *is* -- a documentation directory, a metadata directory, a git directory --
    # so a plugin-root FILE that merely carries one of those names is none of
    # those things and must be scanned like any other file. Matching on the name
    # alone was a green pass over unread content, the same bypass shape as the
    # trailing-newline one below. `.` and `..` are always directories.
    if [ -d "$target" ]; then
      case "$component" in
        reference|.claude-plugin|.git|.|..) continue ;;
      esac
    fi
    plugin_scanned=$((plugin_scanned + 1))
    scanned=$((scanned + 1))
    # grep exits 0 = matched, 1 = clean, >=2 = it could not do the job (unreadable file,
    # I/O error, bad regex). The old `if hits=$(grep ...)` form read >=2 as "clean" and
    # threw away any hits it had already found -- a gate that dies quietly reporting the
    # same "nothing to see" as a gate that passed. Same lesson invariants-check.sh names.
    # Two passes: TIER1 and TIER3 case-sensitive; TIER2, TIER4 and LOGINS case-insensitive.
    for pass in "-rnE|$PATTERN_CS" "-rniE|$PATTERN_CI"; do
      status=0
      hits=$(grep "${pass%%|*}" "${pass#*|}" "$target") || status=$?
      if [ "$status" -eq 0 ]; then
        echo "COUPLING FAIL: repo-specific literal in $target" >&2
        echo "$hits" >&2
        fail=1
      elif [ "$status" -ne 1 ]; then
        echo "COUPLING FAIL: grep exited $status on $target -- that is an error, not a clean" >&2
        echo "result. Refusing to report a pass over a tree this gate could not read." >&2
        fail=1
      fi
    done
  done
  if [ "$plugin_scanned" -eq 0 ]; then
    echo "COUPLING FAIL: nothing scannable in $plugin_dir -- every entry was excluded or it is empty." >&2
    echo "A plugin this gate never looked at must not be reported as a pass." >&2
    fail=1
  fi
done

# The per-plugin guard above cannot fire when there are no plugins at all.
if [ "$plugins" -eq 0 ]; then
  echo "COUPLING FAIL: found no plugin directories under plugins/*/ -- the tree is missing, empty, or this script is running from the wrong cwd. A gate that scans nothing and reports pass is the exact failure mode #49/#53 exist to close." >&2
  exit 1
fi

if [ "$fail" -ne 0 ]; then
  cat >&2 <<'EOF'

Shared plugin code names a repo-specific value. Two correct fixes, per
project-schema.md:
  1. Add a schema key and read it from .ai/project.yml (usually this one).
  2. The behavior was never portable -- move it back to being repo-local, out
     of the plugin.
"Override it locally in the consuming repo" is not a third option.

A third case is narrower than either: the sentence didn't need the value at
all. If it's descriptive prose rather than a behavior that varies per repo,
say the concept (e.g. "the plugin's source repo"), not the name.
EOF
  exit 1
fi

echo "Coupling check passed: scanned $scanned entries across $plugins plugin(s) under plugins/*/ (every entry except reference/, .claude-plugin/, .git/), no repo-specific literals found."
