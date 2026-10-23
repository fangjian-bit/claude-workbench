#!/bin/sh
# Fixture tests for scripts/identity/wow-review-poll, the host poller that launches wow-review (#626).
#
# The poller runs from a fake installed bin/ (the poller, wow-common.sh, the plugin's token-check.sh,
# gh-identity.sh and review-gate-state.sh, a stub wow-review-mint and a stub wow-review that records
# its argv and exits with a per-case code). Stub gh and docker go first on PATH; the stub gh answers
# from per-case fixture files and records every call. stdin is closed throughout, to prove nothing
# prompts.
#
# Permitted toolset: POSIX sh and its standard utilities, jq and yq (skipped, loudly, if absent).
set -u

root_dir="$(cd "$(dirname "$0")/.." && pwd)"

for t in jq yq timeout; do
  if ! command -v "$t" >/dev/null 2>&1; then
    echo "SKIP - $t not on PATH; wow-review-poll fixtures not run" >&2
    exit 0
  fi
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
ok() { printf 'ok - %s\n' "$1"; }
bad() { printf 'FAIL - %s\n' "$1" >&2; fail=1; }
check() { # check <label> <command...>
  l=$1; shift
  if "$@"; then ok "$l"; else bad "$l"; fi
}
assert_eq() { # assert_eq <label> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: expected [$2], got [$3]"; fi
}
has() { grep -qF -- "$2" "$1" 2>/dev/null; }   # has <file> <fixed string>
lines() { if [ -f "$1" ]; then wc -l <"$1" | tr -d ' '; else echo 0; fi; }

stubs="$tmp/stubs"
mkdir "$stubs"

# --- the stubs -----------------------------------------------------------------------------
cat >"$stubs/docker" <<'STUB'
#!/bin/sh
exit 0
STUB

cat >"$stubs/gh" <<'STUB'
#!/bin/sh
S=$STUB_DIR
method= jqx= path= host=
shift
while [ $# -gt 0 ]; do
  case $1 in
    --hostname) host=$2; shift ;;
    --paginate) ;;
    -H) shift ;;
    --jq) jqx=$2; shift ;;
    -X) method=$2; shift ;;
    -f|-F|--field|--raw-field|--input) echo "$1" >>"$S/gh.bad" ;;
    *) path=$1 ;;
  esac
  shift
done
for v in GH_HOST GH_ENTERPRISE_TOKEN GITHUB_TOKEN GITHUB_ENTERPRISE_TOKEN; do
  eval "x=\${$v:-}"; [ -z "$x" ] || echo "$v set" >>"$S/gh.bad"
done
[ -n "${GH_TOKEN:-}" ] || echo "empty GH_TOKEN for $path" >>"$S/gh.bad"
[ "$host" = github.com ] || echo "host [$host] for $path" >>"$S/gh.bad"
printf '%s|%s|%s\n' "$method" "$path" "$jqx" >>"$S/gh.calls"
if [ "$method" = DELETE ] && [ "$path" = installation/token ]; then
  printf '%s\n' "$GH_TOKEN" >>"$S/revoked"
  exit 0
fi
fx="$S/gh/$(printf '%s' "$path" | tr '/?#=&' '_____')"
if [ -e "$fx.fail" ]; then echo "HTTP 500" >&2; exit 1; fi
if [ ! -e "$fx" ]; then echo "HTTP 404 $path" >&2; exit 1; fi
if [ -n "$jqx" ]; then jq -r "$jqx" <"$fx"; else cat "$fx"; fi
STUB

cat >"$stubs/wow-review-mint" <<'STUB'
#!/bin/sh
S=$STUB_DIR
n=$(( $(cat "$S/mint.n" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$S/mint.n"
echo "$n $*" >>"$S/mint.calls"
out= prev=
for a in "$@"; do [ "$prev" != --out ] || out=$a; prev=$a; done
[ ! -e "$S/mint.fail.$1" ] || exit 1
tok=$(printf 'ghs_Tokenxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx%03d' "$n")
printf '%s\n2999-01-01T00:00:00Z\n' "$tok" >"$out"
echo "$tok" >>"$S/mint.tokens"
STUB

cat >"$stubs/wow-review" <<'STUB'
#!/bin/sh
S=$STUB_DIR
echo "$*" >>"$S/review.calls"
[ -n "${WOW_HOME:-}" ] || echo "no WOW_HOME" >>"$S/review.bad"
key=$(printf '%s' "$*" | tr '/ ' '__')
echo "wow-review ran for $*"
[ ! -f "$S/hook.sh" ] || sh "$S/hook.sh"
if [ -e "$S/review.rc.$key" ]; then exit "$(cat "$S/review.rc.$key")"; fi
exit "$(cat "$S/review.rc.default" 2>/dev/null || echo 0)"
STUB
chmod +x "$stubs/docker" "$stubs/gh" "$stubs/wow-review-mint"

# --- a case: a fresh $WOW_HOME, bin/ and stub directory -------------------------------------
SHA1=1111111111111111111111111111111111111111
SHA2=2222222222222222222222222222222222222222
SHA3=3333333333333333333333333333333333333333
orig_path=$(printf '%s\n' "$PATH" | tr ':' '\n' | grep -v '^/mnt/' | paste -sd: -)

# mkrepo <owner> <name>: an installation that reaches it, an App-mode gated project.yml, no PRs
mkrepo() {
  g="$STUB/gh"; p="repos_$1_$2"
  printf '{"repositories":[{"full_name":"o/r"},{"full_name":"o2/r2"}]}\n' >"$g/installation_repositories"
  cat >"$g/${p}_contents_.ai_project.yml" <<YML
identities:
  maintainer: [{login: maint, id: 11}]
  reviewer_app: {login: "glunk-review[bot]", id: 4242}
review:
  ci_gate:
    check: gate
YML
  printf '[]\n' >"$g/${p}_pulls_state_open"
  printf '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"ci"},{"context":"gate"}]}}]\n' >"$g/${p}_rules_branches_main"
}

new_case() {
  rm -rf "$tmp/case"
  home="$tmp/case/home"; STUB="$tmp/case/stub"; export STUB
  mkdir -p "$home/bin" "$STUB/gh"
  cp "$root_dir/scripts/identity/wow-review-poll" "$root_dir/scripts/identity/wow-common.sh" "$home/bin/"
  for f in token-check.sh gh-identity.sh review-gate-state.sh; do cp "$root_dir/plugins/way-of-working/bin/$f" "$home/bin/"; done
  cp "$stubs/wow-review-mint" "$stubs/wow-review" "$home/bin/"
  : >"$STUB/gh.calls"; : >"$STUB/mint.calls"; : >"$STUB/review.calls"
  printf '{"repos": ["o/r"]}\n' >"$home/review-poll.json"
  mkrepo o r
}

# addpr <owner> <name> <N> <sha> <draft> <ci-conclusion|inprogress> <gate-conclusion|none>
addpr() {
  g="$STUB/gh"; p="repos_$1_$2"
  jq --argjson n "$3" --arg sha "$4" --argjson d "$5" \
    '. + [{number: $n, draft: $d, head: {sha: $sha}, base: {ref: "main"}, title: "T", body: "B", user: {login: "someone"}}]' \
    "$g/${p}_pulls_state_open" >"$g/x" && mv "$g/x" "$g/${p}_pulls_state_open"
  runs='[]'
  case $6 in
    inprogress) runs=$(printf '%s' "$runs" | jq -c '. + [{name:"ci",status:"in_progress",conclusion:null}]') ;;
    *) runs=$(printf '%s' "$runs" | jq -c --arg c "$6" '. + [{name:"ci",status:"completed",conclusion:$c}]') ;;
  esac
  case $7 in
    none) ;;
    *) runs=$(printf '%s' "$runs" | jq -c --arg c "$7" '. + [{name:"gate",status:"completed",conclusion:$c}]') ;;
  esac
  printf '{"statuses":[]}\n' >"$g/${p}_commits_$4_status"
  printf '{"check_runs":%s}\n' "$runs" >"$g/${p}_commits_$4_check-runs"
}

runp() { # runp <args...>: the poller from the fake bin, stdin closed, the stubs first on PATH
  rc=0
  env PATH="$stubs:$orig_path" STUB_DIR="$STUB" WOW_HOME="$home" sh "$home/bin/wow-review-poll" "$@" <&- >"$tmp/out" 2>"$tmp/err" || rc=$?
}
reviews() { lines "$STUB/review.calls"; }
log="review-poll.log"

# runw <WOW_HOME value>: the poller with that WOW_HOME and, when a drive-letter value is given, a stub
# cygpath (in its own directory, outside $tmp/case) ahead of the shared stubs, the way a Windows host has one
runw() {
  rc=0; cyg="$tmp/cygstub"; rm -rf "$cyg"; mkdir "$cyg"; wv=$1
  case $wv in
    [A-Za-z]:*)
      cat >"$cyg/cygpath" <<STUB
#!/bin/sh
case \$1 in
  -u) [ "\$2" = '$(printf '%s' "$wv" | sed "s/'/'\\\\''/g")' ] || exit 1; printf '%s\\n' '$home' ;;
  -m) printf '%s\\n' "\$2" ;;
  *) exit 1 ;;
esac
STUB
      chmod +x "$cyg/cygpath" ;;
  esac
  env PATH="$cyg:$stubs:$orig_path" STUB_DIR="$STUB" WOW_HOME="$wv" sh "$home/bin/wow-review-poll" <&- >"$tmp/out" 2>"$tmp/err" || rc=$?
}

# =========================================================================================
new_case; rm -f "$home/review-poll.json"; runp
assert_eq "no review-poll.json: exit 0" 0 "$rc"
assert_eq "no review-poll.json: no gh call" 0 "$(lines "$STUB/gh.calls")"
check "no review-poll.json: logged" has "$home/$log" "no review-poll.json; nothing to poll"

new_case; printf '{"repos": "o/r"}\n' >"$home/review-poll.json"; runp
assert_eq "wrong-shaped review-poll.json: exit 1" 1 "$rc"
new_case; printf 'not json\n' >"$home/review-poll.json"; runp
assert_eq "malformed review-poll.json: exit 1" 1 "$rc"
assert_eq "malformed review-poll.json: no mint" 0 "$(lines "$STUB/mint.calls")"

new_case; runp extra
assert_eq "an argument: exit 2" 2 "$rc"
assert_eq "an argument: no gh call" 0 "$(lines "$STUB/gh.calls")"

new_case; printf '{"repos": ["bad name/x", "o/r/x", "o/r"]}\n' >"$home/review-poll.json"
addpr o r 7 "$SHA1" false success none; runp
assert_eq "a bad repo entry: exit 0" 0 "$rc"
check "a bad repo entry: logged" has "$home/$log" "bad repo entry skipped"
assert_eq "a bad repo entry: the next entry is polled" "o/r 7" "$(cat "$STUB/review.calls")"

new_case; addpr o r 7 "$SHA1" false success none
mkdir -p "$home/review-state/.poll-lock"; runp
assert_eq "the poll lock held: exit 0" 0 "$rc"
assert_eq "the poll lock held: no mint" 0 "$(lines "$STUB/mint.calls")"
assert_eq "the poll lock held: no review" 0 "$(reviews)"
check "the poll lock held: logged" has "$home/$log" "a poll is running"

new_case; addpr o r 7 "$SHA1" false success none
mkdir -p "$home/review-state/.poll-lock"; touch -d "@$(( $(date +%s) - 20000 ))" "$home/review-state/.poll-lock"; runp
assert_eq "a stale poll lock: exit 0" 0 "$rc"
assert_eq "a stale poll lock: the run proceeds" "o/r 7" "$(cat "$STUB/review.calls")"
check "a stale poll lock: cleared in the log" has "$home/$log" "cleared a stale poll lock"
check "a finished run leaves no lock" test ! -e "$home/review-state/.poll-lock"

new_case; addpr o r 7 "$SHA1" false success none
yq -i '.identities = null' "$STUB/gh/repos_o_r_contents_.ai_project.yml"; runp
assert_eq "identities null: no review" 0 "$(reviews)"
check "identities null: logged" has "$home/$log" "not App-mode gated"
new_case; addpr o r 7 "$SHA1" false success none
yq -i 'del(.review)' "$STUB/gh/repos_o_r_contents_.ai_project.yml"; runp
assert_eq "no review.ci_gate: no review" 0 "$(reviews)"

new_case; addpr o r 7 "$SHA1" true success none; runp
assert_eq "a draft PR: no review" 0 "$(reviews)"
new_case; addpr o r 7 "$SHA1" false success none; mkdir -p "$home/review-state/o/r/7/$SHA1"; runp
assert_eq "a ledger entry: no review" 0 "$(reviews)"
new_case; addpr o r 7 "$SHA1" false success success; runp
assert_eq "a green gate: no review" 0 "$(reviews)"
new_case; addpr o r 7 "$SHA1" false inprogress none; runp
assert_eq "a pending required check: no review" 0 "$(reviews)"
new_case; addpr o r 7 "$SHA1" false failure none; runp
assert_eq "a failed required check: no review" 0 "$(reviews)"
new_case; addpr o r 7 "$SHA1" false success bogus; runp
assert_eq "an unreadable gate: no review" 0 "$(reviews)"
assert_eq "an unreadable gate: exit 0" 0 "$rc"
new_case; addpr o r 7 "$SHA1" false success none; : >"$STUB/gh/repos_o_r_rules_branches_main.fail"; runp
assert_eq "an unreadable required-check list: no review" 0 "$(reviews)"

new_case; addpr o r 7 "$SHA1" false success none; runp
assert_eq "a qualifying head: exit 0" 0 "$rc"
assert_eq "a qualifying head: one call, exact argv" "o/r 7" "$(cat "$STUB/review.calls")"
check "a qualifying head: no --rerun" test -z "$(grep -e '--rerun' "$STUB/review.calls")"
check "a qualifying head: the read token was minted for the bare name" has "$STUB/mint.calls" "1 r --read --out"
check "no gh call had a body flag or a stray env" test ! -s "$STUB/gh.bad"
check "wow-review got WOW_HOME" test ! -e "$STUB/review.bad"

# the PR-list projection
pl=$(grep 'pulls?state=open' "$STUB/gh.calls" | head -n 1)
check "the PR-list call was made" test -n "$pl"
for f in .title .body .user; do
  check "the PR-list projection does not read $f" test -z "$(printf '%s' "$pl" | grep -F -- "$f")"
done
check "the PR-list projection reads number, draft, head sha and base ref" has "$STUB/gh.calls" '[.number, .draft, .head.sha, .base.ref]'

# exit-code policy
two_repos() {
  new_case; addpr o r 7 "$SHA1" false success none; addpr o r 8 "$SHA2" false success none
  mkrepo o2 r2; addpr o2 r2 5 "$SHA3" false success none
  printf '{"repos": ["o/r", "o2/r2"]}\n' >"$home/review-poll.json"
}
two_repos; echo 6 >"$STUB/review.rc.o_r_7"; runp
assert_eq "wow-review exit 6: exit 0" 0 "$rc"
assert_eq "wow-review exit 6: the rest of that repo is skipped, the next repo polled" "o/r 7
o2/r2 5" "$(cat "$STUB/review.calls")"

two_repos; echo 75 >"$STUB/review.rc.o_r_7"; runp
assert_eq "wow-review exit 75: exit 0" 0 "$rc"
assert_eq "wow-review exit 75: the run stops" "o/r 7" "$(cat "$STUB/review.calls")"
check "wow-review exit 75: logged as busy" has "$home/$log" "busy"

new_case; addpr o r 7 "$SHA1" false success none; addpr o r 8 "$SHA2" false success none
echo 1 >"$STUB/review.rc.o_r_7"; runp
assert_eq "wow-review exit 1: the next head is launched" "o/r 7
o/r 8" "$(cat "$STUB/review.calls")"

for c in 103 104; do
  new_case; addpr o r 7 "$SHA1" false success none; addpr o r 8 "$SHA2" false success none
  echo "$c" >"$STUB/review.rc.o_r_7"; runp
  assert_eq "wow-review exit $c: the next head is launched" "o/r 7
o/r 8" "$(cat "$STUB/review.calls")"
  check "wow-review exit $c: an UNCONFIRMED line" has "$home/$log" "UNCONFIRMED"
done

for c in 0 3 4 5; do
  new_case; addpr o r 7 "$SHA1" false success none; addpr o r 8 "$SHA2" false success none
  echo "$c" >"$STUB/review.rc.o_r_7"; runp
  assert_eq "wow-review exit $c: the next head is launched" 2 "$(reviews)"
done
for c in 2 124 99; do
  new_case; addpr o r 7 "$SHA1" false success none; addpr o r 8 "$SHA2" false success none
  echo "$c" >"$STUB/review.rc.o_r_7"; runp
  assert_eq "wow-review exit $c: the run stops" 1 "$(reviews)"
  assert_eq "wow-review exit $c: the poller exits 0" 0 "$rc"
done


# a head that goes red while an earlier review runs is not launched on the stale read
new_case; addpr o r 7 "$SHA1" false success none; addpr o r 8 "$SHA2" false success none
printf '%s\n' "printf '{\"check_runs\":[{\"name\":\"ci\",\"status\":\"completed\",\"conclusion\":\"failure\"}]}\n' >\"$STUB/gh/repos_o_r_commits_${SHA2}_check-runs\"" >"$STUB/hook.sh"; runp
assert_eq "a head that went red during the first review is not launched" "o/r 7" "$(cat "$STUB/review.calls")"
# revocation and cleanup
rundir_gone() { ! ls -d "$home"/review-host/poll-* >/dev/null 2>&1; }
revoked_all() { # every minted token was revoked, once each
  [ -s "$STUB/mint.tokens" ] || return 1
  [ "$(sort "$STUB/mint.tokens")" = "$(sort "$STUB/revoked" 2>/dev/null)" ]
}
new_case; addpr o r 7 "$SHA1" false success none; runp
check "success path: the run dir is gone" rundir_gone
check "success path: every minted token was revoked" revoked_all
case $(cat "$home/$log" "$STUB/review.calls") in *ghs_*) bad "a token reached the log" ;; *) ok "no token reaches the log" ;; esac
check "the log holds wow-review output" has "$home/$log" "wow-review ran for o/r 7"
two_repos; runp
check "two repos: every token revoked" revoked_all
check "two repos: the run dir is gone" rundir_gone
new_case; addpr o r 7 "$SHA1" false success none; : >"$STUB/gh/repos_o_r_pulls_state_open.fail"; runp
check "failure path (PR list fails): the run dir is gone" rundir_gone
check "failure path (PR list fails): the token was revoked" revoked_all
assert_eq "failure path (PR list fails): no review" 0 "$(reviews)"
new_case; addpr o r 7 "$SHA1" false success none; echo 75 >"$STUB/review.rc.o_r_7"; runp
check "exit-75 path: the run dir is gone" rundir_gone
check "exit-75 path: the token was revoked" revoked_all
new_case; touch "$STUB/mint.fail.r"; runp
assert_eq "a failed mint: no review" 0 "$(reviews)"
check "a failed mint: the run dir is gone" rundir_gone
check "a failed mint: logged" has "$home/$log" "the session-token mint failed"

# the WOW_HOME check: the drive-letter forms the registration script and the operator write
new_case; addpr o r 7 "$SHA1" false success none; runw 'C:\wowhome'
assert_eq "a backslash drive-letter WOW_HOME: exit 0" 0 "$rc"
assert_eq "a backslash drive-letter WOW_HOME: one call, exact argv" "o/r 7" "$(cat "$STUB/review.calls")"
check "a backslash drive-letter WOW_HOME: poll start logged" has "$home/$log" "poll start"
check "a backslash drive-letter WOW_HOME: poll done logged" has "$home/$log" "poll done"
check "a backslash drive-letter WOW_HOME: not refused" test -z "$(grep 'must be set and absolute' "$tmp/err")"
new_case; addpr o r 7 "$SHA1" false success none; runw 'C:/wowhome'
assert_eq "a forward-slash drive-letter WOW_HOME: exit 0" 0 "$rc"
check "a forward-slash drive-letter WOW_HOME: poll done logged" has "$home/$log" "poll done"
for bad in '' 'wowhome' 'C:wowhome'; do
  new_case; addpr o r 7 "$SHA1" false success none; runw "$bad"
  assert_eq "WOW_HOME [$bad] refused: exit 1" 1 "$rc"
  check "WOW_HOME [$bad] refused: said so" has "$tmp/err" "WOW_HOME must be set and absolute"
  assert_eq "WOW_HOME [$bad] refused: no gh call" 0 "$(lines "$STUB/gh.calls")"
  assert_eq "WOW_HOME [$bad] refused: no mint" 0 "$(lines "$STUB/mint.calls")"
done

# the poller is installed beside wow-review
check "install-host-tools.ps1's table names wow-review-poll" has "$root_dir/scripts/identity/install-host-tools.ps1" "@('scripts/identity/wow-review-poll', 'wow-review-poll')"

check "register-review-poll-task.ps1 builds the action as conhost --headless" has "$root_dir/scripts/identity/register-review-poll-task.ps1" '$conArg = "--headless `"$pwsh`" $arg"'
check "register-review-poll-task.ps1 registers conhost as the executable" has "$root_dir/scripts/identity/register-review-poll-task.ps1" 'New-ScheduledTaskAction -Execute $conhost -Argument $conArg'
check "register-review-poll-task.ps1 writes WOW_HOME with forward slashes" has "$root_dir/scripts/identity/register-review-poll-task.ps1" "WOW_HOME = '\$(\$WowHome.Replace('\\', '/'))'"

[ "$fail" = 0 ] && echo "all review-poll fixtures passed"
exit "$fail"
