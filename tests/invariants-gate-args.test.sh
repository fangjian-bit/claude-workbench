#!/bin/sh
# Fixture tests for scripts/invariants-check.sh's check 24: the gate runs the checker with no
# argument (#874).
#
# Each case mutates a COPY of the real tree and asserts the check fires (or stays silent), so
# a check that only passes on the real tree cannot hide. Only check 24's own message is
# asserted, never the script's overall exit.
#
# Every case but the first control runs just check 24 (`--only 24`); that control runs the full checker.
#
# Permitted toolset: POSIX sh. No jq, no yq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/scripts/invariants-check.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
MSG="carries an argument (#874)"

tree() {
  d="$tmp/$1"
  mkdir -p "$d/.ai"
  cp -R "$root_dir/plugins" "$d/plugins"
  cp -R "$root_dir/.github" "$d/.github"
  cp "$root_dir/.ai/project.yml" "$d/.ai/project.yml"
  echo "$d"
}

sel="--only 24"

run() { ( cd "$1" || exit 1; rc=0; bash "$script" $sel 2>&1 >/dev/null || rc=$?; [ "$rc" -ne 2 ] || : >"$tmp/usage-exit" ) || true; }

assert_fires() { # <desc> <dir>
  if run "$2" | grep -qF -- "$MSG"; then
    echo "ok - $1"
  else
    echo "FAIL - $1: expected check 24 to fire" >&2
    fail=1
  fi
}

assert_silent() { # <desc> <dir>
  if run "$2" | grep -qF -- "$MSG"; then
    echo "FAIL - $1: check 24 fired" >&2
    fail=1
  else
    echo "ok - $1"
  fi
}

# Append text after the path on every call line of a file.
suffix() { # <file> <text>
  sed "s|\(scripts/invariants-check\.sh\)\$|\1 $2|" "$1" >"$1.new" && mv "$1.new" "$1"
}

# Control: the real tree is clean, under the full checker.
sel=
d="$(tree control)"
assert_silent "real tree passes" "$d"
sel="--only 24"

d="$(tree comment)"
printf '%s\n' '# bash scripts/invariants-check.sh --only 1' >>"$d/.github/workflows/ci.yml"
assert_silent "a whole-line comment naming an argument is silent" "$d"

d="$(tree quoted)"
printf '%s\n' 'jobs:' '  x:' '    steps:' '      - run: "bash scripts/invariants-check.sh"' >"$d/.github/workflows/new.yml"
assert_silent "a quoted bare call is silent" "$d"

d="$(tree trailing)"
suffix "$d/.github/workflows/ci.yml" '# note'
assert_silent "a bare call with a trailing comment is silent" "$d"

d="$(tree ci)"
suffix "$d/.github/workflows/ci.yml" '--only 1'
assert_fires "an argument on the ci.yml call fires" "$d"

d="$(tree release)"
suffix "$d/.github/workflows/release.yml" '--bogus'
assert_fires "an argument on the release.yml call fires" "$d"

d="$(tree green)"
sed 's|bash scripts/invariants-check.sh }|bash scripts/invariants-check.sh --only 1 }|' "$d/.ai/project.yml" >"$d/p.new" && mv "$d/p.new" "$d/.ai/project.yml"
assert_fires "an argument on the gates.green entry fires" "$d"

d="$(tree eq)"
printf '%s\n' 'jobs:' '  x:' '    steps:' '      - run: bash scripts/invariants-check.sh --only=1' >"$d/.github/workflows/extra.yaml"
assert_fires "a --only= form in a .yaml workflow fires" "$d"

d="$(tree cont)"
printf '%s\n' 'jobs:' '  x:' '    steps:' '      - run: bash scripts/invariants-check.sh \' '          --only 1' >"$d/.github/workflows/new.yml"
assert_fires "a backslash continuation fires" "$d"

d="$(tree sq)"
printf '%s\n' 'jobs:' '  x:' '    steps:' "      - run: 'bash scripts/invariants-check.sh --only 1'" >"$d/.github/workflows/new.yml"
assert_fires "an argument inside single quotes fires" "$d"

d="$(tree dot)"
printf '%s\n' 'jobs:' '  x:' '    steps:' '      - run: ./scripts/invariants-check.sh 1' >"$d/.github/workflows/new.yml"
assert_fires "a ./-prefixed call with an argument fires" "$d"

d="$(tree nowf)"
rm -rf "$d/.github/workflows"
assert_fires "a copy with no workflows fires" "$d"

d="$(tree noyml)"
rm -f "$d/.ai/project.yml"
assert_fires "a copy with no project.yml fires" "$d"

[ ! -e "$tmp/usage-exit" ] || { echo "FAIL - the checker exited 2 (usage) in at least one case" >&2; fail=1; }

[ "$fail" -eq 0 ]
