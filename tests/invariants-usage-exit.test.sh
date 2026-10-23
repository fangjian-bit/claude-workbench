#!/bin/sh
# Fixture test for the usage-exit guard in every check-specific tests/invariants-*.test.sh:
# their run() helper keeps the checker's stderr and drops its exit status, so a checker that
# exits 2 with its usage line (a `sel` naming an id it does not have) would let every
# assert_silent case pass without running a check (#837). Each such file now leaves a marker
# on status 2 and fails at its end.
#
# One case per target: a scratch copy (taken from one pristine copy of plugins/, scripts/, .github/,
# .claude-plugin/ and .ai/project.yml, read from the checkout once) of those five and the target, every
# `sel="--only N"` line rewritten to id 0 (no checker id), run, and asserted to fail with the
# guard's line. A glob that finds no target fails too.
#
# Permitted toolset: POSIX sh, no yq, no python. The targets need jq on PATH
# (tests/invariants-files-filter.test.sh skips without it), so this test skips, loudly, without it.
set -eu

command -v jq >/dev/null 2>&1 || { echo "SKIP - jq is not on PATH; the targets cannot run" >&2; exit 0; }

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
self="$(basename "$0")"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# One read of the checkout per run: every target's scratch tree copies from this, never from the root.
pristine="$tmp/.pristine"
mkdir -p "$pristine/.ai"
cp -R "$root_dir/plugins" "$pristine/plugins"
cp -R "$root_dir/scripts" "$pristine/scripts"
cp -R "$root_dir/.github" "$pristine/.github"
cp -R "$root_dir/.claude-plugin" "$pristine/.claude-plugin"
cp "$root_dir/.ai/project.yml" "$pristine/.ai/project.yml"

fail=0
MSG="exited 2 (usage)"
n=0

for f in "$root_dir"/tests/invariants-*.test.sh; do
  name="$(basename "$f")"
  [ "$name" != "$self" ] || continue
  grep -q '^sel="--only ' "$f" || continue
  n=$((n + 1))
  d="$tmp/$name"
  mkdir -p "$d/tests"
  cp -R "$pristine/plugins" "$d/plugins"
  cp -R "$pristine/scripts" "$d/scripts"
  cp -R "$pristine/.github" "$d/.github"
  cp -R "$pristine/.claude-plugin" "$d/.claude-plugin"
  mkdir -p "$d/.ai"
  cp "$pristine/.ai/project.yml" "$d/.ai/project.yml"
  sed 's/^sel="--only .*/sel="--only 0"/' "$f" >"$d/tests/$name"
  rc=0
  out="$(cd "$d" && sh "tests/$name" 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -qF -- "$MSG"; then
    echo "ok - $name fails when the checker exits 2"
  else
    echo "FAIL - $name did not fail with '$MSG' on a usage exit (exit $rc)" >&2
    fail=1
  fi
done

if [ "$n" -eq 0 ]; then
  echo "FAIL - no tests/invariants-*.test.sh holding a sel=\"--only line was found" >&2
  fail=1
fi

exit "$fail"
