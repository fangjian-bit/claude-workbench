#!/bin/sh
# Fixture tests for scripts/invariants-check.sh's check 20: the --jq filter on a
# `gh api` call to pulls/<N>/files reads the endpoint's array-per-page shape and projects
# f, p and s for every file (#698).
#
# Each case mutates a COPY of the real tree and asserts the check fires (or stays silent),
# so a check that only passes on the real tree cannot hide. Only check 20's own hit message
# is asserted, never the script's overall exit.
#
# Every case but the first control runs just check 20 (`--only 20`); that control runs the full checker.
#
# Permitted toolset: POSIX sh, no yq, no python. The checker this runs needs jq on PATH
# (check 20 does), so the test skips, loudly, without it.
set -eu

command -v jq >/dev/null 2>&1 || { echo "SKIP - jq is not on PATH; check 20 cannot run" >&2; exit 0; }

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/scripts/invariants-check.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
MSG="does not read the endpoint's page (#698)"
GOOD='.[] | {f: .filename, p: (.previous_filename // null), s: .status}'

tree() {
  d="$tmp/$1"
  mkdir -p "$d"
  cp -R "$root_dir/plugins" "$d/plugins"
  echo "$d"
}

sel="--only 20"

run() { ( cd "$1" || exit 1; rc=0; bash "$script" $sel 2>&1 >/dev/null || rc=$?; [ "$rc" -ne 2 ] || : >"$tmp/usage-exit" ) || true; }

assert_fires() { # <desc> <dir> [<reason substring>]
  out="$(run "$2")"
  if printf '%s\n' "$out" | grep -qF -- "$MSG" && { [ -z "${3:-}" ] || printf '%s\n' "$out" | grep -qF -- "$3"; }; then
    echo "ok - $1"
  else
    echo "FAIL - $1: expected check 20 to fire" >&2
    fail=1
  fi
}

assert_silent() { # <desc> <dir>
  if run "$2" | grep -qF -- "$MSG"; then
    echo "FAIL - $1: check 20 fired" >&2
    fail=1
  else
    echo "ok - $1"
  fi
}

skill() { ls "$1"/plugins/*/skills/"$2"/SKILL.md; }

# Replace the shipped filter text in architect-review with <new>, as a literal string.
swap() { # <dir> <new> [<old>]
  f="$(skill "$1" architect-review)"
  grep -qF -- "${3:-$GOOD}" "$f" || { echo "FAIL - the filter is not in architect-review as expected" >&2; fail=1; return; }
  NEW="$2" awk -v old="${3:-$GOOD}" '{
    n = index($0, old)
    if (n) $0 = substr($0, 1, n - 1) ENVIRON["NEW"] substr($0, n + length(old))
    print
  }' "$f" >"$f.new" && mv "$f.new" "$f"
}

# Control: the real tree is clean.
sel=
d="$(tree control)"
assert_silent "real tree passes" "$d"
sel="--only 20"

d="$(tree prefix)"
swap "$d" '{f: .filename, p: (.previous_filename // null), s: .status}'
assert_fires "the pre-fix object filter fires" "$d"

d="$(tree syntax)"
swap "$d" '.[] | {f: .filename, p: (.previous_filename // null'
assert_fires "a jq syntax error fires" "$d"

d="$(tree field)"
swap "$d" '.[] | {f: .name, p: (.previous_filename // null), s: .status}'
assert_fires "a wrong field name fires" "$d"

d="$(tree firsttwo)"
swap "$d" '.[:2][] | {f: .filename, p: (.previous_filename // null), s: .status}'
assert_fires "a filter that keeps only the first two files fires" "$d"

d="$(tree onevalue)"
swap "$d" '[.[] | {f: .filename, p: (.previous_filename // null), s: .status}]'
assert_fires "a filter that yields one value for the whole page fires" "$d"

d="$(tree dquote)"
swap "$d" "\"$GOOD\"" "'$GOOD'"
assert_fires "a double-quoted --jq argument fires" "$d"

d="$(tree removed)"
f="$(skill "$d" architect-review)"
grep -vF -- "$GOOD" "$f" >"$f.new" && mv "$f.new" "$f"
assert_fires "the line removed from architect-review fires" "$d"

# The same correct filter on another skill is held to the same output and passes.
d="$(tree other)"
f="$(skill "$d" ship)"
printf '%s\n' "  gh api --paginate \"repos/{repo}/pulls/<N>/files\" --jq '$GOOD' >\"\$T/f.jsonl\"" >>"$f"
assert_silent "the same filter on another skill stays silent" "$d"

# A correct call wrapped with a trailing backslash before --jq is joined and still checked.
d="$(tree wrapped)"
f="$(skill "$d" ship)"
printf '%s\n' "  gh api --paginate \"repos/{repo}/pulls/<N>/files\" \\" "    --jq '$GOOD'" >>"$f"
assert_silent "a wrapped correct call stays silent" "$d"

BROKEN='{f: .filename, p: (.previous_filename // null), s: .status}'

# The other skills are scanned too: a broken filter there fires, on one line and wrapped.
d="$(tree otherbad)"
f="$(skill "$d" ship)"
printf '%s\n' "  gh api --paginate \"repos/{repo}/pulls/<N>/files\" --jq '$BROKEN' >\"\$T/f.jsonl\"" >>"$f"
assert_fires "a broken filter on another skill fires" "$d"

d="$(tree wrappedbad)"
f="$(skill "$d" ship)"
printf '%s\n' "  gh api --paginate \"repos/{repo}/pulls/<N>/files\" \\" "    --jq '$BROKEN'" >>"$f"
assert_fires "a broken filter on a wrapped call fires" "$d"

d="$(tree dash)"
swap "$d" "-n"
assert_fires "a filter that starts with a dash fires" "$d" "starts with a dash"

d="$(tree noclose)"
swap "$d" "'.[] | {f: .filename" "'$GOOD'"
assert_fires "an unclosed single quote fires" "$d"

d="$(tree builtin)"
# Passes the jq compare on its own, so only the builtin refusal can catch it.
swap "$d" "$GOOD | debug"
assert_fires "a filter naming a refused builtin fires" "$d" "names a jq builtin"

d="$(tree noclose2)"
swap "$d" "'.[] | {f: .filename" "'$GOOD'"
assert_fires "an unclosed single quote is reported for that reason" "$d" "no closing single quote"

[ ! -e "$tmp/usage-exit" ] || { echo "FAIL - the checker exited 2 (usage) in at least one case" >&2; fail=1; }

exit "$fail"
