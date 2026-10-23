#!/usr/bin/env bash
# Check that a PR title's Conventional Commits scope is a declared area (#839).
#
# Usage: bash scripts/pr-title-check.sh TITLE      (run from the repo root; reads ./CLAUDE.md)
# Exit:  0 pass, 1 fail, 2 usage (no argument, or more than one).
#
# Outcomes for a title:
#   - no scope (`type: subject`, `type!: subject`) passes: the spanning rule in
#     CLAUDE.md `## Areas` allows a title without a scope.
#   - a scope (`type(scope): subject`, optional `!` before the colon) passes when it is
#     exactly one of the declared areas, or is Dependabot's `ci(deps)` (type `ci`, scope
#     `deps`, the exception `## Areas` names). Any other scope fails, naming the scope
#     and listing every declared area.
#   - a malformed title fails with the expected shape. Malformed means not matching, as a
#     whole string: a lowercase-letter type, an optional parenthesized scope of lowercase
#     letters, digits and hyphens, an optional `!`, a colon, one space and a non-empty
#     subject; any ASCII control character (CR, LF and tab included) is malformed too.
#
# The area list is the first backtick span of each top-level `- ` bullet between the
# `## Areas` heading and the next level-2 heading of CLAUDE.md, the only source. When
# CLAUDE.md is missing, has no such heading or yields no area, the script fails closed;
# so it does for an area that does not fit the scope grammar (`[a-z0-9-]+`), which no
# title could ever use.
#
# No message echoes the title or its subject; the only part of it printed is a scope that
# passed the grammar, so no part of a title can start a workflow command in the job log.
# The title is matched with bash `[[ =~ ]]` against the whole string, not a line-oriented
# grep (see the comment on `version` in scripts/lint.sh for why).
set -eu
export LC_ALL=C

if [ "$#" -ne 1 ]; then
  echo "pr-title: usage: bash scripts/pr-title-check.sh TITLE" >&2
  exit 2
fi
title="$1"

areas=()
in_areas=0
if [ -f CLAUDE.md ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$in_areas" = 0 ]; then
      [ "$line" = "## Areas" ] && in_areas=1
      continue
    fi
    case "$line" in "## "*) break ;; esac
    if [[ "$line" =~ ^-\ [^\`]*\`([^\`]+)\` ]]; then
      areas+=("${BASH_REMATCH[1]}")
    fi
  done <CLAUDE.md
fi
if [ "${#areas[@]}" -eq 0 ]; then
  echo "pr-title: could not read the area list from the '## Areas' section of CLAUDE.md" >&2
  exit 1
fi
for a in "${areas[@]}"; do
  if ! [[ "$a" =~ ^[a-z0-9-]+$ ]]; then
    echo "pr-title: an area in the '## Areas' section of CLAUDE.md is not a valid scope (lowercase letters, digits and hyphens only)" >&2
    exit 1
  fi
done

shape='^([a-z]+)(\(([a-z0-9-]+)\))?(!)?: (.+)$'
if [[ "$title" == *[[:cntrl:]]* ]] || ! [[ "$title" =~ $shape ]]; then
  echo "pr-title: malformed title; expected 'type(scope): subject', 'type(scope)!: subject' or 'type: subject' (lowercase type, optional scope of lowercase letters, digits and hyphens)" >&2
  exit 1
fi

type="${BASH_REMATCH[1]}"
scope="${BASH_REMATCH[3]}"
[ -n "${BASH_REMATCH[2]}" ] || exit 0
if [ "$type" = ci ] && [ "$scope" = deps ]; then
  exit 0
fi
for a in "${areas[@]}"; do
  [ "$scope" = "$a" ] && exit 0
done
echo "pr-title: scope '$scope' is not a declared area; declared areas: ${areas[*]}" >&2
exit 1
