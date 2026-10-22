#!/bin/sh
# Fixture tests for scripts/invariants-check.sh's check 24: the gate runs the checker with no
# argument (#874).
#
# Each case mutates a COPY of the real tree and asserts the check fires (or stays silent), so
# a check that only passes on the real tree cannot hide. Only check 24's own message is
# asserted, never the script's overall exit.
#
# A trailing comment after the path starts only at an ASCII space or tab then `#`, and one
# holding a quote is a hit; a whole-line comment counts only after
# ASCII spaces and tabs.
#
# The two U+2003 cases need a working C.UTF-8 and skip loudly without it.
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

em="$(printf '\342\200\203')"

d="$(tree qhash)"
printf '%s\n' 'jobs:' '  x:' '    steps:' '      - run: |' '          bash scripts/invariants-check.sh " #" || true' >"$d/.github/workflows/new.yml"
assert_fires "a quoted space-hash then || true fires" "$d"

d="$(tree qhash2)"
printf '%s\n' 'jobs:' '  x:' '    steps:' '      - run: |' "          bash scripts/invariants-check.sh ' #' || bash scripts/invariants-check.sh --only 1" >"$d/.github/workflows/new.yml"
assert_fires "a single-quoted space-hash then a narrowed call fires" "$d"

# Under a missing C.UTF-8 the tools fall back to C, where [[:space:]] never matches U+2003 and the
# pre-#917 checker fires on both lines too: the fixtures would guard nothing. Probe the two matchers
# the old code used (sed's bracket class, the bash glob) under the same locale before relying on them.
if (
  LC_ALL=C.UTF-8; export LC_ALL
  [ "$(printf 'a%s#b\n' "$em" | sed -E 's/[[:space:]]#.*$//')" = a ] &&
    bash -c 'case "$1" in [[:space:]]) exit 0 ;; *) exit 1 ;; esac' _ "$em"
) 2>/dev/null; then
  d="$(tree emhash)"
  printf '%s\n' 'jobs:' '  x:' '    steps:' '      - run: |' "          bash scripts/invariants-check.sh${em}# || true" >"$d/.github/workflows/new.yml"
  ( LC_ALL=C.UTF-8; export LC_ALL; assert_fires "a hash after U+2003 then || true fires" "$d"; [ "$fail" -eq 0 ] ) || fail=1

  d="$(tree emfirst)"
  printf '%s\n' 'jobs:' '  x:' '    steps:' '      - run: |' "          ${em}#|| true; bash scripts/invariants-check.sh --only 1" >"$d/.github/workflows/new.yml"
  ( LC_ALL=C.UTF-8; export LC_ALL; assert_fires "a line starting with U+2003 then a hash fires" "$d"; [ "$fail" -eq 0 ] ) || fail=1
else
  echo "skip - U+2003 fixtures (emhash, emfirst): [[:space:]] does not match U+2003 under LC_ALL=C.UTF-8 on this host (the locale is missing or does not class U+2003 as space)"
fi

[ ! -e "$tmp/usage-exit" ] || { echo "FAIL - the checker exited 2 (usage) in at least one case" >&2; fail=1; }

[ "$fail" -eq 0 ]
