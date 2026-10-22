#!/bin/sh
# Fixture tests for scripts/invariants-check.sh's `--only <id>[,<id>...]` selector (#810).
#
# The selector exists so the tests/invariants-*.test.sh fixtures can run one check instead of all
# of them. What must hold: no argument runs every check; a malformed selection exits 2 and runs
# nothing (never a run of nothing that passes); an exported `only` cannot narrow a run, because
# the selector is an argument; and every check still runs on its own under `set -u`.
#
# The checker's messages and exit codes are asserted, and its source layout (the ids, the guards).
# The run-each-id-alone case needs yq, jq
# (checks 7 and 20) and git (check 9) and skips itself, loudly, without them.
#
# Permitted toolset: POSIX sh, awk, grep, sed and tr. No jq, no yq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/scripts/invariants-check.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
M1="cursor freshness compared by commit range"
M11="gh output is piped directly into a bin/ predicate script"
M18="the spec-task skill contains a posting form"
M22="a git/commits request sets an author or committer"
USAGE="usage: invariants-check.sh"

tree() {
  d="$tmp/$1"
  mkdir -p "$d"
  cp -R "$root_dir/plugins" "$d/plugins"
  echo "$d"
}

append() { printf '\n%s\n' "$2" >>"$1"; } # <file> <line(s)>

# A copy that breaks checks 1, 11, 18 and 22.
broken="$(tree broken)"
append "$(ls "$broken"/plugins/*/skills/resume/SKILL.md)" 'git diff last_commit..HEAD'
append "$(ls "$broken"/plugins/*/skills/pr-checks/SKILL.md)" 'gh api repos/x | blocked-state.sh BLOCKED 1'
append "$(ls "$broken"/plugins/*/skills/spec-task/SKILL.md)" 'gh issue comment 611 --body-file draft.md'
append "$(ls "$broken"/plugins/*/bin/api-commit.sh)" "jq -n '{message: \$m, author: {name: \$n}}' | gh api repos/o/r/git/commits --input -"

# run <dir> [env-prefix-free args...] -> merged stdout+stderr; the exit code lands in $rc.
run() {
  d="$1"; shift
  rc=0
  out="$( cd "$d" && bash "$script" "$@" 2>&1 )" || rc=$?
}

has() { printf '%s\n' "$out" | grep -qF -- "$1"; } # <message>

expect() { # <desc> <condition-result: 0 ok>
  if [ "$2" -eq 0 ]; then echo "ok - $1"; else echo "FAIL - $1" >&2; fail=1; fi
}

# --- a malformed selection exits 2, prints the usage line and runs no check ----------
bad() { # <desc> <args...>
  desc="$1"; shift
  run "$broken" "$@"
  ok=0
  [ "$rc" -eq 2 ] || ok=1
  has "$USAGE" || ok=1
  has "INVARIANT FAIL" && ok=1
  expect "$desc exits 2 with the usage line and runs no check" "$ok"
}
bad "--only with no value" --only
bad "--only with an empty value" --only ""
bad "a leading comma" --only ,11
bad "a trailing comma" --only 11,
bad "a doubled comma" --only 11,,18
bad "unknown id 0" --only 0
bad "unknown id 25" --only 25
bad "unknown id 2c" --only 2c
bad "a glob element" --only '*'
bad "an element with a leading space" --only ' 11'
bad "an element holding a space" --only '1 2'
bad "--only twice" --only 11 --only 18
bad "the --only= form" --only=11
bad "an unknown flag" --bogus
bad "a stray positional" 11
bad "a stray positional after --only" --only 11 extra

# --- the selection --------------------------------------------------------------------
run "$broken"
ok=0; [ "$rc" -eq 1 ] || ok=1
for m in "$M1" "$M11" "$M18" "$M22"; do has "$m" || ok=1; done
expect "no argument reports all four broken checks and exits 1" "$ok"

only_set=1 only=,11, run "$broken"
ok=0; [ "$rc" -eq 1 ] || ok=1
for m in "$M1" "$M11" "$M18" "$M22"; do has "$m" || ok=1; done
expect "an exported only_set=1 only=,11, does not narrow a no-argument run" "$ok"

run "$broken" --only 11
ok=0; [ "$rc" -eq 1 ] || ok=1
has "$M11" || ok=1
for m in "$M1" "$M18" "$M22"; do has "$m" && ok=1; done
expect "--only 11 reports check 11 only" "$ok"

run "$broken" --only 11,18
ok=0; [ "$rc" -eq 1 ] || ok=1
has "$M11" || ok=1; has "$M18" || ok=1
for m in "$M1" "$M22"; do has "$m" && ok=1; done
expect "--only 11,18 reports both and no other" "$ok"

run "$broken" --only 11,11
n="$(printf '%s\n' "$out" | grep -cF -- "INVARIANT FAIL: $M11" || true)"
ok=0; [ "$rc" -eq 1 ] || ok=1; [ "$n" -eq 1 ] || ok=1
expect "--only 11,11 runs check 11 once" "$ok"

# --- every declared id passes alone on the real tree, from the repository root --------
ids="$(sed -n 's/^ALL_IDS=(\(.*\))$/\1/p' "$script")"
if command -v yq >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 && command -v git >/dev/null 2>&1; then
  for id in $ids; do
    run "$root_dir" --only "$id"
    ok=0; [ "$rc" -eq 0 ] || ok=1
    has "Invariant check passed" || ok=1
    has "checks $id only" || ok=1
    expect "--only $id passes alone on the real tree" "$ok"
  done
else
  echo "SKIP - the run-each-id-alone case needs yq, jq and git on PATH" >&2
fi

# --- the headings, the declared list and the guards are one set, in place --------------
headings="$(sed -n 's/^# --- \([0-9][0-9]*b\{0,1\}\)\. .*/\1/p' "$script" | tr '\n' ' ')"
wants="$(sed -n 's/^if want \([0-9][0-9]*b\{0,1\}\); then$/\1/p' "$script" | tr '\n' ' ')"
declared="$(printf '%s ' $ids)"
ok=0
[ -n "$declared" ] || ok=1
[ "$headings" = "$declared" ] || ok=1
[ "$wants" = "$declared" ] || ok=1
expect "the headings, the declared list and the want guards are the same ids in the same order" "$ok"

# Each `if want <id>; then` line lies between its own heading and the next heading (the last one,
# before the closing `if [ "$fail" -ne 0 ]`).
bad_place="$(awk '
  /^# --- [0-9]+b?\. / { split($0, a, " "); id = a[3]; sub(/\.$/, "", id); cur = id; seen[cur] = 0; next }
  /^if want [0-9]+b?; then$/ { w = $3; sub(/;$/, "", w); if (w != cur || seen[cur]) print "misplaced " w; seen[cur] = 1; next }
  /^if \[ "\$fail" -ne 0 \]/ { cur = "" }
' "$script")"
[ -z "$bad_place" ] || printf '%s\n' "$bad_place" >&2
expect "each want guard sits between its own heading and the next" "$([ -z "$bad_place" ] && echo 0 || echo 1)"

[ "$fail" -eq 0 ] || exit 1
echo "all invariants-only fixtures passed"
