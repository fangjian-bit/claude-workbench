#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/leak-screen.sh (#914): the predicate retro runs over
# the transcript-reader's report. Every secret-shaped fixture is assembled at run time from a prefix
# and a body, so no token- or key-shaped string is committed.
# Permitted toolset: POSIX sh, grep, sed.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/plugins/way-of-working/bin/leak-screen.sh"
spec_post="$root_dir/plugins/way-of-working/bin/spec-post.sh"
outbox="$root_dir/plugins/way-of-working/bin/review-outbox.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok - $1"
  else
    echo "FAIL - $1: expected [$2], got [$3]" >&2
    fail=1
  fi
}

body="AbCdEfGhIjKlMnOpQrStUvWxYz0123"
# run <file>: stdout to $tmp/out, stderr to $tmp/err, status in $rc
run() {
  rc=0
  sh "$script" "$@" >"$tmp/out" 2>"$tmp/err" || rc=$?
}
# case_ <name> <expected stdout> <expected rc> <content...>: content is printf'd into a fixture
case_() {
  _name="$1"; _want="$2"; _wrc="$3"; shift 3
  printf '%s\n' "$@" >"$tmp/f.txt"
  run "$tmp/f.txt"
  assert_eq "$_name stdout" "$_want" "$(cat "$tmp/out")"
  assert_eq "$_name rc" "$_wrc" "$rc"
}

case_ "clean" "ok" 0 "see https://example.com/a/b" "short ghp_short token"
case_ "drive" "leak 1 drive" 1 "C:\\work\\x"
case_ "users" "leak 1 users" 1 "at /Users/someone/x"
case_ "home" "leak 1 home" 1 "at /home/someone/x"
case_ "appdata" "leak 1 appdata" 1 "in AppData here"
case_ "pem" "leak 1 pem" 1 "-----BEGIN""x"
case_ "token classic" "leak 1 token" 1 "t ghp""_$body"
case_ "token fine-grained" "leak 1 token" 1 "t github""_pat_$body"
case_ "anthropic" "leak 1 anthropic" 1 "k sk-""ant-$body"
case_ "tilde" "leak 1 tilde" 1 "see ~/.aws/x"
case_ "later line" "leak 3 home" 1 "a" "b" "/home/x"
case_ "order wins over line order" "leak 2 home" 1 "ghp""_$body" "/home/x"

run "$tmp/missing.txt"
assert_eq "missing stdout" "unreadable" "$(cat "$tmp/out")"
assert_eq "missing rc" "1" "$rc"

printf '%s\n' "/home/x" >"$tmp/-v"
(cd "$tmp" && rc=0 && sh "$script" -v >"$tmp/out" 2>"$tmp/err" </dev/null) || true
assert_eq "dash-leading name is read as a file" "leak 1 home" "$(cat "$tmp/out")"

run
assert_eq "no argument stdout" "" "$(cat "$tmp/out")"
assert_eq "no argument rc" "2" "$rc"

printf '%s\n' "x ghp""_$body" "/home/$body" >"$tmp/f.txt"
run "$tmp/f.txt"
assert_eq "one stdout line" "1" "$(wc -l <"$tmp/out" | tr -d ' ')"
if grep -qF "$body" "$tmp/out" "$tmp/err"; then bad=1; else bad=0; fi
assert_eq "no matched text on either stream" "0" "$bad"

# parity: spec-post.sh's six leak lines appear verbatim, and the anthropic fragment is review-outbox.sh's
for shape in drive users home appdata pem token; do
  line="$(grep "^leak $shape " "$spec_post")"
  if [ -n "$line" ] && grep -qxF "$line" "$script"; then ok=0; else ok=1; fi
  assert_eq "parity $shape" "0" "$ok"
done
if grep -qF 'sk-ant-[A-Za-z0-9_-]{20,}' "$outbox" && grep -qF "leak anthropic -E -e 'sk-ant-[A-Za-z0-9_-]{20,}'" "$script"; then ok=0; else ok=1; fi
assert_eq "parity anthropic" "0" "$ok"

[ "$fail" = 0 ] && echo "leak-screen: ok"
exit "$fail"
