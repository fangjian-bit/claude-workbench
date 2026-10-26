#!/bin/sh
# Fixture tests for scripts/invariants-check.sh's check 26: every required check name in
# .ai/project.yml is a job's check run in .github/workflows/, and a matrix job backing one cannot
# be skipped (#1104).
#
# Each case mutates a COPY of the real files and asserts the check fires (or stays silent), so a
# check that only passes on the real tree cannot hide. Only check 26's own message is asserted,
# never the script's overall exit; a usage exit (2) fails the suite.
#
# Every case but the first control runs just check 26 (`--only 26`); that control runs the full checker.
#
# Permitted toolset: POSIX sh, sed, grep and yq (the fixtures edit YAML with it; the checker needs
# it too, so this test skips, loudly, without it). No jq, no python.
set -eu

command -v yq >/dev/null 2>&1 || { echo "SKIP - yq is not on PATH; check 26 cannot run" >&2; exit 0; }

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/scripts/invariants-check.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# One read of the checkout per run: every fixture copies from this, never from the root.
pristine="$tmp/.pristine"
mkdir -p "$pristine/.ai"
cp -R "$root_dir/plugins" "$pristine/plugins"
cp -R "$root_dir/.github" "$pristine/.github"
cp "$root_dir/.ai/project.yml" "$pristine/.ai/project.yml"

fail=0
MSG="a required check name is not a job's check run, or its matrix job can be skipped (#1104)"

tree() {
  d="$tmp/$1"
  mkdir -p "$d/.ai"
  cp -R "$pristine/plugins" "$d/plugins"
  cp -R "$pristine/.github" "$d/.github"
  cp "$pristine/.ai/project.yml" "$d/.ai/project.yml"
  echo "$d"
}

sel="--only 26"

run() { ( cd "$1" || exit 1; rc=0; bash "$script" $sel 2>&1 >/dev/null || rc=$?; [ "$rc" -ne 2 ] || : >"$tmp/usage-exit" ) || true; }

assert_fires() { # <desc> <dir> [<hit-line fragment>]
  out="$(run "$2")"
  if ! printf '%s\n' "$out" | grep -qF -- "$MSG"; then
    echo "FAIL - $1: expected check 26 to fire" >&2
    fail=1
  elif [ $# -ge 3 ] && ! printf '%s\n' "$out" | grep -qF -- "$3"; then
    echo "FAIL - $1: fired without the hit line '$3'" >&2
    fail=1
  else
    echo "ok - $1"
  fi
}

assert_silent() { # <desc> <dir>
  if run "$2" | grep -qF -- "$MSG"; then
    echo "FAIL - $1: check 26 fired" >&2
    fail=1
  else
    echo "ok - $1"
  fi
}

ci() { echo "$1/.github/workflows/ci.yml"; }
yml() { echo "$1/.ai/project.yml"; }
yqedit() { # <file> <program>
  yq -i "$2" "$1"
}

# Control: the real files are clean, under the full checker.
sel=
d="$(tree control)"
assert_silent "real files pass" "$d"
sel="--only 26"

d="$(tree renamed)"
yqedit "$(ci "$d")" '.jobs |= with_entries(select(.key == "tests-launchers") .key = "tests-launch")'
assert_fires "the tests-launchers job id renamed fires" "$d" 'required check tests-launchers'

d="$(tree fixedname)"
yqedit "$(ci "$d")" '.jobs.tests.name = "tests"'
assert_fires "the tests job given a fixed name fires" "$d" 'required check tests-1'

d="$(tree shard)"
yqedit "$(ci "$d")" '.jobs.tests.strategy.matrix.shard = [1, 3]'
assert_fires "shard values [1, 3] fire (tests-2 unreported)" "$d" 'required check tests-2'

d="$(tree jobif)"
yqedit "$(ci "$d")" '.jobs.tests.["if"] = "${{ always() && needs.changed-paths.outputs.cursor_only != '"'true'"' }}"'
assert_fires "a job-level if on the matrix job fires" "$d" 'other than always()'

d="$(tree noif)"
yqedit "$(ci "$d")" 'del(.jobs.tests.["if"])'
assert_fires "needs with no job-level if on the matrix job fires" "$d" 'declares needs and has no job-level if'

d="$(tree twokeys)"
yqedit "$(ci "$d")" '.jobs.tests.strategy.matrix.os = ["a", "b"]'
assert_fires "a second matrix key fires" "$d" 'required check tests-1'

d="$(tree include)"
yqedit "$(ci "$d")" '.jobs.tests.strategy.matrix.include = [{"shard": 3}]'
assert_fires "a matrix include (a second key) fires" "$d" 'required check tests-1'

d="$(tree twoexpr)"
yqedit "$(ci "$d")" '.jobs.tests.name = "tests-${{ matrix.shard }}-${{ matrix.shard }}"'
assert_fires "a name with two expressions fires (no reported name matches)" "$d" 'required check tests-1'

d="$(tree newline)"
yqedit "$(ci "$d")" '.jobs.tests.strategy.matrix.shard = ["1\n2", 2]'
assert_fires "a matrix value holding a newline fires" "$d" 'required check tests-1'

d="$(tree usesjob)"
yqedit "$(ci "$d")" '.jobs.tests-launchers.uses = "./.github/workflows/x.yml"'
assert_fires "a reusable-workflow job fires" "$d" 'required check tests-launchers'

d="$(tree nonstr)"
yqedit "$(yml "$d")" '.rulesets[0].required_checks += [5]'
assert_fires "a non-string required_checks entry fires" "$d" 'not a single-line string'

d="$(tree multiline)"
yqedit "$(yml "$d")" '.rulesets[0].required_checks += ["tests-1\ntests-2"]'
assert_fires "a multi-line required_checks entry fires" "$d" 'not a single-line string'

d="$(tree nonstrname)"
yqedit "$(ci "$d")" '.jobs.tests-launchers.name = 5'
assert_fires "a job with a non-string name fires" "$d" 'required check tests-launchers'

d="$(tree nullval)"
yqedit "$(ci "$d")" '.jobs.tests.strategy.matrix.shard = [1, 2, null]'
assert_fires "a null matrix value fires" "$d" 'required check tests-1'

d="$(tree extra)"
yqedit "$(yml "$d")" '.rulesets[0].required_checks += ["zzq-no-such-job"]'
assert_fires "an unreported name in .rulesets[0] fires" "$d" 'required check zzq-no-such-job'

d="$(tree extralegacy)"
yqedit "$(yml "$d")" '.ruleset.required_checks += ["zzq-no-such-job"]'
assert_fires "an unreported name in .ruleset fires" "$d" 'required check zzq-no-such-job'

d="$(tree gate)"
yqedit "$(yml "$d")" '.review.ci_gate.check = "something-else"'
assert_fires "architect-review no longer excluded fires" "$d" 'required check architect-review'

d="$(tree empty)"
yqedit "$(yml "$d")" '.rulesets[].required_checks = [] | .ruleset.required_checks = []'
assert_fires "both required_checks lists emptied fire" "$d" 'no required check names'

d="$(tree nowf)"
rm -f "$d"/.github/workflows/*
assert_fires "no workflow file fires" "$d" '(no .github/workflows/*.yml or *.yaml file found)'
assert_fires "no workflow file reports each required check as no job's run" "$d" "required check lint is no job's check run"

d="$(tree noyml)"
rm -f "$(yml "$d")"
assert_fires "a missing .ai/project.yml fires" "$d" '.ai/project.yml: missing'

d="$(tree badyml)"
printf 'a: [\n' >"$(yml "$d")"
assert_fires "an unparseable .ai/project.yml fires" "$d" '.ai/project.yml: unreadable'

d="$(tree launchname)"
yqedit "$(ci "$d")" '.jobs |= with_entries(select(.key == "tests-launchers") .key = "tests-launch") | .jobs.tests-launch.name = "tests-launchers"'
assert_silent "the tests-launchers job id renamed and given that name is silent" "$d"

d="$(tree bare)"
yqedit "$(ci "$d")" '.jobs.tests.["if"] = "always()"'
assert_silent "the matrix job's if written as bare always() is silent" "$d"

# yq missing: bash by absolute path, PATH one empty directory (the checker then exits 127 after
# its message, as cat is not there either; only the message is asserted).
d="$(tree noyq)"
bash_bin="$(command -v bash)"
mkdir -p "$tmp/emptybin"
noyq_out="$( ( cd "$d" || exit 1; rc=0; PATH="$tmp/emptybin" "$bash_bin" "$script" --only 26 2>&1 >/dev/null || rc=$?; [ "$rc" -ne 2 ] || : >"$tmp/usage-exit" ) || true )"
if printf '%s\n' "$noyq_out" | grep -qF -- "$MSG" && printf '%s\n' "$noyq_out" | grep -qF -- 'yq not found on PATH'; then
  echo "ok - check 26 fires when yq is not on PATH"
else
  echo "FAIL - check 26 fires when yq is not on PATH: expected it to fire" >&2
  fail=1
fi

[ ! -e "$tmp/usage-exit" ] || { echo "FAIL - the checker exited 2 (usage) in at least one case" >&2; fail=1; }

[ "$fail" -eq 0 ]
