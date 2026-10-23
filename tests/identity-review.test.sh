#!/bin/sh
# Fixture tests for scripts/identity/wow-review, the App-mode review launcher (#635).
#
# The launcher runs from a fake installed bin/ (the launcher, wow-common.sh, the plugin's
# token-check.sh, gh-identity.sh and review-gate-state.sh, a stub wow-review-mint, a MANIFEST).
# Stub docker, gh and sleep go first on PATH. Each records its argv (gh also its token prefix, its
# GH_CONFIG_DIR and every --input file) under $STUB, and answers from per-case fixture files. The
# stub docker answers `run ... outbox-read <kind>` by running the real outbox-read, sed-substituted
# to a fixture outbox (as tests/review-image.test.sh does), and answers `inspect` from the argv the
# container was created with, so the launcher's preflight reads what it asked for. stdin is closed
# throughout, to prove nothing prompts.
#
# Permitted toolset: POSIX sh and its standard utilities, jq and yq (skipped, loudly, if absent).
#
# Concurrency (#955): the sections run at once, each in a subshell with its own scratch directory ($tmp: its
# case tree and its out, err and log scratch files) over the stubs, which are written once before any section
# starts. Each section's output goes to files that are replayed in section order; the suite fails if any
# section reports a FAIL through `bad` (the invariants' included) or exits non-zero.
#
# Runtime (#755, #955): run alone, in the dev container as built (GNU coreutils 9.7 `timeout`, linked
# by #741; 28 cores by `nproc`, on ext4), this suite takes 26 s; with the sections one after another it took
# 92 s. The uutils 0.8.0 `timeout` first on PATH took 775 s with the sections one after another (measured
# before #935). The cause is the container's `timeout` build: a run makes
# about 7,500 `timeout` calls (the launcher wraps nearly every docker and gh call in it), and an
# isolated `timeout 5 true` costs 62.2 ms with uutils against 0.8 ms with GNU in a 100-call loop
# (a 61.4 ms difference; the figure varies with load, and the suite's effective overhead is
# higher, about 90 ms per call). The other uutils tools' share was not measured. The 300 s overrun seen while #710
# was built was not reproduced on the GNU build. Run it alone, in its own Bash call, with the
# tool timeout at least 52 s (twice the 26 s). On a container whose `timeout` is uutils the bound
# is about 1550 s: run it in the background, or stop and ask the maintainer to remove a uutils
# copy from ~/.local/bin or recreate the container (DEV-CONTAINER.md, Lanes).
set -u

root_dir="$(cd "$(dirname "$0")/.." && pwd)"

for t in jq yq timeout; do
  if ! command -v "$t" >/dev/null 2>&1; then
    echo "SKIP - $t not on PATH; wow-review fixtures not run" >&2
    exit 0
  fi
done

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

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
has() { grep -qF -- "$2" "$1" 2>/dev/null; }          # has <file> <fixed string>
hasre() { grep -qE -- "$2" "$1" 2>/dev/null; }        # hasre <file> <regex>
sed_esc() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

real_sleep=$(command -v sleep)
stubs="$tmp_root/stubs"
mkdir "$stubs"

# =========================================================================================
# --- the stubs -------------------------------------------------------------------------
# =========================================================================================
cat >"$stubs/sleep" <<'STUB'
#!/bin/sh
# The gate poll's 15 second pause is skipped and the injector poll's 0.2 second pause is cut to
# 0.02; every other sleep is real.
[ "$1" != 15 ] || exit 0
[ "$1" != 0.2 ] || set -- 0.02
exec "$REAL_SLEEP" "$@"
STUB

cat >"$stubs/gh" <<'STUB'
#!/bin/sh
S=$STUB_DIR
seq=$(( $(cat "$S/gh.seq" 2>/dev/null || echo 0) + 1 )); echo "$seq" >"$S/gh.seq"
method= input= jqx= path= pag= host=
shift
while [ $# -gt 0 ]; do
  case $1 in
    --hostname) host=$2; shift ;;
    --paginate) pag=1 ;;
    -H) shift ;;
    --jq) jqx=$2; shift ;;
    -X) method=$2; shift ;;
    --input) input=$2; shift ;;
    -f|-F|--field|--raw-field) echo "$1" >>"$S/gh.bad" ;;
    *) path=$1 ;;
  esac
  shift
done
cfg=no
if [ -n "${GH_CONFIG_DIR:-}" ] && [ -d "$GH_CONFIG_DIR" ] && [ -z "$(ls -A "$GH_CONFIG_DIR")" ]; then cfg=yes; fi
for v in GH_HOST GH_ENTERPRISE_TOKEN GITHUB_TOKEN GITHUB_ENTERPRISE_TOKEN; do
  eval "x=\${$v:-}"; [ -z "$x" ] || echo "$v set" >>"$S/gh.bad"
done
inp=
if [ -n "$input" ]; then cp "$input" "$S/inputs/$seq"; inp=$seq; fi
printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$seq" "$(printf %s "${GH_TOKEN:-}" | cut -c1-4)" "$cfg" "$host" "$method" "$pag" "$path" "$inp" >>"$S/gh.calls"
fx="$S/gh/$(printf '%s' "$path" | tr '/?#=&' '_____')"
if [ "$method" = DELETE ] && [ "$path" = installation/token ]; then
  echo "gh-DELETE" >>"$S/events"
  printf '%s\n' "$GH_TOKEN" >>"$S/revoked"
  [ ! -e "$S/gh/revoke.fail" ] || exit 1
  exit 0
fi
if [ "$method" = POST ]; then
  case $path in
    */pulls/*/reviews) echo "gh-POST-review" >>"$S/events"; fx="$S/gh/post_review" ;;
    */issues)
      echo "gh-POST-issue" >>"$S/events"
      n=$(( $(cat "$S/issue.n" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$S/issue.n"
      if [ -e "$S/gh/issue_fail_at" ] && [ "$n" = "$(cat "$S/gh/issue_fail_at")" ]; then echo "HTTP 422" >&2; exit 1; fi
      printf '{"number": %s}\n' $((100 + n)) >"$S/gh/issue_response"; fx="$S/gh/issue_response" ;;
  esac
fi
case $path in graphql) fx="$S/gh/graphql"; echo "gh-graphql" >>"$S/events" ;; esac
# A path read more than once may change after its first reads (a head that moves).
if [ -e "$fx.after" ]; then
  rn=$(( $(cat "$fx.reads" 2>/dev/null || echo 0) + 1 )); echo "$rn" >"$fx.reads"
  if [ "$rn" -gt "$(cat "$fx.after.n" 2>/dev/null || echo 1)" ]; then fx="$fx.after"; fi
fi
if [ -e "$fx.fail" ]; then echo "HTTP 500" >&2; exit 1; fi
if [ ! -e "$fx" ]; then echo "HTTP 404 $path" >&2; exit 1; fi
if [ -n "$jqx" ]; then jq -r "$jqx" <"$fx"; else cat "$fx"; fi
STUB

cat >"$stubs/docker" <<'STUB'
#!/bin/sh
S=$STUB_DIR
# The stub's own jq calls take key=/path arguments that MSYS would rewrite.
MSYS2_ARG_CONV_EXCL='*'; export MSYS2_ARG_CONV_EXCL
{ printf 'CALL'; printf ' [%s]' "$@"; printf '\n'; } >>"$S/docker.calls"
cmd=${1:-}; shift
last() { for a; do :; done; printf '%s' "$a"; }
ct_save() { # ct_save <args...>: remember how a container was made
  name= net=
  p=
  for a in "$@"; do
    [ "$p" = --name ] && name=$a
    [ "$p" = --network ] && net=$a
    p=$a
  done
  mkdir -p "$S/ct"
  printf '%s\n' "$@" >"$S/ct/$name.args"
  printf '%s\n' "$net" >"$S/ct/$name.net"
  printf '%s' "$name"
}
kind_of() { case $1 in *-session-*) echo session ;; *-holder-*) echo holder ;; *-inject-*) echo inject ;; *-proxy-*) echo proxy ;; *) echo other ;; esac; }
ctjson() { # ctjson <name>
  name=$1; k=$(kind_of "$name")
  a="$S/ct/$name.args"
  envs= mounts= capdrop= secopt= ro=false netmode=bridge labels= prev=
  if [ -f "$a" ]; then
    while IFS= read -r l; do
      case $prev in
        -e) envs="$envs$l
" ;;
        --mount) mounts="$mounts$l
" ;;
        --network) netmode=$l ;;
        --cap-drop) capdrop=$l ;;
        --security-opt) secopt=$l ;;
        --label) labels="$labels$l
" ;;
      esac
      [ "$l" != --read-only ] || ro=true
      prev=$l
    done <"$a"
  fi
  running=false; started='0001-01-01T00:00:00Z'
  if [ -e "$S/state/$name.started" ]; then started=$(cat "$S/state/$name.started"); fi
  case $k in
    holder|proxy|inject) running=true ;;
    session) if [ -e "$S/state/$name.started" ] && [ -e "$S/inspect.stillrunning" ] && [ ! -e "$S/killed" ]; then running=true; fi ;;
  esac
  out=$(jq -n --arg name "$name" --arg envs "$envs" --arg mounts "$mounts" --arg capdrop "$capdrop" --arg secopt "$secopt" --argjson ro "$ro" \
    --arg netmode "$netmode" --arg labels "$labels" --argjson running "$running" --arg started "$started" '
    [{Name: ("/" + $name),
      Config: {User: "1000:1000", Env: ($envs | split("\n") | map(select(. != ""))),
               Labels: ($labels | split("\n") | map(select(. != "") | split("=") | {(.[0]): .[1]}) | add // {})},
      HostConfig: {ReadonlyRootfs: $ro, CapDrop: (if $capdrop == "" then [] else [$capdrop] end), SecurityOpt: (if $secopt == "" then [] else [$secopt] end), Privileged: false, NetworkMode: $netmode},
      State: {Running: $running, StartedAt: $started},
      Mounts: ($mounts | split("\n") | map(select(. != "") | split(",") as $p
        | ($p | map(select(contains("=")) | split("=") | {(.[0]): .[1]}) | add) as $kv
        | {Type: $kv.type, Name: (if $kv.type == "volume" then $kv.source else null end), Source: $kv.source,
           Destination: $kv.target, RW: (($p | index("readonly")) == null)}))}]')
  if [ -f "$S/docker/inspect.$k.jq" ]; then out=$(printf '%s' "$out" | jq "$(cat "$S/docker/inspect.$k.jq")"); fi
  printf '%s\n' "$out"
}
case $cmd in
  image) exit $([ -e "$S/docker/noimage" ] && echo 1 || echo 0) ;;
  build) echo docker-build >>"$S/events"; exit 0 ;;
  network)
    sub=$1; shift
    case $sub in
      create) echo "docker-net-create $*" >>"$S/events"; printf '%s\n' "$*" >>"$S/net.create"; exit 0 ;;
      connect) exit 0 ;;
      rm) echo "docker-net-rm $*" >>"$S/events"; exit 0 ;;
      inspect)
        net=$1
        members=$(for f in "$S"/ct/*.net; do [ -f "$f" ] || continue; [ "$(cat "$f")" = "$net" ] || continue; b=$(basename "$f" .net); case $(kind_of "$b") in proxy|inject) echo "$b" ;; esac; done)
        j=$(printf '%s\n' "$members" | jq -R -s --arg n "$net" '[{Name: $n, Internal: true, EnableIPv6: false,
          Options: {"com.docker.network.bridge.gateway_mode_ipv4": "isolated"}, IPAM: {Config: [{Subnet: "172.30.0.0/16"}]},
          Containers: (split("\n") | map(select(. != "")) | map({key: ., value: {Name: .}}) | from_entries)}]')
        if [ -f "$S/docker/net.jq" ]; then j=$(printf '%s' "$j" | jq "$(cat "$S/docker/net.jq")"); fi
        printf '%s\n' "$j"; exit 0 ;;
    esac ;;
  volume)
    sub=$1; shift
    case $sub in
      create) echo "docker-vol-create" >>"$S/events"; printf '%s\n' "$*" >>"$S/vol.create"; exit 0 ;;
      rm) echo "docker-vol-rm $*" >>"$S/events"; exit 0 ;;
    esac ;;
  run)
    case " $* " in
      *outbox-read*)
        kind=$(last "$@")
        echo "docker-outbox-read-$kind" >>"$S/events"
        [ -e "$S/hdir.after-log" ] || ls -A "$WOW_HOME"/review-host/*/ >"$S/hdir.after-log" 2>&1
        printf '%s\n' "$*" >>"$S/outbox.calls"
        sh "$S/outbox-read-copy" "$kind"; exit $? ;;
    esac
    name=$(ct_save "$@")
    echo "docker-run $name" >>"$S/events"
    printf 'id-%s\n' "$name"; exit 0 ;;
  create)
    name=$(ct_save "$@")
    echo "docker-create $name" >>"$S/events"
    printf 'id-%s\n' "$name"; exit 0 ;;
  start)
    case " $* " in
      *" -ai "*)
        name=$(last "$@")
        cat >"$S/inject-stdin"
        mkdir -p "$S/logs"
        [ ! -e "$S/inject.delay" ] || "$REAL_SLEEP" "$(cat "$S/inject.delay")"
        [ -e "$S/inject.noup" ] || echo "inject up" >"$S/logs/$name"
        exit 0 ;;
    esac
    name=$(last "$@")
    echo "docker-start $name" >>"$S/events"
    if [ -e "$S/start.fail" ]; then exit 1; fi
    mkdir -p "$S/state"; date -u +%Y-%m-%dT%H:%M:%SZ >"$S/state/$name.started"
    if [ -e "$S/lockcheck" ]; then [ ! -d "$S/lockcheck.path" ] ; fi
    exit 0 ;;
  wait)
    name=$(last "$@")
    echo "docker-wait $name" >>"$S/events"
    if [ -d "$WOW_HOME/review-state/.lock" ]; then echo lock-held >>"$S/wait.notes"; else echo lock-gone >>"$S/wait.notes"; fi
    if [ -e "$S/wait.hang" ]; then
      while [ ! -e "$S/killed" ] && [ ! -e "$S/rmed" ]; do "$REAL_SLEEP" 0.2; done
    else
      i=0; max=$(( $(cat "$S/wait.sleep" 2>/dev/null || echo 0) * 5 ))
      while [ "$i" -lt "$max" ]; do "$REAL_SLEEP" 0.2; i=$((i + 1)); done
    fi
    echo "docker-wait-done" >>"$S/events"
    echo 0; exit 0 ;;
  kill)
    echo "docker-kill $*" >>"$S/events"; : >"$S/killed"; exit 0 ;;
  rm)
    for a in "$@"; do
      case $a in -*) ;; *) echo "docker-rm $a" >>"$S/events"; echo "$a" >>"$S/removed" ;; esac
    done
    : >"$S/rmed"; exit 0 ;;
  inspect)
    name=$(last "$@")
    echo "docker-inspect $(kind_of "$name")" >>"$S/events"
    ctjson "$name"; exit 0 ;;
  logs)
    name=$(last "$@")
    echo "docker-logs $(kind_of "$name")" >>"$S/events"
    if [ "$(kind_of "$name")" = session ]; then cat "$S/session-log" 2>/dev/null; else cat "$S/logs/$name" 2>/dev/null; fi
    exit 0 ;;
  ps)
    flt= q=0 fmt=
    while [ $# -gt 0 ]; do
      case $1 in --filter) flt=${2#label=}; shift ;; --format) fmt=$2; shift ;; -q) q=1 ;; esac
      shift
    done
    # A preexisting record is "<id> <role label> [<deadline>] [home=<key>]": the home= field cannot be read as a deadline.
    {
      [ -f "$S/preexisting" ] && cat "$S/preexisting"
      for f in "$S"/ct/*.args; do
        [ -f "$f" ] || continue
        b=$(basename "$f" .args); lab=; dl=0; hm=; p=
        while IFS= read -r l; do
          [ "$p" = --label ] && case $l in wow.review.deadline=*) dl=${l#*=} ;; wow.review.home=*) hm=home=${l#*=} ;; wow.review=1|wow.review.holder=1|wow.review.sidecar=1) lab=$l ;; esac
          p=$l
        done <"$f"
        [ -n "$lab" ] && echo "$b $lab $dl $hm"
      done
    } | while read -r id lab r1 r2; do
      [ "$lab" = "$flt" ] || continue
      grep -qxF "$id" "$S/removed" 2>/dev/null && continue
      dl= hm=
      for r in $r1 $r2; do case $r in home=*) hm=${r#home=} ;; *) dl=$r ;; esac; done
      if [ "$q" = 1 ]; then echo "$id"
      else
        case $fmt in
          *wow.review.deadline*) echo "$id|$dl|$hm" ;;
          *) echo "$id|$hm" ;;
        esac
      fi
    done
    exit 0 ;;
esac
echo "stub docker: unhandled: $cmd $*" >&2
exit 1
STUB

cat >"$stubs/wow-review-mint" <<'STUB'
#!/bin/sh
S=$STUB_DIR
n=$(( $(cat "$S/mint.n" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$S/mint.n"
echo "$n $*" >>"$S/mint.calls"
kind=post out= prev=
for a in "$@"; do
  case $a in --read) kind=read ;; --file) kind=file ;; esac
  [ "$prev" != --out ] || out=$a
  prev=$a
done
echo "mint-$kind" >>"$S/events"
if env | grep -q '^MSYS_NO_PATHCONV=\|^MSYS2_ARG_CONV_EXCL='; then echo "msys-leak" >>"$S/mint.bad"; fi
[ ! -e "$S/mint.fail.$n" ] || exit 1
[ ! -e "$S/mint.fail.kind.$kind" ] || exit 1
exp=2999-01-01T00:00:00Z
[ ! -e "$S/mint.expired.$n" ] || exp=2000-01-01T00:00:00Z
tok=$(printf 'ghs_%sTokenxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx%03d' "$kind" "$n")
mkdir -p "$(dirname "$out")"
printf '%s\n%s\n' "$tok" "$exp" >"$out"
echo "$kind $tok" >>"$S/mint.tokens"
STUB
chmod +x "$stubs/sleep" "$stubs/gh" "$stubs/docker" "$stubs/wow-review-mint"


# =========================================================================================
# --- a case: a fresh $WOW_HOME, bin/, stub directory and fixtures -------------------------
# =========================================================================================
SHA=0123456789abcdef0123456789abcdef01234567
TIP=fedcba9876543210fedcba9876543210fedcba98
HDRTXT='ARCHITECT-REVIEW FROZEN HEADER v1'
ATTTXT='The reviewer attests this review was written in a fresh session.'
CRED='sk-ant-oat01-FIXTURE-credential-not-a-secret-0123456789'

new_case() {
  rm -rf "$tmp/case"
  home="$tmp/case/home"; STUB="$tmp/case/stub"; export STUB
  mkdir -p "$home/bin/review" "$STUB/gh" "$STUB/inputs" "$STUB/outbox" "$STUB/docker"
  cp "$root_dir/scripts/identity/wow-review" "$root_dir/scripts/identity/wow-common.sh" "$home/bin/"
  for f in token-check.sh gh-identity.sh review-gate-state.sh; do cp "$root_dir/plugins/way-of-working/bin/$f" "$home/bin/"; done
  cp "$stubs/wow-review-mint" "$home/bin/wow-review-mint"
  printf 'commit 0123456789abcdef0123456789abcdef0123456a\ninstalled 2026-10-15T00:00:00Z\n' >"$home/bin/MANIFEST"
  printf '%s\n' "$CRED" >"$home/claude-credential"
  # outbox-read, pointed at the fixture outbox
  sed "s|^outbox='.*'\$|outbox='$(sed_esc "$STUB/outbox")'|" "$root_dir/scripts/identity/review/outbox-read" >"$STUB/outbox-read-copy"
  # project.yml of the default branch
  cat >"$STUB/gh/repos_o_r_contents_.ai_project.yml" <<EOF
identities:
  maintainer: [{login: maint, id: 11}]
  dev_app: {login: "glunk-dev[bot]", id: 4141}
  reviewer_app: {login: "glunk-review[bot]", id: 4242}
review:
  ci_gate:
    header: "$HDRTXT"
    attestation: "$ATTTXT"
    check: gate
    triggers_on: [src/, scripts/]
code_paths: [src/]
models:
  architect: opus
backlog:
  kind: github_issues
  repo: null
EOF
  g="$STUB/gh"
  printf '{"default_branch":"main"}\n' >"$g/repos_o_r"
  printf '{"state":"open","head":{"sha":"%s"},"base":{"ref":"main"}}\n' "$SHA" >"$g/repos_o_r_pulls_7"
  printf '{"repositories":[{"full_name":"o/r"},{"full_name":"o/backlog"}]}\n' >"$g/installation_repositories"
  printf '{"data":{"viewer":{"login":"glunk-review[bot]","databaseId":4242}}}\n' >"$g/graphql"
  printf '{"commit_id":"%s","state":"COMMENTED","user":{"login":"glunk-review[bot]","id":4242},"html_url":"https://github.com/o/r/pull/7#pullrequestreview-555","submitted_at":"2026-10-17T16:35:56Z"}\n' "$SHA" >"$g/post_review"
  printf '{"object":{"sha":"%s"}}\n' "$TIP" >"$g/repos_o_r_git_ref_heads_main"
  printf '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"ci"},{"context":"gate"}]}}]\n' >"$g/repos_o_r_rules_branches_main"
  printf '{"statuses":[]}\n' >"$g/repos_o_r_commits_${SHA}_status"
  printf '{"check_runs":[{"name":"ci","status":"completed","conclusion":"success"},{"name":"gate","status":"completed","conclusion":"skipped"}]}\n' >"$g/repos_o_r_commits_${SHA}_check-runs"
  printf '[]\n' >"$g/repos_o_r_pulls_7_reviews"
  for l in bug feature chore docs; do printf '{"name":"%s"}\n' "$l" >"$g/repos_o_backlog_labels_$l"; done
  : >"$STUB/events"; : >"$STUB/docker.calls"; : >"$STUB/gh.calls"; : >"$STUB/mint.calls"
  set_compare ahead 2 '[{"filename":"docs/readme.md"}]'
  set_outcome "review 7 $SHA"
  set_body "$HDRTXT

$ATTTXT

Reviewed against head $SHA

Looks fine."
  rm -f "$STUB/outbox/findings.json" "$STUB/outbox/verdict"
}

set_outcome() { printf '%s\n' "$1" >"$STUB/outbox/outcome"; }
set_body() { printf '%s\n' "$1" >"$STUB/outbox/review.md"; }
set_findings() { printf '%s\n' "$1" >"$STUB/outbox/findings.json"; }
set_verdict() { printf '%s\n' "$1" >"$STUB/outbox/verdict"; }
set_compare() { # set_compare <status> <ahead_by> <files json or 'none'>
  if [ "$3" = none ]; then
    printf '{"status":"%s","ahead_by":%s}\n' "$1" "$2" >"$STUB/gh/repos_o_r_compare_${TIP}...${SHA}"
  else
    printf '{"status":"%s","ahead_by":%s,"files":%s}\n' "$1" "$2" "$3" >"$STUB/gh/repos_o_r_compare_${TIP}...${SHA}"
  fi
}
set_yml() { # set_yml <yq expression>: edit the default branch's project.yml
  yq -i "$1" "$STUB/gh/repos_o_r_contents_.ai_project.yml"
}
# The Windows directories WSL appends to PATH make every command lookup crawl; the stubs need none of them.
orig_path=$(printf '%s\n' "$PATH" | tr ':' '\n' | grep -v '^/mnt/' | paste -sd: -)

reset_logs() {
  rm -rf "$STUB/inputs" "$STUB/state" "$STUB/ct" "$STUB/logs"
  mkdir -p "$STUB/inputs"
  for x in events docker.calls gh.calls gh.seq gh.bad mint.calls mint.n mint.tokens mint.bad revoked issue.n killed rmed removed net.create vol.create wait.notes outbox.calls inject-stdin; do rm -f "$STUB/$x"; done
  rm -f "$STUB"/gh/*.reads
  : >"$STUB/events"; : >"$STUB/docker.calls"; : >"$STUB/gh.calls"; : >"$STUB/mint.calls"
}

# run <launcher args...>: the launcher from the fake bin, stdin closed, the stubs first on PATH.
run() {
  rc=0; reset_logs
  reset_logs
  env PATH="$stubs:$orig_path" REAL_SLEEP="$real_sleep" STUB_DIR="$STUB" WOW_HOME="${RUN_HOME-$home}" \
    WOW_REVIEW_TIMEOUT="${T_TIMEOUT:-20}" WOW_REVIEW_REFRESH="${T_REFRESH:-1}" WOW_REVIEW_MAX="${T_MAX:-1}" \
    GH_HOST=evil.example GITHUB_TOKEN=ghp_env GH_ENTERPRISE_TOKEN=x GITHUB_ENTERPRISE_TOKEN=x \
    sh "$home/bin/wow-review" "$@" <&- >"$tmp/out" 2>"$tmp/err" || rc=$?
  invariants
}

# What must hold across every run: the stub gh's write surface, tokens and config; the credential.
invariants() {
  if [ -f "$STUB/gh.calls" ] && [ -s "$STUB/gh.calls" ]; then
    badw=$(awk -F'|' '
      $7 == "graphql" { next }
      $5 == "" && $8 == "" { next }
      $5 == "POST" && $8 != "" && $7 == "repos/o/r/pulls/7/reviews" { next }
      $5 == "POST" && $8 != "" && ($7 == "repos/o/r/issues" || $7 == "repos/o/backlog/issues") { next }
      $5 == "DELETE" && $8 == "" && $7 == "installation/token" { next }
      { print }' "$STUB/gh.calls")
    [ -z "$badw" ] || bad "a gh write other than the three allowed: $badw"
    for n in $(awk -F'|' '$7 == "graphql" {print $8}' "$STUB/gh.calls"); do
      [ "$(jq -c . <"$STUB/inputs/$n")" = '{"query":"{ viewer { login databaseId } }"}' ] || bad "a graphql call that is not the fixed viewer query"
    done
    if awk -F'|' '$2 != "ghs_" || $3 != "yes" || $4 != "github.com"' "$STUB/gh.calls" | grep -q .; then
      bad "a gh call without a ghs_ token, an empty GH_CONFIG_DIR or --hostname github.com: $(awk -F'|' '$2 != "ghs_" || $3 != "yes" || $4 != "github.com"' "$STUB/gh.calls" | head -1)"
    fi
    if awk -F'|' '$7 == "graphql" && $8 == "" {print}' "$STUB/gh.calls" | grep -q .; then bad "a graphql call without --input"; fi
  fi
  [ ! -s "$STUB/gh.bad" ] || { bad "gh saw a forbidden flag or environment: $(head -1 "$STUB/gh.bad")"; }
  [ ! -s "$STUB/mint.bad" ] || bad "MSYS conversion switches leaked into a child"
  if [ -f "$STUB/docker.calls" ] && grep -qF -- "$CRED" "$STUB/docker.calls"; then bad "the credential is in a docker argument"; fi
  if grep -rlF -- "$CRED" "$home" 2>/dev/null | grep -v '/claude-credential$' | grep -q .; then bad "the credential is in a file under WOW_HOME"; fi
}

# =========================================================================================
# --- helpers over the recorded calls -------------------------------------------------------
# =========================================================================================
ev() { cat "$STUB/events"; }
ev_line() { grep -n -m1 -- "$1" "$STUB/events" | cut -d: -f1; }                       # first line of an event
ev_last() { grep -n -- "$1" "$STUB/events" | tail -1 | cut -d: -f1; }
ev_count() { grep -c -- "$1" "$STUB/events" 2>/dev/null || true; }
dcalls() { cat "$STUB/docker.calls"; }
n_posts() { grep -c '|POST||repos/o/r/pulls/7/reviews|' "$STUB/gh.calls" 2>/dev/null || true; }
n_issues() { grep -c '|POST||repos/o/[a-z]*/issues|' "$STUB/gh.calls" 2>/dev/null || true; }
post_input() { grep '|POST||repos/o/r/pulls/7/reviews|' "$STUB/gh.calls" | tail -1 | awk -F'|' '{print $8}'; }
post_body() { jq -j .body <"$STUB/inputs/$(post_input)" | tr -d '\r'; }
n_dockers() { grep -c . "$STUB/docker.calls" 2>/dev/null || true; }
entry_dir() { printf '%s/review-state/o/r/7/%s' "$home" "$SHA"; }
dirs_gone() { [ -z "$(ls -A "$home/review-sessions" 2>/dev/null)" ] && [ -z "$(ls -A "$home/review-host" 2>/dev/null)" ] && [ ! -d "$home/review-state/.lock" ]; }
failure_text() { # failure_text <code>
  printf 'Automated architect review: no review posted for head %s (%s). The review gate stays red. Rerun on the host: wow-review o/r 7 --rerun' "$SHA" "$1"
}
expect_failure_post() { # expect_failure_post <label> <code>
  assert_eq "$1: exit 3" 3 "$rc"
  assert_eq "$1: one POST" 1 "$(n_posts)"
  assert_eq "$1: the fixed template with $2" "$(failure_text "$2")" "$(post_body)"
  check "$1: both directories and the lock are gone" dirs_gone
  if post_body | grep -qF -e "$HDRTXT" -e "$ATTTXT"; then bad "$1: the failure body holds a frozen string"; else ok "$1: no frozen string in the failure body"; fi
}

# =========================================================================================
# --- helpers the sections share (defined before any section starts) ------------------------
# =========================================================================================
untouched() { # untouched <label>: no mint, gh or docker call was made
  assert_eq "$1: no mint" 0 "$(grep -c . "$STUB/mint.calls")"
  assert_eq "$1: no gh" 0 "$(grep -c . "$STUB/gh.calls")"
  assert_eq "$1: no docker" 0 "$(grep -c . "$STUB/docker.calls")"
}
dl_of() { printf '%s' "$1" | grep -o '\[wow.review.deadline=[0-9]*\]' | head -n 1; }
no_docker() { assert_eq "$1: no docker call" 0 "$(grep -c . "$STUB/docker.calls")"; }
no_post() { assert_eq "$1: nothing posted" 0 "$(n_posts)"; }
key_case() { # key_case <label> <file content, printf format>: a run with a key file already there
  new_case
  mkdir -p "$home/review-state"; printf -- "$2" >"$home/review-state/.home-key"
}
review_doc() { # review_doc <uid> <commit> <state> <submitted_at json> [body]
  jq -n --argjson uid "$1" --arg c "$2" --arg s "$3" --argjson t "$4" --arg b "${5-$HDRTXT

$ATTTXT

other text}" '{user:{id:$uid}, commit_id:$c, state:$s, submitted_at:$t, body:$b}'
}
vbody() { printf '%s\n\n%s\n\nReview verdict: %s\n\nrest' "$HDRTXT" "$ATTTXT" "$1"; }
exempt_case() { # exempt_case <label> <compare files json or none> [yq edit] [status] [ahead_by]
  new_case; set_outcome "exempt 7 $SHA"
  [ -z "${3:-}" ] || set_yml "$3"
  set_compare "${4:-ahead}" "${5:-2}" "$2"
  run o/r 7
  expect_failure_post "exempt ($1)" bad-outcome
  if grep -E '/compare/' "$STUB/gh.calls" | grep -vE "\|repos/o/r/compare/[0-9a-f]{40}\.\.\.[0-9a-f]{40}\|" | grep -q .; then bad "exempt ($1): a compare call sent something other than two SHAs"; fi
}
body_case() { # body_case <label> <code> <extra text>
  new_case
  set_body "$HDRTXT

$ATTTXT

Reviewed against head $SHA

$3"
  run o/r 7
  expect_failure_post "$1" "$2"
}
findings_case() { # findings_case <label> <code> <findings json>
  new_case; set_findings "$3"
  run o/r 7
  assert_eq "findings ($1): the review posts, exit 0" 0 "$rc"
  assert_eq "findings ($1): the footer" "Host: findings not filed ($2)" "$(post_body | tail -1)"
  assert_eq "findings ($1): nothing filed" 0 "$(n_issues)"
}
FIND1='[{"title":"T","body":"b","type":"bug"}]'
BEFORE=2026-10-17T16:00:00Z; AFTER=2026-10-17T17:00:00Z; SUBMITTED=2026-10-17T16:35:56Z
glog() { cat "$home"/review-logs/*.log; }
gpolls() { glog | grep -c -E 'gate poll [0-9]'; }
gline() { glog | grep -c -E -- "Z gate poll $1\$"; }                  # gline <text>: that exact poll line
status_doc() { # status_doc <context> <state> <updated_at json>
  printf '{"statuses":[{"context":"%s","state":"%s","updated_at":%s}]}\n' "$1" "$2" "$3"
}
run_gate_case() { # run_gate_case <label>: golden path, exit 0 and the one finding filed
  run o/r 7
  assert_eq "$1: exit 0" 0 "$rc"
  assert_eq "$1: the finding is filed" 1 "$(n_issues)"
}
gate_case() { new_case; set_findings "$FIND1"; printf '{"check_runs":[{"name":"ci","status":"completed","conclusion":"success"}]}\n' >"$STUB/gh/repos_o_r_commits_${SHA}_check-runs"; }
pre_case() { # pre_case <label> <stub file under docker/> <jq filter>
  new_case; printf '%s\n' "$3" >"$STUB/docker/$2"
  run o/r 7
  assert_eq "preflight ($1): exit 1" 1 "$rc"
  assert_eq "preflight ($1): the session was not started" 0 "$(ev_count 'docker-start wow-review-session')"
  check "preflight ($1): the never-started entry is freed" test ! -d "$(entry_dir)"
  check "preflight ($1): directories gone" dirs_gone
}
no_leftover() { ! ps -ef 2>/dev/null | grep -F "$home/bin/wow-review" | grep -v grep | grep -q .; }
cleaned() { # cleaned <label>
  check "$1: both directories and the lock are gone" dirs_gone
  check "$1: no launcher or refresher process is left" no_leftover
  for c in session holder inject proxy; do check "$1: docker rm -f of the $c" has "$STUB/events" "docker-rm wow-review-$c-"; done
  check "$1: both networks removed" has "$STUB/events" "docker-net-rm wow-review-net-"
  check "$1: both volumes removed" has "$STUB/events" "docker-vol-rm -f wow-review-work-"
}

sec_args() {
# =========================================================================================
# --- arguments and environment: exit 2 before any mint, gh or docker call ----------------
# =========================================================================================
new_case
for argv in "a" "a/b/c" "-a/b" "a/.." "o/r 0" "o/r 012" "o/r x" "o/r 7 --bogus" "o/r 7 --rerun --rerun" "o/r" "o/r 7 8" "/r 7" "o/ 7"; do
  # shellcheck disable=SC2086
  run $argv
  assert_eq "usage [$argv]: exit 2" 2 "$rc"
  untouched "usage [$argv]"
done
RUN_HOME=""; run o/r 7
assert_eq "unset WOW_HOME: exit 2" 2 "$rc"
untouched "unset WOW_HOME"
RUN_HOME=relative/path; run o/r 7
assert_eq "relative WOW_HOME: exit 2" 2 "$rc"
untouched "relative WOW_HOME"
unset RUN_HOME
for tv in "WOW_REVIEW_MAX=0" "WOW_REVIEW_MAX=10" "WOW_REVIEW_MAX=x" "WOW_REVIEW_TIMEOUT=6001" "WOW_REVIEW_TIMEOUT=0" "WOW_REVIEW_REFRESH=1501" "WOW_REVIEW_REFRESH=07"; do
  rc=0; reset_logs
  env PATH="$stubs:$orig_path" STUB_DIR="$STUB" WOW_HOME="$home" "$tv" sh "$home/bin/wow-review" o/r 7 <&- >"$tmp/out" 2>"$tmp/err" || rc=$?
  assert_eq "tunable $tv: exit 2" 2 "$rc"
  untouched "tunable $tv"
done
:
}

sec_golden() {
# =========================================================================================
# --- the golden run: a valid review, same-owner backlog, two findings ----------------------
# =========================================================================================
new_case
set_yml '.backlog.repo = "o/backlog"'
set_findings '[{"title":"Missing test for x","body":"Detail with a ```` run of four backticks.","type":"bug","area":"area/x"},{"title":"Second","body":"plain","type":"docs"}]'
mkdir -p "$home/review-tokens/r"; printf 'untouched\n' >"$home/review-tokens/r/reviewer-token"
printf 'x\n' >"$STUB/wait.sleep.unused"; printf '3\n' >"$STUB/wait.sleep"
run o/r 7
assert_eq "golden: exit 0" 0 "$rc"
[ "$rc" = 0 ] || { sed 's/^/  stderr: /' "$tmp/err" >&2; tail -20 "$home"/review-logs/*.log >&2; }
assert_eq "golden: one review POST" 1 "$(n_posts)"
assert_eq "golden: two issue POSTs" 2 "$(n_issues)"
assert_eq "golden: the POST body is the outbox body, a blank line, the footer" \
  "$(cat "$STUB/outbox/review.md")

Host: 2 findings will be filed in o/backlog" "$(post_body)"
assert_eq "golden: the POST --input has exactly commit_id, event, body" 'body,commit_id,event' "$(jq -r 'keys | join(",")' <"$STUB/inputs/$(post_input)")"
assert_eq "golden: commit_id is the pin" "$SHA" "$(jq -r .commit_id <"$STUB/inputs/$(post_input)")"
assert_eq "golden: event is COMMENT" COMMENT "$(jq -r .event <"$STUB/inputs/$(post_input)")"
check "golden: the entry is kept" test -d "$(entry_dir)"
check "golden: both directories and the lock are gone" dirs_gone
assert_eq "golden: the in-session review-tokens file is untouched" untouched "$(cat "$home/review-tokens/r/reviewer-token")"
check "golden: the credential reached only the injector's stdin" test "$(cat "$STUB/inject-stdin")" = "$CRED"

# mints
m1=$(sed -n 1p "$STUB/mint.calls")
case $m1 in
  "1 r --read --out $home/review-sessions/r-7-"*"/session-token") ok "golden: the first mint is --read into the mounted directory" ;;
  *) bad "golden: the first mint was [$m1]" ;;
esac
hasre "$STUB/mint.calls" "^2 r --read --also backlog --out $home/review-sessions/r-7-[0-9-]+/session-token\$" && ok "golden: the backlog mint adds --also backlog" || bad "golden: no --also mint"
hasre "$STUB/mint.calls" "^[0-9]+ r --read --also backlog --out $home/review-host/r-7-[0-9-]+/read-token\$" && ok "golden: the read-token is minted into the host directory" || bad "golden: no read-token mint"
hasre "$STUB/mint.calls" "^[0-9]+ r --out $home/review-host/r-7-[0-9-]+/post-token\$" && ok "golden: the post mint goes to <host dir>/post-token" || bad "golden: post mint"
hasre "$STUB/mint.calls" "^[0-9]+ backlog --file --out $home/review-host/r-7-[0-9-]+/filing-token\$" && ok "golden: the filing mint is --file into the host directory" || bad "golden: filing mint"
if grep -q 'review-tokens' "$STUB/mint.calls"; then bad "golden: a mint wrote to review-tokens/"; else ok "golden: no mint to review-tokens/"; fi
if grep -E -- '--read.*--out .*/review-host/' "$STUB/mint.calls" | grep -v read-token | grep -q .; then bad "golden: a session token went to the host directory"; else ok "golden: session tokens only in the mounted directory"; fi
reads=$(grep -c -- '--read' "$STUB/mint.calls")
check "golden: first, backlog, re-mint, at least one refresher mint, then the read token ($reads)" test "$reads" -ge 5
check "golden: the filing mint comes after the review POST" test "$(ev_line mint-file)" -gt "$(ev_line gh-POST-review)"
check "golden: the post mint comes after the wait" test "$(ev_last mint-post)" -gt "$(ev_line docker-wait-done)"

# revocation: every session token, once, at the end of the wait and before any outbox-read
sess=$(grep '^read ' "$STUB/mint.tokens" | sed '$d' | sed 's/^read //' | sort -u)
revd=$(sort -u "$STUB/revoked")
assert_eq "golden: every session token minted was revoked, once each" "$sess" "$revd"
assert_eq "golden: no token revoked twice" "$(sort "$STUB/revoked" | uniq | wc -l | tr -d ' ')" "$(grep -c . "$STUB/revoked")"
check "golden: no revocation before the wait ended" test "$(ev_line gh-DELETE)" -gt "$(ev_line docker-wait-done)"
check "golden: every revocation precedes the first outbox-read" test "$(ev_last gh-DELETE)" -lt "$(ev_line docker-outbox-read)"

# docker create argv
cs=$(grep '^CALL \[create\].*wow-review-session' "$STUB/docker.calls")
for want in "[--label] [wow.review=1]" "[--read-only]" "[--cap-drop] [ALL]" "[no-new-privileges]" "[--log-opt] [max-size=10m]" "[--log-opt] [max-file=1]" "[--log-opt] [compress=false]" \
    "[/home/app:rw,exec,nosuid,uid=1000,gid=1000,mode=0700,size=1g]" "[/tmp:rw,nosuid,size=512m]" "volume-nocopy=true]" \
    "target=/run/glunk-identity/review,readonly]" "target=/work,volume-nocopy=true]" "target=/review-out,volume-nocopy=true]" \
    "[WOW_REVIEW_SHA=$SHA]" "[WOW_REVIEW_MODEL=opus]" "[WOW_REVIEW_REPO=o/r]" "[WOW_REVIEW_PR=7]" \
    "[CLAUDE_CODE_OAUTH_TOKEN=wow-review-placeholder-not-a-credential]"; do
  case $cs in *"$want"*) ok "golden: session create has $want" ;; *) bad "golden: session create lacks $want: $cs" ;; esac
done
case $cs in *"wow.review.deadline="*) ok "golden: the deadline label" ;; *) bad "golden: no deadline label" ;; esac
case $cs in *"docker.sock"*) bad "golden: docker.sock" ;; *) ok "golden: no docker.sock" ;; esac
assert_eq "golden: exactly three --mount arguments on the session" 3 "$(printf '%s' "$cs" | grep -o '\[--mount\]' | wc -l | tr -d ' ')"
for want in "[NO_PROXY=wow-review-inject-" "[no_proxy=wow-review-inject-" "[ANTHROPIC_BASE_URL=http://wow-review-inject-" "[HTTPS_PROXY=http://wow-review-proxy-" "[HTTP_PROXY=http://wow-review-proxy-"; do
  case $cs in *"$want"*) ok "golden: session env has $want" ;; *) bad "golden: session env lacks $want" ;; esac
done
sc=$(dcalls)
hold=$(grep '^CALL \[run\].*\[--name\] \[wow-review-holder-' "$STUB/docker.calls")
case $hold in *"[--network] [none]"*"[--read-only]"*"[--cap-drop] [ALL]"*) ok "golden: the holder is network-less, read-only, caps dropped" ;; *) bad "golden: the holder flags: $hold" ;; esac
case $hold in *"wow.review.holder=1"*) ok "golden: the holder label" ;; *) bad "golden: holder label" ;; esac
case $hold in *"[wow.review=1]"*) bad "golden: the holder carries the counted label" ;; *) ok "golden: the holder is not counted by the cap" ;; esac
case $hold in *"target=/review-out,readonly,volume-nocopy=true]"*) ok "golden: the holder mounts the outbox read-only" ;; *) bad "golden: holder mount" ;; esac
assert_eq "golden: the holder mounts only the outbox" 1 "$(printf '%s' "$hold" | grep -o '\[--mount\]' | wc -l | tr -d ' ')"
check "golden: the holder runs before the session is created" test "$(ev_line 'docker-run wow-review-holder')" -lt "$(ev_line 'docker-create wow-review-session')"
check "golden: the holder is removed" has "$STUB/events" "docker-rm wow-review-holder-"
pr=$(grep '^CALL \[run\].*\[--name\] \[wow-review-proxy-' "$STUB/docker.calls")
ij=$(grep '^CALL \[create\].*\[--name\] \[wow-review-inject-' "$STUB/docker.calls")
case $pr in *"[--entrypoint] [python3]"*"/opt/review/proxy.py]"*) ok "golden: the proxy uses --entrypoint python3" ;; *) bad "golden: proxy entrypoint: $pr" ;; esac
case $ij in *"[--entrypoint] [python3]"*"/opt/review/inject.py]"*) ok "golden: the injector uses --entrypoint python3" ;; *) bad "golden: injector entrypoint: $ij" ;; esac
case $pr in *"LOOP_ALLOW_HOSTS=github.com,api.github.com]"*) ok "golden: the proxy allows only the two GitHub hosts" ;; *) bad "golden: proxy hosts" ;; esac
case $ij in *"LOOP_CREDENTIAL_ENV=CLAUDE_CODE_OAUTH_TOKEN]"*"[-i]"*|*"[-i]"*"LOOP_CREDENTIAL_ENV=CLAUDE_CODE_OAUTH_TOKEN]"*) ok "golden: the injector is created -i with the credential variable named" ;; *) bad "golden: injector create: $ij" ;; esac
for h in "$pr" "$ij"; do
  case $h in *"[--read-only]"*"[--cap-drop] [ALL]"*"no-new-privileges"*"[--pids-limit] [512]"*"[--memory] [256m]"*"/tmp:rw,nosuid,size=16m"*) ok "golden: a sidecar is hardened" ;; *) bad "golden: sidecar hardening: $h" ;; esac
done
# every sidecar carries the session's log cap on its own call; the patterns name the container, so the
# session's create line (whose env values name the injector) cannot satisfy a sidecar check
assert_eq "golden: exactly one proxy run call" 1 "$(grep -c '^CALL \[run\].*\[--name\] \[wow-review-proxy-' "$STUB/docker.calls")"
assert_eq "golden: exactly one injector create call" 1 "$(grep -c '^CALL \[create\].*\[--name\] \[wow-review-inject-' "$STUB/docker.calls")"
assert_eq "golden: exactly one holder run call" 1 "$(grep -c '^CALL \[run\].*\[--name\] \[wow-review-holder-' "$STUB/docker.calls")"
for pair in "proxy|$pr" "injector|$ij" "holder|$hold"; do
  who=${pair%%|*}; call=${pair#*|}
  for want in "[--log-opt] [max-size=10m]" "[--log-opt] [max-file=1]" "[--log-opt] [compress=false]"; do
    case $call in *"$want"*) ok "golden: the $who has $want" ;; *) bad "golden: the $who lacks $want: $call" ;; esac
  done
  assert_eq "golden: exactly three --log-opt arguments on the $who" 3 "$(printf '%s' "$call" | grep -o '\[--log-opt[]=]' | wc -l | tr -d ' ')"
  assert_eq "golden: no --log-driver argument on the $who" 0 "$(printf '%s' "$call" | grep -o '\[--log-driver[]=]' | wc -l | tr -d ' ')"
done
for pair in "proxy|$pr" "injector|$ij"; do
  who=${pair%%|*}; call=${pair#*|}
  case $call in *"[--label] [wow.review.sidecar=1]"*) ok "golden: the $who carries the sweep label" ;; *) bad "golden: the $who lacks the sweep label: $call" ;; esac
  case $call in *"[--label] [wow.review.deadline="*) ok "golden: the $who carries a deadline label" ;; *) bad "golden: the $who lacks a deadline label: $call" ;; esac
  case $call in *"[wow.review=1]"*) bad "golden: the $who carries the counted label" ;; *) ok "golden: the $who is not counted by the cap" ;; esac
done
sc=$(grep '^CALL \[create\].*wow-review-session' "$STUB/docker.calls")
assert_eq "golden: the launcher takes its deadline in exactly one place" 1 "$(grep -c '^[[:space:]]*DL=' "$root_dir/scripts/identity/wow-review")"
assert_eq "golden: the proxy and the holder carry one deadline" "$(dl_of "$hold")" "$(dl_of "$pr")"
assert_eq "golden: the injector and the holder carry one deadline" "$(dl_of "$hold")" "$(dl_of "$ij")"
assert_eq "golden: the session and the holder carry one deadline" "$(dl_of "$hold")" "$(dl_of "$sc")"
check "golden: the internal isolated network" has "$STUB/net.create" "--internal -o com.docker.network.bridge.gateway_mode_ipv4=isolated wow-review-net-"
# the home key (#815): created from the run's own id, and the label of every container, network and volume
hk=$(cat "$home/review-state/.home-key" 2>/dev/null)
case $hk in [0-9]*-[0-9]*) ok "golden: the home key file was created, epoch-pid" ;; *) bad "golden: the home key is '$hk'" ;; esac
for who_call in "session|$cs" "proxy|$pr" "injector|$ij" "holder|$hold"; do
  who=${who_call%%|*}; call=${who_call#*|}
  case $call in *"[--label] [wow.review.home=$hk]"*) ok "golden: the $who carries the home label" ;; *) bad "golden: the $who lacks the home label: $call" ;; esac
done
assert_eq "golden: the proxy and the holder carry the home label right after run" 2 "$(grep -c "^CALL \[run\] \[--label\] \[wow.review.home=$hk\]" "$STUB/docker.calls")"
assert_eq "golden: the injector and the session carry the home label right after create" 2 "$(grep -c "^CALL \[create\] \[--label\] \[wow.review.home=$hk\]" "$STUB/docker.calls")"
check "golden: the sweep lists id, deadline and home, pipe-separated" has "$STUB/docker.calls" '[--format] [{{.ID}}|{{.Label "wow.review.deadline"}}|{{.Label "wow.review.home"}}]'
check "golden: the cap lists id and home, pipe-separated" has "$STUB/docker.calls" '[--format] [{{.ID}}|{{.Label "wow.review.home"}}]'
assert_eq "golden: both network create calls carry the home label" 2 "$(grep -c -- "^--label wow.review.home=$hk " "$STUB/net.create")"
assert_eq "golden: both volume create calls carry the home label" 2 "$(grep -c -- "^--label wow.review.home=$hk " "$STUB/vol.create")"
assert_eq "golden: two volumes created, tmpfs-backed with the session's ownership" 2 "$(grep -c 'type=tmpfs --opt device=tmpfs --opt o=size=.*uid=1000,gid=1000' "$STUB/vol.create")"
check "golden: the work volume is 2g and the outbox 64m" sh -c "grep -q 'size=2g' '$STUB/vol.create' && grep -q 'size=64m' '$STUB/vol.create'"
# order and cleanup
check "golden: docker logs comes before any removal" test "$(ev_line 'docker-logs session')" -lt "$(ev_line 'docker-rm ')"
check "golden: every outbox-read follows the wait" test "$(ev_line docker-outbox-read)" -gt "$(ev_line docker-wait-done)"
check "golden: every outbox-read follows the not-running inspect" test "$(ev_line docker-outbox-read)" -gt "$(ev_last 'docker-inspect session')"
for k in outcome body findings; do check "golden: outbox-read $k ran" has "$STUB/events" "docker-outbox-read-$k"; done
while IFS= read -r l; do
  case $l in
    *"--network none --read-only --cap-drop ALL --security-opt no-new-privileges"*"readonly,volume-nocopy=true --entrypoint /usr/local/libexec/outbox-read "*) ok "golden: an outbox-read is isolated and read-only" ;;
    *) bad "golden: an outbox-read call: $l" ;;
  esac
done <"$STUB/outbox.calls"
for c in session holder inject proxy; do check "golden: docker rm -f of the $c" has "$STUB/events" "docker-rm wow-review-$c-"; done
check "golden: both networks removed" has "$STUB/events" "docker-net-rm wow-review-net-"
check "golden: both volumes removed" has "$STUB/events" "docker-vol-rm -f wow-review-work-"
check "golden: the lock was released during the wait" has "$STUB/wait.notes" lock-gone
# the footer, filing
assert_eq "golden: the first issue request" \
  "Non-blocking finding from the automated architect review of o/r#7 at $SHA: https://github.com/o/r/pull/7#pullrequestreview-555. Written by the review session; not yet read by a human.

\`\`\`\`\`
Detail with a \`\`\`\` run of four backticks.
\`\`\`\`\`" "$(jq -r .body <"$STUB/inputs/$(grep '|POST||repos/o/backlog/issues|' "$STUB/gh.calls" | head -1 | awk -F'|' '{print $8}')")"
assert_eq "golden: labels kept only where the stub answers (area/x is not there, bug is)" '["bug"]' "$(jq -c .labels <"$STUB/inputs/$(grep '|POST||repos/o/backlog/issues|' "$STUB/gh.calls" | head -1 | awk -F'|' '{print $8}')")"
check "golden: area/x was read as area%2Fx" has "$STUB/gh.calls" 'labels/area%2Fx'
assert_eq "golden: the second issue has a three-backtick fence" '```' "$(jq -r .body <"$STUB/inputs/$(grep '|POST||repos/o/backlog/issues|' "$STUB/gh.calls" | tail -1 | awk -F'|' '{print $8}')" | tail -1)"
assert_eq "golden: the filed ledger lines" "0 101
1 102" "$(cat "$(entry_dir)/filed")"
check "golden: the outcome is recorded" test "$(cat "$(entry_dir)/outcome")" = "0 reviewed"
check "golden: no write call used a field flag" test ! -s "$STUB/gh.bad"
:
}

sec_schema() {
# =========================================================================================
# --- the schema: exit 6 before any docker call ---------------------------------------------
# =========================================================================================
while IFS='|' read -r label expr; do
  new_case
  set_yml "$expr"
  run o/r 7
  assert_eq "schema ($label): exit 6" 6 "$rc"
  no_docker "schema ($label)"; no_post "schema ($label)"
done <<'EOF'
identities null|.identities = null
no reviewer_app|del(.identities.reviewer_app)
non-integer reviewer id|.identities.reviewer_app.id = "abc"
null ci_gate|.review.ci_gate = null
no triggers and no code_paths|del(.review.ci_gate.triggers_on) | del(.code_paths)
empty trigger list|.review.ci_gate.triggers_on = []
bad models.architect|.models.architect = "-x y"
missing models.architect|del(.models.architect)
malformed backlog.repo|.backlog.repo = "a/b/c"
attestation not a string|.review.ci_gate.attestation = 5
EOF
new_case
set_yml 'del(.review.ci_gate.triggers_on) | .code_paths = ["src/"]'
run o/r 7
assert_eq "schema: a null triggers_on falls back to code_paths" 0 "$rc"
:
}

sec_ident() {
# =========================================================================================
# --- the identity and the PR: exit 1 before any docker call --------------------------------
# =========================================================================================
new_case; printf '{"repositories":[{"full_name":"o/other"}]}\n' >"$STUB/gh/installation_repositories"
run o/r 7; assert_eq "identity (not reached): exit 1" 1 "$rc"; no_docker "identity (not reached)"
new_case; printf '{"data":{"viewer":{"login":"someone-else[bot]","databaseId":9999}}}\n' >"$STUB/gh/graphql"
run o/r 7; assert_eq "identity (another App): exit 1" 1 "$rc"; no_docker "identity (another App)"
new_case; : >"$STUB/mint.expired.1"
run o/r 7; assert_eq "identity (expired token file): exit 1" 1 "$rc"; no_docker "identity (expired)"
assert_eq "identity (expired token file): no gh call was made with it, not even a revocation" 0 "$(grep -c . "$STUB/gh.calls")"
new_case; printf '{"state":"closed","head":{"sha":"%s"},"base":{"ref":"main"}}\n' "$SHA" >"$STUB/gh/repos_o_r_pulls_7"
run o/r 7; assert_eq "PR (closed): exit 1" 1 "$rc"; no_docker "PR (closed)"
new_case; printf '{"state":"open","head":{"sha":"NOTAHEX"},"base":{"ref":"main"}}\n' >"$STUB/gh/repos_o_r_pulls_7"
run o/r 7; assert_eq "PR (malformed head): exit 1" 1 "$rc"; no_docker "PR (malformed head)"
new_case; printf '{"state":"open","head":{"sha":"%s"},"base":{"ref":"a/../b"}}\n' "$SHA" >"$STUB/gh/repos_o_r_pulls_7"
run o/r 7; assert_eq "PR (base ref with a .. segment): exit 1" 1 "$rc"; no_docker "PR (bad base ref)"
new_case; printf '{"default_branch":"-main"}\n' >"$STUB/gh/repos_o_r"
run o/r 7; assert_eq "default branch with a leading dash: exit 1" 1 "$rc"; no_docker "default branch"
new_case; rm -f "$STUB/gh/repos_o_r_contents_.ai_project.yml"
run o/r 7; assert_eq "no project.yml readable: exit 1" 1 "$rc"; no_docker "no project.yml"
:
}

sec_mints() {
# =========================================================================================
# --- the backlog mints -----------------------------------------------------------------------
# =========================================================================================
new_case
set_findings '[{"title":"T","body":"b","type":"chore"}]'
run o/r 7
assert_eq "null backlog: exit 0" 0 "$rc"
if grep -q -- '--also' "$STUB/mint.calls"; then bad "null backlog: --also was used"; else ok "null backlog: no --also"; fi
hasre "$STUB/mint.calls" "^[0-9]+ r --file --out $home/review-host/r-7-[0-9-]+/filing-token\$" && ok "null backlog: filing token minted for the repo itself" || bad "null backlog: filing mint"
assert_eq "null backlog: one issue filed in the repo itself" 1 "$(grep -c '|POST||repos/o/r/issues|' "$STUB/gh.calls")"
assert_eq "null backlog: the footer" "Host: 1 findings will be filed in o/r" "$(post_body | tail -1)"

for variant in "cross-owner-backlog|.backlog.repo = \"other/backlog\"" "no-issue-backlog|.backlog.kind = \"file\""; do
  code=${variant%%|*}; expr=${variant#*|}
  new_case; set_yml "$expr"
  set_findings '[{"title":"T","body":"b","type":"chore"}]'
  run o/r 7
  assert_eq "$code: exit 0" 0 "$rc"
  if grep -q -- '--also\|--file' "$STUB/mint.calls"; then bad "$code: a backlog mint was made"; else ok "$code: no backlog mint"; fi
  assert_eq "$code: no issue filed" 0 "$(n_issues)"
  assert_eq "$code: the footer says why" "Host: findings not filed ($code)" "$(post_body | tail -1)"
done

new_case; : >"$STUB/mint.fail.2"
run o/r 7
assert_eq "re-mint failure: exit 1" 1 "$rc"
assert_eq "re-mint failure: no docker start" 0 "$(ev_count 'docker-start wow-review-session')"
check "re-mint failure: the never-started entry is freed" test ! -d "$(entry_dir)"
check "re-mint failure: directories gone" dirs_gone

new_case; : >"$STUB/mint.fail.3"; printf '3\n' >"$STUB/wait.sleep"
run o/r 7
assert_eq "failed refresher mint: exit 0" 0 "$rc"
has "$(ls "$home"/review-logs/*.log)" "refresher: the re-mint FAILED" && ok "failed refresher mint: logged" || bad "failed refresher mint: not logged"
sess=$(grep '^read ' "$STUB/mint.tokens" | sed '$d' | sed 's/^read //' | sort -u)
assert_eq "failed refresher mint: every distinct session token revoked once" "$sess" "$(sort -u "$STUB/revoked")"

new_case; : >"$STUB/mint.fail.kind.post"
run o/r 7
assert_eq "post-token mint failure: exit 1" 1 "$rc"
no_post "post-token mint failure"
check "post-token mint failure: the entry is kept" test -d "$(entry_dir)"
:
}

sec_lock() {
# =========================================================================================
# --- the lock, the ledger and the cap --------------------------------------------------------
# =========================================================================================
new_case
mkdir -p "$home/review-state/.lock"; echo other-run >"$home/review-state/.lock/id"
run o/r 7
assert_eq "fresh held lock: exit 75" 75 "$rc"
assert_eq "fresh held lock: no container created" 0 "$(ev_count 'docker-create')"
assert_eq "fresh held lock: another run's lock survives this run's trap" other-run "$(cat "$home/review-state/.lock/id")"
check "fresh held lock: no entry" test ! -d "$(entry_dir)"

new_case
mkdir -p "$home/review-state/.lock"; echo other-run >"$home/review-state/.lock/id"; touch -t 202001010000 "$home/review-state/.lock"
run o/r 7
assert_eq "backdated lock: cleared, the run proceeds" 0 "$rc"
check "backdated lock: gone afterwards" test ! -d "$home/review-state/.lock"
has "$(ls "$home"/review-logs/*.log)" "cleared a stale lock" && ok "backdated lock: logged" || bad "backdated lock: not logged"

new_case
mkdir -p "$(entry_dir)"
run o/r 7
assert_eq "existing entry: exit 5" 5 "$rc"
assert_eq "existing entry: no docker call" 0 "$(grep -c . "$STUB/docker.calls")"
check "existing entry: untouched" test -d "$(entry_dir)"
check "existing entry: the lock is released" test ! -d "$home/review-state/.lock"

new_case
mkdir -p "$(entry_dir)"; : >"$STUB/mint.fail.2"
run o/r 7 --rerun
assert_eq "--rerun reuses the entry (the run then fails at the re-mint): exit 1" 1 "$rc"
check "--rerun: the entry survives an exit 1" test -d "$(entry_dir)"

new_case
mkdir -p "$(entry_dir)"
set_outcome "stopped 7 $SHA head-moved"; cp "$STUB/gh/repos_o_r_pulls_7" "$STUB/gh/repos_o_r_pulls_7.after"
sed -i 's/0123456789abcdef0123456789abcdef01234567/ffffffffffffffffffffffffffffffffffffffff/' "$STUB/gh/repos_o_r_pulls_7.after"
run o/r 7 --rerun
assert_eq "--rerun with a moved head: exit 1" 1 "$rc"
check "--rerun with a moved head: the entry is kept" test -d "$(entry_dir)"

new_case
printf 'old1 wow.review=1 9999999999\n' >"$STUB/preexisting"
run o/r 7
assert_eq "cap reached: exit 75" 75 "$rc"
check "cap reached: no entry left behind" test ! -d "$(entry_dir)"
assert_eq "cap reached: no container created" 0 "$(ev_count 'docker-create')"
check "cap reached: the lock is released" test ! -d "$home/review-state/.lock"

new_case
printf 'old1 wow.review=1 100\noldh wow.review.holder=1 100\nnodl wow.review=1\nfresh1 wow.review=1 9999999999\nsidep wow.review.sidecar=1 100\nsidei wow.review.sidecar=1 100\nsidend wow.review.sidecar=1\nsidefut wow.review.sidecar=1 9999999999\n' >"$STUB/preexisting"
T_MAX=2; run o/r 7; unset T_MAX
assert_eq "overdue sweep: the run proceeds under a cap of 2" 0 "$rc"
for c in old1 oldh nodl sidep sidei sidend; do check "overdue sweep: $c removed" has "$STUB/events" "docker-rm $c"; done
check "overdue sweep: a container with a future deadline is left running" test "$(grep -c 'docker-rm fresh1' "$STUB/events")" = 0
check "overdue sweep: a sidecar with a future deadline is left running" test "$(grep -c 'docker-rm sidefut' "$STUB/events")" = 0

# the home key and the per-home cap and sweep (#815)
new_case
run o/r 7
assert_eq "home key absent: the run proceeds" 0 "$rc"
check "home key absent: the session carries the file's value" has "$STUB/docker.calls" "[wow.review.home=$(cat "$home/review-state/.home-key")]"
check "home key absent: the key has the epoch-pid form" sh -c "grep -Eqx '[0-9]+-[0-9]+' '$home/review-state/.home-key'"
check "home key absent: no temporary file is left" test -z "$(ls -A "$home/review-state" | grep '^\.home-key\.')"
key_case x '4-2\n'
run o/r 7
assert_eq "home key present: the run proceeds" 0 "$rc"
assert_eq "home key present: the file is unchanged" 4-2 "$(cat "$home/review-state/.home-key")"
check "home key present: the session carries it" has "$STUB/docker.calls" "[wow.review.home=4-2]"
key_case x '4-2\r\n'
run o/r 7
assert_eq "home key with a carriage return: the run proceeds" 0 "$rc"
check "home key with a carriage return: the label is the bare key" has "$STUB/docker.calls" "[wow.review.home=4-2]"
for bad_key in "empty|" "three parts|1-2-3\n" "second line|1-2\n3-4\n" "no hyphen|12\n" "letters|a-b\n" "trailing hyphen|1-\n" "leading hyphen|-1\n"; do
  bk_label=${bad_key%%|*}; bk=${bad_key#*|}
  key_case x "$bk"
  run o/r 7
  assert_eq "malformed home key ($bk_label): exit 1" 1 "$rc"
  assert_eq "malformed home key ($bk_label): no container, network or volume created" 0 "$(ev_count 'docker-create\|docker-run\|docker-net-create\|docker-vol-create')"
  assert_eq "malformed home key ($bk_label): no docker call at all" 0 "$(n_dockers)"
  check "malformed home key ($bk_label): the lock is released" test ! -d "$home/review-state/.lock"
done

new_case
mkdir -p "$home/review-state/.lock"; echo other-run >"$home/review-state/.lock/id"
run o/r 7
assert_eq "home key: a held lock exits 75" 75 "$rc"
check "home key: a held lock leaves no key file" test ! -e "$home/review-state/.home-key"
key_case x '7-7\n'; rm -f "$home/review-state/.home-key"; mkdir "$home/review-state/.home-key"
run o/r 7
assert_eq "home key: an unreadable key (a directory) exits 1" 1 "$rc"
assert_eq "home key: an unreadable key makes no docker call" 0 "$(n_dockers)"
key_case x '7-7\n'
printf 'own1 wow.review=1 9999999999 home=7-7\nother1 wow.review=1 9999999999 home=8-8\n' >"$STUB/preexisting"
T_MAX=2; run o/r 7; unset T_MAX
assert_eq "cap: one own and one other-home live session under a cap of 2 proceeds" 0 "$rc"
key_case x '7-7\n'
printf 'own1 wow.review=1 9999999999 home=7-7\nold1 wow.review=1 9999999999\n' >"$STUB/preexisting"
T_MAX=2; run o/r 7; unset T_MAX
assert_eq "cap: one own and one unlabelled live session under a cap of 2 is busy" 75 "$rc"

key_case x '7-7\n'
printf 'other1 wow.review=1 9999999999 home=8-8\n' >"$STUB/preexisting"
run o/r 7
assert_eq "cap: another home's live session does not make the run busy" 0 "$rc"
key_case x '7-7\n'
printf 'own1 wow.review=1 9999999999 home=7-7\n' >"$STUB/preexisting"
run o/r 7
assert_eq "cap: this home's live session makes the run busy" 75 "$rc"
assert_eq "cap: busy, no container created" 0 "$(ev_count 'docker-create')"
key_case x '7-7\n'
printf 'old1 wow.review=1 9999999999\n' >"$STUB/preexisting"
run o/r 7
assert_eq "cap: an unlabelled live session still counts" 75 "$rc"

key_case x '7-7\n'
printf 'xs wow.review=1 100 home=8-8\nxh wow.review.holder=1 100 home=8-8\nxc wow.review.sidecar=1 100 home=8-8\nxn wow.review=1 home=8-8\n' >"$STUB/preexisting"
run o/r 7
assert_eq "sweep: another home's overdue containers do not stop the run" 0 "$rc"
for c in xs xh xc xn; do check "sweep: another home's $c is left" test "$(grep -c "docker-rm $c\$" "$STUB/events")" = 0; done
key_case x '7-7\n'
printf 'os wow.review=1 100 home=7-7\noh wow.review.holder=1 100 home=7-7\noc wow.review.sidecar=1 100 home=7-7\n' >"$STUB/preexisting"
run o/r 7
assert_eq "sweep: this home's overdue containers are removed and the run proceeds" 0 "$rc"
for c in os oh oc; do check "sweep: this home's $c is removed" has "$STUB/events" "docker-rm $c"; done

# the ledger rule
new_case
set_outcome "stopped 7 $SHA checks-pending"
printf '{"check_runs":[{"name":"ci","status":"in_progress","conclusion":null},{"name":"gate","status":"completed","conclusion":"failure"}]}\n' >"$STUB/gh/repos_o_r_commits_${SHA}_check-runs"
run o/r 7
assert_eq "verified checks-pending: exit 1" 1 "$rc"; no_post "verified checks-pending"
check "verified checks-pending: the entry is freed" test ! -d "$(entry_dir)"
assert_eq "verified checks-pending: the counter is incremented" 1 "$(cat "$(entry_dir).frees")"
new_case
set_outcome "stopped 7 $SHA checks-pending"; mkdir -p "$home/review-state/o/r/7"; printf '3\n' >"$(entry_dir).frees"
printf '{"check_runs":[{"name":"ci","status":"queued","conclusion":null}]}\n' >"$STUB/gh/repos_o_r_commits_${SHA}_check-runs"
run o/r 7
expect_failure_post "checks-pending on the fourth" retry-limit
check "checks-pending on the fourth: the entry is kept" test -d "$(entry_dir)"
new_case
set_outcome "stopped 7 $SHA checks-pending"; mkdir -p "$(entry_dir)"
printf '{"check_runs":[{"name":"ci","status":"queued","conclusion":null}]}\n' >"$STUB/gh/repos_o_r_commits_${SHA}_check-runs"
run o/r 7 --rerun
assert_eq "checks-pending under --rerun: exit 1, nothing posted" 1 "$rc"; no_post "checks-pending under --rerun"
check "checks-pending under --rerun: the entry is never freed and no free is counted" test -d "$(entry_dir)" -a ! -e "$(entry_dir).frees"
new_case
set_outcome "stopped 7 $SHA checks-pending"
run o/r 7
expect_failure_post "checks-pending with every required check finished" stopped-checks-pending
new_case
set_outcome "stopped 7 $SHA checks-pending"
printf '{"check_runs":[{"name":"ci","status":"completed","conclusion":"success"},{"name":"added-by-pr","status":"in_progress","conclusion":null}]}\n' >"$STUB/gh/repos_o_r_commits_${SHA}_check-runs"
run o/r 7
expect_failure_post "checks-pending when only a check the PR added is running" stopped-checks-pending
new_case
set_outcome "stopped 7 $SHA head-moved"
cp "$STUB/gh/repos_o_r_pulls_7" "$STUB/gh/repos_o_r_pulls_7.after"
sed -i 's/0123456789abcdef0123456789abcdef01234567/ffffffffffffffffffffffffffffffffffffffff/' "$STUB/gh/repos_o_r_pulls_7.after"
run o/r 7
assert_eq "confirmed head-moved: exit 1" 1 "$rc"; no_post "confirmed head-moved"
check "confirmed head-moved: the entry is kept" test -d "$(entry_dir)"
check "confirmed head-moved: no free counted" test ! -e "$(entry_dir).frees"
new_case
set_outcome "stopped 7 $SHA head-moved"
run o/r 7
expect_failure_post "head-moved with the head unchanged" stopped-head-moved
new_case
cp "$STUB/gh/repos_o_r_pulls_7" "$STUB/gh/repos_o_r_pulls_7.after"
sed -i 's/0123456789abcdef0123456789abcdef01234567/ffffffffffffffffffffffffffffffffffffffff/' "$STUB/gh/repos_o_r_pulls_7.after"
run o/r 7
assert_eq "moved head at the pre-post re-read: exit 1" 1 "$rc"; no_post "moved head at the pre-post re-read"
check "moved head at the pre-post re-read: the entry is kept" test -d "$(entry_dir)"
check "moved head at the pre-post re-read: no free counted" test ! -e "$(entry_dir).frees"
:
}

sec_reviewed() {
# =========================================================================================
# --- outcomes: already-reviewed and exempt, each verified on the host -----------------------
# =========================================================================================
new_case; set_outcome "already-reviewed 7 $SHA"
printf '[%s]\n' "$(review_doc 4242 "$SHA" COMMENTED '"2026-10-15T10:00:00Z"')" >"$STUB/gh/repos_o_r_pulls_7_reviews"
run o/r 7
assert_eq "already-reviewed (matching COMMENTED review): exit 4" 4 "$rc"; no_post "already-reviewed"
check "already-reviewed: the entry is kept" test -d "$(entry_dir)"
new_case; set_outcome "already-reviewed 7 $SHA"
printf '[]\n[%s]\n' "$(review_doc 4242 "$SHA" COMMENTED '"2026-10-15T10:00:00Z"')" >"$STUB/gh/repos_o_r_pulls_7_reviews"
run o/r 7
assert_eq "already-reviewed (the match is on the second page): exit 4" 4 "$rc"; no_post "already-reviewed page 2"
new_case; set_outcome "already-reviewed 7 $SHA"
run o/r 7
expect_failure_post "already-reviewed with no review" bad-outcome
new_case; set_outcome "already-reviewed 7 $SHA"
printf '[%s]\n' "$(review_doc 4242 "$SHA" PENDING null)" >"$STUB/gh/repos_o_r_pulls_7_reviews"
run o/r 7
expect_failure_post "already-reviewed with only a PENDING review" bad-outcome
for variant in "another user|9 $SHA COMMENTED" "another commit|4242 ffffffffffffffffffffffffffffffffffffffff COMMENTED"; do
  new_case; set_outcome "already-reviewed 7 $SHA"
  # shellcheck disable=SC2086
  printf '[%s]\n' "$(review_doc ${variant#*|} '"2026-10-15T10:00:00Z"')" >"$STUB/gh/repos_o_r_pulls_7_reviews"
  run o/r 7
  expect_failure_post "already-reviewed ($(printf '%s' "$variant" | cut -d'|' -f1))" bad-outcome
done
new_case; set_outcome "already-reviewed 7 $SHA"
printf '[%s]\n' "$(review_doc 4242 "$SHA" COMMENTED '"2026-10-15T10:00:00Z"' 'wrong header

'"$ATTTXT")" >"$STUB/gh/repos_o_r_pulls_7_reviews"
run o/r 7
expect_failure_post "already-reviewed (the review's header differs)" bad-outcome

for vc in \
  "latest pass|4|pass:2026-10-15T10:00:00Z" \
  "latest old form|4|old:2026-10-15T10:00:00Z" \
  "latest changes-needed|F|changes-needed:2026-10-15T10:00:00Z" \
  "changes-needed after an earlier pass|F|pass:2026-10-15T10:00:00Z changes-needed:2026-10-15T11:00:00Z" \
  "pass after an earlier changes-needed|4|changes-needed:2026-10-15T10:00:00Z pass:2026-10-15T11:00:00Z" \
  "equal times, the later in list order decides (pass)|4|changes-needed:2026-10-15T10:00:00Z pass:2026-10-15T10:00:00Z" \
  "equal times, the later in list order decides (changes-needed)|F|pass:2026-10-15T10:00:00Z changes-needed:2026-10-15T10:00:00Z" \
  "a malformed verdict line|F|bogus:2026-10-15T10:00:00Z"; do
  vlabel=${vc%%|*}; vrest=${vc#*|}; vexp=${vrest%%|*}; vlist=${vrest#*|}
  new_case; set_outcome "already-reviewed 7 $SHA"
  vdocs=
  for item in $vlist; do
    vw=${item%%:*}; vt=${item#*:}
    case $vw in
      old) vb="$HDRTXT

$ATTTXT

other text" ;;
      bogus) vb=$(vbody 'maybe') ;;
      *) vb=$(vbody "$vw") ;;
    esac
    vdocs="${vdocs:+$vdocs,}$(review_doc 4242 "$SHA" COMMENTED "\"$vt\"" "$vb")"
  done
  printf '[%s]\n' "$vdocs" >"$STUB/gh/repos_o_r_pulls_7_reviews"
  run o/r 7
  if [ "$vexp" = 4 ]; then
    assert_eq "already-reviewed ($vlabel): exit 4" 4 "$rc"; no_post "already-reviewed ($vlabel)"
  else
    expect_failure_post "already-reviewed ($vlabel)" bad-outcome
  fi
done

new_case; set_outcome "already-reviewed 7 $SHA"
printf '[{"user":{"id":4242},"commit_id":"%s","state":"COMMENTED","submitted_at":"2026-10-15T10:00:00Z","body":7}]\n' "$SHA" >"$STUB/gh/repos_o_r_pulls_7_reviews"
run o/r 7
expect_failure_post "already-reviewed (the match program errors)" bad-outcome
cat "$home"/review-logs/*.log >"$tmp/arlog"; has "$tmp/arlog" "already-reviewed: no passing review (unreadable)" && ok "already-reviewed (the match program errors): logged unreadable" || bad "already-reviewed (the match program errors): not logged unreadable"

new_case; set_outcome "exempt 7 $SHA"
run o/r 7
assert_eq "exempt (only non-trigger paths): exit 4" 4 "$rc"; no_post "exempt"
check "exempt: the entry is kept" test -d "$(entry_dir)"
exempt_case "a path under a src/ entry" '[{"filename":"src/x.c"}]'
exempt_case "a path under a slashless src entry" '[{"filename":"srcfoo/x.c"}]' '.review.ci_gate.triggers_on = ["src"]'
exempt_case "an exact-path match" '[{"filename":"docs/readme.md"}]' '.review.ci_gate.triggers_on = ["docs/readme.md"]'
exempt_case "a renamed file whose previous path matches" '[{"filename":"docs/new.md","previous_filename":"src/old.md"}]'
exempt_case "a glob entry" '[{"filename":"docs/readme.md"}]' '.review.ci_gate.triggers_on = ["src/**"]'
exempt_case "an entry starting with ./" '[{"filename":"docs/readme.md"}]' '.review.ci_gate.triggers_on = ["./src/"]'
exempt_case "an entry starting with /" '[{"filename":"docs/readme.md"}]' '.review.ci_gate.triggers_on = ["/src/"]'
exempt_case "an entry with a .. segment" '[{"filename":"docs/readme.md"}]' '.review.ci_gate.triggers_on = ["a/../b"]'
exempt_case "an entry with a bang" '[{"filename":"docs/readme.md"}]' '.review.ci_gate.triggers_on = ["!src"]'
exempt_case "a compare listing 300 files" "$(jq -nc '[range(300) | {filename: ("docs/f\(.)")}]')"
exempt_case "a compare with no files array" none
exempt_case "a compare with an empty files array" '[]'
exempt_case "a renamed entry without previous_filename" '[{"filename":"docs/new.md","status":"renamed"}]'
exempt_case "a compare whose status is identical" '[{"filename":"docs/readme.md"}]' '' identical 0
exempt_case "a compare whose status is behind" '[{"filename":"docs/readme.md"}]' '' behind 0
new_case; set_outcome "exempt 7 $SHA"
printf '{"state":"open","head":{"sha":"%s"},"base":{"ref":"dev"}}\n' "$SHA" >"$STUB/gh/repos_o_r_pulls_7"
run o/r 7
expect_failure_post "exempt (the PR base is not the default branch)" bad-outcome
assert_eq "exempt (non-default base): no compare was made" 0 "$(grep -c '/compare/' "$STUB/gh.calls")"
new_case; set_outcome "exempt 7 $SHA"
printf '{"check_runs":[{"name":"gate","status":"completed","conclusion":"skipped"}]}\n' >"$STUB/gh/repos_o_r_commits_${SHA}_check-runs"
run o/r 7
assert_eq "exempt: a gate check reading skipped changes nothing (still exempt)" 4 "$rc"
:
}

sec_verdict() {
# =========================================================================================
# --- the verdict line: host-inserted at zero-based line 4, or a bad-verdict failure ---------
# =========================================================================================
for w in pass changes-needed; do
  new_case; set_verdict "$w"
  run o/r 7
  assert_eq "verdict $w: exit 0" 0 "$rc"
  assert_eq "verdict $w: one review POST" 1 "$(n_posts)"
  assert_eq "verdict $w: the body, the verdict line after the attestation, then the rest" \
    "$HDRTXT

$ATTTXT

Review verdict: $w

Reviewed against head $SHA

Looks fine.

Host: no findings to file" "$(post_body)"
  assert_eq "verdict $w: line 4 is the verdict line" "Review verdict: $w" "$(post_body | sed -n 5p)"
  assert_eq "verdict $w: lines 0 and 2 are the header and attestation" "$HDRTXT|$ATTTXT" "$(post_body | sed -n 1p)|$(post_body | sed -n 3p)"
done
new_case; set_verdict pass
set_body "$HDRTXT

$ATTTXT
Reviewed against head $SHA
Looks fine."
run o/r 7
assert_eq "verdict with a non-empty line 4: exit 0" 0 "$rc"
assert_eq "verdict with a non-empty line 4: the verdict line, one blank line, then every session line" \
  "Review verdict: pass||Reviewed against head $SHA|Looks fine." "$(post_body | sed -n 5,8p | tr '\n' '|' | sed 's/|$//')"
new_case
run o/r 7
assert_eq "no verdict file: the body has no verdict line" 0 "$(post_body | grep -c '^Review verdict:' || true)"
for bv in maybe 'Pass' 'pass changes-needed' ''; do
  new_case; set_verdict "$bv"
  run o/r 7
  expect_failure_post "a malformed verdict [$bv]" bad-verdict
done
new_case; printf 'pass\nchanges-needed\n' >"$STUB/outbox/verdict"
run o/r 7
expect_failure_post "a two-line verdict" bad-verdict
new_case; set_verdict pass; mkdir -p "$STUB/outbox/verdict.d"; rm -f "$STUB/outbox/verdict"; mkdir "$STUB/outbox/verdict"
run o/r 7
expect_failure_post "a verdict that is a directory" bad-verdict
rm -rf "$STUB/outbox/verdict" "$STUB/outbox/verdict.d"
new_case; set_verdict pass; set_findings '[{"title":"T","body":"b","type":"bug"}]'
run o/r 7
assert_eq "verdict with findings: the footer follows the body" "Host: 1 findings will be filed in o/r" "$(post_body | tail -1)"
assert_eq "verdict with findings: line 4 is the verdict line" "Review verdict: pass" "$(post_body | sed -n 5p)"
:
}

sec_outcomes() {
# =========================================================================================
# --- outcomes: review and the failure reviews -----------------------------------------------
# =========================================================================================
new_case
set_body "$HDRTXT
$ATTTXT

Reviewed against head $SHA"
run o/r 7
expect_failure_post "a body without the blank line 2" header-mismatch
new_case
set_body "$HDRTXT

wrong attestation

Reviewed against head $SHA"
run o/r 7
expect_failure_post "a body with another attestation" header-mismatch
new_case
set_body "$HDRTXT

$ATTTXT

Reviewed against head $SHA

Uses actions/checkout@abcdef0123, mail user@example.com, and mentions a \`ghs_\` token in prose."
run o/r 7
assert_eq "benign @ and prefix prose pass: exit 0" 0 "$rc"

body_case "a mention at a line start" mention '@user please look'
body_case "a mention after a dash" mention 'see -@user'
body_case "a mention after a dot" mention 'see .@user'
body_case "an &#64; mention" mention 'see &#64;user'
body_case "an &#064; mention" mention 'see &#064;user'
body_case "an &#x40; mention" mention 'see &#X40;user'
body_case "an &commat; mention" mention 'see &commat;user'
body_case "a semicolon-less &#64 mention" mention 'see &#64octocat'
body_case "a semicolon-less &#x40 mention" mention 'see &#x40octocat'
body_case "a Host: line behind a leading space" bad-body ' Host: 1 findings will be filed in o/r'
body_case "a Host: line behind markup" bad-body '**Host: 2 findings will be filed in x/y**'
body_case "a Host: line behind a quote marker" bad-body '> Host: no findings to file'
new_case
set_body "$HDRTXT

$ATTTXT

Reviewed against head $SHA

- \`Host:\` header is not validated by the proxy."
run o/r 7
assert_eq "prose about an HTTP Host: header is not mistaken for a forged footer" 0 "$rc"
body_case "a stateless token-shaped string" secret 'token ghs_123456_eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJpYXQiOjE2.sig-nature_0123456789'
body_case "a classic token-shaped string" secret 'token ghp_0123456789abcdefghijklmnopqrstuvwxyzABCD'
body_case "a fine-grained PAT shape" secret 'token github_pat_0123456789abcdefghijkl_xyz'
body_case "an Anthropic key shape" secret 'key sk-ant-oat01-abcdefghijklmnopqrstuvwx'
body_case "a Host: line in the body" bad-body 'Host: forged'
new_case
set_body "$HDRTXT

$ATTTXT

body without the head line"
run o/r 7
expect_failure_post "no head line" no-head-line
new_case
{ printf '%s\n\n%s\n\nReviewed against head %s\n\n' "$HDRTXT" "$ATTTXT" "$SHA"; printf 'bad \377 byte\n'; } >"$STUB/outbox/review.md"
run o/r 7
expect_failure_post "a non-UTF-8 body" bad-body
new_case
{ printf '%s\n\n%s\n\nReviewed against head %s\n\n' "$HDRTXT" "$ATTTXT" "$SHA"; } >"$tmp/over-head"
pad=$((65520 - $(wc -c <"$tmp/over-head" | tr -d ' ') - 1))
{ cat "$tmp/over-head"; head -c "$pad" /dev/zero | tr '\0' 'y'; printf '\n'; } >"$STUB/outbox/review.md"
size=$(wc -c <"$STUB/outbox/review.md" | tr -d ' ')
assert_eq "the oversize fixture is accepted by outbox-read but too big with the footer" 65520 "$size"
run o/r 7
expect_failure_post "an oversized body plus footer ($size bytes)" oversize
new_case; rm -f "$STUB/outbox/review.md"
run o/r 7
expect_failure_post "a missing body" no-body
new_case; printf 'bad \033[31m body\n' >"$STUB/outbox/review.md"
run o/r 7
expect_failure_post "a body outbox-read refuses (ESC)" bad-body

for variant in "stopped 7 $SHA entry-clone|stopped-entry-clone" "stopped 7 $SHA never-heard-of|stopped-other" "stopped 7 $SHA checks-red|stopped-checks-red" \
    "stopped 7 $SHA needs-human|stopped-needs-human" "stopped 7 $SHA base-override|stopped-base-override" \
    "stopped 7 $SHA Bad_Reason|bad-outcome" "review|bad-outcome" "review 8 $SHA|bad-outcome" "review 7 ffffffffffffffffffffffffffffffffffffffff|bad-outcome" \
    "review 7 $SHA trailing|bad-outcome" "review  7 $SHA|bad-outcome" "done|bad-outcome"; do
  line=${variant%|*}; code=${variant#*|}
  new_case; set_outcome "$line"
  run o/r 7
  expect_failure_post "outcome [$line]" "$code"
  check "outcome [$line]: the entry is kept" test -d "$(entry_dir)"
done
new_case; rm -f "$STUB/outbox/outcome"
run o/r 7
expect_failure_post "a missing outcome" no-outbox
new_case; rm -f "$STUB/outbox/outcome"
if ln -s /etc/hostname "$STUB/outbox/outcome" 2>/dev/null && [ -L "$STUB/outbox/outcome" ]; then
  run o/r 7
  expect_failure_post "a symlinked outcome" bad-outcome
else
  ok "a symlinked outcome (skipped: no symlinks here)"
fi
new_case; printf 'wait\n' >/dev/null; : >"$STUB/wait.hang"; T_TIMEOUT=1
run o/r 7
T_TIMEOUT=20
expect_failure_post "a session that overruns the timeout" timed-out
check "timeout: docker kill was recorded" has "$STUB/events" "docker-kill"
assert_eq "timeout: the outbox was not read" 0 "$(ev_count docker-outbox-read)"
:
}

sec_post() {
# =========================================================================================
# --- the post ----------------------------------------------------------------------------------
# =========================================================================================
for variant in "a commit mismatch|104|.commit_id = \"ffffffffffffffffffffffffffffffffffffffff\"" "a state other than COMMENTED|104|.state = \"PENDING\"" \
    "a user mismatch|103|.user = {login: \"someone[bot]\", id: 9}"; do
  label=${variant%%|*}; rest=${variant#*|}; want=${rest%%|*}; expr=${rest#*|}
  new_case; set_findings '[{"title":"T","body":"b","type":"bug"}]'
  jq "$expr" "$STUB/gh/post_review" >"$STUB/gh/post_review.new" && mv "$STUB/gh/post_review.new" "$STUB/gh/post_review"
  run o/r 7
  assert_eq "post response ($label): exit $want" "$want" "$rc"
  assert_eq "post response ($label): nothing filed" 0 "$(n_issues)"
  check "post response ($label): the entry is kept" test -d "$(entry_dir)"
  assert_eq "post response ($label): no filing token minted" 0 "$(grep -c -- '--file' "$STUB/mint.calls")"
done
new_case; set_findings '[{"title":"T","body":"b","type":"bug"}]'; : >"$STUB/gh/post_review.fail"
run o/r 7
assert_eq "a failing POST: exit 104" 104 "$rc"
assert_eq "a failing POST: nothing filed" 0 "$(n_issues)"
check "a failing POST: the entry is kept" test -d "$(entry_dir)"
new_case; printf '{}\n' >"$STUB/gh/post_review"
run o/r 7
assert_eq "an empty POST response: exit 104" 104 "$rc"
:
}

sec_findings() {
# =========================================================================================
# --- findings ----------------------------------------------------------------------------------
# =========================================================================================
findings_case "not JSON" findings-unreadable 'not json'
findings_case "an object" findings-shape '{"a":1}'
findings_case "a missing type" findings-shape '[{"title":"t","body":"b"}]'
findings_case "an extra key" findings-shape '[{"title":"t","body":"b","type":"bug","x":1}]'
findings_case "a non-string title" findings-shape '[{"title":5,"body":"b","type":"bug"}]'
findings_case "six findings" findings-count "$(jq -nc '[range(6) | {title:"t",body:"b",type:"bug"}]')"
findings_case "an empty title" findings-title '[{"title":"","body":"b","type":"bug"}]'
findings_case "a long title" findings-title "$(jq -nc '[{title:("x"*121),body:"b",type:"bug"}]')"
findings_case "a long body" findings-body "$(jq -nc '[{title:"t",body:("x"*4001),type:"bug"}]')"
findings_case "a bad type" findings-type '[{"title":"t","body":"b","type":"task"}]'
findings_case "a bad area" findings-area '[{"title":"t","body":"b","type":"bug","area":"x/y"}]'
findings_case "ESC in a body" findings-control '[{"title":"t","body":"a\u001b[31mb","type":"bug"}]'
findings_case "U+009B in a title" findings-control '[{"title":"a\u009bb","body":"b","type":"bug"}]'
findings_case "DEL in a title" findings-control '[{"title":"a\u007fb","body":"b","type":"bug"}]'
findings_case "a mention in a body" findings-mention '[{"title":"t","body":"ping @someone","type":"bug"}]'
findings_case "a character-reference mention in a title" findings-mention '[{"title":"&#64;someone","body":"b","type":"bug"}]'
findings_case "a token in a body" findings-secret '[{"title":"t","body":"ghp_0123456789abcdefghijklmnopqrstuvwxyzABCD","type":"bug"}]'
findings_case "two JSON documents" findings-shape '[{"title":"a","body":"b","type":"bug"}]
[{"title":"c","body":"d","type":"bug"}]'
new_case; set_findings '[]'
run o/r 7
assert_eq "an empty findings array: the footer" "Host: no findings to file" "$(post_body | tail -1)"
new_case
run o/r 7
assert_eq "no findings file: the footer" "Host: no findings to file" "$(post_body | tail -1)"
assert_eq "no findings file: no filing token" 0 "$(grep -c -- '--file' "$STUB/mint.calls")"
new_case; set_findings '[{"title":"T","body":"b","type":"bug"}]'
sed -i 's|pull/7#pullrequestreview-555|pull/7#pullrequestreview-abc|' "$STUB/gh/post_review"
run o/r 7
assert_eq "a bad html_url: exit 0" 0 "$rc"; assert_eq "a bad html_url: nothing filed" 0 "$(n_issues)"
new_case; set_findings '[{"title":"T","body":"b","type":"bug"}]'
sed -i 's|github.com/o/r/pull/7|github.com/o/other/pull/7|' "$STUB/gh/post_review"
run o/r 7
assert_eq "an html_url for another repository: nothing filed" 0 "$(n_issues)"
new_case; set_findings '[{"title":"T","body":"b","type":"bug"}]'
sed -i 's|github.com/o/r/pull/7|github.com/O/R/pull/7|' "$STUB/gh/post_review"
run o/r 7
assert_eq "an html_url differing only in case still files" 1 "$(n_issues)"
new_case; set_findings '[{"title":"T","body":"b","type":"bug"}]'; mkdir -p "$(entry_dir)"; printf '0 77\n' >"$(entry_dir)/filed"
run o/r 7 --rerun
assert_eq "--rerun with a filed line: the review posts" 0 "$rc"
assert_eq "--rerun with a filed line: the footer" "Host: findings not filed (already-filed)" "$(post_body | tail -1)"
assert_eq "--rerun with a filed line: nothing filed" 0 "$(n_issues)"
new_case; set_findings '[{"title":"T","body":"b","type":"bug"},{"title":"U","body":"b","type":"bug"}]'; printf '2\n' >"$STUB/gh/issue_fail_at"
run o/r 7
assert_eq "a failed create stops the rest, the exit stays 0" 0 "$rc"
assert_eq "a failed create: only one file line" "0 101" "$(cat "$(entry_dir)/filed")"
:
}

sec_gate() {
# =========================================================================================
# --- the gate poll: a failure is final only when posted after the review ---------------------
# =========================================================================================

gate_case
status_path="$STUB/gh/repos_o_r_commits_${SHA}_status"
status_doc gate failure "\"$BEFORE\"" >"$status_path"; status_doc gate success "\"$AFTER\"" >"$status_path.after"; printf '1\n' >"$status_path.after.n"
run_gate_case "stale status failure, then success"
assert_eq "stale then success: the stale line" 1 "$(gline '1: failure, not posted after the review')"
assert_eq "stale then success: then success" 1 "$(gline '2: success')"
assert_eq "stale then success: two polls" 2 "$(gpolls)"
assert_eq "stale then success: one status call per poll" 2 "$(grep -c "|repos/o/r/commits/$SHA/status|" "$STUB/gh.calls")"
assert_eq "stale then success: one check-runs call per poll" 2 "$(grep -c "|repos/o/r/commits/$SHA/check-runs|" "$STUB/gh.calls")"

gate_case
status_path="$STUB/gh/repos_o_r_commits_${SHA}_status"
status_doc gate failure "\"$AFTER\"" >"$status_path"
run_gate_case "status failure after the review"
assert_eq "status failure after: final on poll 1" 1 "$(gline '1: failure')"
assert_eq "status failure after: one poll" 1 "$(gpolls)"

gate_case
status_path="$STUB/gh/repos_o_r_commits_${SHA}_status"
status_doc gate failure "\"$SUBMITTED\"" >"$status_path"
run_gate_case "status failure at exactly submitted_at"
assert_eq "status failure at submitted_at: stale on every poll" 6 "$(gline '[1-6]: failure, not posted after the review')"
assert_eq "status failure at submitted_at: six polls" 6 "$(gpolls)"

gate_case
printf '{"check_runs":[{"name":"gate","status":"completed","conclusion":"failure","completed_at":"%s"}]}\n' "$BEFORE" >"$STUB/gh/repos_o_r_commits_${SHA}_check-runs"
printf '{"check_runs":[{"name":"gate","status":"completed","conclusion":"failure","completed_at":"%s"}]}\n' "$AFTER" >"$STUB/gh/repos_o_r_commits_${SHA}_check-runs.after"
printf '1\n' >"$STUB/gh/repos_o_r_commits_${SHA}_check-runs.after.n"
run_gate_case "stale check-run failure, then a fresh one"
assert_eq "check-run: the stale line" 1 "$(gline '1: failure, not posted after the review')"
assert_eq "check-run: then a final failure" 1 "$(gline '2: failure')"
assert_eq "check-run: two polls" 2 "$(gpolls)"

gate_case
status_path="$STUB/gh/repos_o_r_commits_${SHA}_status"
status_doc gate failure "\"$BEFORE\"" >"$status_path"
printf '{"check_runs":[{"name":"ci","status":"completed","conclusion":"success","completed_at":"%s"}]}\n' "$AFTER" >"$STUB/gh/repos_o_r_commits_${SHA}_check-runs"
run_gate_case "a ci check-run after the review beside a stale gate failure"
assert_eq "other name: never final" 6 "$(gline '[1-6]: failure, not posted after the review')"

gate_case
status_path="$STUB/gh/repos_o_r_commits_${SHA}_status"
printf '{"statuses":[{"context":"gate","state":"failure","updated_at":"%s"},{"context":"ci","state":"success","updated_at":"%s"}]}\n' "$BEFORE" "$AFTER" >"$status_path"
run_gate_case "a ci status after the review beside a stale gate failure"
assert_eq "other context: never final" 6 "$(gline '[1-6]: failure, not posted after the review')"

for variant in "missing|" "malformed|2026-10-17T16:35:56.123Z"; do
  label=${variant%%|*}; val=${variant#*|}
  gate_case
  status_path="$STUB/gh/repos_o_r_commits_${SHA}_status"
  status_doc gate failure '"2999-01-01T00:00:00Z"' >"$status_path"
  if [ -n "$val" ]; then sed -i "s|\"submitted_at\":\"[^\"]*\"|\"submitted_at\":\"$val\"|" "$STUB/gh/post_review"
  else sed -i 's|,"submitted_at":"[^"]*"||' "$STUB/gh/post_review"; fi
  run_gate_case "a $label submitted_at"
  assert_eq "$label submitted_at: the reason line, once" 1 "$(glog | grep -c 'gate poll: no usable submitted_at; no failure is final')"
  assert_eq "$label submitted_at: six polls" 6 "$(gpolls)"
  assert_eq "$label submitted_at: every read stale" 6 "$(gline '[1-6]: failure, not posted after the review')"
done

gate_case
status_path="$STUB/gh/repos_o_r_commits_${SHA}_status"
status_doc gate failure null >"$status_path"; status_doc gate success "\"$AFTER\"" >"$status_path.after"; printf '1\n' >"$status_path.after.n"
run_gate_case "a null updated_at, then success"
assert_eq "null updated_at: not final" 1 "$(gline '1: failure, not posted after the review')"
assert_eq "null updated_at: then success" 1 "$(gline '2: success')"
for bad in '"not-a-time"' '"2999-01-01T00:00:00.5Z"' '""'; do
  gate_case
  status_path="$STUB/gh/repos_o_r_commits_${SHA}_status"
  status_doc gate failure "$bad" >"$status_path"
  run_gate_case "a gate timestamp $bad"
  assert_eq "gate timestamp $bad: never final" 6 "$(gline '[1-6]: failure, not posted after the review')"
done
:
}

sec_log() {
# =========================================================================================
# --- the log -----------------------------------------------------------------------------------
# =========================================================================================
new_case
{ printf 'FIRSTLINE\nA\033[31mred\n\302\233X\n\302\302\233\233[2J\n'; head -c 1500000 /dev/zero | tr '\0' 'a'; printf '\nLASTLINE\n'; } >"$STUB/session-log"
run o/r 7
logf=$(ls "$home"/review-logs/*.log)
sed -n '/^--- session log/,/^--- end of session log/{//!p}' "$logf" >"$tmp/logpart"
# The filtered stream, as the launcher stages it: C0 and DEL deleted, each C1 pair replaced by ?.
LC_ALL=C tr -d '\000-\010\013-\037\177' <"$STUB/session-log" | LC_ALL=C sed "s/$(printf '\302')[$(printf '\200')-$(printf '\237')]/?/g" >"$tmp/stream"
slen=$(wc -c <"$tmp/stream" | tr -d ' ')
omit="--- $((slen - 1048576)) bytes of the session log omitted ---"
check "log: the session part is at most the 1 MiB bound plus the inserted newline and the omitted line" test "$(wc -c <"$tmp/logpart" | tr -d ' ')" -le "$((1048577 + 1 + ${#omit} + 1))"
check "log: the first line of the stream is kept" grep -qxF FIRSTLINE "$tmp/logpart"
check "log: the last line of the stream is kept" grep -qxF LASTLINE "$tmp/logpart"
assert_eq "log: the omitted line, once" 1 "$(grep -cxF -- "$omit" "$tmp/logpart")"
head -c 786432 "$tmp/stream" >"$tmp/head"; printf '\n%s\n' "$omit" >>"$tmp/head"
check "log: the omitted line follows the head's 786432 bytes and a newline" test "$(head -c "$(wc -c <"$tmp/head" | tr -d ' ')" "$tmp/logpart" | cmp - "$tmp/head" >/dev/null 2>&1; echo $?)" -eq 0
{ tail -c 262144 "$tmp/stream"; printf '\n'; } >"$tmp/tail"
check "log: the part ends with the stream's last 262144 bytes and the blank line before the end line" test "$(tail -c 262145 "$tmp/logpart" | cmp - "$tmp/tail" >/dev/null 2>&1; echo $?)" -eq 0
check "log: the staged session-stream is gone from the host directory at the outbox read" test -f "$STUB/hdir.after-log" -a -z "$(grep -x session-stream "$STUB/hdir.after-log" || true)"
assert_eq "log: no ESC byte survives" 0 "$(grep -c "$(printf '\033')" "$logf")"
assert_eq "log: no C1 sequence survives" 0 "$(LC_ALL=C grep -c "$(printf '\302\233')" "$logf")"
check "log: the log is kept and the header warns it may hold secrets" has "$logf" "may hold secrets"

# A stream under the cap is kept whole, with no omitted line.
new_case
{ printf 'FIRSTLINE\nsmall\n'; head -c 2000 /dev/zero | tr '\0' 'b'; printf '\nLASTLINE\n'; } >"$STUB/session-log"
run o/r 7
logf=$(ls "$home"/review-logs/*.log)
sed -n '/^--- session log/,/^--- end of session log/{//!p}' "$logf" >"$tmp/logpart"
LC_ALL=C tr -d '\000-\010\013-\037\177' <"$STUB/session-log" >"$tmp/stream"; printf '\n' >>"$tmp/stream"
check "log (under the cap): the stream is kept whole, byte for byte" cmp -s "$tmp/stream" "$tmp/logpart"
assert_eq "log (under the cap): no omitted line" 0 "$(grep -c 'bytes of the session log omitted' "$logf")"
check "log (under the cap): the staged session-stream is gone at the outbox read" test -z "$(grep -x session-stream "$STUB/hdir.after-log" || true)"
:
}

sec_preflight() {
# =========================================================================================
# --- the preflight, the sidecars and the credential ----------------------------------------
# =========================================================================================
pre_case "a writable root filesystem" inspect.session.jq '.[0].HostConfig.ReadonlyRootfs = false'
pre_case "an extra bind mount" inspect.session.jq '.[0].Mounts += [{Type:"bind",Source:"/home/x",Destination:"/x",RW:true}]'
pre_case "a docker.sock mount" inspect.session.jq '.[0].Mounts += [{Type:"bind",Source:"/var/run/docker.sock",Destination:"/s",RW:false}]'
pre_case "a root user" inspect.session.jq '.[0].Config.User = "root"'
pre_case "root:group as the user" inspect.session.jq '.[0].Config.User = "root:1000"'
pre_case "an added capability" inspect.session.jq '.[0].HostConfig.CapAdd = ["SYS_ADMIN"]'
pre_case "no no-new-privileges" inspect.session.jq '.[0].HostConfig.SecurityOpt = []'
pre_case "the host PID namespace" inspect.session.jq '.[0].HostConfig.PidMode = "host"'
pre_case "a device" inspect.session.jq '.[0].HostConfig.Devices = [{PathOnHost:"/dev/kvm"}]'
pre_case "a privileged session" inspect.session.jq '.[0].HostConfig.Privileged = true'
pre_case "capabilities not dropped" inspect.session.jq '.[0].HostConfig.CapDrop = []'
pre_case "a session on the default network" inspect.session.jq '.[0].HostConfig.NetworkMode = "bridge"'
pre_case "a credential variable that is not the placeholder" inspect.session.jq '.[0].Config.Env |= map(if startswith("CLAUDE_CODE_OAUTH_TOKEN=") then "CLAUDE_CODE_OAUTH_TOKEN=other" else . end)'
pre_case "the credential string in the session's environment" inspect.session.jq ".[0].Config.Env += [\"X=$CRED\"]"
pre_case "the credential string in the injector's inspect output" inspect.inject.jq ".[0].Config.Env += [\"X=$CRED\"]"
pre_case "a third member of the network" net.jq '.[0].Containers += {"x":{"Name":"intruder"}}'
pre_case "a network that is not internal" net.jq '.[0].Internal = false'
pre_case "a network with IPv6 on" net.jq '.[0].EnableIPv6 = true'
pre_case "a network with a gateway" net.jq '.[0].IPAM.Config = [{Subnet:"10.0.0.0/24",Gateway:"10.0.0.1"}]'
pre_case "a holder that is not running" inspect.holder.jq '.[0].State.Running = false'
pre_case "a holder with a network" inspect.holder.jq '.[0].HostConfig.NetworkMode = "bridge"'
pre_case "a holder with a writable outbox mount" inspect.holder.jq '.[0].Mounts[0].RW = true'

new_case; rm -f "$home/claude-credential"
run o/r 7
assert_eq "no credential file: exit 1" 1 "$rc"
assert_eq "no credential file: no container started" 0 "$(ev_count 'docker-run')"
new_case; : >"$home/claude-credential"
run o/r 7
assert_eq "an empty credential file: exit 1" 1 "$rc"
assert_eq "an empty credential file: no container started" 0 "$(ev_count 'docker-run')"
new_case; : >"$STUB/inject.noup"
run o/r 7
assert_eq "an injector that never says 'inject up': exit 1" 1 "$rc"
assert_eq "an injector that never says 'inject up': the session was not created" 0 "$(ev_count 'docker-create wow-review-session')"
n=$(ev_count 'docker-logs inject'); check "an injector that never says 'inject up': more than ten checks, at most fifty" sh -c '[ "$1" -gt 10 ] && [ "$1" -le 50 ]' x "$n"
new_case; printf '0.7\n' >"$STUB/inject.delay"
run o/r 7
assert_eq "a late injector: exit 0" 0 "$rc"
assert_eq "a late injector: the session was created" 1 "$(ev_count 'docker-create wow-review-session')"
n=$(ev_count 'docker-logs inject'); check "a late injector: polled at least three times" sh -c '[ "$1" -ge 3 ]' x "$n"
new_case; : >"$STUB/start.fail"
run o/r 7
assert_eq "docker start failing before the session ran: exit 1" 1 "$rc"
check "docker start failing: the never-started entry is freed" test ! -d "$(entry_dir)"
new_case; : >"$STUB/docker/noimage"
run o/r 7
assert_eq "no image yet: the run proceeds" 0 "$rc"
check "no image yet: docker build ran, from the installed review/ context" has "$STUB/docker.calls" "[build] [-q] [-t] [wow-review:0123456789ab]"
new_case; printf '[{"type":"required_status_checks","parameters":{"required_status_checks":[]}}]\n' >"$STUB/gh/repos_o_r_rules_branches_main"
printf 'junk\n' >"$home/bin/MANIFEST"
run o/r 7
assert_eq "an unreadable MANIFEST: exit 1" 1 "$rc"
assert_eq "an unreadable MANIFEST: no container started" 0 "$(ev_count 'docker-run')"
:
}

sec_cleanup() {
# =========================================================================================
# --- cleanup: every directory, the lock and every container, whatever the ending -----------
# =========================================================================================
new_case; run o/r 7;                                   cleaned "after a success"
new_case; set_outcome "stopped 7 $SHA entry-clone"; run o/r 7; cleaned "after a failure review"
new_case; set_outcome "stopped 7 $SHA checks-pending"
printf '{"check_runs":[{"name":"ci","status":"queued","conclusion":null}]}\n' >"$STUB/gh/repos_o_r_commits_${SHA}_check-runs"
run o/r 7;                                              cleaned "after a retryable stop"
new_case; : >"$STUB/wait.hang"; T_TIMEOUT=1; run o/r 7; T_TIMEOUT=20; cleaned "after a timeout"
check "after a timeout: the stuck session was killed" has "$STUB/events" "docker-kill"

new_case; : >"$STUB/wait.hang"; reset_logs
env PATH="$stubs:$orig_path" REAL_SLEEP="$real_sleep" STUB_DIR="$STUB" WOW_HOME="$home" WOW_REVIEW_TIMEOUT=120 WOW_REVIEW_REFRESH=1 \
  sh "$home/bin/wow-review" o/r 7 <&- >"$tmp/out" 2>"$tmp/err" &
bgpid=$!
i=0
while [ "$i" -lt 200 ] && ! grep -q '^docker-wait ' "$STUB/events" 2>/dev/null; do "$real_sleep" 0.3; i=$((i + 1)); done
"$real_sleep" 2.5
kill -TERM "$bgpid" 2>/dev/null
rc=0; wait "$bgpid" || rc=$?
invariants
assert_eq "TERM during the wait: exit 143" 143 "$rc"
cleaned "after a TERM during the wait"
sess=$(grep '^read ' "$STUB/mint.tokens" | sed 's/^read //' | sort -u)
assert_eq "TERM during the wait: every session token minted was revoked" "$sess" "$(sort -u "$STUB/revoked")"
check "TERM during the wait: the started session keeps its ledger entry" test -d "$(entry_dir)"
assert_eq "TERM during the wait: nothing posted" 0 "$(n_posts)"
:
}

# Run every section at once, each in a subshell with its own scratch directory ($tmp: its case tree, its out
# and err files, its log scratch files) over the shared stubs; replay each one's output in order.
sections="args golden schema ident mints lock reviewed verdict outcomes post findings gate log preflight cleanup"
pids=
# An interrupt stops the section subshells and leaves the scratch tree (the stubs in it) in place: a launcher
# already in flight ends on its own, within its own timeout, and must not lose its stubs to the real gh and
# docker. test-all.sh's header allows a stopped suite to leave its temp directory behind.
stop_sections() { kill $pids 2>/dev/null || :; trap - EXIT; exit "$1"; }
trap 'stop_sections 129' HUP; trap 'stop_sections 130' INT; trap 'stop_sections 143' TERM
for n in $sections; do
  ( tmp="$tmp_root/$n"; mkdir "$tmp"; "sec_$n"; [ "$fail" -eq 0 ] ) >"$tmp_root/$n.out" 2>"$tmp_root/$n.err" &
  eval "pid_$n=$!"; pids="$pids $!"
done
all_ok=1
for n in $sections; do
  eval "p=\$pid_$n"; src=0; wait "$p" || src=$?
  cat "$tmp_root/$n.out"; cat "$tmp_root/$n.err" >&2
  [ "$src" -eq 0 ] || { echo "FAIL - section $n exited $src" >&2; all_ok=0; }
done

[ "$all_ok" -eq 1 ] || { echo "identity-review: FAILED" >&2; exit 1; }
echo "identity-review: all fixtures passed"
