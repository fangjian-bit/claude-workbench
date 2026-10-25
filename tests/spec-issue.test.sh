#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/spec-issue.sh: spec-task's fetch-and-check, moved
# out of SKILL.md into a tested script (#659, child (a) of #627).
#
# The real script runs from a local checkout cloned from a fixture origin repository whose default
# branch (`git init -b main`) carries .ai/project.yml; each case commits the project.yml it needs
# to that origin. First on PATH, only while the script runs, are a stub `gh` (keyed on the shape of
# the call; it logs its argv and does not interpret --jq) and a logging `git` wrapper (it records
# its argv, then runs the real git). Needs git and yq (mikefarah v4); skips, loudly, without yq.
#
# Each case's comment names the outcome the old SKILL.md block gave on the same input; the script
# matches it (the same stop or pass, except the #759 app_check cases), now as a word. Symlink cases skip, loudly, where `ln -s`
# copies instead of linking (Git Bash).
# Permitted toolset: POSIX sh.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
bindir="$root_dir/plugins/way-of-working/bin"
script="$bindir/spec-issue.sh"
skill="$root_dir/plugins/way-of-working/skills/spec-task/SKILL.md"

if ! command -v yq >/dev/null 2>&1; then
  echo "SKIP - yq not on PATH; spec-issue.sh needs it" >&2
  exit 0
fi

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

real_git="$(command -v git)"
real_cat="$(command -v cat)"
real_sh="$(command -v sh)"
scratch="$tmp/scratch"
fakebin="$tmp/fakebin"
mkdir -p "$scratch" "$fakebin" "$tmp/nogit" "$tmp/elsewhere"
glog="$tmp/gh.log"
gall="$tmp/gh.all"
gitlog="$tmp/git.log"
: >"$gall"

MARK="STUB-ECHO-9c1d"

cat >"$fakebin/gh" <<'FAKE_GH'
#!/bin/sh
line=
for a in "$@"; do line="$line$a|"; done
printf '%s\n' "$line" >>"$FX_GHLOG"
fail_with() { # a failure path that leaks the marker on both streams
  echo "$FX_MARK gh failure text"
  echo "$FX_MARK gh failure text" >&2
  exit 1
}
case "$1 $2" in
  "api graphql")
    # the content-time query (#890): FX_CT is the response; by default a never-edited issue created at the
    # served copy's updated_at, so its content time is that updated_at
    [ -z "${FX_CT_FAIL:-}" ] || fail_with
    if [ -n "${FX_CT:-}" ]; then "$FX_CAT" "$FX_CT"; exit 0; fi
    src="$FX_ISSUE"
    [ -z "${FX_ISSUE2:-}" ] || src="$FX_ISSUE2"
    u="$(sed -n 's/.*"updated_at":"\([^"]*\)".*/\1/p' "$src")"
    printf '{"data":{"repository":{"issue":{"createdAt":"%s","updatedAt":"%s","lastEditedAt":null,"timelineItems":{"nodes":[]}}}}}\n' "$u" "$u"
    ;;
  "repo view")
    [ -n "$3" ] || exit 1
    [ -z "${FX_VIEW_FAIL:-}" ] || fail_with
    case "$*" in
      *nameWithOwner*) printf '%s\n' "$FX_NWO" ;;
      *defaultBranchRef*) printf '%s\n' "$FX_DEF" ;;
      *) exit 1 ;;
    esac
    ;;
  "api repos/"*)
    case "$2" in
      */issues/*/reactions)
        [ -z "${FX_RX_FAIL:-}" ] || fail_with
        if [ -n "${FX_RX:-}" ]; then "$FX_CAT" "$FX_RX"; fi
        ;;
      */issues/*)
        [ -z "${FX_ISSUE_FAIL:-}" ] || fail_with
        # the second issue read of a run is the one that can differ
        nreads="$(grep -c '^api|repos/[^|]*/issues/[0-9]*|$' "$FX_GHLOG" || true)"
        if [ "$nreads" -ge 2 ]; then
          [ -z "${FX_ISSUE2_FAIL:-}" ] || fail_with
          if [ -n "${FX_ISSUE2:-}" ]; then "$FX_CAT" "$FX_ISSUE2"; exit 0; fi
        fi
        case "${FX_PLANT:-}" in
          file) printf 'planted\n' >"$FX_OUT/issue.json" ;;
          link) ln -s "$FX_LINK_TARGET" "$FX_OUT/issue.json" ;;
        esac
        "$FX_CAT" "$FX_ISSUE"
        ;;
      *)
        [ -z "${FX_PERM_FAIL:-}" ] || fail_with
        printf '{"admin":false,"push":true}\n'
        ;;
    esac
    ;;
  *) exit 1 ;;
esac
FAKE_GH
cat >"$fakebin/git" <<'FAKE_GIT'
#!/bin/sh
line=
for a in "$@"; do line="$line$a|"; done
printf '%s\n' "$line" >>"$FX_GITLOG"
exec "$FX_REAL_GIT" "$@"
FAKE_GIT
chmod +x "$fakebin/gh" "$fakebin/git"

export FX_GHLOG="$glog" FX_GITLOG="$gitlog" FX_REAL_GIT="$real_git" FX_CAT="$real_cat" FX_MARK="$MARK"

can_link=no
ln -s "$tmp/elsewhere" "$tmp/probe-link" 2>/dev/null && [ -L "$tmp/probe-link" ] && can_link=yes
rm -rf "$tmp/probe-link"

# --- the fixture origin and the checkout ------------------------------------------------------
origin="$tmp/origin"
"$real_git" init -q -b main "$origin"
gc() { "$real_git" -C "$origin" -c core.autocrlf=false -c user.name=fx -c user.email=fx@example.test "$@"; }
mkdir -p "$origin/.ai"
setyml() { # setyml <file> -- commit it as the default branch's .ai/project.yml
  mkdir -p "$origin/.ai"
  cp "$1" "$origin/.ai/project.yml"
  gc add .ai/project.yml
  gc commit -q --allow-empty -m "project.yml"
}
mk() { printf '%s\n' "$2" >"$tmp/$1.yml"; }

MAP='identities:
  maintainer:
    - { login: maint, id: 100 }
  dev_app: { login: "dev[bot]", id: 200 }
  reviewer_app: { login: "rev[bot]", id: 300 }
  loop_app: { login: "loop[bot]", id: 400 }'
mk map "repo: acme/repo
pr_base: main
backlog:
  repo: acme/backlog
orchestration:
  loop_identity: \"other-loop[bot]\"
$MAP"
mk loopmap "repo: acme/repo
pr_base: main
backlog:
  repo: acme/backlog
orchestration:
  loop_identity: \"loop[bot]\"
$MAP"
mk mapnoloop "repo: acme/repo
pr_base: main
backlog:
  repo: acme/backlog
orchestration:
  loop_identity: null
$MAP"
mk devloop "repo: acme/repo
pr_base: main
backlog:
  repo: acme/backlog
orchestration:
  loop_identity: \"dev[bot]\"
$MAP"
# maintainer lists the App-filed path must read as unreadable
mk mapnomaint "repo: acme/repo
pr_base: main
backlog:
  repo: acme/backlog
identities:
  maintainer: { login: maint, id: 100 }
  dev_app: { login: \"dev[bot]\", id: 200 }
  reviewer_app: { login: \"rev[bot]\", id: 300 }
  loop_app: { login: \"loop[bot]\", id: 400 }"
mk mapemptymaint "repo: acme/repo
pr_base: main
backlog:
  repo: acme/backlog
identities:
  maintainer: []
  dev_app: { login: \"dev[bot]\", id: 200 }
  reviewer_app: { login: \"rev[bot]\", id: 300 }
  loop_app: { login: \"loop[bot]\", id: 400 }"
mk mapbadmaint "repo: acme/repo
pr_base: main
backlog:
  repo: acme/backlog
identities:
  maintainer:
    - { login: maint, id: 100 }
    - { login: other, id: \"101\" }
  dev_app: { login: \"dev[bot]\", id: 200 }
  reviewer_app: { login: \"rev[bot]\", id: 300 }
  loop_app: { login: \"loop[bot]\", id: 400 }"
mk legacy 'repo: acme/repo
pr_base: main
backlog:
  repo: acme/backlog
identities: null'
mk loopid 'repo: acme/repo
pr_base: main
backlog:
  repo: acme/backlog
orchestration:
  loop_identity: "glunk-loop[bot]"
identities: null'
mk dup 'repo: acme/repo
pr_base: main
backlog:
  repo: acme/backlog
identities:
  maintainer:
    - { login: maint, id: 100 }
    - { login: other, id: 100 }
  dev_app: null
  reviewer_app: null
  loop_app: null'
mk noid 'repo: acme/repo
pr_base: main
backlog:
  repo: acme/backlog'
mk mismatch "repo: acme/other
pr_base: main
backlog:
  repo: acme/backlog
identities: null"
mk nullbacklog 'repo: acme/repo
pr_base: main
backlog:
  repo: null
identities: null'
mk nobacklog 'repo: acme/repo
pr_base: main
identities: null'
mk badbl1 'repo: acme/repo
pr_base: main
backlog:
  repo: ../x
identities: null'
mk badbl2 'repo: acme/repo
pr_base: main
backlog:
  repo: a/b/c
identities: null'
mk badbase 'repo: acme/repo
pr_base: -main
backlog:
  repo: acme/backlog
identities: null'

setyml "$tmp/legacy.yml"
co="$tmp/co"
"$real_git" -c core.autocrlf=false clone -q "$origin" "$co"
"$real_git" -C "$co" config core.autocrlf false
ourl="$("$real_git" -C "$co" remote get-url origin)"
# The checkout's own copy names a different backlog, base and identities, uncommitted.
printf 'repo: acme/repo\npr_base: tree-base\nbacklog:\n  repo: elsewhere/tree\nidentities:\n  maintainer:\n    - { login: treeuser, id: 999 }\n  dev_app: null\n  reviewer_app: null\n  loop_app: null\n' >"$co/.ai/project.yml"

mkissue_to() { # mkissue_to <file> <login> <id-json> <assoc-json> [pr|-] [updated_at] [title-json] [body-json]
  pr=
  [ "${5:-}" != pr ] || pr=',"pull_request":{"url":"x"}'
  _upd="${6:-2026-10-17T20:10:28Z}"
  _dq='"'
  _title="${7:-$_dq$MARK title$_dq}"
  _body="${8:-$_dq$MARK body$_dq}"
  printf '{"number":611,"title":%s,"body":%s,"updated_at":"%s","user":{"login":"%s","id":%s},"author_association":%s%s}\n' \
    "$_title" "$_body" "$_upd" "$2" "$3" "$4" "$pr" >"$1"
}
mkissue() { # mkissue <login> <id-json> <assoc-json> [pr|-] [updated_at] [title-json] [body-json]
  mkissue_to "$tmp/issue.json" "$@"
}
mkissue2() { # the second copy, same arguments
  mkissue_to "$tmp/issue2.json" "$@"
}
# mkrx <file> <rows...> -- each row "id content created_at", written tab-separated
mkrx() {
  _f="$1"; shift
  : >"$_f"
  for _r in "$@"; do
    set -- $_r
    printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$_f"
  done
}

reset_fx() {
  FX_NWO=acme/repo FX_DEF=main FX_ISSUE="$tmp/issue.json" FX_ECHO=1
  FX_VIEW_FAIL= FX_PERM_FAIL= FX_ISSUE_FAIL= FX_PLANT= FX_OUT= FX_LINK_TARGET=
  FX_RX= FX_RX_FAIL= FX_ISSUE2= FX_ISSUE2_FAIL= FX_CT= FX_CT_FAIL=
  export FX_NWO FX_DEF FX_ISSUE FX_ECHO FX_VIEW_FAIL FX_PERM_FAIL FX_ISSUE_FAIL FX_PLANT FX_OUT FX_LINK_TARGET
  export FX_RX FX_RX_FAIL FX_ISSUE2 FX_ISSUE2_FAIL FX_CT FX_CT_FAIL
}
reset_fx
mkissue maint 100 '"OWNER"'

# the content-time query text, read back from the script, and the argv line the stub logs for it
CTQ="$(sed -n "s/^  gh api graphql -f query='\(.*\)' -f owner=.*/\1/p" "$script")"
assert_eq "the script carries one content-time query line" yes "$([ -n "$CTQ" ] && [ "$(printf '%s\n' "$CTQ" | wc -l)" -eq 1 ] && echo yes || echo no)"
CTLINE="api|graphql|-f|query=$CTQ|-f|owner=acme|-f|name=backlog|-F|number=611|"
# mkct <created> <updated> <lastEditedAt-json> [rename-createdAt ...] -- the query's response, to $tmp/ct.json
mkct() {
  _c="$1"; _u="$2"; _e="$3"; shift 3
  _nodes=
  for _n in "$@"; do _nodes="${_nodes:+$_nodes,}{\"createdAt\":\"$_n\"}"; done
  printf '{"data":{"repository":{"issue":{"createdAt":"%s","updatedAt":"%s","lastEditedAt":%s,"timelineItems":{"nodes":[%s]}}}}}\n' \
    "$_c" "$_u" "$_e" "$_nodes" >"$tmp/ct.json"
}

newout() { mktemp -d "$scratch/o.XXXXXX"; }
calls() { # calls <log> -- the number of lines
  n=0
  while IFS= read -r _; do n=$((n + 1)); done <"$1"
  echo "$n"
}

# run <args...>: sets rc, out, err. SCRIPT, RUNDIR and XPATH override the defaults.
run() {
  : >"$glog"; : >"$gitlog"
  rc=0
  out="$(cd "${RUNDIR:-$co}" && PATH="${XPATH:-$fakebin:$PATH}" "$real_sh" "${SCRIPT:-$script}" "$@" 2>"$tmp/err")" || rc=$?
  err="$("$real_cat" "$tmp/err")"
  "$real_cat" "$glog" >>"$gall"
  reset_fx
  unset SCRIPT RUNDIR XPATH
  case "$out$err" in
    *"$MARK"*) echo "FAIL - $desc: the marker reached the script's output" >&2; fail=1 ;;
  esac
}
stop_is() { # stop_is <word> <out-dir> -- one word, exit 1, nothing on stderr, out-dir still empty
  assert_eq "$desc (word)" "$1" "$out"
  assert_eq "$desc (rc)" 1 "$rc"
  assert_eq "$desc (stderr)" "" "$err"
  assert_eq "$desc (out-dir empty)" "" "$(ls -A "$2")"
}
usage_is() { # usage_is [git-calls]
  assert_eq "$desc (stdout)" "" "$out"
  assert_eq "$desc (rc)" 2 "$rc"
  assert_eq "$desc (no gh call)" 0 "$(calls "$glog")"
  assert_eq "$desc (git calls)" "${1:-0}" "$(calls "$gitlog")"
}

# -- a pass under a map (today: the ok line, then issue.json read) ---------------------------
setyml "$tmp/map.yml"
desc="pass under a map, declared maintainer"
o="$(newout)"
run fetch 611 "$o"
assert_eq "$desc (line)" "ok B=acme/backlog BASE=main VERDICT=trusted ASSOC=OWNER" "$out"
assert_eq "$desc (rc)" 0 "$rc"
assert_eq "$desc (issue.json is the response)" yes "$(cmp -s "$tmp/issue.json" "$o/issue.json" && echo yes || echo no)"
assert_eq "$desc (nothing else in the out-dir)" issue.json "$(ls -A "$o")"
assert_eq "$desc (gh log)" "repo|view|$ourl|--json|nameWithOwner|--jq|.nameWithOwner|
repo|view|$ourl|--json|defaultBranchRef|--jq|.defaultBranchRef.name // \"\"|
api|repos/acme/backlog|--jq|.permissions|
api|repos/acme/backlog/issues/611|" "$("$real_cat" "$glog")"
assert_eq "$desc (no reactions read)" 0 "$(grep -c reactions "$glog" || true)"

# -- legacy allowlist (today: legacy/OWNER|MEMBER|COLLABORATOR pass, anything else stops) ------
setyml "$tmp/legacy.yml"
for a in OWNER MEMBER COLLABORATOR; do
  desc="identities null, $a passes"
  mkissue someone 7 "\"$a\""
  o="$(newout)"
  run fetch 611 "$o"
  assert_eq "$desc (line)" "ok B=acme/backlog BASE=main VERDICT=legacy ASSOC=$a" "$out"
  assert_eq "$desc (no reactions read)" 0 "$(grep -c reactions "$glog" || true)"
done
for a in CONTRIBUTOR NONE; do
  desc="identities null, $a is untrusted"
  mkissue someone 7 "\"$a\""
  o="$(newout)"
  run fetch 611 "$o"
  stop_is untrusted "$o"
done

# -- a map: nobody but a declared maintainer (today: not-trusted) -----------------------------
setyml "$tmp/map.yml"
for who in 'stranger 9' 'loop[bot] 400'; do
  set -- $who
  desc="map, loop_identity another login: $1 is untrusted"
  mkissue "$1" "$2" '"MEMBER"'
  o="$(newout)"
  run fetch 611 "$o"
  stop_is untrusted "$o"
done
for who in 'dev[bot] 200' 'rev[bot] 300'; do
  set -- $who
  desc="map, loop_identity another login: $1 with no reaction is unreacted (was untrusted before WB-D32)"
  mkissue "$1" "$2" '"MEMBER"'
  o="$(newout)"
  run fetch 611 "$o"
  stop_is unreacted "$o"
done
setyml "$tmp/mapnoloop.yml"
for who in 'stranger 9' 'loop[bot] 400'; do
  set -- $who
  desc="map, loop_identity null: $1 is untrusted"
  mkissue "$1" "$2" '"MEMBER"'
  o="$(newout)"
  run fetch 611 "$o"
  stop_is untrusted "$o"
done
for who in 'dev[bot] 200' 'rev[bot] 300'; do
  set -- $who
  desc="map, loop_identity null: $1 with no reaction is unreacted"
  mkissue "$1" "$2" '"MEMBER"'
  o="$(newout)"
  run fetch 611 "$o"
  stop_is unreacted "$o"
done

desc="a map maintainer whose association reads CONTRIBUTOR (an App-token read) still passes"
mkissue maint 100 '"CONTRIBUTOR"'
o="$(newout)"
run fetch 611 "$o"
assert_eq "$desc (line)" "ok B=acme/backlog BASE=main VERDICT=trusted ASSOC=CONTRIBUTOR" "$out"

desc="the loop identity under a map"
setyml "$tmp/loopmap.yml"
mkissue 'loop[bot]' 400 '"MEMBER"'
o="$(newout)"
run fetch 611 "$o"
stop_is loop-identity "$o"
setyml "$tmp/map.yml"
mkissue maint 100 '"OWNER"'

# -- the App-filed path (WB-D32, #664): an agent-filed issue passes once a maintainer reacted ----
# The issue is last updated at 20:10:28; the good reaction is a maintainer's, at 20:10:39.
RXF="$tmp/rx.tsv"
RX_GOOD='100 +1 2026-10-17T20:10:39Z'
setyml "$tmp/map.yml"

desc="reacted pass: the dev App's issue, a maintainer's +1 after its last update"
mkissue 'dev[bot]' 200 '"CONTRIBUTOR"'
mkissue2 'dev[bot]' 200 '"NONE"' - 2026-10-17T20:10:28Z '"second title"' '"second body"'
mkrx "$RXF" "$RX_GOOD"
o="$(newout)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" run fetch 611 "$o"
assert_eq "$desc (line, ASSOC from the second copy)" "ok B=acme/backlog BASE=main VERDICT=reacted ASSOC=NONE" "$out"
assert_eq "$desc (rc)" 0 "$rc"
assert_eq "$desc (issue.json is the second copy)" yes "$(cmp -s "$tmp/issue2.json" "$o/issue.json" && echo yes || echo no)"
assert_eq "$desc (nothing else in the out-dir)" issue.json "$(ls -A "$o")"
assert_eq "$desc (gh log: the reactions are read before the second issue read)" "repo|view|$ourl|--json|nameWithOwner|--jq|.nameWithOwner|
repo|view|$ourl|--json|defaultBranchRef|--jq|.defaultBranchRef.name // \"\"|
api|repos/acme/backlog|--jq|.permissions|
api|repos/acme/backlog/issues/611|
api|repos/acme/backlog/issues/611/reactions|--paginate|--jq|.[] | [(.user.id|tostring), .content, .created_at] | @tsv|
api|repos/acme/backlog/issues/611|
$CTLINE" "$("$real_cat" "$glog")"

for c in '+1' heart hooray rocket; do
  desc="reacted pass: the reviewer App's issue, a maintainer's $c"
  mkissue 'rev[bot]' 300 '"NONE"'
  mkrx "$RXF" "100 $c 2026-10-17T20:10:39Z"
  o="$(newout)"
  FX_RX="$RXF" run fetch 611 "$o"
  assert_eq "$desc (line)" "ok B=acme/backlog BASE=main VERDICT=reacted ASSOC=NONE" "$out"
done

mkrx "$RXF" "$RX_GOOD"
desc="reacted pass: a CRLF body (a browser-edited issue)"
mkissue 'dev[bot]' 200 '"NONE"' - 2026-10-17T20:10:28Z '"title"' '"line one\r\nline two\r\n"'
o="$(newout)"
FX_RX="$RXF" run fetch 611 "$o"
assert_eq "$desc (line)" "ok B=acme/backlog BASE=main VERDICT=reacted ASSOC=NONE" "$out"

desc="reacted pass: a null body"
mkissue 'dev[bot]' 200 '"NONE"' - 2026-10-17T20:10:28Z '"title"' null
o="$(newout)"
FX_RX="$RXF" run fetch 611 "$o"
assert_eq "$desc (line)" "ok B=acme/backlog BASE=main VERDICT=reacted ASSOC=NONE" "$out"

desc="reacted pass: a bracket that is not a link definition at the start of a line"
mkissue 'dev[bot]' 200 '"NONE"' - 2026-10-17T20:10:28Z '"title"' '"see [a]: b and [x](y)"'
o="$(newout)"
FX_RX="$RXF" run fetch 611 "$o"
assert_eq "$desc (line)" "ok B=acme/backlog BASE=main VERDICT=reacted ASSOC=NONE" "$out"

# unreacted: each of these stops in a map, whichever App filed the issue
mkissue 'dev[bot]' 200 '"NONE"'
desc="unreacted: no reaction at all"
mkrx "$RXF"
o="$(newout)"
FX_RX="$RXF" run fetch 611 "$o"
stop_is unreacted "$o"

desc="unreacted: only non-maintainers reacted (either App's own +1 included)"
mkrx "$RXF" "200 +1 2026-10-17T20:10:39Z" "300 +1 2026-10-17T20:10:39Z" "9 +1 2026-10-17T20:10:39Z"
o="$(newout)"
FX_RX="$RXF" run fetch 611 "$o"
stop_is unreacted "$o"

for c in '-1' eyes laugh confused; do
  desc="unreacted: a maintainer's $c does not approve"
  mkrx "$RXF" "100 $c 2026-10-17T20:10:39Z"
  o="$(newout)"
  FX_RX="$RXF" run fetch 611 "$o"
  stop_is unreacted "$o"
done

desc="unreacted: an approving reaction at the issue's updated_at"
mkrx "$RXF" "100 +1 2026-10-17T20:10:28Z"
o="$(newout)"
FX_RX="$RXF" run fetch 611 "$o"
stop_is unreacted "$o"

desc="unreacted: an approving reaction before the issue's updated_at"
mkrx "$RXF" "100 +1 2026-10-17T20:10:27Z"
o="$(newout)"
FX_RX="$RXF" run fetch 611 "$o"
stop_is unreacted "$o"

desc="unreacted: the second copy's content time moved past the reaction (a never-edited issue created at its updated_at)"
mkrx "$RXF" "$RX_GOOD"
mkissue2 'dev[bot]' 200 '"NONE"' - 2026-10-17T20:10:46Z
o="$(newout)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" run fetch 611 "$o"
stop_is unreacted "$o"

# -- the content time (#890): a comment, a label or a milestone change moves updated_at, not the content time
mkissue 'dev[bot]' 200 '"NONE"'
mkissue2 'dev[bot]' 200 '"NONE"' - 2026-10-17T20:10:46Z '"second title"' '"second body"'
mkrx "$RXF" "$RX_GOOD"
desc="reacted pass: updated_at after the reaction, content time before it (a comment, a label or a milestone change)"
mkct 2026-10-17T20:00:00Z 2026-10-17T20:10:46Z null
o="$(newout)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" FX_CT="$tmp/ct.json" run fetch 611 "$o"
assert_eq "$desc (line)" "ok B=acme/backlog BASE=main VERDICT=reacted ASSOC=NONE" "$out"
assert_eq "$desc (issue.json is the second copy)" yes "$(cmp -s "$tmp/issue2.json" "$o/issue.json" && echo yes || echo no)"

desc="reacted pass: an earlier body edit and an earlier rename"
mkct 2026-10-17T20:00:00Z 2026-10-17T20:10:46Z '"2026-10-17T20:05:00Z"' 2026-10-17T20:08:00Z
o="$(newout)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" FX_CT="$tmp/ct.json" run fetch 611 "$o"
assert_eq "$desc (line)" "ok B=acme/backlog BASE=main VERDICT=reacted ASSOC=NONE" "$out"

desc="unreacted: a body edit after the reaction"
mkct 2026-10-17T20:00:00Z 2026-10-17T20:10:46Z '"2026-10-17T20:10:46Z"'
o="$(newout)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" FX_CT="$tmp/ct.json" run fetch 611 "$o"
stop_is unreacted "$o"

desc="unreacted: a body edit after the reaction, with an older rename (the latest time wins, not the last read)"
mkct 2026-10-17T20:00:00Z 2026-10-17T20:10:46Z '"2026-10-17T20:10:46Z"' 2026-10-17T20:08:00Z
o="$(newout)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" FX_CT="$tmp/ct.json" run fetch 611 "$o"
stop_is unreacted "$o"

desc="unreacted: a title rename after the reaction"
mkct 2026-10-17T20:00:00Z 2026-10-17T20:10:46Z null 2026-10-17T20:10:46Z
o="$(newout)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" FX_CT="$tmp/ct.json" run fetch 611 "$o"
stop_is unreacted "$o"

desc="unreacted: a content time equal to the reaction's time (a body edit)"
mkct 2026-10-17T20:00:00Z 2026-10-17T20:10:46Z '"2026-10-17T20:10:39Z"'
o="$(newout)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" FX_CT="$tmp/ct.json" run fetch 611 "$o"
stop_is unreacted "$o"

desc="unreacted: a content time equal to the reaction's time (a rename)"
mkct 2026-10-17T20:00:00Z 2026-10-17T20:10:46Z null 2026-10-17T20:10:39Z
o="$(newout)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" FX_CT="$tmp/ct.json" run fetch 611 "$o"
stop_is unreacted "$o"

desc="a failed content-time query is unreachable"
o="$(newout)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" FX_CT_FAIL=1 run fetch 611 "$o"
stop_is unreachable "$o"

CTOK='"createdAt":"2026-10-17T20:00:00Z","updatedAt":"2026-10-17T20:10:46Z"'
n=0
for v in \
  'an errors key|{"errors":[{"message":"x"}],"data":{"repository":{"issue":{'"$CTOK"',"lastEditedAt":null,"timelineItems":{"nodes":[]}}}}}' \
  'a null issue|{"data":{"repository":{"issue":null}}}' \
  'a missing data key|{}' \
  'an absent lastEditedAt|{"data":{"repository":{"issue":{'"$CTOK"',"timelineItems":{"nodes":[]}}}}}' \
  'a malformed lastEditedAt|{"data":{"repository":{"issue":{'"$CTOK"',"lastEditedAt":"2026-10-17 20:00:00","timelineItems":{"nodes":[]}}}}}' \
  'a numeric lastEditedAt|{"data":{"repository":{"issue":{'"$CTOK"',"lastEditedAt":5,"timelineItems":{"nodes":[]}}}}}' \
  'a missing nodes key|{"data":{"repository":{"issue":{'"$CTOK"',"lastEditedAt":null,"timelineItems":{}}}}}' \
  'a nodes object|{"data":{"repository":{"issue":{'"$CTOK"',"lastEditedAt":null,"timelineItems":{"nodes":{}}}}}}' \
  'a null nodes|{"data":{"repository":{"issue":{'"$CTOK"',"lastEditedAt":null,"timelineItems":{"nodes":null}}}}}' \
  'a node without createdAt|{"data":{"repository":{"issue":{'"$CTOK"',"lastEditedAt":null,"timelineItems":{"nodes":[{}]}}}}}' \
  'a node with a malformed createdAt|{"data":{"repository":{"issue":{'"$CTOK"',"lastEditedAt":null,"timelineItems":{"nodes":[{"createdAt":"yesterday"}]}}}}}' \
  'two nodes|{"data":{"repository":{"issue":{'"$CTOK"',"lastEditedAt":null,"timelineItems":{"nodes":[{"createdAt":"2026-10-17T20:01:00Z"},{"createdAt":"2026-10-17T20:02:00Z"}]}}}}}' \
  'an updatedAt unequal to the second copy|{"data":{"repository":{"issue":{"createdAt":"2026-10-17T20:00:00Z","updatedAt":"2026-10-17T20:10:47Z","lastEditedAt":null,"timelineItems":{"nodes":[]}}}}}' \
  'a malformed createdAt|{"data":{"repository":{"issue":{"createdAt":"x","updatedAt":"2026-10-17T20:10:46Z","lastEditedAt":null,"timelineItems":{"nodes":[]}}}}}' \
  'a missing createdAt|{"data":{"repository":{"issue":{"updatedAt":"2026-10-17T20:10:46Z","lastEditedAt":null,"timelineItems":{"nodes":[]}}}}}' \
  'a non-string updatedAt|{"data":{"repository":{"issue":{"createdAt":"2026-10-17T20:00:00Z","updatedAt":5,"lastEditedAt":null,"timelineItems":{"nodes":[]}}}}}' \
  'a response that is not JSON|'"$MARK"' not json {'; do
  n=$((n + 1))
  desc="content-time response with ${v%%|*} is unreadable"
  printf '%s\n' "${v#*|}" >"$tmp/ct.json"
  o="$(newout)"
  FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" FX_CT="$tmp/ct.json" run fetch 611 "$o"
  stop_is unreadable "$o"
done

# a maintainer's issue and a legacy issue make no content-time query
setyml "$tmp/map.yml"
mkissue maint 100 '"OWNER"'
desc="no content-time query for a declared maintainer's issue"
o="$(newout)"
run fetch 611 "$o"
assert_eq "$desc (line)" "ok B=acme/backlog BASE=main VERDICT=trusted ASSOC=OWNER" "$out"
assert_eq "$desc (no graphql call)" 0 "$(grep -c graphql "$glog" || true)"
setyml "$tmp/legacy.yml"
desc="no content-time query under identities: null"
o="$(newout)"
run fetch 611 "$o"
assert_eq "$desc (line)" "ok B=acme/backlog BASE=main VERDICT=legacy ASSOC=OWNER" "$out"
assert_eq "$desc (no graphql call)" 0 "$(grep -c graphql "$glog" || true)"
setyml "$tmp/map.yml"
mkissue 'dev[bot]' 200 '"NONE"'
mkrx "$RXF" "$RX_GOOD"

desc="unreacted: the reviewer App's own +1 on its issue"
mkissue 'rev[bot]' 300 '"NONE"'
mkrx "$RXF" "300 +1 2026-10-17T20:10:39Z"
o="$(newout)"
FX_RX="$RXF" run fetch 611 "$o"
stop_is unreacted "$o"

# failed reads stop unreachable, never unreacted
mkissue 'dev[bot]' 200 '"NONE"'
mkrx "$RXF" "$RX_GOOD"
desc="a failed reactions read is unreachable, not unreacted"
o="$(newout)"
FX_RX="$RXF" FX_RX_FAIL=1 run fetch 611 "$o"
stop_is unreachable "$o"

desc="a failed second issue read is unreachable, not unreacted"
o="$(newout)"
FX_RX="$RXF" FX_ISSUE2_FAIL=1 run fetch 611 "$o"
stop_is unreachable "$o"

# the second copy's shape and identity
mkissue 'dev[bot]' 200 '"NONE"'
for v in \
  "another login|'rev[bot]' 300 '\"NONE\"'" \
  "the maintainer as author|maint 100 '\"OWNER\"'" \
  "the same login with another id|'dev[bot]' 201 '\"NONE\"'" \
  "a lowercase association|'dev[bot]' 200 '\"none\"'" \
  "a malformed updated_at|'dev[bot]' 200 '\"NONE\"' - '2026-10-17 20:10:28'" \
  "an updated_at with a zone offset|'dev[bot]' 200 '\"NONE\"' - '2026-10-17T20:10:28+00:00'" \
  "a non-string title|'dev[bot]' 200 '\"NONE\"' - 2026-10-17T20:10:28Z 5" \
  "a null title|'dev[bot]' 200 '\"NONE\"' - 2026-10-17T20:10:28Z null" \
  "a numeric body|'dev[bot]' 200 '\"NONE\"' - 2026-10-17T20:10:28Z '\"t\"' 5" \
  "an object body|'dev[bot]' 200 '\"NONE\"' - 2026-10-17T20:10:28Z '\"t\"' '{}'"; do
  desc="second copy with ${v%%|*} is unreadable"
  eval "mkissue2 ${v#*|}"
  o="$(newout)"
  FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" run fetch 611 "$o"
  stop_is unreadable "$o"
done

desc="second copy that is not JSON is unreadable"
printf '%s not json {\n' "$MARK" >"$tmp/issue2.json"
o="$(newout)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" run fetch 611 "$o"
stop_is unreadable "$o"

desc="second copy that is a pull request is not-an-issue"
mkissue2 'dev[bot]' 200 '"NONE"' pr
o="$(newout)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" run fetch 611 "$o"
stop_is not-an-issue "$o"

for y in mapnomaint mapemptymaint mapbadmaint; do
  desc="a maintainer list that is not well formed ($y) is unreadable"
  setyml "$tmp/$y.yml"
  o="$(newout)"
  FX_RX="$RXF" run fetch 611 "$o"
  stop_is unreadable "$o"
done
setyml "$tmp/map.yml"

# hidden: the screen runs on the decoded title and body of a reacted issue
mkrx "$RXF" "$RX_GOOD"
# each row: a label, a title (JSON), a body (JSON)
for v in \
  "a lone CR in the body|\"t\"|\"a\\rb\"" \
  "a zero-width space in the body|\"t\"|\"a\\u200bb\"" \
  "a zero-width space in the title|\"a\\u200bb\"|\"b\"" \
  "a right-to-left override in the body|\"t\"|\"a\\u202eb\"" \
  "a byte order mark in the title|\"\\ufeffa\"|\"b\"" \
  "a link reference definition line in the body|\"t\"|\"x\\n[//]: # (hidden)\\ny\"" \
  "an indented link reference definition in the body|\"t\"|\"x\\n   [label]: http://x\\ny\"" \
  "a link reference definition as the title|\"[//]: # (x)\"|\"b\"" \
  "an HTML comment opener in the body|\"t\"|\"a <!-- x -->\"" \
  "an HTML comment opener in the title|\"t <!-- x\"|\"b\"" \
  "an HTML declaration opener in the body|\"t\"|\"a <!DOCTYPE x>\"" \
  "a CDATA opener in the body|\"t\"|\"a <![CDATA[ x ]]>\"" \
  "a processing instruction opener in the title|\"t <?x y ?>\"|\"b\"" \
  "an HTML comment opener written as a JSON escape|\"t\"|\"a \\u003c!-- x\"" \
  "a zero-width space written as a JSON escape|\"t\"|\"\\u200b\"" \
  "a soft hyphen in the body|\"t\"|\"a\\u00adb\"" \
  "a decimal numeric reference in the body|\"t\"|\"a &#8203; b\"" \
  "a hex numeric reference in the title|\"a &#x200b; b\"|\"b\"" \
  "a shy reference in the body|\"t\"|\"a &shy; b\"" \
  "a zwj reference in the body|\"t\"|\"a &zwj; b\"" \
  "a closing-tag opener at the end of a line|\"t\"|\"a </\\nb\"" \
  "a bogus closing tag in the body|\"t\"|\"a </ x>\"" \
  "a variation selector 16 in the title|\"a\\ufe0fb\"|\"b\"" \
  "a variation selector 17 in the body|\"t\"|\"a\\udb40\\udd00b\"" \
  "a combining grapheme joiner in the body|\"t\"|\"a\\u034fb\"" \
  "a Mongolian vowel separator in the body|\"t\"|\"a\\u180eb\"" \
  "an inhibit symmetric swapping in the title|\"a\\u206ab\"|\"b\"" \
  "a tag character in the title|\"a\\udb40\\udc41b\"|\"b\""; do
  label="${v%%|*}"
  rest="${v#*|}"
  ttl="${rest%%|*}"
  bdy="${rest#*|}"
  desc="hidden: $label"
  mkissue 'dev[bot]' 200 '"NONE"' - 2026-10-17T20:10:28Z "$ttl" "$bdy"
  o="$(newout)"
  FX_RX="$RXF" run fetch 611 "$o"
  stop_is hidden "$o"
done

desc="hidden: a normal closing tag, a plain ampersand and a bracketed line indented four spaces pass"
mkissue 'dev[bot]' 200 '"NONE"' - 2026-10-17T20:10:28Z '"t &amp; u"' '"a </b> c &copy; d\n    [x]: y"'
o="$(newout)"
FX_RX="$RXF" run fetch 611 "$o"
assert_eq "$desc" "ok B=acme/backlog BASE=main VERDICT=reacted ASSOC=NONE" "$out"

desc="hidden: the screen runs on the second copy, not the first"
mkissue 'dev[bot]' 200 '"NONE"'
mkissue2 'dev[bot]' 200 '"NONE"' - 2026-10-17T20:10:28Z '"t"' '"a\u200bb"'
o="$(newout)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" run fetch 611 "$o"
stop_is hidden "$o"

# who is still refused, with a good reaction on file
mkissue 'loop[bot]' 400 '"NONE"'
desc="the loop App stays untrusted, and no reaction is read for it"
o="$(newout)"
FX_RX="$RXF" run fetch 611 "$o"
stop_is untrusted "$o"
assert_eq "$desc (no reactions read)" 0 "$(grep -c reactions "$glog" || true)"
mkissue stranger 9 '"NONE"'
desc="an undeclared author stays untrusted, and no reaction is read for it"
o="$(newout)"
FX_RX="$RXF" run fetch 611 "$o"
stop_is untrusted "$o"
assert_eq "$desc (no reactions read)" 0 "$(grep -c reactions "$glog" || true)"

desc="the loop's login stops loop-identity before the author is judged, with a reaction on file"
setyml "$tmp/devloop.yml"
mkissue 'dev[bot]' 200 '"NONE"'
o="$(newout)"
FX_RX="$RXF" run fetch 611 "$o"
stop_is loop-identity "$o"
assert_eq "$desc (no reactions read)" 0 "$(grep -c reactions "$glog" || true)"
setyml "$tmp/map.yml"
mkissue maint 100 '"OWNER"'

desc="a maintainer's issue passes as trusted with a reaction file present, and none is read"
o="$(newout)"
FX_RX="$RXF" run fetch 611 "$o"
assert_eq "$desc (line)" "ok B=acme/backlog BASE=main VERDICT=trusted ASSOC=OWNER" "$out"
assert_eq "$desc (no reactions read)" 0 "$(grep -c reactions "$glog" || true)"

desc="HID is spec-fresh.sh's line, byte for byte"
assert_eq "$desc" "$(grep '^HID=' "$bindir/spec-fresh.sh")" "$(grep '^HID=' "$script")"
assert_eq "$desc (one line each)" 1 "$(grep -c '^HID=' "$script")"
for k in HREF LDEF; do
  assert_eq "$k is spec-fresh.sh's line, byte for byte" "$(grep "^$k=" "$bindir/spec-fresh.sh")" "$(grep "^$k=" "$script")"
  assert_eq "$k is one line" 1 "$(grep -c "^$k=" "$script")"
done
mkissue maint 100 '"OWNER"'

# -- gh-identity.sh exit 2 (today: not-trusted) ---------------------------------------------
mkissue maint 100 '"OWNER"'
for y in dup noid; do
  setyml "$tmp/$y.yml"
  desc="gh-identity.sh cannot judge ($y)"
  o="$(newout)"
  run fetch 611 "$o"
  stop_is untrusted "$o"
done

# -- the loop's identity (today: loop-identity, before the allowlist) ------------------------
setyml "$tmp/loopid.yml"
for l in 'glunk-loop[bot]' 'GLUNK-LOOP[bot]' 'glunk-loop' 'Glunk-Loop[BOT]'; do
  desc="loop identity $l, association MEMBER"
  mkissue "$l" 400 '"MEMBER"'
  o="$(newout)"
  run fetch 611 "$o"
  stop_is loop-identity "$o"
done

# -- the response (today: a PR is not-an-issue; the rest read unchecked, now unreadable) ------
setyml "$tmp/legacy.yml"
desc="a pull request"
mkissue maint 100 '"OWNER"' pr
o="$(newout)"
run fetch 611 "$o"
stop_is not-an-issue "$o"

desc="a response that is not JSON"
printf '%s this is not json {\n' "$MARK" >"$tmp/bad.json"
o="$(newout)"
FX_ISSUE="$tmp/bad.json" run fetch 611 "$o"
stop_is unreadable "$o"

desc="a string user id"
mkissue maint '"100"' '"OWNER"'
o="$(newout)"
run fetch 611 "$o"
stop_is unreadable "$o"

desc="an association with lowercase letters"
mkissue maint 100 '"owner"'
o="$(newout)"
run fetch 611 "$o"
stop_is unreadable "$o"

desc="a pull request with a malformed user reads unreadable (not-an-issue before)"
printf '{"user":null,"author_association":"OWNER","pull_request":{}}\n' >"$tmp/bad.json"
o="$(newout)"
FX_ISSUE="$tmp/bad.json" run fetch 611 "$o"
stop_is unreadable "$o"
mkissue maint 100 '"OWNER"'

desc="a pull_request key that is null is still a pull request"
mkissue maint 100 '"OWNER"'
sed 's/}$/,"pull_request":null}/' "$tmp/issue.json" >"$tmp/prnull.json"
o="$(newout)"
FX_ISSUE="$tmp/prnull.json" run fetch 611 "$o"
stop_is not-an-issue "$o"

desc="a login with a space"
mkissue 'a b' 100 '"OWNER"'
o="$(newout)"
run fetch 611 "$o"
stop_is unreadable "$o"

desc="a malformed nameWithOwner"
mkissue maint 100 '"OWNER"'
o="$(newout)"
FX_NWO='acme/repo/x' run fetch 611 "$o"
stop_is unreadable "$o"

# -- the repository, backlog and base (today: the block stops) ---------------------------------
desc="project.yml names another repository"
setyml "$tmp/mismatch.yml"
o="$(newout)"
run fetch 611 "$o"
stop_is repo-mismatch "$o"

for y in badbl1 badbl2; do
  desc="bad backlog ($y)"
  setyml "$tmp/$y.yml"
  o="$(newout)"
  run fetch 611 "$o"
  stop_is bad-backlog "$o"
done

desc="a base beginning with a dash"
setyml "$tmp/badbase.yml"
o="$(newout)"
run fetch 611 "$o"
stop_is bad-base "$o"

for y in nullbacklog nobacklog; do
  desc="backlog.repo ($y) is the origin's nameWithOwner, in its own case"
  setyml "$tmp/$y.yml"
  o="$(newout)"
  FX_NWO=ACME/Repo run fetch 611 "$o"
  assert_eq "$desc (line)" "ok B=ACME/Repo BASE=main VERDICT=legacy ASSOC=OWNER" "$out"
  assert_eq "$desc (read at the backlog)" 1 "$(grep -c '^api|repos/ACME/Repo/issues/611|' "$glog" || true)"
done

desc="the working tree's project.yml is ignored"
setyml "$tmp/legacy.yml"
o="$(newout)"
run fetch 611 "$o"
assert_eq "$desc (line)" "ok B=acme/backlog BASE=main VERDICT=legacy ASSOC=OWNER" "$out"
assert_eq "$desc (no tree backlog read)" 0 "$(grep -c 'elsewhere' "$glog" || true)"

# -- failed reads --------------------------------------------------------------------------------
desc="a failed permissions read"
o="$(newout)"
FX_PERM_FAIL=1 run fetch 611 "$o"
stop_is unreachable "$o"

desc="a failed issue fetch"
o="$(newout)"
FX_ISSUE_FAIL=1 run fetch 611 "$o"
stop_is unreachable "$o"

desc="a failed gh repo view"
o="$(newout)"
FX_VIEW_FAIL=1 run fetch 611 "$o"
stop_is unreadable "$o"

desc="an empty default branch name"
o="$(newout)"
FX_DEF= run fetch 611 "$o"
stop_is unreadable "$o"

desc="a default branch name with a dash first"
o="$(newout)"
FX_DEF=-main run fetch 611 "$o"
stop_is unreadable "$o"

desc="an origin URL beginning with a dash"
"$real_git" -C "$co" config remote.origin.url '-evil'
o="$(newout)"
run fetch 611 "$o"
stop_is unreadable "$o"
assert_eq "$desc (no gh call)" 0 "$(calls "$glog")"
"$real_git" -C "$co" config remote.origin.url "$ourl"

desc="project.yml missing from the default branch"
gc rm -q .ai/project.yml
gc commit -q -m "drop project.yml"
o="$(newout)"
run fetch 611 "$o"
stop_is unreadable "$o"
setyml "$tmp/legacy.yml"

if [ "$can_link" = yes ]; then
  desc="yq missing from PATH"
  lb="$tmp/linkbin"
  mkdir -p "$lb"
  for t in git gh tr sed mktemp cp mv rm dirname uname ls cat; do
    if [ "$t" = gh ] || [ "$t" = git ]; then p="$fakebin/$t"; else p="$(command -v "$t")"; fi
    ln -s "$p" "$lb/$t"
  done
  o="$(newout)"
  XPATH="$lb" run fetch 611 "$o"
  stop_is unreadable "$o"
else
  echo "SKIP - yq-missing case: ln -s copies here" >&2
fi

# -- usage: exit 2, nothing on stdout, no gh call -----------------------------------------------
o="$(newout)"
desc="no arguments"
run
usage_is
desc="a leading-zero N"
run fetch 0611 "$o"
usage_is
desc="N that is not a number"
run fetch 6x "$o"
usage_is
desc="an unknown mode"
run write 611 "$o"
usage_is
desc="a missing out-dir"
run fetch 611 "$scratch/does-not-exist"
usage_is
desc="a relative out-dir"
mkdir -p "$scratch/rel"
RUNDIR="$scratch" run fetch 611 rel
usage_is
desc="a non-empty out-dir"
o2="$(newout)"
: >"$o2/file"
run fetch 611 "$o2"
usage_is
desc="a slash-less \$0"
SCRIPT=spec-issue.sh RUNDIR="$bindir" run fetch 611 "$o"
usage_is
desc="a copy of the script with no sibling gh-identity.sh"
mkdir -p "$tmp/lone"
cp "$script" "$tmp/lone/spec-issue.sh"
SCRIPT="$tmp/lone/spec-issue.sh" run fetch 611 "$o"
usage_is
desc="a copy of the script with gh-identity.sh but no sibling spec-reaction.sh"
mkdir -p "$tmp/lone2"
cp "$script" "$tmp/lone2/spec-issue.sh"
cp "$bindir/gh-identity.sh" "$tmp/lone2/gh-identity.sh"
SCRIPT="$tmp/lone2/spec-issue.sh" run fetch 611 "$o"
usage_is
desc="a copy of the script with gh-identity.sh and spec-reaction.sh but no sibling declared-ids.sh"
mkdir -p "$tmp/lone3"
cp "$script" "$tmp/lone3/spec-issue.sh"
cp "$bindir/gh-identity.sh" "$bindir/spec-reaction.sh" "$tmp/lone3/"
SCRIPT="$tmp/lone3/spec-issue.sh" run fetch 611 "$o"
usage_is
# A helper that fails or misprints stops a maintainer's issue `unreadable` at app_check (#1079), never a pass.
setyml "$tmp/map.yml"
si=0
for stub in 'exit 2' 'exit 1' 'echo unreadable' 'echo "ok 101"' 'echo "ok 101 - "' 'echo "ok 101 -  "' 'echo "ok  - "' 'echo "ok 101 02001"' 'echo "ok 101 x"' 'echo "ok 101 - -"' 'printf "ok 101 -\\nok 101 -\\n"' ': # no output'; do
  si=$((si + 1))
  mkdir -p "$tmp/stub$si"
  cp "$script" "$tmp/stub$si/spec-issue.sh"
  cp "$bindir/gh-identity.sh" "$bindir/spec-reaction.sh" "$tmp/stub$si/"
  printf '#!/bin/sh\n%s\n' "$stub" >"$tmp/stub$si/declared-ids.sh"
  desc="a helper stub that does [$stub] stops a maintainer's issue unreadable"
  mkissue maint 100 '"OWNER"'
  o="$(newout)"
  SCRIPT="$tmp/stub$si/spec-issue.sh" run fetch 611 "$o"
  stop_is unreadable "$o"
done
setyml "$tmp/legacy.yml"
desc="an out-dir inside the checkout"
mkdir -p "$co/inside"
run fetch 611 "$co/inside"
usage_is 1
assert_eq "$desc (the one git call)" "rev-parse|--show-toplevel|" "$("$real_cat" "$gitlog")"
desc="git rev-parse fails"
RUNDIR="$tmp/nogit" run fetch 611 "$o"
usage_is 1
assert_eq "$desc (the one git call)" "rev-parse|--show-toplevel|" "$("$real_cat" "$gitlog")"

if [ "$can_link" = yes ]; then
  desc="a symlinked out-dir"
  ln -s "$o" "$tmp/outlink"
  run fetch 611 "$tmp/outlink"
  usage_is
  desc="an out-dir reached through a symlinked parent that resolves inside the checkout"
  ln -s "$co" "$tmp/colink"
  mkdir -p "$co/inside2"
  run fetch 611 "$tmp/colink/inside2"
  usage_is 1
  assert_eq "$desc (the one git call)" "rev-parse|--show-toplevel|" "$("$real_cat" "$gitlog")"
  desc="an out-dir reached through a symlinked parent that resolves outside the checkout passes"
  ln -s "$scratch" "$tmp/scrlink"
  o3="$(newout)"
  run fetch 611 "$tmp/scrlink/$(basename "$o3")"
  assert_eq "$desc (line)" "ok B=acme/backlog BASE=main VERDICT=legacy ASSOC=OWNER" "$out"
  assert_eq "$desc (issue.json in the resolved dir)" yes "$([ -f "$o3/issue.json" ] && echo yes || echo no)"

  desc="an issue.json planted as a symlink after the emptiness check"
  o4="$(newout)"
  FX_PLANT=link FX_OUT="$o4" FX_LINK_TARGET="$tmp/elsewhere/target" run fetch 611 "$o4"
  assert_eq "$desc (word)" unreadable "$out"
  assert_eq "$desc (rc)" 1 "$rc"
  assert_eq "$desc (left alone, not written through)" "issue.json" "$(ls -A "$o4")"
  assert_eq "$desc (still a link)" yes "$([ -L "$o4/issue.json" ] && echo yes || echo no)"
  assert_eq "$desc (target untouched)" "" "$(ls -A "$tmp/elsewhere")"
else
  echo "SKIP - symlink cases: ln -s copies here" >&2
fi
desc="an issue.json planted as a file after the emptiness check"
o5="$(newout)"
FX_PLANT=file FX_OUT="$o5" run fetch 611 "$o5"
assert_eq "$desc (word)" unreadable "$out"
assert_eq "$desc (rc)" 1 "$rc"
assert_eq "$desc (left alone)" planted "$("$real_cat" "$o5/issue.json")"

# -- a declared App's id on the maintainer list (#759): every such config stops `unreadable` ----
# for a maintainer author and an App author alike, before the issue's reactions are read.
DEVV='{ login: "dev[bot]", id: 200 }'
REVV='{ login: "rev[bot]", id: 300 }'
LOOPV='{ login: "loop[bot]", id: 400 }'
mkcfg() { # mkcfg <name> <extra maintainer entry|-> <dev|-|null> <rev|-|null> <loop|-|null>; "-" omits the key
  {
    printf 'repo: acme/repo\npr_base: main\nbacklog:\n  repo: acme/backlog\norchestration:\n  loop_identity: "other-loop[bot]"\nidentities:\n  maintainer:\n    - { login: maint, id: 100 }\n'
    [ "$2" = - ] || printf '    - %s\n' "$2"
    [ "$3" = - ] || printf '  dev_app: %s\n' "$3"
    [ "$4" = - ] || printf '  reviewer_app: %s\n' "$4"
    [ "$5" = - ] || printf '  loop_app: %s\n' "$5"
  } >"$tmp/$1.yml"
}
unread_is() { # unread_is <cfg> <login> <id> <assoc> [rx-file] [body-json] -- stops unreadable, no reactions or second read
  setyml "$tmp/$1.yml"
  mkissue "$2" "$3" "$4" - 2026-10-17T20:10:28Z '"title"' "${6:-\"body\"}"
  mkissue2 "$2" "$3" "$4" - 2026-10-17T20:10:28Z '"title"' "${6:-\"body\"}"
  o="$(newout)"
  FX_RX="${5:-$RXF}" FX_ISSUE2="$tmp/issue2.json" run fetch 611 "$o"
  stop_is unreadable "$o"
  assert_eq "$desc (no reactions read)" 0 "$(grep -c reactions "$glog" || true)"
  assert_eq "$desc (no second issue read)" 1 "$(grep -c -x 'api|repos/acme/backlog/issues/611|' "$glog" || true)"
}
mkrx "$RXF" "$RX_GOOD"
for k in dev rev loop; do
  case "$k" in
    dev) kv=$DEVV; kentry='{ login: "dev[bot]", id: 200 }'; other_l='rev[bot]'; other_i=300 ;;
    rev) kv=$REVV; kentry='{ login: "rev[bot]", id: 300 }'; other_l='dev[bot]'; other_i=200 ;;
    loop) kv=$LOOPV; kentry='{ login: "loop[bot]", id: 400 }'; other_l='dev[bot]'; other_i=200 ;;
  esac
  mkcfg "coll_$k" "$kentry" "$DEVV" "$REVV" "$LOOPV"
  desc="$k App's id on the maintainer list, maintainer's issue"
  unread_is "coll_$k" maint 100 '"OWNER"'
  desc="$k App's id on the maintainer list, issue by the $other_l App"
  unread_is "coll_$k" "$other_l" "$other_i" '"NONE"'
  desc="$k App's id on the maintainer list, App issue with no reaction (not unreacted)"
  mkrx "$tmp/rx_none.tsv"
  unread_is "coll_$k" "$other_l" "$other_i" '"NONE"' "$tmp/rx_none.tsv"
  desc="$k App's id on the maintainer list, App issue with only an older reaction (not unreacted)"
  mkrx "$tmp/rx_old.tsv" '100 +1 2026-10-17T20:00:00Z'
  unread_is "coll_$k" "$other_l" "$other_i" '"NONE"' "$tmp/rx_old.tsv"
  desc="$k App's id on the maintainer list, App issue with hidden text and a fresh reaction (not hidden)"
  unread_is "coll_$k" "$other_l" "$other_i" '"NONE"' "$RXF" '"a​b"'
done

# the exploit: the reviewer App's id on the list, a dev-App issue, only the reviewer App's own fresh +1
desc="exploit: the reviewer App's own +1 on a dev-App issue, its id on the maintainer list"
mkrx "$tmp/rx_rev.tsv" '300 +1 2026-10-17T20:10:39Z'
unread_is coll_rev 'dev[bot]' 200 '"NONE"' "$tmp/rx_rev.tsv"

# a declared App entry that is not well formed, or whose id is not canonical decimal
for k in dev rev loop; do
  case "$k" in
    dev) other_l='rev[bot]'; other_i=300; aid=200 ;;
    rev) other_l='dev[bot]'; other_i=200; aid=300 ;;
    loop) other_l='dev[bot]'; other_i=200; aid=400 ;;
  esac
  n=0
  for bad in 'nope' "{ login: \"x[bot]\", id: \"$aid\" }" '{ login: "x[bot]", id: 0 }' "{ login: 5, id: $aid }" \
    "{ login: \"x[bot]\", id: +$aid }" '{ login: "x[bot]", id: 0x12C }' '{ login: "x[bot]", id: 0100 }'; do
    n=$((n + 1))
    d=- r=- l=-
    case "$k" in dev) d=$bad ;; rev) r=$bad ;; loop) l=$bad ;; esac
    [ "$d" != - ] || d=$DEVV
    [ "$r" != - ] || r=$REVV
    [ "$l" != - ] || l=$LOOPV
    mkcfg "bad_${k}_$n" - "$d" "$r" "$l"
    desc="$k App entry $bad, maintainer's issue"
    unread_is "bad_${k}_$n" maint 100 '"OWNER"'
    desc="$k App entry $bad, issue by the $other_l App"
    unread_is "bad_${k}_$n" "$other_l" "$other_i" '"NONE"'
  done
done

# a maintainer's issue under a list with a malformed extra entry (it passed as `trusted` before)
desc="a maintainer's issue under mapbadmaint"
cp "$tmp/mapbadmaint.yml" "$tmp/badmaint_copy.yml"
unread_is badmaint_copy maint 100 '"OWNER"'

# no check for a null or missing App key; a fresh maintainer +1 still passes
pass_is() { # pass_is <cfg> <login> <id>
  setyml "$tmp/$1.yml"
  mkissue "$2" "$3" '"NONE"' - 2026-10-17T20:10:28Z '"title"' '"body"'
  mkissue2 "$2" "$3" '"NONE"' - 2026-10-17T20:10:28Z '"title"' '"body"'
  mkrx "$RXF" "$RX_GOOD"
  o="$(newout)"
  FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" run fetch 611 "$o"
  assert_eq "$desc (line)" "ok B=acme/backlog BASE=main VERDICT=reacted ASSOC=NONE" "$out"
}
mkcfg nul_rl - "$DEVV" null null
desc="reviewer_app and loop_app null, a dev-App issue"
pass_is nul_rl 'dev[bot]' 200
mkcfg mis_rl - "$DEVV" - -
desc="reviewer_app and loop_app missing, a dev-App issue"
pass_is mis_rl 'dev[bot]' 200
mkcfg nul_d - null "$REVV" "$LOOPV"
desc="dev_app null, a reviewer-App issue"
pass_is nul_d 'rev[bot]' 300
mkcfg mis_d - - "$REVV" "$LOOPV"
desc="dev_app missing, a reviewer-App issue"
pass_is mis_d 'rev[bot]' 300
setyml "$tmp/map.yml"

# -- the skill's snippet with a failing mktemp ---------------------------------------------------
desc="the skill snippet with a failing mktemp"
awk '/^   ```bash/ { on = 1; next } /^   ```/ { if (on) exit } on { sub(/^   /, ""); print }' "$skill" |
  sed 's/^N=<digits>/N=611/' >"$tmp/snippet.sh"
assert_eq "$desc (snippet found)" yes "$(grep -q 'spec-issue.sh fetch' "$tmp/snippet.sh" && echo yes || echo no)"
mkdir -p "$tmp/mtbin" "$tmp/fakeco"
printf '#!/bin/sh\nexit 1\n' >"$tmp/mtbin/mktemp"
chmod +x "$tmp/mtbin/mktemp"
printf 'keep\n' >"$tmp/fakeco/a"
rc=0
(cd "$tmp/fakeco" && PATH="$tmp/mtbin:$fakebin:$PATH" "$real_sh" "$tmp/snippet.sh" >"$tmp/snip.out" 2>"$tmp/snip.err") || rc=$?
assert_eq "$desc (stops)" 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)"
assert_eq "$desc (checkout files still there)" keep "$("$real_cat" "$tmp/fakeco/a")"
assert_eq "$desc (stop line)" "stopped: no word" "$("$real_cat" "$tmp/snip.err")"

# -- every gh call is a GET; the marker never reaches the script's streams -----------------------
assert_eq "gh calls were made" yes "$([ -s "$gall" ] && echo yes || echo no)"
# the one exception is the read-only content-time query's exact argv (#890), and nothing else
assert_eq "the content-time query was made" yes "$(grep -qxF -e "$CTLINE" "$gall" && echo yes || echo no)"
assert_eq "every gh call is a GET, but the one content-time query" 0 "$(grep -vxF -e "$CTLINE" "$gall" | grep -c -e '|-X|' -e '|--method|' -e '|-f|' -e '|-F|' -e '|--field|' -e '|--raw-field|' -e '|--input|' -e 'graphql' || true)"

exit "$fail"
