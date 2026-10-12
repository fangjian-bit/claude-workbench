#!/bin/sh
# Fixture tests for scripts/identity/broker.ps1 (issue #392).
#
# Stub mint.sh and wow-review-mint stand in for the real minters (their own suites cover them): they
# record their argv and write a canned token. A throwaway $WOW_HOME is laid out like the real one
# (apps.json with a "dev" entry, broker.json). The broker runs with -Once, one pass per case.
#
#   mint         no token -> minted for the dev installation, one repo, the dev permissions, written to
#                tokens/<repo>/dev-token; the staging file is gone
#   current      a token with more than 30 minutes left is left alone (mint never called)
#   rotation     a token with 10 minutes left, then an expired one, are replaced by the new token
#   failure      a failed mint, or one that yields a non-token or already-expired file, exits 1 and
#                keeps the old token untouched; no token text reaches stdout, stderr or broker.log
#   request      req/<repo>/reviewer-token is consumed and wow-review-mint gets the bare repo name and
#                nothing from the file; a directory of that name is ignored; a repo not in broker.json
#                is never served
#   survival     a repo whose token cannot be published (a directory in the way) is logged and exits 1;
#                the other repo is still minted
#   token shape  a CRLF token file, or one with a blank line, is not "current" and is replaced
#   gating       a request waits while the sandbox root (-SandboxRoot, else ${TMPDIR:-/tmp}/review-sandbox)
#                holds anything, and is served once it is empty
#   expiry       a reviewer-token file older than the TTL is removed, a recent one kept
#   registration -WhatIf: trailing backslash trimmed, no version-pinned Store pwsh path
#   config       a bad repo name (or a trailing dot) or a missing broker.json exits 2 before anything
#                is minted
#
# Permitted toolset: POSIX sh, its standard utilities and pwsh (skipped, loudly, if absent).
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v pwsh >/dev/null 2>&1; then
  echo "SKIP - pwsh not on PATH; identity-broker fixtures not run" >&2
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Native pwsh wants native paths; under MSYS that is cygpath -m, elsewhere the path as is.
wp() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }

scripts="$tmp/scripts" home="$tmp/home" stubdir="$tmp/stub"
mkdir "$scripts" "$home" "$stubdir"
cat >"$scripts/mint.sh" <<'STUB'
#!/bin/sh
printf '%s\n' "$@" >"$STUB_DIR/mint-argv"
echo called >>"$STUB_DIR/mint-calls"
while [ $# -gt 0 ]; do [ "$1" = --out ] && out=$2; shift; done
[ -z "${STUB_FAIL:-}" ] || { echo "mint.sh: GitHub answered HTTP 401: Bad credentials" >&2; exit 1; }
printf '%s\n%s\n' "$STUB_TOKEN" "$STUB_EXPIRES" >"$out"
STUB
cat >"$scripts/wow-review-mint" <<'STUB'
#!/bin/sh
printf '%s\n' "$@" >"$STUB_DIR/review-argv"
echo called >>"$STUB_DIR/review-calls"
STUB
cat >"$home/apps.json" <<'CONF'
{"dev": {"client_id": "Iv1devclient", "installation_id": "4242", "key": "dev.pem"}}
CONF
echo pem >"$home/dev.pem"
repos_ok='{"repos": ["alpha", "beta"]}'
echo "$repos_ok" >"$home/broker.json"

sh_path=$(wp "$(command -v sh)")
fresh=ghs_FRESHfreshFRESHfreshFRESHfreshFRESH0001
old=ghs_OLDoldOLDoldOLDoldOLDoldOLDoldOLDold00001
STUB_DIR=$stubdir; export STUB_DIR
STUB_TOKEN=$fresh; export STUB_TOKEN

stamp() { date -u -d "$1" +%Y-%m-%dT%H:%M:%SZ; }
live=$(stamp '+60 minutes')
STUB_EXPIRES=$live; export STUB_EXPIRES

fail=0
ok() { echo "ok - $1"; }
bad() { echo "FAIL - $1" >&2; fail=1; }
check() { # check <label> <command...>
  l=$1; shift
  if "$@"; then ok "$l"; else bad "$l"; fi
}

run_broker() { # leaves the exit code in $rc, output in $tmp/out
  rc=0
  pwsh -NoProfile -NonInteractive -File "$(wp "$root_dir/scripts/identity/broker.ps1")" \
    -WowHome "$(wp "$home")" -Sh "$sh_path" -ScriptsDir "$(wp "$scripts")" -Once >"$tmp/out" 2>&1 || rc=$?
}
reset() { rm -f "$stubdir"/*; rm -rf "$home/tokens" "$home/staging" "$home/req" "$home/broker.log"; echo "$repos_ok" >"$home/broker.json"; }
calls() { if [ -f "$stubdir/$1" ]; then wc -l <"$stubdir/$1" | tr -d ' '; else echo 0; fi; }
write_token() { # write_token <repo> <token> <expires>
  mkdir -p "$home/tokens/$1"; printf '%s\n%s\n' "$2" "$3" >"$home/tokens/$1/dev-token"
}
tokfile() { cat "$home/tokens/$1/dev-token" 2>/dev/null || true; }
expect_fresh() { printf '%s\n%s' "$fresh" "$live"; }

# --- mint ------------------------------------------------------------------------------------
reset; run_broker
check "mint: exits 0" test "$rc" -eq 0
check "mint: one mint per repo" test "$(calls mint-calls)" -eq 2
check "mint: alpha token and expiry written" test "$(tokfile alpha)" = "$(expect_fresh)"
check "mint: beta token and expiry written" test "$(tokfile beta)" = "$(expect_fresh)"
check "mint: staging file gone" test ! -e "$home/staging/alpha/dev-token"
argv=$(tr '\n' ' ' <"$stubdir/mint-argv")
case "$argv" in
  *"--client-id Iv1devclient"*"--installation-id 4242"*"--repos beta --perms contents=write,pull_requests=write,issues=write,checks=read,actions=read,statuses=read"*)
    ok "mint: dev App, one repo, dev permissions" ;;
  *) bad "mint: argv was $argv" ;;
esac
case "$argv" in *administration*) bad "mint: asked for administration" ;; *) ok "mint: no administration permission" ;; esac

# --- current ---------------------------------------------------------------------------------
reset
soon=$(stamp '+45 minutes')
write_token alpha "$old" "$soon"; write_token beta "$old" "$soon"
run_broker
check "current: exits 0" test "$rc" -eq 0
check "current: mint never called" test "$(calls mint-calls)" -eq 0
check "current: token untouched" test "$(tokfile alpha)" = "$old
$soon"

# --- rotation --------------------------------------------------------------------------------
reset
write_token alpha "$old" "$(stamp '+10 minutes')"; write_token beta "$old" "$(stamp '-5 minutes')"
run_broker
check "rotation: exits 0" test "$rc" -eq 0
check "rotation: expiring token replaced" test "$(tokfile alpha)" = "$(expect_fresh)"
check "rotation: expired token replaced" test "$(tokfile beta)" = "$(expect_fresh)"
check "rotation: both minted" test "$(calls mint-calls)" -eq 2

# --- failure ---------------------------------------------------------------------------------
reset
write_token alpha "$old" "$(stamp '+10 minutes')"; write_token beta "$old" "$(stamp '+10 minutes')"
before=$(tokfile alpha)
STUB_FAIL=1; export STUB_FAIL; run_broker; unset STUB_FAIL
check "failure: exits 1" test "$rc" -eq 1
check "failure: old token kept" test "$(tokfile alpha)" = "$before"
check "failure: error in the log" grep -q 'mint failed' "$home/broker.log"
for bad_token in notatoken ghs_short; do
  reset; write_token alpha "$old" "$(stamp '+10 minutes')"; before=$(tokfile alpha)
  STUB_TOKEN=$bad_token; run_broker; STUB_TOKEN=$fresh
  check "failure: $bad_token not published" test "$(tokfile alpha)" = "$before"
  check "failure: $bad_token exits 1" test "$rc" -eq 1
done
reset; write_token alpha "$old" "$(stamp '+10 minutes')"; before=$(tokfile alpha)
STUB_EXPIRES=$(stamp '-1 minutes'); run_broker; STUB_EXPIRES=$live
check "failure: already-expired mint not published" test "$(tokfile alpha)" = "$before"
for f in "$tmp/out" "$home/broker.log"; do
  if grep -q "$fresh\|$old" "$f"; then bad "secrecy: token text in $(basename "$f")"; else ok "secrecy: no token text in $(basename "$f")"; fi
done

# --- request ---------------------------------------------------------------------------------
reset
soon=$(stamp '+45 minutes')
write_token alpha "$old" "$soon"; write_token beta "$old" "$soon"
mkdir -p "$home/req/alpha" "$home/req/beta" "$home/req/gamma"
printf '%s\n' '--out /etc/evil; rm -rf /' >"$home/req/alpha/reviewer-token"
mkdir "$home/req/beta/reviewer-token"; echo keep >"$home/req/beta/reviewer-token/x"
echo x >"$home/req/gamma/reviewer-token"
run_broker
check "request: exits 0" test "$rc" -eq 0
check "request: consumed" test ! -e "$home/req/alpha/reviewer-token"
check "request: one reviewer mint" test "$(calls review-calls)" -eq 1
check "request: only the repo name is passed" test "$(cat "$stubdir/review-argv")" = alpha
check "request: directory of that name ignored" test -f "$home/req/beta/reviewer-token/x"
check "request: repo not in broker.json not served" test -f "$home/req/gamma/reviewer-token"
check "request: no dev mint needed" test "$(calls mint-calls)" -eq 0

# --- survival --------------------------------------------------------------------------------
reset
mkdir -p "$home/tokens/alpha/dev-token"   # unpublishable: a directory where the token file goes
run_broker
check "survival: failed repo exits 1" test "$rc" -eq 1
check "survival: the other repo is still minted" test "$(tokfile beta)" = "$(expect_fresh)"
check "survival: failure is logged" grep -q 'dev alpha' "$home/broker.log"

# --- token shape -----------------------------------------------------------------------------
reset
mkdir -p "$home/tokens/alpha" "$home/tokens/beta"
printf '%s\r\n%s\r\n' "$old" "$(stamp '+55 minutes')" >"$home/tokens/alpha/dev-token"
printf '%s\n\n%s\n' "$old" "$(stamp '+55 minutes')" >"$home/tokens/beta/dev-token"
run_broker
check "shape: CRLF token is replaced" test "$(tokfile alpha)" = "$(expect_fresh)"
check "shape: token with a blank line is replaced" test "$(tokfile beta)" = "$(expect_fresh)"

# --- request gating --------------------------------------------------------------------------
reset
soon=$(stamp '+45 minutes')
write_token alpha "$old" "$soon"; write_token beta "$old" "$soon"
mkdir -p "$home/req/alpha" "$tmp/sandbox"; echo x >"$tmp/sandbox/pr-1"
echo x >"$home/req/alpha/reviewer-token"
run_broker_extra() { rc=0
  pwsh -NoProfile -NonInteractive -File "$(wp "$root_dir/scripts/identity/broker.ps1")" \
    -WowHome "$(wp "$home")" -Sh "$sh_path" -ScriptsDir "$(wp "$scripts")" -Once "$@" >"$tmp/out" 2>&1 || rc=$?
}
run_broker_extra -SandboxRoot "$(wp "$tmp/sandbox")"
check "gating: a live review sandbox holds the request" test -f "$home/req/alpha/reviewer-token"
check "gating: no reviewer mint while it exists" test "$(calls review-calls)" -eq 0
rm "$tmp/sandbox/pr-1"; run_broker_extra -SandboxRoot "$(wp "$tmp/sandbox")"
check "gating: served once the sandbox is gone" test ! -e "$home/req/alpha/reviewer-token"
check "gating: then the reviewer mint runs" test "$(calls review-calls)" -eq 1

# The same gate with no -SandboxRoot and no REVIEW_SANDBOX_ROOT: the root is ${TMPDIR:-/tmp}/review-sandbox,
# resolved by sh in its MSYS form, exactly as review-sandbox.sh and review-token.sh resolve it.
reset
soon=$(stamp '+45 minutes')
write_token alpha "$old" "$soon"; write_token beta "$old" "$soon"
mkdir -p "$home/req/alpha" "$tmp/tmpd/review-sandbox"; echo x >"$tmp/tmpd/review-sandbox/pr-1"
echo x >"$home/req/alpha/reviewer-token"
rc=0
env -u REVIEW_SANDBOX_ROOT TMPDIR="$tmp/tmpd" pwsh -NoProfile -NonInteractive -File "$(wp "$root_dir/scripts/identity/broker.ps1")" \
  -WowHome "$(wp "$home")" -Sh "$sh_path" -ScriptsDir "$(wp "$scripts")" -Once >"$tmp/out" 2>&1 || rc=$?
check "gating: the default sandbox root is checked too" test -f "$home/req/alpha/reviewer-token"
check "gating: no reviewer mint under the default root" test "$(calls review-calls)" -eq 0
rm -f "$tmp/tmpd/review-sandbox/pr-1"
env -u REVIEW_SANDBOX_ROOT TMPDIR="$tmp/tmpd" pwsh -NoProfile -NonInteractive -File "$(wp "$root_dir/scripts/identity/broker.ps1")" \
  -WowHome "$(wp "$home")" -Sh "$sh_path" -ScriptsDir "$(wp "$scripts")" -Once >"$tmp/out" 2>&1 || rc=$?
check "gating: served once the default root is empty" test ! -e "$home/req/alpha/reviewer-token"

# --- reviewer token expiry -------------------------------------------------------------------
reset
write_token alpha "$old" "$soon"; write_token beta "$old" "$soon"
mkdir -p "$home/review-tokens/alpha" "$home/review-tokens/beta"
echo t >"$home/review-tokens/alpha/reviewer-token"; touch -d '-20 minutes' "$home/review-tokens/alpha/reviewer-token"
echo t >"$home/review-tokens/beta/reviewer-token"
run_broker
check "expiry: an old reviewer token file is removed" test ! -e "$home/review-tokens/alpha/reviewer-token"
check "expiry: a recent one is kept" test -e "$home/review-tokens/beta/reviewer-token"

# --- registration ----------------------------------------------------------------------------
reg=$(pwsh -NoProfile -NonInteractive -File "$(wp "$root_dir/scripts/identity/register-broker-task.ps1")" \
  -WowHome "$(wp "$home")\\" -Sh "$sh_path" -WhatIf 2>&1) || reg="failed: $reg"
case "$reg" in
  *'-WowHome "'*'/home" -Sh'*|*'-WowHome "'*'\home" -Sh'*) ok "register: trailing backslash trimmed from the command line" ;;
  *) bad "register: command line was $reg" ;;
esac
case "$reg" in *WindowsApps\\Microsoft.PowerShell_*) bad "register: version-pinned Store pwsh path recorded" ;; *) ok "register: no version-pinned Store pwsh path" ;; esac

# --- config ----------------------------------------------------------------------------------
reset
echo '{"repos": ["alpha."]}' >"$home/broker.json"
run_broker
check "config: trailing-dot name exits 2" test "$rc" -eq 2
echo "$repos_ok" >"$home/broker.json"
echo '{"repos": ["alpha", "../evil"]}' >"$home/broker.json"
run_broker
check "config: bad repo name exits 2" test "$rc" -eq 2
check "config: nothing minted" test "$(calls mint-calls)" -eq 0
rm "$home/broker.json"; run_broker
check "config: missing broker.json exits 2" test "$rc" -eq 2

[ "$fail" -eq 0 ] || exit 1
echo "all identity-broker fixtures passed"
