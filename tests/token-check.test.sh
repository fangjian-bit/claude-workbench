#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/token-check.sh.
#
# #436 (WB-D24): every consumer of a minted token fails closed on an empty, expired, user or
# wrong-App token before acting, so `gh` never falls back to a human's stored login.
#
# Needs yq (mikefarah v4) for `verify` with an actor; skips those cases, loudly, when absent.
# Permitted toolset: POSIX sh.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/plugins/way-of-working/bin/token-check.sh"

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

run() {
  rc=0
  out=$(sh "$script" "$@" 2>"$tmp/err") || rc=$?
}
expect() { # expect <desc> <out> <rc>
  assert_eq "$1 (stdout)" "$2" "$out"
  assert_eq "$1 (rc)" "$3" "$rc"
}

tok=ghs_0123456789abcdefghijklmnopqrstuvwxyzABCD
mkfile() { printf '%s' "$2" >"$tmp/$1"; }
mkfile live "$tok
2999-01-01T00:00:00Z
"
mkfile expired "$tok
2000-01-01T00:00:00Z
"
mkfile empty ""
mkfile onlytoken "$tok
"
mkfile three "$tok
2999-01-01T00:00:00Z
extra
"
mkfile userpat "ghp_0123456789abcdefghijklmnopqrstuvwxyzABCD
2999-01-01T00:00:00Z
"
mkfile finegrained "github_pat_0123456789abcdefghijklmnopqrstuvwxyzABCD
2999-01-01T00:00:00Z
"
mkfile short "ghs_short
2999-01-01T00:00:00Z
"
mkfile badchar "ghs_0123456789abcdefghijklmnopqrstuvwxyz\$(id)
2999-01-01T00:00:00Z
"
printf '%s\r\n2999-01-01T00:00:00Z\r\n' "$tok" >"$tmp/crlf"
mkfile badtime "$tok
tomorrow
"
mkfile baddate "$tok
2999-99-99T99:99:99Z
"
mkfile badsec "$tok
2999-01-01T00:00:61Z
"
mkfile nolf "$tok
2999-01-01T00:00:00Z"
printf '%s\n2999-01-01T00:00:00Z\nextra' "$tok" >"$tmp/unterminated"
printf 'ghs_0123456789abcdefghijkl\001mnopqrstuvwxyzABCD\n2999-01-01T00:00:00Z\n' >"$tmp/ctl"
printf 'ghs_0123456789abcdefghijkl\0mnopqrstuvwxyzABCD\n2999-01-01T00:00:00Z\n' >"$tmp/nul"
mkdir "$tmp/dir"
ln -s live "$tmp/link" 2>/dev/null || cp "$tmp/live" "$tmp/link"

# -- file / token ---------------------------------------------------------------------
run file "$tmp/live"
expect "file: a live installation token" live 0
run file "$tmp/empty"
expect "file: empty" "" 2
run file "$tmp/expired"
expect "file: expired" "" 2
run file "$tmp/onlytoken"
expect "file: no expires_at line" "" 2
run file "$tmp/three"
expect "file: a third line" "" 2
run file "$tmp/unterminated"
expect "file: an unterminated third line" "" 2
run file "$tmp/userpat"
expect "file: a user token (ghp_)" "" 2
run file "$tmp/finegrained"
expect "file: a fine-grained user token" "" 2
run file "$tmp/short"
expect "file: a token too short" "" 2
run file "$tmp/badchar"
expect "file: a token with shell characters" "" 2
run file "$tmp/crlf"
expect "file: carriage returns" "" 2
run file "$tmp/badtime"
expect "file: expires_at is not a timestamp" "" 2
run file "$tmp/baddate"
expect "file: an impossible date" "" 2
run file "$tmp/badsec"
expect "file: seconds above 60" "" 2
run file "$tmp/ctl"
expect "file: a control character inside the token" "" 2
run file "$tmp/nul"
expect "file: a NUL byte inside the token" "" 2
run file "$tmp/nolf"
expect "file: second line without a newline is one line" "" 2
run file "$tmp/absent"
expect "file: missing" "" 2
run file "$tmp/dir"
expect "file: a directory" "" 2
if [ -L "$tmp/link" ]; then
  run file "$tmp/link"
  expect "file: a symlink" "" 2
fi
run file ""
expect "file: no path" "" 2
run file
expect "file: too few arguments" "" 2

run token "$tmp/live"
expect "token: prints line 1 only" "$tok" 0
run token "$tmp/expired"
expect "token: expired prints nothing" "" 2
run token "$tmp/empty"
expect "token: empty prints nothing" "" 2
if grep -q "$tok" "$tmp/err"; then
  echo "FAIL - token: a refusal echoed the token" >&2; fail=1
else
  echo "ok - token: a refusal never echoes the token"
fi

# -- verify ---------------------------------------------------------------------------
printf 'acme/other\nAcme/App\n' >"$tmp/inst"
: >"$tmp/inst-empty"
printf 'acme/other\n' >"$tmp/inst-wrong"
printf 'not a repo\n' >"$tmp/inst-bad"

run verify admin acme/app "$tmp/live" "$tmp/inst" /dev/null
expect "verify admin: installation reaches the repo" installation 0
run verify any acme/app "$tmp/live" "$tmp/inst" /dev/null
expect "verify any: installation only" installation 0
run verify dev_app acme/app "$tmp/live" "$tmp/inst" /dev/null
expect "verify dev_app without an actor is refused (exit code, not just a word)" "" 2
run verify reviewer_app acme/app "$tmp/live" "$tmp/inst" /dev/null
expect "verify reviewer_app without an actor is refused" "" 2
run verify loop_app acme/app "$tmp/live" "$tmp/inst" /dev/null
expect "verify loop_app without an actor is refused" "" 2
run verify any acme/app "$tmp/empty" "$tmp/inst" /dev/null
expect "verify: an empty token file" "" 2
run verify any acme/app "$tmp/expired" "$tmp/inst" /dev/null
expect "verify: an expired token file" "" 2
run verify any acme/app "$tmp/userpat" "$tmp/inst" /dev/null
expect "verify: a user token file" "" 2
run verify any acme/app "$tmp/live" "$tmp/inst-empty" /dev/null
expect "verify: empty installation records (a user token cannot list them)" "" 2
run verify any acme/app "$tmp/live" "$tmp/absent" /dev/null
expect "verify: no installation records" "" 2
run verify any acme/app "$tmp/live" "$tmp/inst-wrong" /dev/null
expect "verify: installation does not list the repo" "" 2
run verify any acme/app "$tmp/live" "$tmp/inst-bad" /dev/null
expect "verify: malformed installation records" "" 2
run verify bogus acme/app "$tmp/live" "$tmp/inst" /dev/null
expect "verify: unknown role" "" 2
run verify maintainer acme/app "$tmp/live" "$tmp/inst" /dev/null
expect "verify: a maintainer is not a token role" "" 2
run verify any acme/app "$tmp/live" "$tmp/inst"
expect "verify: too few arguments" "" 2
run verify admin acme/app "$tmp/live" "$tmp/inst" /dev/null acme-dev 1
expect "verify admin: an actor is refused" "" 2
run verify any acme/app "$tmp/live" "$tmp/inst" /dev/null acme-dev 1
expect "verify any: an actor is refused" "" 2
run verify dev_app acme/app "$tmp/live" "$tmp/inst" /dev/null acme-dev
expect "verify: an actor login without an id" "" 2

if ! command -v yq >/dev/null 2>&1; then
  echo "SKIP - yq not on PATH; token-check actor cases not run" >&2
else
  printf '%s\n' 'identities:
  maintainer:
    - { login: alice, id: 1001 }
  dev_app: { login: "acme-dev[bot]", id: 2001 }
  reviewer_app: { login: "acme-review[bot]", id: 2002 }
  loop_app: null' >"$tmp/full.yml"
  printf '%s\n' 'identities: null' >"$tmp/null.yml"
  printf '%s\n' 'repo: acme/x' >"$tmp/absent.yml"

  run verify dev_app acme/app "$tmp/live" "$tmp/inst" "$tmp/full.yml" 'acme-dev[bot]' 2001
  expect "verify: the right App" app 0
  run verify reviewer_app acme/app "$tmp/live" "$tmp/inst" "$tmp/full.yml" 'acme-review[bot]' 2002
  expect "verify: the right reviewer App" app 0
  run verify reviewer_app acme/app "$tmp/live" "$tmp/inst" "$tmp/full.yml" 'acme-dev[bot]' 2001
  expect "verify: the wrong App (dev where reviewer expected)" "" 2
  run verify dev_app acme/app "$tmp/live" "$tmp/inst" "$tmp/full.yml" 'acme-review[bot]' 2002
  expect "verify: the wrong App (reviewer where dev expected)" "" 2
  run verify dev_app acme/app "$tmp/live" "$tmp/inst" "$tmp/full.yml" alice 1001
  expect "verify: a maintainer is not the dev App" "" 2
  run verify dev_app acme/app "$tmp/live" "$tmp/inst" "$tmp/full.yml" stranger 9999
  expect "verify: an undeclared account" "" 2
  run verify dev_app acme/app "$tmp/live" "$tmp/inst" "$tmp/full.yml" 'acme-dev[bot]' 9999
  expect "verify: the dev login with another id" "" 2
  run verify loop_app acme/app "$tmp/live" "$tmp/inst" "$tmp/full.yml" 'acme-dev[bot]' 2001
  expect "verify: loop_app is declared null, so nothing matches it" "" 2
  run verify dev_app acme/app "$tmp/live" "$tmp/inst" "$tmp/null.yml" 'acme-dev[bot]' 2001
  expect "verify: identities null cannot declare an actor" "" 2
  run verify dev_app acme/app "$tmp/live" "$tmp/inst" "$tmp/absent.yml" 'acme-dev[bot]' 2001
  expect "verify: identities absent" "" 2
  run verify dev_app acme/app "$tmp/live" "$tmp/inst" "$tmp/nofile.yml" 'acme-dev[bot]' 2001
  expect "verify: unreadable project file" "" 2
  run verify dev_app acme/app "$tmp/live" "$tmp/inst" "$tmp/full.yml" 'acme-dev[bot]' abc
  expect "verify: a non-numeric actor id" "" 2
  run verify dev_app acme/app "$tmp/expired" "$tmp/inst" "$tmp/full.yml" 'acme-dev[bot]' 2001
  expect "verify: the right App with an expired token" "" 2
  run verify dev_app acme/app "$tmp/live" "$tmp/inst-wrong" "$tmp/full.yml" 'acme-dev[bot]' 2001
  expect "verify: the right App on a repo its installation lacks" "" 2
fi

run
expect "no subcommand" "" 2
run bogus
expect "unknown subcommand" "" 2

# -- never run from the cwd ---------------------------------------------------------------------
# A slash-less $0 could find a gh-identity.sh a branch under review planted in the cwd.
mkdir "$tmp/plant"
cp "$script" "$tmp/plant/token-check.sh"
printf '#!/bin/sh\ntouch "%s/marker"\necho reached\n' "$tmp/plant" >"$tmp/plant/gh-identity.sh"
rc=0
out="$(cd "$tmp/plant" && sh token-check.sh verify any acme/app "$tmp/live" "$tmp/inst" /dev/null 2>/dev/null)" || rc=$?
assert_eq "slash-less verify refuses (stdout)" "" "$out"
assert_eq "slash-less verify refuses (rc)" 2 "$rc"
assert_eq "slash-less verify never reached the planted gh-identity.sh" no "$([ -e "$tmp/plant/marker" ] && echo yes || echo no)"
rc=0
out="$(cd "$tmp/plant" && sh token-check.sh file "$tmp/live" 2>/dev/null)" || rc=$?
assert_eq "slash-less file refuses (stdout)" "" "$out"
assert_eq "slash-less file refuses (rc)" 2 "$rc"

if [ "$fail" -ne 0 ]; then exit 1; fi
echo "token-check: all assertions passed"
