#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/cursor-drift.sh.
#
# Each fixture is a throwaway git repo built in a tempdir so the assertions run
# against real git plumbing, not a mock of it -- the bug class this guards
# against (v0.3.0 SHA equality, v0.4.0 the commit-range form) was a wrong
# argument to real git commands, which only a real repo can catch. See issue #21
# and docs/decisions.md WB-D7.
#
# Permitted toolset: git, POSIX sh. No jq, no yq, no python. Plus bash, optionally,
# for the one shell-portability fixture -- skipped, loudly, where bash is absent or
# too old to know `lastpipe`; the script under test itself never needs it.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/plugins/way-of-working/bin/cursor-drift.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0

assert_eq() {
  desc="$1"
  expected="$2"
  actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "ok - $desc"
  else
    echo "FAIL - $desc: expected [$expected], got [$actual]" >&2
    fail=1
  fi
}

new_repo() {
  repo="$tmp/$1"
  git init -q "$repo"
  cd "$repo"
  git config user.email test@example.com
  git config user.name test
  git config core.autocrlf false
}

base_branch() {
  git symbolic-ref --short HEAD
}

# Build a repo where HEAD's tree differs from last_commit's by exactly the given
# paths, in the same squash-merge shape as the drift fixture below: last_commit
# is the tip of a work branch, a second commit on that branch writes the paths,
# and the branch squash-merges -- so last_commit is never an ancestor of HEAD.
# Sets $last for the caller's assertion.
squash_delta() {
  name="$1"
  new_repo "$name"
  shift
  base="$(base_branch)"
  echo a >a.txt && git add a.txt && git commit -qm "initial"
  git checkout -qb work
  echo work >a.txt && git add a.txt && git commit -qm "commit A: the work"
  last="$(git rev-parse HEAD)"
  for p in "$@"; do
    mkdir -p "$(dirname "$p")"
    echo x >"$p"
    git add "$p"
  done
  git commit -qm "commit B: $*"
  git checkout -q "$base"
  git merge --squash work -q >/dev/null
  git commit -qm "squash-merged"
  # Assert the shape rather than trust the construction: a later edit to this
  # helper that degraded it to a fast-forward would leave every fixture green
  # while proving nothing about squash-merge.
  if git merge-base --is-ancestor "$last" HEAD 2>/dev/null; then
    echo "FAIL - fixture invariant broken ($name): last_commit IS an ancestor of HEAD" >&2
    fail=1
  fi
}

# --- clean: last_commit IS HEAD --------------------------------------------
new_repo clean
echo a >a.txt && git add a.txt && git commit -qm a
last="$(git rev-parse HEAD)"
assert_eq "clean: last_commit == HEAD" "clean" "$("$script" "$last")"

# --- cursor-sync: the v0.4.0 regression fixture -----------------------------
# The actual bug needs TWO sequential squash-merges, not one -- a single squash
# of "the work + the cursor commit together" also satisfies the old buggy
# carve-out (`git rev-list --count <last_commit>..HEAD` == 1), so it proves
# nothing. The real shape: last_commit is recorded as the tip of a code branch
# (A) while its own PR is still open; that branch squash-merges first (A ->
# A', a new commit object A never becomes an ancestor of); only THEN does a
# separate cursor-sync commit (B, parent A') get its own squash-merge (B ->
# B'). At that point `git rev-list --count A..B'` is 2, not 1 -- the exact
# count the old carve-out required and did not get.
new_repo cursor-sync
base="$(base_branch)"
mkdir -p .ai
echo a >a.txt && git add a.txt && git commit -qm "initial"
git checkout -qb code
echo work >a.txt && git add a.txt && git commit -qm "commit A: the work"
last="$(git rev-parse HEAD)" # last_commit, captured while the code branch is still unmerged
git checkout -q "$base"
git merge --squash code -q >/dev/null
git commit -qm "squash-merged: code" # A -> A', a new commit object
git checkout -qb docs-sync
echo cursor >.ai/next-steps.md && git add .ai/next-steps.md && git commit -qm "commit B: cursor sync"
git checkout -q "$base"
git merge --squash docs-sync -q >/dev/null
git commit -qm "squash-merged: cursor sync" # B -> B', HEAD now
if git merge-base --is-ancestor "$last" HEAD 2>/dev/null; then
  echo "FAIL - fixture invariant broken: last_commit IS an ancestor of HEAD (squash-merge simulation is wrong)" >&2
  fail=1
fi
range_count="$(git rev-list --count "$last"..HEAD)"
if [ "$range_count" -le 1 ]; then
  echo "FAIL - fixture invariant broken: rev-list --count last_commit..HEAD is $range_count, not >1 -- this fixture would not have caught the v0.4.0 bug" >&2
  fail=1
fi
assert_eq "cursor-sync: only .ai/next-steps.md differs, last_commit not an ancestor" \
  "cursor-sync" "$("$script" "$last")"

# --- drift: negative control -- an unrelated file changed too --------------
new_repo drift
base="$(base_branch)"
mkdir -p .ai
echo a >a.txt && git add a.txt && git commit -qm "initial"
git checkout -qb work
echo work >a.txt && git add a.txt && git commit -qm "commit A: the work"
last="$(git rev-parse HEAD)"
echo cursor >.ai/next-steps.md
echo b >b.txt
git add .ai/next-steps.md b.txt && git commit -qm "commit B: cursor sync + unrelated file"
git checkout -q "$base"
git merge --squash work -q >/dev/null
git commit -qm "squash-merged"
assert_eq "drift: an unrelated path changed alongside the cursor" \
  "drift" "$("$script" "$last")"

# --- cursor-sync: the .ai/parked/ carve-out (issue #87) ---------------------
# /way-of-working:park-sprint's cursor-sync PR commits the parked snapshot
# beside (or instead of) the ledger. A parked file describes a DIFFERENT sprint
# and cannot invalidate the live next_action, so it is admitted; nothing else
# under .ai/ or anywhere else is.
squash_delta parked-only .ai/parked/s14-state.json .ai/parked/s14-next-steps.md
assert_eq "cursor-sync: only files under .ai/parked/ differ" \
  "cursor-sync" "$("$script" "$last")"

squash_delta parked-plus-ledger .ai/parked/s14-state.json .ai/next-steps.md
assert_eq "cursor-sync: .ai/parked/* plus .ai/next-steps.md" \
  "cursor-sync" "$("$script" "$last")"

squash_delta parked-plus-roadmap .ai/parked/s14-state.json docs/roadmap.md
assert_eq "drift: a roadmap file changed alongside a parked snapshot" \
  "drift" "$("$script" "$last")"

# A FILE at .ai/parked is `.ai/parked` with no trailing slash; it is not
# "under .ai/parked/" and the allowlist pattern must reject it.
squash_delta parked-as-file .ai/parked
assert_eq "drift: .ai/parked is a file, not a directory" \
  "drift" "$("$script" "$last")"

# The two edges the script's own comments assert, pinned: a sibling that
# merely shares the prefix, and a nested path under the directory.
squash_delta parked-sibling .ai/parked.md
assert_eq "drift: .ai/parked.md shares the prefix but is not under .ai/parked/" \
  "drift" "$("$script" "$last")"

squash_delta parked-nested .ai/parked/s14/state.json
assert_eq "cursor-sync: a nested path under .ai/parked/" \
  "cursor-sync" "$("$script" "$last")"

# core.quotePath regression: with git's default, a non-ASCII byte in the name
# makes --name-only emit ".ai/parked/caf\303\251.md" -- quoted -- which no
# allowlist pattern matches. The script pins quotePath off; this fixture would
# read drift if that pin were ever dropped.
squash_delta parked-non-ascii ".ai/parked/café-state.json"
assert_eq "cursor-sync: a non-ASCII parked filename is not quoted into drift" \
  "cursor-sync" "$("$script" "$last")"

# --- drift: a rename into .ai/parked/ also lists the path it left ------------
# With rename detection (git's default) the move below lists only
# .ai/parked/plan.md and would read cursor-sync; --no-renames adds docs/plan.md,
# outside the allowlist. The premise and the assertion both run with renames forced
# on through git's environment config, so the fixture exercises detection, and
# fails on a script that drops --no-renames, whatever the caller's git config says.
new_repo rename-into-parked
echo plan >docs-plan.tmp && mkdir docs && mv docs-plan.tmp docs/plan.md
mkdir -p .ai && echo cursor >.ai/next-steps.md
git add docs/plan.md .ai/next-steps.md && git commit -qm "plan and ledger"
last="$(git rev-parse HEAD)"
mkdir -p .ai/parked
git mv docs/plan.md .ai/parked/plan.md && git commit -qm "move plan into parked"
detected="$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=diff.renames GIT_CONFIG_VALUE_0=true \
  git diff --name-only "$last" HEAD)"
if [ "$detected" != ".ai/parked/plan.md" ]; then
  echo "FAIL - fixture invariant broken: rename detection did not list only the new path, got [$detected]" >&2
  fail=1
fi
assert_eq "drift: a file renamed into .ai/parked/ from outside the allowlist" \
  "drift" "$(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=diff.renames GIT_CONFIG_VALUE_0=true "$script" "$last")"

# --- shell portability: the drift verdict under a lastpipe shell -------------
# POSIX lets a shell run the last stage of a pipeline in the current
# environment (ksh93 does; bash does under `shopt -s lastpipe`). An `exit`
# inside the allowlist loop -- the form this fixture was added to catch, before
# it landed -- kills the whole script there: empty stdout, exit 1, on precisely
# the drift answer. Every other fixture invokes the script under `sh`, which
# cannot see that. Run the roadmap case once under bash with lastpipe on. Probe
# the CAPABILITY, not the binary: bash < 4.2 (stock macOS ships 3.2) rejects
# the option with exit 2 and never runs the script, which would read as a
# spurious FAIL pointing at the script. Skip, loudly, on such a machine.
if command -v bash >/dev/null 2>&1 && bash -O lastpipe -c true 2>/dev/null; then
  squash_delta lastpipe-drift .ai/parked/s14-state.json docs/roadmap.md
  out="$(bash -O lastpipe "$script" "$last")" && rc=0 || rc=$?
  assert_eq "lastpipe: drift verdict survives a current-environment pipeline stage" \
    "drift/0" "$out/$rc"
else
  echo "skip - lastpipe fixture: no bash with lastpipe support on PATH"
fi

# --- unreadable: last_commit is not an object git has -----------------------
new_repo unreadable
echo a >a.txt && git add a.txt && git commit -qm a
assert_eq "unreadable: last_commit is not a commit git has" \
  "unreadable" "$("$script" 0000000000000000000000000000000000dead)"

# --- unreadable: a revision name is never resolved (#1159) -------------------
# Each of these resolves to HEAD through ref lookup; none may read clean.
new_repo revision-names
base="$(base_branch)"
echo a >a.txt && git add a.txt && git commit -qm "first"
parent="$(git rev-parse HEAD)"
echo b >a.txt && git commit -qam "second"
head_full="$(git rev-parse HEAD)"
assert_eq "unreadable: HEAD" "unreadable" "$("$script" HEAD)"
assert_eq "unreadable: @" "unreadable" "$("$script" @)"
assert_eq "unreadable: the branch name" "unreadable" "$("$script" "$base")"
upper="$(printf '%s' "$head_full" | tr 'a-f' 'A-F')"
assert_eq "unreadable: HEAD's full id uppercased" "unreadable" "$("$script" "$upper")"
atag=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
git tag "$atag" HEAD
assert_eq "unreadable: a 64-hex-named tag pointing at HEAD" "unreadable" "$("$script" "$atag")"
short3="$(printf '%s' "$head_full" | cut -c1-3)"
assert_eq "unreadable: 3 characters of HEAD's id" "unreadable" "$("$script" "$short3")"
# The begins-with test: under SHA-1 git matches a 41-character value by its leading 40, so
# HEAD's id plus one more hex digit resolves to HEAD, and only that test refuses it.
if [ "${#head_full}" -eq 40 ]; then
  assert_eq "unreadable: HEAD's full id plus one extra hex digit" \
    "unreadable" "$("$script" "${head_full}0")"
fi
# The commit-type check: the abbreviation of exactly one object that is not a commit.
git tag -a -m t anntag HEAD
assert_eq "unreadable: an annotated tag's id" "unreadable" "$("$script" "$(git rev-parse anntag)")"
assert_eq "unreadable: a tree's id" "unreadable" "$("$script" "$(git rev-parse 'HEAD^{tree}')")"
assert_eq "unreadable: a blob's id" "unreadable" "$("$script" "$(git rev-parse HEAD:a.txt)")"
# git's own floor is 4 characters, so the 3-character value above is refused whatever this
# script does; the 4-character value below is what pins the script's own minimum (raise it
# to 5 and this fixture reads unreadable).
short4="$(printf '%s' "$head_full" | cut -c1-4)"
assert_eq "clean: 4 characters of HEAD's id" "clean" "$("$script" "$short4")"
short7="$(printf '%s' "$head_full" | cut -c1-7)"
assert_eq "clean: 7 characters of HEAD's id" "clean" "$("$script" "$short7")"
git tag "$short7" "$parent"
assert_eq "clean: the same 7 characters, with a tag of that name on HEAD's parent" \
  "clean" "$("$script" "$short7")"

# --- drift: the review shape's cursor, read from the base (WB-D22, `#283`) ---
# After a no-op handoff `last_commit` is the work branch's HEAD, and the checkout
# is switched to the base. The base lacks that work, so this script reads `drift`
# -- and must. That is why the review shape does not consult it: review-step.sh
# `decide` checks the cursor's own two fields agree on the pin instead. This
# fixture pins the premise the rule rests on (a work-branch last_commit read from
# the base is `drift`, never `clean` or `cursor-sync`), so the rule is not
# quietly dropped on the theory that the base would read clean.
new_repo review-shape
base="$(base_branch)"
echo a >a.txt && git add a.txt && git commit -qm "initial"
git checkout -qb work
echo work >a.txt && git add a.txt && git commit -qm "the work"
last="$(git rev-parse HEAD)"
assert_eq "review shape: last_commit is clean on the work branch it names" \
  "clean" "$("$script" "$last")"
git checkout -q "$base"
assert_eq "review shape: the same last_commit read from the base is drift" \
  "drift" "$("$script" "$last")"

exit "$fail"
