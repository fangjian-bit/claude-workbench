#!/bin/sh
# Fixture tests for scripts/invariants-check.sh's check 21: the three task-issue author readers
# (resume's SKILL.md, the coder agent and architect-review's SKILL.md) judge the author with
# `gh-identity.sh task-author`, never the old `gh-identity.sh author` (#664, WB-D32).
#
# Each case mutates a COPY of the real tree and asserts the check fires (or stays silent), so a
# check that only passes on the real tree cannot hide. Only check 21's own message is asserted,
# never the script's overall exit.
#
# Permitted toolset: POSIX sh. No jq, no yq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/scripts/invariants-check.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
MSG="a task-issue author reader is on the old verb, or a reader is missing"

tree() {
  d="$tmp/$1"
  mkdir -p "$d"
  cp -R "$root_dir/plugins" "$d/plugins"
  mkdir -p "$d/scripts/loop"
  cp "$root_dir/scripts/loop/preflight.sh" "$d/scripts/loop/preflight.sh"
  echo "$d"
}

run() { ( cd "$1" && bash "$script" 2>&1 >/dev/null ) || true; }

assert_fires() { # <desc> <dir>
  if run "$2" | grep -qF -- "$MSG"; then
    echo "ok - $1"
  else
    echo "FAIL - $1: expected check 21 to fire" >&2
    fail=1
  fi
}

assert_silent() { # <desc> <dir>
  if run "$2" | grep -qF -- "$MSG"; then
    echo "FAIL - $1: check 21 fired" >&2
    fail=1
  else
    echo "ok - $1"
  fi
}

# the three sites, relative to a tree
resume=plugins/way-of-working/skills/resume/SKILL.md
coder=plugins/way-of-working/agents/coder.md
arch=plugins/way-of-working/skills/architect-review/SKILL.md

d="$(tree control)"
assert_silent "the real tree passes" "$d"

for site in "$resume" "$coder" "$arch"; do
  name="$(basename "$(dirname "$site")")/$(basename "$site")"

  d="$(tree "old-$(printf '%s' "$name" | tr '/.' '__')")"
  printf '%s\n' 'Run `gh-identity.sh author "$LOGIN" "$ID" "$DEF_YML_FILE"` on it.' >>"$d/$site"
  assert_fires "$name naming gh-identity.sh author fires" "$d"

  d="$(tree "eol-$(printf '%s' "$name" | tr '/.' '__')")"
  printf '%s\n' 'Run gh-identity.sh author' >>"$d/$site"
  assert_fires "$name ending a line on gh-identity.sh author fires" "$d"

  d="$(tree "none-$(printf '%s' "$name" | tr '/.' '__')")"
  sed 's#gh-identity\.sh task-author#gh-identity.sh judge-author#g' "$d/$site" >"$d/$site.new" && mv "$d/$site.new" "$d/$site"
  assert_fires "$name without gh-identity.sh task-author fires" "$d"

  d="$(tree "gone-$(printf '%s' "$name" | tr '/.' '__')")"
  rm -f "$d/$site"
  assert_fires "a missing $name fires" "$d"
done

# `task-author` and a word that merely begins with `author` do not match the old-verb pattern.
d="$(tree wordok)"
printf '%s\n' 'See gh-identity.sh task-author, and gh-identity.sh author-ish words are not the verb.' >>"$d/$resume"
assert_silent "task-author and an author-prefixed word are silent" "$d"

[ "$fail" -eq 0 ]
