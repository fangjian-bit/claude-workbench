#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/spec-post.sh: spec-task's one write, the post of a
# checked draft as a new comment by the declared dev App, or the hold of the composed comment for
# a human (WB-D29).
#
# The real script runs from a local checkout cloned from a fixture origin repository whose default
# branch (`git init -b main`) carries .ai/project.yml; each case commits the project.yml it needs
# to that origin. First on PATH, only while the script runs, are a stub `gh` (keyed on the shape of
# the call; it logs its argv, saves the standard input of the comment POST and does not interpret --jq) and
# a logging `git` wrapper. Needs git and yq (mikefarah v4); skips, loudly, without yq.
#
# What it pins: the happy path makes exactly one write that is not the viewer query, and its
# standard input is the marker line, an empty line, then the draft's bytes; every stop and every
# hold makes none, except `post-unknown`, which makes exactly one and is never retried. The
# `escalate` mode (#746) makes the same comment POST under the escalated marker and then, only
# after a confirmed post, one label read and at most one label write (never retried); its stops,
# holds, `post-unknown` and `posted-unreadable` make no label call. Symlink
# cases skip, loudly, where `ln -s` copies instead of linking (Git Bash).
# Permitted toolset: POSIX sh.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
bindir="$root_dir/plugins/way-of-working/bin"
script="$bindir/spec-post.sh"

if ! command -v yq >/dev/null 2>&1; then
  echo "SKIP - yq not on PATH; spec-post.sh needs it" >&2
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
gstdin="$tmp/gh.stdin"
gitlog="$tmp/git.log"

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
if [ "$1 $2" = "repo view" ]; then
  [ -n "$3" ] || exit 1
  [ -z "${FX_VIEW_FAIL:-}" ] || fail_with
  if [ -n "${FX_HOOK:-}" ]; then printf 'swapped draft\n' >"$FX_HOOK"; fi
  case "$*" in
    *nameWithOwner*) printf '%s\n' "$FX_NWO" ;;
    *defaultBranchRef*) printf '%s\n' "$FX_DEF" ;;
    *) exit 1 ;;
  esac
  exit 0
fi
case "$*" in
  *graphql*)
    [ -z "${FX_VIEWER_FAIL:-}" ] || fail_with
    printf '%s\t%s\n' "$FX_VLOGIN" "$FX_VID"
    ;;
  *"labels?per_page=100"*)
    [ -z "${FX_LBLR_FAIL:-}" ] || fail_with
    if [ -n "${FX_LABELS:-}" ]; then "$FX_CAT" "$FX_LABELS"; fi
    ;;
  *"--method POST"*"issues/"*"/labels"*)
    [ -z "${FX_LBLW_FAIL:-}" ] || fail_with
    printf '[]\n'
    ;;
  *"--method|POST"* | *"--method POST"*)
    "$FX_CAT" >"$FX_STDIN"
    [ -z "${FX_POST_FAIL:-}" ] || fail_with
    "$FX_CAT" "$FX_RESP"
    ;;
  *"issues/"*"/reactions"*)
    [ -z "${FX_RX_FAIL:-}" ] || fail_with
    if [ -n "${FX_RX:-}" ]; then "$FX_CAT" "$FX_RX"; fi
    ;;
  *"issues/"*)
    [ -z "${FX_ISSUE_FAIL:-}" ] || fail_with
    # the second issue read of a run is the one that can differ
    nreads="$(grep -c '^api|--hostname|github.com|repos/[^|]*/issues/[0-9]*|$' "$FX_GHLOG" || true)"
    if [ "$nreads" -ge 2 ]; then
      [ -z "${FX_ISSUE2_FAIL:-}" ] || fail_with
      if [ -n "${FX_ISSUE2:-}" ]; then "$FX_CAT" "$FX_ISSUE2"; exit 0; fi
    fi
    "$FX_CAT" "$FX_ISSUE"
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

export FX_GHLOG="$glog" FX_GITLOG="$gitlog" FX_REAL_GIT="$real_git" FX_CAT="$real_cat" FX_MARK="$MARK" FX_STDIN="$gstdin"

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
mk legacy 'repo: acme/repo
pr_base: main
backlog:
  repo: acme/backlog
identities: null'
mk noident 'repo: acme/repo
pr_base: main
backlog:
  repo: acme/backlog'
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
mk nobranch 'repo: acme/repo
pr_base: no-such-branch
backlog:
  repo: acme/backlog
identities: null'
mk badbase 'repo: acme/repo
pr_base: -main
backlog:
  repo: acme/backlog
identities: null'

setyml "$tmp/map.yml"
co="$tmp/co"
"$real_git" -c core.autocrlf=false clone -q "$origin" "$co"
"$real_git" -C "$co" config core.autocrlf false
ourl="$("$real_git" -C "$co" remote get-url origin)"
# The checkout's own copy names a different backlog, base and identities, uncommitted.
printf 'repo: acme/repo\npr_base: tree-base\nbacklog:\n  repo: elsewhere/tree\nidentities: null\n' >"$co/.ai/project.yml"

SHA="$("$real_git" -C "$origin" rev-parse HEAD)"
SIDE="$("$real_git" -C "$co" -c user.name=fx -c user.email=fx@example.test commit-tree "HEAD^{tree}" -p HEAD -m side)"
GONE=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

mkdraft() { # mkdraft <file> [extra-line] -- a draft in the fixed shape; the extra line sits in Goal
  {
    printf '%s\n' 'Spec for the thing. Drafted against main at abc1234. Back\slash and {pr_base} braces.'
    printf '\n### Goal\n'
    [ -z "${2:-}" ] || printf '%s\n' "$2"
    printf '%s\n' 'Goal text with back\slash, {pr_base} and ${HOME} left alone.'
    printf '\n### Files touched\nOne file.\n'
    printf '\n### Done when\nIt runs.\n'
    printf '\n### Tests\nA test.\n'
    printf '\n### Out of scope\nNothing else.\n'
    printf '\n### Restated from the issue body\nnothing\n'
  } >"$1"
}

mkissue_to() { # mkissue_to <file> <login> <id-json> <assoc-json> [state] [locked] [pr|-] [updated_at] [title-json] [body-json]
  st="${5:-open}"
  lk="${6:-false}"
  pr=
  [ "${7:-}" != pr ] || pr=',"pull_request":{"url":"x"}'
  _upd="${8:-2026-10-17T20:10:28Z}"
  _dq='"'
  _title="${9:-$_dq$MARK title$_dq}"
  _body="${10:-$_dq$MARK body$_dq}"
  printf '{"number":661,"title":%s,"body":%s,"updated_at":"%s","user":{"login":"%s","id":%s},"author_association":%s,"state":"%s","locked":%s%s}\n' \
    "$_title" "$_body" "$_upd" "$2" "$3" "$4" "$st" "$lk" "$pr" >"$1"
}
mkissue() { mkissue_to "$tmp/issue.json" "$@"; }
mkissue2() { mkissue_to "$tmp/issue2.json" "$@"; }
# mkrx <file> <rows...> -- each row "id content created_at", written tab-separated
mkrx() {
  _f="$1"; shift
  : >"$_f"
  for _r in "$@"; do
    set -- $_r
    printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$_f"
  done
}
mkresp() { # mkresp <id> <login> <uid> <issue-no> -- the POST response
  printf '{"id":%s,"user":{"login":"%s","id":%s},"issue_url":"https://api.github.com/repos/acme/backlog/issues/%s","html_url":"https://github.com/acme/backlog/issues/661#issuecomment-%s"}\n' \
    "$1" "$2" "$3" "$4" "$1" >"$tmp/resp.json"
}

reset_fx() {
  FX_NWO=acme/repo FX_DEF=main FX_ISSUE="$tmp/issue.json" FX_RESP="$tmp/resp.json"
  FX_VLOGIN='dev[bot]' FX_VID=200
  FX_VIEW_FAIL= FX_ISSUE_FAIL= FX_VIEWER_FAIL= FX_POST_FAIL= FX_HOOK=
  FX_RX= FX_RX_FAIL= FX_ISSUE2= FX_ISSUE2_FAIL=
  FX_LABELS="$tmp/labels.txt" FX_LBLR_FAIL= FX_LBLW_FAIL=
  export FX_LABELS FX_LBLR_FAIL FX_LBLW_FAIL
  export FX_NWO FX_DEF FX_ISSUE FX_RESP FX_VLOGIN FX_VID FX_VIEW_FAIL FX_ISSUE_FAIL FX_VIEWER_FAIL FX_POST_FAIL FX_HOOK
  export FX_RX FX_RX_FAIL FX_ISSUE2 FX_ISSUE2_FAIL
  printf 'bug\nstatus/needs-human\n' >"$tmp/labels.txt"
  mkissue maint 100 '"OWNER"'
  mkresp 777 'dev[bot]' 200 661
}
reset_fx

newdir() { mktemp -d "$scratch/d.XXXXXX"; }
calls() { # calls <log> -- the number of lines
  n=0
  while IFS= read -r _; do n=$((n + 1)); done <"$1"
  echo "$n"
}
writes() { # every gh call that is not a known read (repo view, the issue GET, its reactions GET, the exact viewer query)
  grep -vc -e '^repo|view|' -e '^api|--hostname|github.com|repos/[^|]*/issues/[0-9]*|$' -e '^api|--hostname|github.com|repos/[^|]*/issues/[0-9]*/reactions|--paginate|--jq|' -e '^api|--hostname|github.com|graphql|-f|query={ viewer { login databaseId } }|--jq|' -e '^api|--hostname|github.com|repos/[^|]*/labels?per_page=100|--paginate|--jq|.\[\].name|' "$glog" || true
}
lblcalls() { # lblcalls <read|write> -- the number of label reads or label writes in the gh log
  case "$1" in
    read) grep -c 'labels?per_page=100' "$glog" || true ;;
    *) grep -c -e '--method|POST|repos/[^|]*/issues/[0-9]*/labels|' "$glog" || true ;;
  esac
}

# run <args...>: sets rc, out, err. SCRIPT, RUNDIR and XPATH override the defaults.
run() {
  : >"$glog"; : >"$gitlog"; rm -f "$gstdin"
  rc=0
  out="$(cd "${RUNDIR:-$co}" && PATH="${XPATH:-$fakebin:$PATH}" "$real_sh" "${SCRIPT:-$script}" "$@" 2>"$tmp/err")" || rc=$?
  err="$("$real_cat" "$tmp/err")"
  reset_fx
  unset SCRIPT RUNDIR XPATH
  case "$out$err" in
    *"$MARK"*) echo "FAIL - $desc: the marker reached the script's output" >&2; fail=1 ;;
  esac
}
# post <draft> <out-dir> -- the usual call
post() { run post 661 "$SHA" "$1" "$2"; }
esc() { run escalate 661 "$SHA" "$1" "$2"; }

stop_is() { # stop_is <word> -- one word, exit 1, nothing on stderr, no write
  assert_eq "$desc (word)" "$1" "$out"
  assert_eq "$desc (rc)" 1 "$rc"
  assert_eq "$desc (stderr)" "" "$err"
  assert_eq "$desc (no write)" 0 "$(writes)"
  assert_eq "$desc (no label call)" 0 "$(( $(lblcalls read) + $(lblcalls write) ))"
}
held_is() { # held_is <reason> <out-dir> [marker-prefix] -- a hold: the composed comment is kept, nothing posted
  assert_eq "$desc (line)" "held $1 $2/comment.md" "$out"
  assert_eq "$desc (rc)" 1 "$rc"
  assert_eq "$desc (stderr)" "" "$err"
  assert_eq "$desc (no write)" 0 "$(writes)"
  assert_eq "$desc (comment kept)" comment.md "$(ls -A "$2")"
  assert_eq "$desc (marker first)" "${3:-spec-task}: issue=661 base=main sha=$SHA" "$(head -n 1 "$2/comment.md")"
  assert_eq "$desc (no label call)" 0 "$(( $(lblcalls read) + $(lblcalls write) ))"
}
usage_is() {
  assert_eq "$desc (stdout)" "" "$out"
  assert_eq "$desc (rc)" 2 "$rc"
  assert_eq "$desc (no gh call)" 0 "$(calls "$glog")"
}

dr="$(newdir)"
mkdraft "$dr/draft.md"
expect="$tmp/expect.md"
{ printf 'spec-task: issue=661 base=main sha=%s\n\n' "$SHA"; "$real_cat" "$dr/draft.md"; } >"$expect"

# -- the happy path: the dev App posts ---------------------------------------------------------
desc="pass under a map as the dev App"
o="$(newdir)"
post "$dr/draft.md" "$o"
assert_eq "$desc (line)" "posted 777 dev[bot] https://github.com/acme/backlog/issues/661#issuecomment-777" "$out"
assert_eq "$desc (rc)" 0 "$rc"
assert_eq "$desc (stderr)" "" "$err"
assert_eq "$desc (exactly one POST)" 1 "$(writes)"
assert_eq "$desc (stdin is marker, blank line, draft bytes)" yes "$(cmp -s "$expect" "$gstdin" && echo yes || echo no)"
assert_eq "$desc (comment.md is the posted body)" yes "$(cmp -s "$expect" "$o/comment.md" && echo yes || echo no)"
assert_eq "$desc (nothing else in the out-dir)" comment.md "$(ls -A "$o")"
assert_eq "$desc (gh log)" "repo|view|$ourl|--json|nameWithOwner|--jq|.nameWithOwner|
repo|view|$ourl|--json|defaultBranchRef|--jq|.defaultBranchRef.name // \"\"|
api|--hostname|github.com|repos/acme/backlog/issues/661|
api|--hostname|github.com|graphql|-f|query={ viewer { login databaseId } }|--jq|[.data.viewer.login, .data.viewer.databaseId] | @tsv|
api|--hostname|github.com|--method|POST|repos/acme/backlog/issues/661/comments|-F|body=@-|" "$("$real_cat" "$glog")"
assert_eq "$desc (no label call)" 0 "$(( $(lblcalls read) + $(lblcalls write) ))"
assert_eq "$desc (the draft keeps its backslash and braces)" 2 "$(grep -c -e 'back\\slash' -e '{pr_base}' "$o/comment.md" || true)"

# -- escalate (#746) -----------------------------------------------------------------------------
eexpect="$tmp/eexpect.md"
{ printf 'spec-task-escalated: issue=661 base=main sha=%s\n\n' "$SHA"; "$real_cat" "$dr/draft.md"; } >"$eexpect"
ehurl="https://github.com/acme/backlog/issues/661#issuecomment-777"

desc="escalate: pass under a map as the dev App"
o="$(newdir)"
esc "$dr/draft.md" "$o"
assert_eq "$desc (line)" "escalated 777 dev[bot] $ehurl labelled" "$out"
assert_eq "$desc (rc)" 0 "$rc"
assert_eq "$desc (stderr)" "" "$err"
assert_eq "$desc (comment POST and label write)" 2 "$(writes)"
assert_eq "$desc (stdin is escalated marker, blank line, draft bytes)" yes "$(cmp -s "$eexpect" "$gstdin" && echo yes || echo no)"
assert_eq "$desc (comment.md is the posted body)" yes "$(cmp -s "$eexpect" "$o/comment.md" && echo yes || echo no)"
assert_eq "$desc (gh log)" "repo|view|$ourl|--json|nameWithOwner|--jq|.nameWithOwner|
repo|view|$ourl|--json|defaultBranchRef|--jq|.defaultBranchRef.name // \"\"|
api|--hostname|github.com|repos/acme/backlog/issues/661|
api|--hostname|github.com|graphql|-f|query={ viewer { login databaseId } }|--jq|[.data.viewer.login, .data.viewer.databaseId] | @tsv|
api|--hostname|github.com|--method|POST|repos/acme/backlog/issues/661/comments|-F|body=@-|
api|--hostname|github.com|repos/acme/backlog/labels?per_page=100|--paginate|--jq|.[].name|
api|--hostname|github.com|--method|POST|repos/acme/backlog/issues/661/labels|-f|labels[]=status/needs-human|" "$("$real_cat" "$glog")"

desc="escalate: the label is absent from the repository"
printf 'bug\nstatus/needs-human-not\n' >"$tmp/labels.txt"
o="$(newdir)"
FX_LABELS="$tmp/labels.txt" esc "$dr/draft.md" "$o"
assert_eq "$desc (line)" "escalated 777 dev[bot] $ehurl label-absent" "$out"
assert_eq "$desc (rc)" 0 "$rc"
assert_eq "$desc (one label read)" 1 "$(lblcalls read)"
assert_eq "$desc (no label write)" 0 "$(lblcalls write)"
assert_eq "$desc (one write)" 1 "$(writes)"

desc="escalate: the label read fails"
o="$(newdir)"
FX_LBLR_FAIL=1 esc "$dr/draft.md" "$o"
assert_eq "$desc (line)" "escalated 777 dev[bot] $ehurl label-unreadable" "$out"
assert_eq "$desc (rc)" 0 "$rc"
assert_eq "$desc (one label read)" 1 "$(lblcalls read)"
assert_eq "$desc (no label write)" 0 "$(lblcalls write)"

desc="escalate: the label write fails, made once and never retried"
o="$(newdir)"
FX_LBLW_FAIL=1 esc "$dr/draft.md" "$o"
assert_eq "$desc (line)" "escalated 777 dev[bot] $ehurl label-failed" "$out"
assert_eq "$desc (rc)" 0 "$rc"
assert_eq "$desc (one label read)" 1 "$(lblcalls read)"
assert_eq "$desc (one label write)" 1 "$(lblcalls write)"

desc="escalate: post-unknown makes the comment POST and no label call"
o="$(newdir)"
FX_POST_FAIL=1 esc "$dr/draft.md" "$o"
assert_eq "$desc (word)" post-unknown "$out"
assert_eq "$desc (one write)" 1 "$(writes)"
assert_eq "$desc (no label call)" 0 "$(( $(lblcalls read) + $(lblcalls write) ))"
assert_eq "$desc (comment kept, escalated marker)" "spec-task-escalated: issue=661 base=main sha=$SHA" "$(head -n 1 "$o/comment.md")"

desc="escalate: posted-unreadable makes the comment POST and no label call"
mkresp 777 'maint' 100 661
o="$(newdir)"
esc "$dr/draft.md" "$o"
assert_eq "$desc (word)" posted-unreadable "$out"
assert_eq "$desc (one write)" 1 "$(writes)"
assert_eq "$desc (no label call)" 0 "$(( $(lblcalls read) + $(lblcalls write) ))"

desc="escalate hold: identities null"
setyml "$tmp/legacy.yml"
o="$(newdir)"
esc "$dr/draft.md" "$o"
held_is no-identities "$o" spec-task-escalated
setyml "$tmp/map.yml"

desc="escalate hold: the viewer is not the dev App"
o="$(newdir)"
FX_VLOGIN=maint FX_VID=100 esc "$dr/draft.md" "$o"
held_is not-dev-app "$o" spec-task-escalated

for m in post escalate; do
  for pre in 'spec-task: issue=1 base=main sha=x' 'spec-task-escalated: issue=1 base=main sha=x'; do
    desc="stop: has-marker in $m mode for a draft line '${pre%%:*}:'"
    d4="$(newdir)"
    mkdraft "$d4/draft.md" "$pre"
    o="$(newdir)"
    run "$m" 661 "$SHA" "$d4/draft.md" "$o"
    stop_is has-marker
    assert_eq "$desc (out-dir empty)" "" "$(ls -A "$o")"
  done
done

desc="the checkout's own project.yml is ignored (backlog read at the default branch's)"
assert_eq "$desc" 0 "$(grep -c 'elsewhere' "$glog" || true)"

desc="an ancestor of the base, not its tip, is accepted"
setyml "$tmp/map.yml"
o="$(newdir)"
post "$dr/draft.md" "$o"
assert_eq "$desc (line)" "posted 777 dev[bot] https://github.com/acme/backlog/issues/661#issuecomment-777" "$out"
{ printf 'spec-task: issue=661 base=main sha=%s\n\n' "$SHA"; "$real_cat" "$dr/draft.md"; } >"$expect"
assert_eq "$desc (marker names the sha given)" yes "$(cmp -s "$expect" "$gstdin" && echo yes || echo no)"

desc="backlog.repo null is the origin's repository"
setyml "$tmp/nullbacklog.yml"
o="$(newdir)"
FX_NWO=ACME/Repo post "$dr/draft.md" "$o"
assert_eq "$desc (word)" "held no-identities $o/comment.md" "$out"
assert_eq "$desc (issue read at the origin's repository)" 1 "$(grep -c '^api|--hostname|github.com|repos/ACME/Repo/issues/661|' "$glog" || true)"
setyml "$tmp/map.yml"

# -- holds: composed, kept, never posted -------------------------------------------------------
desc="hold: identities null"
setyml "$tmp/legacy.yml"
o="$(newdir)"
post "$dr/draft.md" "$o"
held_is no-identities "$o"
assert_eq "$desc (no viewer read)" 0 "$(grep -c 'graphql' "$glog" || true)"

# An absent `identities` key is a config gh-identity.sh cannot judge, so the author check stops it
# as `untrusted` before the hold is reached, as in spec-issue.sh.
desc="stop: identities key absent"
setyml "$tmp/noident.yml"
o="$(newdir)"
post "$dr/draft.md" "$o"
stop_is untrusted

setyml "$tmp/map.yml"
for who in 'maint 100' 'rev[bot] 300' 'loop[bot] 400' 'stranger 9'; do
  set -- $who
  desc="hold: the viewer is $1"
  o="$(newdir)"
  FX_VLOGIN="$1" FX_VID="$2" post "$dr/draft.md" "$o"
  held_is not-dev-app "$o"
done

desc="hold: a viewer read that gh-identity.sh cannot judge (exit 2)"
o="$(newdir)"
FX_VLOGIN='not a login' post "$dr/draft.md" "$o"
held_is not-dev-app "$o"

desc="hold: the graphql call fails"
o="$(newdir)"
FX_VIEWER_FAIL=1 post "$dr/draft.md" "$o"
held_is actor-unreadable "$o"

# -- stops --------------------------------------------------------------------------------------
desc="stop: project.yml missing from the default branch"
gc rm -q .ai/project.yml
gc commit -q -m "drop project.yml"
o="$(newdir)"
post "$dr/draft.md" "$o"
stop_is unreadable
assert_eq "$desc (out-dir empty)" "" "$(ls -A "$o")"
setyml "$tmp/map.yml"

desc="stop: a failed gh repo view"
o="$(newdir)"
FX_VIEW_FAIL=1 post "$dr/draft.md" "$o"
stop_is unreadable

desc="stop: a malformed nameWithOwner"
o="$(newdir)"
FX_NWO='acme/repo/x' post "$dr/draft.md" "$o"
stop_is unreadable

desc="stop: an origin URL beginning with a dash"
"$real_git" -C "$co" config remote.origin.url '-evil'
o="$(newdir)"
post "$dr/draft.md" "$o"
stop_is unreadable
assert_eq "$desc (no gh call)" 0 "$(calls "$glog")"
"$real_git" -C "$co" config remote.origin.url "$ourl"

desc="stop: project.yml names another repository"
setyml "$tmp/mismatch.yml"
o="$(newdir)"
post "$dr/draft.md" "$o"
stop_is repo-mismatch

for y in badbl1 badbl2; do
  desc="stop: bad backlog ($y)"
  setyml "$tmp/$y.yml"
  o="$(newdir)"
  post "$dr/draft.md" "$o"
  stop_is bad-backlog
done

desc="stop: a base beginning with a dash"
setyml "$tmp/badbase.yml"
o="$(newdir)"
post "$dr/draft.md" "$o"
stop_is bad-base

desc="stop: a base branch that is missing on the origin"
setyml "$tmp/nobranch.yml"
o="$(newdir)"
post "$dr/draft.md" "$o"
stop_is unreadable
setyml "$tmp/map.yml"

SHA="$("$real_git" -C "$origin" rev-parse HEAD)"
desc="stop: a commit that is not on the base"
o="$(newdir)"
run post 661 "$SIDE" "$dr/draft.md" "$o"
stop_is bad-sha
assert_eq "$desc (out-dir empty)" "" "$(ls -A "$o")"

desc="stop: a well-formed sha that does not exist"
o="$(newdir)"
run post 661 "$GONE" "$dr/draft.md" "$o"
stop_is bad-sha

desc="stop: a draft with a missing section"
d2="$(newdir)"
printf 'A title.\n\n### Goal\nonly this\n' >"$d2/draft.md"
o="$(newdir)"
post "$d2/draft.md" "$o"
stop_is bad-shape

desc="stop: a draft with a line beginning with the marker prefix"
mkdraft "$d2/draft.md" 'spec-task: issue=1 base=main sha=x'
o="$(newdir)"
post "$d2/draft.md" "$o"
stop_is has-marker
assert_eq "$desc (out-dir empty)" "" "$(ls -A "$o")"

tok='abcdefghijklmnopqrstuvwxyz0123'
for extra in \
  'C:/x' \
  'see C:/Users/x and more' \
  'path D:\work\y' \
  'at /Users/someone/file' \
  'at /home/someone/file' \
  'in AppData' \
  'ghp_'"$tok" \
  'gho_'"$tok" \
  'ghu_'"$tok" \
  'ghs_'"$tok" \
  'ghr_'"$tok" \
  'github_pat_'"$tok" \
  '-----BEGIN PRIVATE KEY-----'; do
  desc="stop: leak shape [$extra]"
  mkdraft "$d2/draft.md" "$extra"
  o="$(newdir)"
  post "$d2/draft.md" "$o"
  stop_is leak
  assert_eq "$desc (out-dir empty)" "" "$(ls -A "$o")"
done

desc="no stop: a URL and a short token are not a leak"
mkdraft "$d2/draft.md" 'See https://github.com/o/r/issues/1 and ghp_short, and e.g. a:b.'
o="$(newdir)"
post "$d2/draft.md" "$o"
assert_eq "$desc (posted)" posted "$(printf '%s' "$out" | cut -d' ' -f1)"

desc="stop: a body over 65536 bytes"
{
  "$real_cat" "$dr/draft.md"
  i=0
  while [ "$i" -lt 1100 ]; do
    printf '%s\n' 'padding padding padding padding padding padding padding padding'
    i=$((i + 1))
  done
} >"$d2/draft.md"
o="$(newdir)"
post "$d2/draft.md" "$o"
stop_is too-long

desc="stop: a failed issue fetch"
o="$(newdir)"
FX_ISSUE_FAIL=1 post "$dr/draft.md" "$o"
stop_is unreachable

desc="stop: an issue response that is not JSON"
printf '%s this is not json {\n' "$MARK" >"$tmp/bad.json"
o="$(newdir)"
FX_ISSUE="$tmp/bad.json" post "$dr/draft.md" "$o"
stop_is unreadable

desc="stop: a pull request"
mkissue maint 100 '"OWNER"' open false pr
o="$(newdir)"
post "$dr/draft.md" "$o"
stop_is not-an-issue

desc="stop: a closed issue"
mkissue maint 100 '"OWNER"' closed false
o="$(newdir)"
post "$dr/draft.md" "$o"
stop_is closed

desc="stop: a locked issue"
mkissue maint 100 '"OWNER"' open true
o="$(newdir)"
post "$dr/draft.md" "$o"
stop_is locked

desc="stop: the loop identity"
setyml "$tmp/loopmap.yml"
mkissue 'loop[bot]' 400 '"MEMBER"'
o="$(newdir)"
post "$dr/draft.md" "$o"
stop_is loop-identity
setyml "$tmp/map.yml"

for who in 'stranger 9' 'loop[bot] 400'; do
  set -- $who
  desc="stop: an untrusted author under a map ($1)"
  mkissue "$1" "$2" '"MEMBER"'
  o="$(newdir)"
  post "$dr/draft.md" "$o"
  stop_is untrusted
done
for who in 'dev[bot] 200' 'rev[bot] 300'; do
  set -- $who
  desc="stop: an App-filed issue with no reaction is unreacted under a map ($1; was untrusted before WB-D32)"
  mkissue "$1" "$2" '"MEMBER"'
  o="$(newdir)"
  post "$dr/draft.md" "$o"
  stop_is unreacted
done

desc="stop: gh-identity.sh cannot judge the config"
setyml "$tmp/dup.yml"
o="$(newdir)"
post "$dr/draft.md" "$o"
stop_is untrusted
setyml "$tmp/map.yml"

desc="legacy: a COLLABORATOR author is trusted (and the comment is then held)"
setyml "$tmp/legacy.yml"
mkissue someone 7 '"COLLABORATOR"'
o="$(newdir)"
post "$dr/draft.md" "$o"
held_is no-identities "$o"
desc="legacy: a CONTRIBUTOR author is untrusted"
mkissue someone 7 '"CONTRIBUTOR"'
o="$(newdir)"
post "$dr/draft.md" "$o"
stop_is untrusted
setyml "$tmp/map.yml"

desc="stop: a failing POST is made exactly once and never retried"
o="$(newdir)"
FX_POST_FAIL=1 post "$dr/draft.md" "$o"
assert_eq "$desc (word)" post-unknown "$out"
assert_eq "$desc (rc)" 1 "$rc"
assert_eq "$desc (stderr)" "" "$err"
assert_eq "$desc (one POST)" 1 "$(writes)"
assert_eq "$desc (comment kept)" comment.md "$(ls -A "$o")"

# -- the response: the comment exists but this run cannot vouch for it ---------------------------
desc="posted-unreadable: a malformed response"
printf '%s not json {\n' "$MARK" >"$tmp/resp.json"
o="$(newdir)"
FX_RESP="$tmp/resp.json" post "$dr/draft.md" "$o"
assert_eq "$desc (word)" posted-unreadable "$out"
assert_eq "$desc (rc)" 1 "$rc"
assert_eq "$desc (one POST)" 1 "$(writes)"

desc="posted-unreadable: an issue_url naming another issue"
mkresp 777 'dev[bot]' 200 662
o="$(newdir)"
post "$dr/draft.md" "$o"
assert_eq "$desc (word)" posted-unreadable "$out"
assert_eq "$desc (one POST)" 1 "$(writes)"

desc="posted-unreadable: a response author other than the actor"
mkresp 777 'maint' 100 661
o="$(newdir)"
post "$dr/draft.md" "$o"
assert_eq "$desc (word)" posted-unreadable "$out"
assert_eq "$desc (one POST)" 1 "$(writes)"

desc="posted-unreadable: a string comment id"
printf '{"id":"777","user":{"login":"dev[bot]","id":200},"issue_url":"https://api.github.com/repos/acme/backlog/issues/661","html_url":"https://github.com/acme/backlog/issues/661#issuecomment-777"}\n' >"$tmp/resp.json"
o="$(newdir)"
FX_RESP="$tmp/resp.json" post "$dr/draft.md" "$o"
assert_eq "$desc (word)" posted-unreadable "$out"

desc="posted-unreadable: an html_url naming another comment"
printf '{"id":777,"user":{"login":"dev[bot]","id":200},"issue_url":"https://api.github.com/repos/acme/backlog/issues/661","html_url":"https://github.com/acme/backlog/issues/661#issuecomment-778"}\n' >"$tmp/resp.json"
o="$(newdir)"
FX_RESP="$tmp/resp.json" post "$dr/draft.md" "$o"
assert_eq "$desc (word)" posted-unreadable "$out"

desc="the repo part of the response URLs is case-folded"
printf '{"id":777,"user":{"login":"dev[bot]","id":200},"issue_url":"https://api.github.com/repos/ACME/Backlog/issues/661","html_url":"https://github.com/ACME/Backlog/issues/661#issuecomment-777"}\n' >"$tmp/resp.json"
o="$(newdir)"
FX_RESP="$tmp/resp.json" post "$dr/draft.md" "$o"
assert_eq "$desc (posted)" posted "$(printf '%s' "$out" | cut -d' ' -f1)"

# -- it reads its own copy -----------------------------------------------------------------------
desc="the caller's draft swapped after the copy"
d3="$(newdir)"
mkdraft "$d3/draft.md"
{ printf 'spec-task: issue=661 base=main sha=%s\n\n' "$SHA"; "$real_cat" "$d3/draft.md"; } >"$expect"
o="$(newdir)"
FX_HOOK="$d3/draft.md" post "$d3/draft.md" "$o"
assert_eq "$desc (swap happened)" "swapped draft" "$("$real_cat" "$d3/draft.md")"
assert_eq "$desc (posted)" posted "$(printf '%s' "$out" | cut -d' ' -f1)"
assert_eq "$desc (stdin is the original)" yes "$(cmp -s "$expect" "$gstdin" && echo yes || echo no)"
assert_eq "$desc (comment.md is the original)" yes "$(cmp -s "$expect" "$o/comment.md" && echo yes || echo no)"

# -- usage: exit 2, nothing on stdout, no gh call ------------------------------------------------
o="$(newdir)"
desc="no arguments"
run
usage_is
desc="an unknown mode"
run write 661 "$SHA" "$dr/draft.md" "$o"
usage_is
desc="a leading-zero N"
run post 0661 "$SHA" "$dr/draft.md" "$o"
usage_is
desc="N that is not a number"
run post 6x "$SHA" "$dr/draft.md" "$o"
usage_is
desc="a short sha"
run post 661 "${SHA%?}" "$dr/draft.md" "$o"
usage_is
desc="an uppercase sha"
up="$(printf '%s' "$SHA" | tr 'a-f' 'A-F')"
case "$up" in *[A-F]*) run post 661 "$up" "$dr/draft.md" "$o"; usage_is ;; *) echo "SKIP - $desc: this sha has no letters" >&2 ;; esac
desc="a relative draft path"
RUNDIR="$dr" run post 661 "$SHA" draft.md "$o"
usage_is
desc="a missing draft"
run post 661 "$SHA" "$dr/none.md" "$o"
usage_is
desc="an empty draft"
: >"$dr/empty.md"
run post 661 "$SHA" "$dr/empty.md" "$o"
usage_is
desc="a draft that is a directory"
run post 661 "$SHA" "$dr" "$o"
usage_is
desc="a draft inside the work tree"
mkdir -p "$co/inside"
mkdraft "$co/inside/draft.md"
run post 661 "$SHA" "$co/inside/draft.md" "$o"
usage_is
desc="a relative out-dir"
mkdir -p "$scratch/rel"
RUNDIR="$scratch" run post 661 "$SHA" "$dr/draft.md" rel
usage_is
desc="a missing out-dir"
run post 661 "$SHA" "$dr/draft.md" "$scratch/does-not-exist"
usage_is
desc="a non-empty out-dir"
o2="$(newdir)"
: >"$o2/file"
run post 661 "$SHA" "$dr/draft.md" "$o2"
usage_is
desc="an out-dir inside the work tree"
mkdir -p "$co/inside-out"
run post 661 "$SHA" "$dr/draft.md" "$co/inside-out"
usage_is
desc="git rev-parse fails"
RUNDIR="$tmp/nogit" run post 661 "$SHA" "$dr/draft.md" "$o"
usage_is
desc="a slash-less \$0"
SCRIPT=spec-post.sh RUNDIR="$bindir" run post 661 "$SHA" "$dr/draft.md" "$o"
usage_is
desc="a copy of the script with no siblings"
mkdir -p "$tmp/lone"
cp "$script" "$tmp/lone/spec-post.sh"
SCRIPT="$tmp/lone/spec-post.sh" run post 661 "$SHA" "$dr/draft.md" "$o"
usage_is
desc="a copy of the script with gh-identity.sh but no spec-shape.sh"
mkdir -p "$tmp/half"
cp "$script" "$tmp/half/spec-post.sh"
cp "$bindir/gh-identity.sh" "$tmp/half/gh-identity.sh"
SCRIPT="$tmp/half/spec-post.sh" run post 661 "$SHA" "$dr/draft.md" "$o"
usage_is

desc="a copy of the script with gh-identity.sh and spec-shape.sh but no spec-reaction.sh"
mkdir -p "$tmp/half2"
cp "$script" "$tmp/half2/spec-post.sh"
cp "$bindir/gh-identity.sh" "$bindir/spec-shape.sh" "$tmp/half2/"
SCRIPT="$tmp/half2/spec-post.sh" run post 661 "$SHA" "$dr/draft.md" "$o"
usage_is

if [ "$can_link" = yes ]; then
  desc="a symlinked draft"
  ln -s "$dr/draft.md" "$dr/link.md"
  run post 661 "$SHA" "$dr/link.md" "$o"
  usage_is
  desc="a symlinked out-dir"
  ln -s "$o" "$tmp/outlink"
  run post 661 "$SHA" "$dr/draft.md" "$tmp/outlink"
  usage_is
else
  echo "SKIP - symlink cases: ln -s copies here" >&2
fi

# -- the App-filed path (WB-D32, #664): an agent-filed issue passes once a maintainer reacted ----
# The issue is last updated at 20:10:28; the good reaction is a maintainer's, at 20:10:39.
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
RXF="$tmp/rx.tsv"
RX_GOOD='100 +1 2026-10-17T20:10:39Z'
setyml "$tmp/map.yml"
mkrx "$RXF" "$RX_GOOD"
dr2="$(newdir)"
mkdraft "$dr2/draft.md"
expect2="$tmp/expect2.md"
{ printf 'spec-task: issue=661 base=main sha=%s\n\n' "$SHA"; "$real_cat" "$dr2/draft.md"; } >"$expect2"

desc="reacted pass: the dev App's issue is posted, one write, the reactions read before the second issue read"
mkissue 'dev[bot]' 200 '"CONTRIBUTOR"'
mkissue2 'dev[bot]' 200 '"NONE"' open false - 2026-10-17T20:10:28Z '"second title"' '"second body"'
o="$(newdir)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" post "$dr2/draft.md" "$o"
assert_eq "$desc (line)" "posted 777 dev[bot] https://github.com/acme/backlog/issues/661#issuecomment-777" "$out"
assert_eq "$desc (rc)" 0 "$rc"
assert_eq "$desc (stderr)" "" "$err"
assert_eq "$desc (exactly one POST)" 1 "$(writes)"
assert_eq "$desc (stdin is marker, blank line, draft bytes)" yes "$(cmp -s "$expect2" "$gstdin" && echo yes || echo no)"
assert_eq "$desc (gh log)" "repo|view|$ourl|--json|nameWithOwner|--jq|.nameWithOwner|
repo|view|$ourl|--json|defaultBranchRef|--jq|.defaultBranchRef.name // \"\"|
api|--hostname|github.com|repos/acme/backlog/issues/661|
api|--hostname|github.com|repos/acme/backlog/issues/661/reactions|--paginate|--jq|.[] | [(.user.id|tostring), .content, .created_at] | @tsv|
api|--hostname|github.com|repos/acme/backlog/issues/661|
api|--hostname|github.com|graphql|-f|query={ viewer { login databaseId } }|--jq|[.data.viewer.login, .data.viewer.databaseId] | @tsv|
api|--hostname|github.com|--method|POST|repos/acme/backlog/issues/661/comments|-F|body=@-|" "$("$real_cat" "$glog")"

for c in '+1' heart hooray rocket; do
  desc="reacted pass: the reviewer App's issue, a maintainer's $c (held for a non-App viewer)"
  mkissue 'rev[bot]' 300 '"NONE"'
  mkrx "$RXF" "100 $c 2026-10-17T20:10:39Z"
  o="$(newdir)"
  FX_RX="$RXF" FX_VLOGIN=maint FX_VID=100 post "$dr2/draft.md" "$o"
  held_is not-dev-app "$o"
done
mkrx "$RXF" "$RX_GOOD"

desc="reacted pass: a CRLF body"
mkissue 'dev[bot]' 200 '"NONE"' open false - 2026-10-17T20:10:28Z '"t"' '"line one\r\nline two\r\n"'
o="$(newdir)"
FX_RX="$RXF" post "$dr2/draft.md" "$o"
assert_eq "$desc (line)" "posted 777 dev[bot] https://github.com/acme/backlog/issues/661#issuecomment-777" "$out"

desc="reacted pass: a null body"
mkissue 'dev[bot]' 200 '"NONE"' open false - 2026-10-17T20:10:28Z '"t"' null
o="$(newdir)"
FX_RX="$RXF" post "$dr2/draft.md" "$o"
assert_eq "$desc (line)" "posted 777 dev[bot] https://github.com/acme/backlog/issues/661#issuecomment-777" "$out"

noout() { assert_eq "$desc (out-dir empty)" "" "$(ls -A "$o")"; }

# unreacted
mkissue 'dev[bot]' 200 '"NONE"'
desc="unreacted: no reaction at all"
mkrx "$RXF"
o="$(newdir)"
FX_RX="$RXF" post "$dr2/draft.md" "$o"
stop_is unreacted
noout

desc="unreacted: only non-maintainers reacted (either App's own +1 included)"
mkrx "$RXF" "200 +1 2026-10-17T20:10:39Z" "300 +1 2026-10-17T20:10:39Z" "9 +1 2026-10-17T20:10:39Z"
mkissue 'dev[bot]' 200 '"NONE"'
o="$(newdir)"
FX_RX="$RXF" post "$dr2/draft.md" "$o"
stop_is unreacted

for c in '-1' eyes laugh confused; do
  desc="unreacted: a maintainer's $c does not approve"
  mkrx "$RXF" "100 $c 2026-10-17T20:10:39Z"
  mkissue 'dev[bot]' 200 '"NONE"'
  o="$(newdir)"
  FX_RX="$RXF" post "$dr2/draft.md" "$o"
  stop_is unreacted
done

desc="unreacted: an approving reaction at the issue's updated_at"
mkrx "$RXF" "100 +1 2026-10-17T20:10:28Z"
mkissue 'dev[bot]' 200 '"NONE"'
o="$(newdir)"
FX_RX="$RXF" post "$dr2/draft.md" "$o"
stop_is unreacted

desc="unreacted: an approving reaction before the issue's updated_at"
mkrx "$RXF" "100 +1 2026-10-17T20:10:27Z"
mkissue 'dev[bot]' 200 '"NONE"'
o="$(newdir)"
FX_RX="$RXF" post "$dr2/draft.md" "$o"
stop_is unreacted

desc="unreacted: the second copy's updated_at moved past the reaction"
mkrx "$RXF" "$RX_GOOD"
mkissue2 'dev[bot]' 200 '"NONE"' open false - 2026-10-17T20:10:46Z
mkissue 'dev[bot]' 200 '"NONE"'
o="$(newdir)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" post "$dr2/draft.md" "$o"
stop_is unreacted

# failed reads stop unreachable, never unreacted
mkissue 'dev[bot]' 200 '"NONE"'
mkrx "$RXF" "$RX_GOOD"
desc="a failed reactions read is unreachable, not unreacted"
o="$(newdir)"
FX_RX="$RXF" FX_RX_FAIL=1 post "$dr2/draft.md" "$o"
stop_is unreachable

desc="a failed second issue read is unreachable, not unreacted"
mkissue 'dev[bot]' 200 '"NONE"'
o="$(newdir)"
FX_RX="$RXF" FX_ISSUE2_FAIL=1 post "$dr2/draft.md" "$o"
stop_is unreachable

# the second copy is the one judged for closed and locked
desc="a second copy that is closed stops closed"
mkissue2 'dev[bot]' 200 '"NONE"' closed false
mkissue 'dev[bot]' 200 '"NONE"'
o="$(newdir)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" post "$dr2/draft.md" "$o"
stop_is closed

desc="a second copy that is locked stops locked"
mkissue2 'dev[bot]' 200 '"NONE"' open true
mkissue 'dev[bot]' 200 '"NONE"'
o="$(newdir)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" post "$dr2/draft.md" "$o"
stop_is locked

desc="a second copy that is a pull request is not-an-issue"
mkissue2 'dev[bot]' 200 '"NONE"' open false pr
mkissue 'dev[bot]' 200 '"NONE"'
o="$(newdir)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" post "$dr2/draft.md" "$o"
stop_is not-an-issue

# the second copy's shape and identity
for v in \
  "another login|'rev[bot]' 300 '\"NONE\"'" \
  "the maintainer as author|maint 100 '\"OWNER\"'" \
  "the same login with another id|'dev[bot]' 201 '\"NONE\"'" \
  "a malformed updated_at|'dev[bot]' 200 '\"NONE\"' open false - '2026-10-17 20:10:28'" \
  "an updated_at with a zone offset|'dev[bot]' 200 '\"NONE\"' open false - '2026-10-17T20:10:28+00:00'" \
  "a non-string title|'dev[bot]' 200 '\"NONE\"' open false - 2026-10-17T20:10:28Z 5" \
  "a null title|'dev[bot]' 200 '\"NONE\"' open false - 2026-10-17T20:10:28Z null" \
  "a numeric body|'dev[bot]' 200 '\"NONE\"' open false - 2026-10-17T20:10:28Z '\"t\"' 5" \
  "an object body|'dev[bot]' 200 '\"NONE\"' open false - 2026-10-17T20:10:28Z '\"t\"' '{}'"; do
  desc="second copy with ${v%%|*} is unreadable"
  eval "mkissue2 ${v#*|}"
  mkissue 'dev[bot]' 200 '"NONE"'
  o="$(newdir)"
  FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" post "$dr2/draft.md" "$o"
  stop_is unreadable
done

desc="second copy that is not JSON is unreadable"
printf '%s not json {\n' "$MARK" >"$tmp/issue2.json"
mkissue 'dev[bot]' 200 '"NONE"'
o="$(newdir)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" post "$dr2/draft.md" "$o"
stop_is unreadable

for y in mapnomaint mapemptymaint mapbadmaint; do
  desc="a maintainer list that is not well formed ($y) is unreadable"
  setyml "$tmp/$y.yml"
  mkissue 'dev[bot]' 200 '"NONE"'
  o="$(newdir)"
  FX_RX="$RXF" post "$dr2/draft.md" "$o"
  stop_is unreadable
done
setyml "$tmp/map.yml"

# hidden
mkrx "$RXF" "$RX_GOOD"
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
  "a tag character in the title|\"a\\udb40\\udc41b\"|\"b\""; do
  label="${v%%|*}"
  rest="${v#*|}"
  ttl="${rest%%|*}"
  bdy="${rest#*|}"
  desc="hidden: $label"
  mkissue 'dev[bot]' 200 '"NONE"' open false - 2026-10-17T20:10:28Z "$ttl" "$bdy"
  o="$(newdir)"
  FX_RX="$RXF" post "$dr2/draft.md" "$o"
  stop_is hidden
  noout
done

desc="hidden: the screen runs on the second copy, not the first"
mkissue 'dev[bot]' 200 '"NONE"'
mkissue2 'dev[bot]' 200 '"NONE"' open false - 2026-10-17T20:10:28Z '"t"' '"a\u200bb"'
o="$(newdir)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" post "$dr2/draft.md" "$o"
stop_is hidden

# who is still refused, with a good reaction on file
mkissue 'loop[bot]' 400 '"NONE"'
desc="the loop App stays untrusted, and no reaction is read for it"
o="$(newdir)"
FX_RX="$RXF" post "$dr2/draft.md" "$o"
stop_is untrusted
assert_eq "$desc (no reactions read)" 0 "$(grep -c reactions "$glog" || true)"
mkissue stranger 9 '"NONE"'
desc="an undeclared author stays untrusted, and no reaction is read for it"
o="$(newdir)"
FX_RX="$RXF" post "$dr2/draft.md" "$o"
stop_is untrusted
assert_eq "$desc (no reactions read)" 0 "$(grep -c reactions "$glog" || true)"

desc="the loop's login stops loop-identity before the author is judged, with a reaction on file"
mk devloop "repo: acme/repo
pr_base: main
backlog:
  repo: acme/backlog
orchestration:
  loop_identity: \"dev[bot]\"
$MAP"
setyml "$tmp/devloop.yml"
mkissue 'dev[bot]' 200 '"NONE"'
o="$(newdir)"
FX_RX="$RXF" post "$dr2/draft.md" "$o"
stop_is loop-identity
assert_eq "$desc (no reactions read)" 0 "$(grep -c reactions "$glog" || true)"
setyml "$tmp/map.yml"

desc="a maintainer's issue passes as trusted with a reaction file present, and none is read"
mkissue maint 100 '"OWNER"'
o="$(newdir)"
FX_RX="$RXF" post "$dr2/draft.md" "$o"
assert_eq "$desc (line)" "posted 777 dev[bot] https://github.com/acme/backlog/issues/661#issuecomment-777" "$out"
assert_eq "$desc (no reactions read)" 0 "$(grep -c reactions "$glog" || true)"

desc="under identities null no reaction is read"
setyml "$tmp/legacy.yml"
mkissue someone 7 '"COLLABORATOR"'
o="$(newdir)"
FX_RX="$RXF" post "$dr2/draft.md" "$o"
assert_eq "$desc (no reactions read)" 0 "$(grep -c reactions "$glog" || true)"
setyml "$tmp/map.yml"

desc="app_check is spec-issue.sh's function, byte for byte"
fnbody() { awk '/^app_check\(\) \{/ { on = 1 } on { print } on && /^}/ { exit }' "$1"; }
assert_eq "$desc" "$(fnbody "$bindir/spec-issue.sh")" "$(fnbody "$script")"
assert_eq "$desc (found)" yes "$([ -n "$(fnbody "$script")" ] && echo yes || echo no)"

desc="HID is spec-fresh.sh's line, byte for byte"
assert_eq "$desc" "$(grep '^HID=' "$bindir/spec-fresh.sh")" "$(grep '^HID=' "$script")"
assert_eq "$desc (one line)" 1 "$(grep -c '^HID=' "$script")"
mkissue maint 100 '"OWNER"'

# -- a declared App's id on the maintainer list (#759): every such config stops `unreadable` ----
# for a maintainer author and an App author alike, before the issue's reactions are read, so no
# comment.md is kept and nothing is posted.
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
unread_is() { # unread_is <cfg> <login> <id> <assoc> [rx-file] [body-json] -- stops unreadable, nothing read or written
  setyml "$tmp/$1.yml"
  mkissue "$2" "$3" "$4" open false - 2026-10-17T20:10:28Z '"title"' "${6:-\"body\"}"
  mkissue2 "$2" "$3" "$4" open false - 2026-10-17T20:10:28Z '"title"' "${6:-\"body\"}"
  o="$(newdir)"
  FX_RX="${5:-$RXF}" FX_ISSUE2="$tmp/issue2.json" post "$dr2/draft.md" "$o"
  stop_is unreadable
  noout
  assert_eq "$desc (no reactions read)" 0 "$(grep -c reactions "$glog" || true)"
}
mkrx "$RXF" "$RX_GOOD"
for k in dev rev loop; do
  case "$k" in
    dev) kentry='{ login: "dev[bot]", id: 200 }'; other_l='rev[bot]'; other_i=300 ;;
    rev) kentry='{ login: "rev[bot]", id: 300 }'; other_l='dev[bot]'; other_i=200 ;;
    loop) kentry='{ login: "loop[bot]", id: 400 }'; other_l='dev[bot]'; other_i=200 ;;
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

desc="exploit: the reviewer App's own +1 on a dev-App issue, its id on the maintainer list"
mkrx "$tmp/rx_rev.tsv" '300 +1 2026-10-17T20:10:39Z'
unread_is coll_rev 'dev[bot]' 200 '"NONE"' "$tmp/rx_rev.tsv"

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

desc="a maintainer's issue under mapbadmaint"
cp "$tmp/mapbadmaint.yml" "$tmp/badmaint_copy.yml"
unread_is badmaint_copy maint 100 '"OWNER"'

# no check for a null or missing App key; the pass depends on the viewer
pass_is() { # pass_is <cfg> <login> <id> <posted|held> -- a held pass is the reviewer App's issue, viewer maint
  setyml "$tmp/$1.yml"
  mkissue "$2" "$3" '"NONE"' open false - 2026-10-17T20:10:28Z '"title"' '"body"'
  mkissue2 "$2" "$3" '"NONE"' open false - 2026-10-17T20:10:28Z '"title"' '"body"'
  mkrx "$RXF" "$RX_GOOD"
  o="$(newdir)"
  if [ "$4" = posted ]; then
    FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" post "$dr2/draft.md" "$o"
    assert_eq "$desc (line)" "posted 777 dev[bot] https://github.com/acme/backlog/issues/661#issuecomment-777" "$out"
  else
    FX_VLOGIN=maint FX_VID=100 FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" post "$dr2/draft.md" "$o"
    held_is not-dev-app "$o"
  fi
  assert_eq "$desc (reactions read)" 1 "$(grep -c reactions "$glog" || true)"
}
mkcfg nul_rl - "$DEVV" null null
desc="reviewer_app and loop_app null, a dev-App issue"
pass_is nul_rl 'dev[bot]' 200 posted
mkcfg mis_rl - "$DEVV" - -
desc="reviewer_app and loop_app missing, a dev-App issue"
pass_is mis_rl 'dev[bot]' 200 posted
mkcfg nul_d - null "$REVV" "$LOOPV"
desc="dev_app null, a reviewer-App issue"
pass_is nul_d 'rev[bot]' 300 held
mkcfg mis_d - - "$REVV" "$LOOPV"
desc="dev_app missing, a reviewer-App issue"
pass_is mis_d 'rev[bot]' 300 held
desc="a reviewer-App issue under a well-formed map"
pass_is map 'rev[bot]' 300 held
setyml "$tmp/map.yml"
mkissue maint 100 '"OWNER"'

# -- every write is the one POST --------------------------------------------------------------------
desc="a missing yq"
if [ "$can_link" = yes ]; then
  lb="$tmp/linkbin"
  mkdir -p "$lb"
  for t in git gh tr sed mktemp cp mv rm dirname uname ls cat grep wc cut; do
    if [ "$t" = gh ] || [ "$t" = git ]; then p="$fakebin/$t"; else p="$(command -v "$t")"; fi
    ln -s "$p" "$lb/$t"
  done
  o="$(newdir)"
  XPATH="$lb" post "$dr/draft.md" "$o"
  stop_is unreadable
else
  echo "SKIP - $desc: ln -s copies here" >&2
fi

exit "$fail"
