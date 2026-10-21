#!/bin/sh
# Fixture tests for scripts/invariants-check.sh's check 22: no file that names the git/commits
# endpoint sends it an `author` or `committer` field (#601, WB-D36).
#
# Each case copies the real plugin tree and adds a line to a copy, then asserts the check's own
# message fires (or stays silent). The safe_* cases are the other half: the shipped shape, a
# header comment that says "no author or committer", and a file that does not name the endpoint,
# must not fire.
#
# Only check 22's own message is asserted, never the script's overall exit.
#
# Every case but the first control runs just check 22 (`--only 22`); that control runs the full checker.
#
# Permitted toolset: POSIX sh. No jq, no yq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/scripts/invariants-check.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
MSG="a git/commits request sets an author or committer"

tree() {
  d="$tmp/$1"
  mkdir -p "$d"
  cp -R "$root_dir/plugins" "$d/plugins"
  echo "$d"
}

bin_in() { ls "$1"/plugins/*/bin/api-commit.sh; }
skill_in() { ls "$1"/plugins/*/skills/ship/SKILL.md; }
agent_in() { ls "$1"/plugins/*/agents/coder.md; }

sel="--only 22"

run() { ( cd "$1" && bash "$script" $sel 2>&1 >/dev/null ) || true; }

assert_fires() { # <desc> <dir>
  if run "$2" | grep -qF -- "$MSG"; then echo "ok - $1"
  else echo "FAIL - $1: expected [$MSG]" >&2; fail=1; fi
}

assert_silent() { # <desc> <dir>
  if run "$2" | grep -qF -- "$MSG"; then echo "FAIL - $1: unexpected [$MSG]" >&2; fail=1
  else echo "ok - $1"; fi
}

append() { printf '\n%s\n' "$2" >>"$1"; } # <file> <line(s)>

# --- control: the shipped tree ---------------------------------------------------
sel=
d="$(tree real)"
assert_silent "the shipped tree passes" "$d"
grep -q 'git/commits' "$(bin_in "$d")" || { echo "FAIL - api-commit.sh does not name git/commits, so the control proves nothing" >&2; fail=1; }
sel="--only 22"

# --- the defect, in each shape it can take ----------------------------------------
d="$(tree key)"
append "$(bin_in "$d")" "jq -n '{message: \$m, author: {name: \$n}}' | gh api repos/o/r/git/commits --input -"
assert_fires "author as a jq object key" "$d"

d="$(tree quoted)"
append "$(bin_in "$d")" "gh api repos/o/r/git/commits --input - <<< '{\"committer\" : {}}'"
assert_fires "committer as a quoted JSON key" "$d"

d="$(tree field)"
append "$(bin_in "$d")" 'gh api repos/o/r/git/commits -f message=x -f author[name]=bot'
assert_fires "author as a gh -f field" "$d"

d="$(tree sq)"
append "$(bin_in "$d")" "gh api repos/o/r/git/commits -f 'author[name]=bot'"
assert_fires "author as a single-quoted gh field" "$d"

d="$(tree bigf)"
append "$(bin_in "$d")" 'gh api repos/o/r/git/commits -F committer=bot'
assert_fires "committer as a gh -F field" "$d"

d="$(tree long)"
append "$(bin_in "$d")" 'gh api repos/o/r/git/commits --raw-field committer.name=bot'
assert_fires "committer as a --raw-field" "$d"

d="$(tree skill)"
append "$(skill_in "$d")" 'gh api repos/o/r/git/commits -f author=bot'
assert_fires "a skill, not only bin/" "$d"

d="$(tree agent)"
append "$(agent_in "$d")" 'gh api repos/o/r/git/commits -f committer=bot'
assert_fires "an agent file" "$d"

# --- the shapes that must stay quiet -----------------------------------------------
d="$(tree comment)"
append "$(bin_in "$d")" '# the commit carries no author: and no committer: field (#588 test 1)'
assert_silent "a whole-line comment naming the fields" "$d"

d="$(tree other)"
append "$(skill_in "$d")" 'git log --format=%an author: tests, committer: tests'
assert_silent "a file that does not name git/commits" "$d"

d="$(tree prose)"
append "$(bin_in "$d")" 'echo "no author or committer is set on git/commits"'
assert_silent "prose that names the fields without a key or a field flag" "$d"

exit "$fail"
