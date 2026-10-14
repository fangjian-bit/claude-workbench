#!/bin/sh
# Fixture tests for scripts/identity/broker.ps1 (issue #392).
#
# Stub mint.sh stands in for the real minter (its own suite covers it): it records its argv and writes a
# canned token. A throwaway $WOW_HOME is laid out like the real one (apps.json with a "dev" entry,
# broker.json). The broker runs with -Once, one pass per case.
#
#   mint         no token -> minted for the dev installation, one repo, the dev permissions, written to
#                tokens/<repo>/dev-token; the staging file is gone
#   current      a token with more than 30 minutes left is left alone (mint never called)
#   rotation     a token with 10 minutes left, then an expired one, are replaced by the new token
#   failure      a failed mint, or one that yields a non-token or already-expired file, exits 1 and
#                keeps the old token untouched; no token text reaches stdout, stderr or broker.log
#   survival     a repo whose token cannot be published (a directory in the way) is logged and exits 1;
#                the other repo is still minted
#   token shape  a CRLF token file, or one with a blank line, is not "current" and is replaced
#   expiry       a reviewer-token file older than the TTL is removed for any repo, a recent one kept
#   install      install-host-tools.ps1 exports committed files only into bin with a MANIFEST (commit, hashes),
#                refuses an uncommitted change or a HEAD not on origin/main, and creates tokens/<repo>;
#                register-broker-task.ps1 -WhatIf points the task at bin and installs nothing
#   no tool on PATH  with PATH holding only an empty directory and no -Sh, register-broker-task, broker
#                and install-host-tools each reach their own "no POSIX sh found" / "git not found" message,
#                never a null .Source error; broker never calls mint.sh and install creates no bin
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
reset() { rm -f "$stubdir"/*; rm -rf "$home/tokens" "$home/staging" "$home/broker.log"; echo "$repos_ok" >"$home/broker.json"; }
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

reset
mkdir -p "$home/review-tokens/gone-repo" "$home/review-tokens/alpha"
echo t >"$home/review-tokens/gone-repo/reviewer-token"; touch -d '-20 minutes' "$home/review-tokens/gone-repo/reviewer-token"
echo t >"$home/review-tokens/alpha/reviewer-token"   # recent
write_token alpha "$old" "$soon"; write_token beta "$old" "$soon"
run_broker
check "expiry: an old file is removed for a repo not in broker.json" test ! -e "$home/review-tokens/gone-repo/reviewer-token"
check "expiry: a recent file is kept" test -e "$home/review-tokens/alpha/reviewer-token"

# --- install-host-tools / register -----------------------------------------------------------
# A throwaway source repo with the host scripts committed on main, and a bare origin it is pushed to.
src="$tmp/src" origin="$tmp/origin.git"
git init -q -b main "$src" && git init -q --bare -b main "$origin"
mkdir -p "$src/scripts/identity"
for f in broker.ps1 mint.sh wow-common.sh wow-review-mint wow-admin register-broker-task.ps1 install-host-tools.ps1; do
  cp "$root_dir/scripts/identity/$f" "$src/scripts/identity/$f"
done
git -C "$src" -c user.name=t -c user.email=t@t add -A
git -C "$src" -c user.name=t -c user.email=t@t commit -q -m seed
git -C "$src" remote add origin "$(wp "$origin")"
git -C "$src" push -q origin main
head=$(git -C "$src" rev-parse HEAD)
run_install() { rc=0
  pwsh -NoProfile -NonInteractive -File "$(wp "$root_dir/scripts/identity/install-host-tools.ps1")" \
    -WowHome "$(wp "$home")" -SourceRepo "$(wp "$src")" "$@" >"$tmp/out" 2>&1 || rc=$?
}
has_cr() { [ "$(tr -cd '\015' <"$1" | wc -c | tr -d ' ')" -gt 0 ]; }
not_cr() { for p in "$@"; do ! has_cr "$p" || return 1; done; }
# A CRLF working tree (autocrlf) that git still reports clean: only a blob export keeps the install LF.
git -C "$src" config core.autocrlf true
rm -f "$src"/scripts/identity/*; git -C "$src" checkout -q -- scripts/identity
check "install setup: the source working tree really is CRLF" has_cr "$src/scripts/identity/mint.sh"
reset; rm -rf "$home/bin"
run_install
check "install: exits 0" test "$rc" -eq 0
check "install: broker and mint.sh land in bin" test -f "$home/bin/broker.ps1" -a -f "$home/bin/mint.sh"
check "install: MANIFEST records the commit" grep -q "^commit $head\$" "$home/bin/MANIFEST"
check "install: MANIFEST has one hash per file" test "$(grep -c '^[0-9a-f]\{64\}  ' "$home/bin/MANIFEST")" -eq 5
ok_hash=1
for f in broker.ps1 mint.sh wow-common.sh wow-review-mint wow-admin; do
  want=$(git -C "$src" cat-file blob "HEAD:scripts/identity/$f" | sha256sum | cut -d' ' -f1)
  grep -q "^$want  $f\$" "$home/bin/MANIFEST" || ok_hash=
  [ "$(sha256sum <"$home/bin/$f" | cut -d' ' -f1)" = "$want" ] || ok_hash=
done
check "install: every installed file is the committed blob" test -n "$ok_hash"
check "install: files are LF" not_cr "$home/bin/mint.sh" "$home/bin/wow-admin" "$home/bin/broker.ps1"
check "install: no staging left" test ! -e "$home/bin.new" -a ! -e "$home/bin.old"
check "install: tokens/<repo> created for each repo" test -d "$home/tokens/alpha" -a -d "$home/tokens/beta"
manifest=$(cat "$home/bin/MANIFEST")

echo '# dirty' >>"$src/scripts/identity/mint.sh"
run_install
check "install: an uncommitted change is refused" test "$rc" -ne 0
check "install: ...for that reason" grep -q 'uncommitted changes' "$tmp/out"
check "install: ...and bin is untouched" test "$(cat "$home/bin/MANIFEST")" = "$manifest"
git -C "$src" checkout -q -- scripts/identity/mint.sh

git -C "$src" -c user.name=t -c user.email=t@t commit -q --allow-empty -m unpushed
run_install
check "install: a HEAD not on origin/main is refused" test "$rc" -ne 0
check "install: ...for that reason" grep -q 'is not on origin/main' "$tmp/out"
check "install: ...and bin is untouched (unmerged)" test "$(cat "$home/bin/MANIFEST")" = "$manifest"
git -C "$src" branch origin/main   # a local branch named like the remote ref must not satisfy the check
run_install
check "install: a local branch named origin/main does not bypass it" test "$rc" -ne 0
check "install: ...still for that reason" grep -q 'is not on origin/main' "$tmp/out"
git -C "$src" branch -q -D origin/main
git -C "$src" reset -q --hard "$head"


rm -rf "$home/bin"
reg=$(pwsh -NoProfile -NonInteractive -File "$(wp "$root_dir/scripts/identity/register-broker-task.ps1")" \
  -WowHome "$(wp "$home")\\" -Sh "$sh_path" -SourceRepo "$(wp "$src")" -TaskName "wow-broker-test-$$" -WhatIf 2>&1) || reg="failed: $reg"
case "$reg" in
  *'-File "'*'bin\broker.ps1" -WowHome "'*'\home" -Sh'*) ok "register: runs the installed copy, trailing backslash trimmed" ;;
  *) bad "register: command line was $reg" ;;
esac
case "$reg" in *WindowsApps\\Microsoft.PowerShell_*) bad "register: version-pinned Store pwsh path recorded" ;; *) ok "register: no version-pinned Store pwsh path" ;; esac
check "register: -WhatIf installs nothing" test ! -e "$home/bin"

# --- no tool on PATH -------------------------------------------------------------------------
# PATH holds only an empty directory, pwsh is run by the absolute path resolved before that, and no -Sh is
# given: each script's own "not found" message must be reached, not a null .Source lookup.
pwsh_abs=$(command -v pwsh)
emptydir="$tmp/empty"; mkdir "$emptydir"
no_source_err() { ! cat "$tmp/out" "$home/broker.log" 2>/dev/null | grep -q "'Source' cannot be found"; }
broker_says_no_sh() { cat "$tmp/out" "$home/broker.log" 2>/dev/null | grep -q 'no POSIX sh found'; }
reset; rm -rf "$home/bin"; rc=0
PATH="$emptydir" "$pwsh_abs" -NoProfile -NonInteractive -File "$(wp "$root_dir/scripts/identity/register-broker-task.ps1")" \
  -WowHome "$(wp "$home")" -SourceRepo "$(wp "$src")" -TaskName "wow-broker-test-nopath-$$" -WhatIf >"$tmp/out" 2>&1 || rc=$?
check "no tool: register exits non-zero" test "$rc" -ne 0
check "no tool: register reports the missing sh" grep -q 'no POSIX sh found: pass -Sh' "$tmp/out"
check "no tool: register has no null .Source error" no_source_err
reset; rc=0
PATH="$emptydir" "$pwsh_abs" -NoProfile -NonInteractive -File "$(wp "$root_dir/scripts/identity/broker.ps1")" \
  -WowHome "$(wp "$home")" -ScriptsDir "$(wp "$scripts")" -Once >"$tmp/out" 2>&1 || rc=$?
check "no tool: broker exits 2" test "$rc" -eq 2
check "no tool: broker reports the missing sh" broker_says_no_sh
check "no tool: broker has no null .Source error" no_source_err
check "no tool: broker never calls mint.sh" test "$(calls mint-calls)" -eq 0
reset; rm -rf "$home/bin"; rc=0
PATH="$emptydir" "$pwsh_abs" -NoProfile -NonInteractive -File "$(wp "$root_dir/scripts/identity/install-host-tools.ps1")" \
  -WowHome "$(wp "$home")" -SourceRepo "$(wp "$src")" >"$tmp/out" 2>&1 || rc=$?
check "no tool: install exits non-zero" test "$rc" -ne 0
check "no tool: install reports the missing git" grep -q 'git not found on PATH' "$tmp/out"
check "no tool: install has no null .Source error" no_source_err
check "no tool: install creates no bin" test ! -e "$home/bin"

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
