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
echo "${WOW_REVIEW_MAX:-unset}" >>"$S/review.max"
key=$(printf '%s' "$*" | tr '/ ' '__')
echo "wow-review ran for $*"
[ ! -f "$S/hook.sh" ] || sh "$S/hook.sh"
# A case with a blocks file holds each launch until its release file (release.<key>) exists, and records
# when it starts and ends so overlap can be observed; it gives up after about 30 seconds.
if [ -e "$S/blocks" ]; then
  echo "start $key" >>"$S/events"
  i=0
  while [ ! -e "$S/release.$key" ] && [ "$i" -lt 600 ]; do "$REAL_SLEEP" 0.05; i=$((i + 1)); done
  echo "end $key" >>"$S/events"
fi
if [ -e "$S/review.rc.$key" ]; then exit "$(cat "$S/review.rc.$key")"; fi
exit "$(cat "$S/review.rc.default" 2>/dev/null || echo 0)"
STUB
# The poller's 5 second wait between passes is cut to 0.05; every other sleep is real.
real_sleep=$(command -v sleep)
cat >"$stubs/sleep" <<'STUB'
#!/bin/sh
[ "$1" != 5 ] || set -- 0.05
exec "$REAL_SLEEP" "$@"
STUB
chmod +x "$stubs/docker" "$stubs/gh" "$stubs/wow-review-mint" "$stubs/sleep"

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
  : >"$STUB/gh.calls"; : >"$STUB/mint.calls"; : >"$STUB/review.calls"; : >"$STUB/events"
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
  env PATH="$stubs:$orig_path" REAL_SLEEP="$real_sleep" STUB_DIR="$STUB" WOW_HOME="$home" WOW_REVIEW_MAX="${T_MAX-1}" sh "$home/bin/wow-review-poll" "$@" <&- >"$tmp/out" 2>"$tmp/err" || rc=$?
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
  env PATH="$cyg:$stubs:$orig_path" REAL_SLEEP="$real_sleep" STUB_DIR="$STUB" WOW_HOME="$wv" WOW_REVIEW_MAX=1 sh "$home/bin/wow-review-poll" <&- >"$tmp/out" 2>"$tmp/err" || rc=$?
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

# =========================================================================================
# the pool (#1107): up to WOW_REVIEW_MAX launches in flight. The stub holds each launch until its release file.
three_heads() { new_case; addpr o r 7 "$SHA1" false success none; addpr o r 8 "$SHA2" false success none; addpr o r 9 "$SHA3" false success none; : >"$STUB/blocks"; }
# runbg: the poller in the background; wait_events <n> waits for n lines of the events file; finish waits for the poller.
runbg() {
  rc=0
  env PATH="$stubs:$orig_path" REAL_SLEEP="$real_sleep" STUB_DIR="$STUB" WOW_HOME="$home" WOW_REVIEW_MAX="${T_MAX-1}" sh "$home/bin/wow-review-poll" <&- >"$tmp/out" 2>"$tmp/err" &
  bgpid=$!
}
finish() { rc=0; wait "$bgpid" || rc=$?; }
wait_events() { # wait_events <pattern> <count>: until the events file holds that many matching lines (about 20 s)
  i=0
  while [ "$(grep -c "$1" "$STUB/events" 2>/dev/null)" -lt "$2" ] && [ "$i" -lt 400 ]; do "$real_sleep" 0.05; i=$((i + 1)); done
  [ "$(grep -c "$1" "$STUB/events" 2>/dev/null)" -ge "$2" ]
}
release() { : >"$STUB/release.$1"; }
settle() { "$real_sleep" 0.5; }   # long enough for a poller that would wrongly start another launch to do so
max_inflight() { # the highest number of started-but-not-ended launches in the events file
  awk '$1 == "start" { n++; if (n > m) m = n } $1 == "end" { n-- } END { print m + 0 }' "$STUB/events"
}

three_heads; T_MAX= runbg
check "default pool: two launches start" wait_events '^start' 2
settle
assert_eq "default pool: the third waits while two are in flight" 2 "$(grep -c '^start' "$STUB/events")"
release o_r_7
check "default pool: the third starts once one has ended" wait_events '^start' 3
release o_r_8; release o_r_9
finish
assert_eq "default pool: exit 0" 0 "$rc"
assert_eq "default pool: never more than two in flight" 2 "$(max_inflight)"
assert_eq "default pool: three launches" 3 "$(reviews)"
assert_eq "default pool: each launch carries WOW_REVIEW_MAX=2" "2
2
2" "$(cat "$STUB/review.max")"
check "default pool: every launch ended before the poller exited" test "$(grep -c '^end' "$STUB/events")" = 3
check "default pool: every token was revoked" revoked_all
check "default pool: the run dir is gone" rundir_gone
check "default pool: the poll lock is gone" test ! -e "$home/review-state/.poll-lock"

three_heads; T_MAX=1 runbg
check "max 1: the first launch starts" wait_events '^start' 1
settle
assert_eq "max 1: no second launch while the first runs" 1 "$(grep -c '^start' "$STUB/events")"
release o_r_7
check "max 1: the second starts after the first ended" wait_events '^start' 2
release o_r_8; release o_r_9
finish
assert_eq "max 1: launches never overlap" 1 "$(max_inflight)"
assert_eq "max 1: each launch carries WOW_REVIEW_MAX=1" "1
1
1" "$(cat "$STUB/review.max")"

three_heads; T_MAX=3 runbg
check "max 3: three launches start together" wait_events '^start' 3
release o_r_7; release o_r_8; release o_r_9
finish
assert_eq "max 3: three in flight at once" 3 "$(max_inflight)"

for v in 0 10 abc 01 -1 2.5; do
  new_case; addpr o r 7 "$SHA1" false success none; T_MAX=$v runp
  assert_eq "WOW_REVIEW_MAX [$v]: exit 1" 1 "$rc"
  check "WOW_REVIEW_MAX [$v]: said so" has "$tmp/err" "WOW_REVIEW_MAX must be 1 to 9"
  assert_eq "WOW_REVIEW_MAX [$v]: no gh call" 0 "$(lines "$STUB/gh.calls")"
  assert_eq "WOW_REVIEW_MAX [$v]: no mint" 0 "$(lines "$STUB/mint.calls")"
  assert_eq "WOW_REVIEW_MAX [$v]: no review" 0 "$(reviews)"
done

# a stop code with another launch in flight: that launch runs to its own end, nothing new starts
for c in 75 2 124; do
  three_heads; echo "$c" >"$STUB/review.rc.o_r_7"; T_MAX=2 runbg
  check "exit $c in flight: both launches start" wait_events '^start' 2
  release o_r_7
  check "exit $c in flight: the first has ended" wait_events '^end' 1
  settle
  assert_eq "exit $c in flight: no third launch" 2 "$(grep -c '^start' "$STUB/events")"
  check "exit $c in flight: the poller still waits for the other launch" kill -0 "$bgpid"
  release o_r_8
  finish
  assert_eq "exit $c in flight: the poller exits 0" 0 "$rc"
  assert_eq "exit $c in flight: the other launch ran to its own end" 2 "$(grep -c '^end' "$STUB/events")"
  assert_eq "exit $c in flight: two launches in all" 2 "$(reviews)"
  check "exit $c in flight: the stopping exit is logged" has "$home/$log" "wow-review exit $c"
  check "exit $c in flight: the other exit is logged" has "$home/$log" "o/r#8 "
  check "exit $c in flight: every token was revoked" revoked_all
  check "exit $c in flight: the run dir is gone" rundir_gone
  check "exit $c in flight: the poll lock is gone" test ! -e "$home/review-state/.poll-lock"
done

# a stop code is noticed with a free slot: a pool of 3 with head 7 exiting 75 at once starts no further launch
three_heads; echo 75 >"$STUB/review.rc.o_r_7"; release o_r_7; release o_r_8; release o_r_9; T_MAX=3 runbg
finish
assert_eq "exit 75 with a free slot: exit 0" 0 "$rc"
check "exit 75 with a free slot: not all three heads launched" test "$(reviews)" -lt 3

# exit 6 stops that repo only
new_case; addpr o r 7 "$SHA1" false success none; addpr o r 8 "$SHA2" false success none
mkrepo o2 r2; addpr o2 r2 5 "$SHA3" false success none
printf '{"repos": ["o/r", "o2/r2"]}\n' >"$home/review-poll.json"
: >"$STUB/blocks"; echo 6 >"$STUB/review.rc.o_r_7"; T_MAX=2 runbg
check "exit 6 in flight: both launches of the first repo start" wait_events '^start' 2
release o_r_7
check "exit 6 in flight: the next repo is still polled" wait_events '^start' 3
release o_r_8; release o2_r2_5
finish
assert_eq "exit 6 in flight: exit 0" 0 "$rc"
assert_eq "exit 6 in flight: the launches" "o/r 7
o/r 8
o2/r2 5" "$(cat "$STUB/review.calls")"
check "exit 6 in flight: logged" has "$home/$log" "no new launch for o/r this run"

# a head in flight is not launched a second time
three_heads; T_MAX=2 runbg
check "no double launch: two start" wait_events '^start' 2
release o_r_7; release o_r_8; release o_r_9
finish
assert_eq "no double launch: each head once" "o/r 7
o/r 8
o/r 9" "$(sort "$STUB/review.calls")"

# a failed gather with a launch in flight
three_heads; T_MAX=2 runbg
check "failed gather: two start" wait_events '^start' 2
: >"$STUB/gh/repos_o_r_pulls_state_open.fail"
release o_r_7
settle
release o_r_8
finish
assert_eq "failed gather: exit 0" 0 "$rc"
assert_eq "failed gather: no further launch" 2 "$(reviews)"
check "failed gather: every token was revoked" revoked_all
check "failed gather: the run dir is gone" rundir_gone
check "failed gather: the poll lock is gone" test ! -e "$home/review-state/.poll-lock"

# a signal: nothing more is launched, the launches in flight are waited for, then the run dir and lock go
three_heads; T_MAX=2 runbg
check "signal: two start" wait_events '^start' 2
kill -TERM "$bgpid"
settle
check "signal: the poller waits for the launches in flight" kill -0 "$bgpid"
check "signal: the run dir is still there while they run" sh -c "ls -d '$home'/review-host/poll-* >/dev/null 2>&1"
check "signal: the poll lock is still held while they run" test -d "$home/review-state/.poll-lock"
release o_r_7; release o_r_8
finish
assert_eq "signal: exit 143" 143 "$rc"
assert_eq "signal: no third launch" 2 "$(reviews)"
check "signal: both launches ended before the poller" test "$(grep -c '^end' "$STUB/events")" = 2
check "signal: every token was revoked" revoked_all
check "signal: the run dir is gone" rundir_gone
check "signal: the poll lock is gone" test ! -e "$home/review-state/.poll-lock"


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
