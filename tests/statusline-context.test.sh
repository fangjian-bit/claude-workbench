#!/bin/sh
# Fixture tests for the project statusLine in .claude/settings.json (#729): an inline jq
# command that prints `ctx NN%` from context_window.used_percentage, or `ctx --` when the value
# is null, absent, not a number or outside 0 to 100.
#
# Runs the REAL command text read out of settings.json with canned stdin. Needs jq on PATH
# (the command's own dependency); skips loudly without it.
#
# Permitted toolset: POSIX sh, jq.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
settings="$root_dir/.claude/settings.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "skip - statusline-context fixtures: no jq on PATH" >&2
  exit 0
fi

fail=0
assert_eq() {
  desc="$1"; expected="$2"; actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "ok - $desc"
  else
    echo "FAIL - $desc: expected [$expected], got [$actual]" >&2
    fail=1
  fi
}

type=$(jq -r '.statusLine.type' "$settings")
assert_eq "statusLine type is command" "command" "$type"
cmd=$(jq -r '.statusLine.command' "$settings")

run() { printf '%s' "$1" | sh -c "$cmd"; }

assert_eq "0 prints ctx 0%" "ctx 0%" "$(run '{"context_window":{"used_percentage":0}}')"
assert_eq "42.7 prints the integer part" "ctx 42%" "$(run '{"context_window":{"used_percentage":42.7}}')"
assert_eq "100 prints ctx 100%" "ctx 100%" "$(run '{"context_window":{"used_percentage":100}}')"
assert_eq "null prints ctx --" "ctx --" "$(run '{"context_window":{"used_percentage":null}}')"
assert_eq "an absent field prints ctx --" "ctx --" "$(run '{"context_window":{}}')"
assert_eq "an absent context_window prints ctx --" "ctx --" "$(run '{"model":{"id":"x"}}')"
assert_eq "a string prints ctx --" "ctx --" "$(run '{"context_window":{"used_percentage":"50"}}')"
assert_eq "a negative number prints ctx --" "ctx --" "$(run '{"context_window":{"used_percentage":-1}}')"
assert_eq "150 prints ctx --" "ctx --" "$(run '{"context_window":{"used_percentage":150}}')"
assert_eq "a non-object input prints ctx --" "ctx --" "$(run '"text"')"
assert_eq "no other field is printed" "ctx 7%" "$(run '{"cwd":"/x","model":{"id":"m"},"context_window":{"used_percentage":7.9}}')"

exit "$fail"
