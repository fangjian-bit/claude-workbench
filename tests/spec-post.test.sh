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
  *lastEditedAt*)
    # the content-time query (#890): FX_CT is the response; by default a never-edited issue created at the
    # served copy's updated_at, so its content time is that updated_at
    [ -z "${FX_CT_FAIL:-}" ] || fail_with
    if [ -n "${FX_CT:-}" ]; then "$FX_CAT" "$FX_CT"; exit 0; fi
    src="$FX_ISSUE"
    [ -z "${FX_ISSUE2:-}" ] || src="$FX_ISSUE2"
    u="$(sed -n 's/.*"updated_at":"\([^"]*\)".*/\1/p' "$src")"
    printf '{"data":{"repository":{"issue":{"createdAt":"%s","updatedAt":"%s","lastEditedAt":null,"timelineItems":{"nodes":[]}}}}}\n' "$u" "$u"
    ;;
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

# _mk <file> <critic-line> <extra> <later> <findings> -- the shared layout of mkdraft and mkesc
_mk() {
  {
    printf '%s\n' 'Spec for the thing. Drafted against main at abc1234. Back\slash and {pr_base} braces.'
    printf '%s\n' "$2"
    printf '\n### Goal\n'
    [ -z "$3" ] || printf '%s\n' "$3"
    printf '%s\n' 'Goal text with back\slash, {pr_base} and ${HOME} left alone.'
    printf '\n### Files touched\nOne file.\n'
    printf '\n### Done when\nIt runs.\n'
    printf '\n### Tests\nA test.\n'
    [ -z "$4" ] || printf '%s\n' "$4"
    printf '\n### Out of scope\nNothing else.\n'
    printf '\n### Restated from the issue body\nnothing\n'
    [ -z "$5" ] || printf '\n### Open findings\n%s\n' "$5"
  } >"$1"
}
CL_OK='Critic gate: architect, security-critic; 3 rounds; converged.'
CL_ESC='Critic gate: architect, security-critic; 5 rounds; cap reached.'
mkdraft() { # mkdraft <file> [extra-line] [later-line] -- a draft in the fixed shape; the extra line sits in Goal, the later line ends Tests
  _mk "$1" "$CL_OK" "${2:-}" "${3:-}" ''
}
mkesc() { # mkesc <file> [extra-line] [later-line] -- the same layout, a cap-reached critic line and an Open findings section
  _mk "$1" "$CL_ESC" "${2:-}" "${3:-}" 'A finding (architect, high): the task is too large. Recommend a split.'
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
  FX_RX= FX_RX_FAIL= FX_ISSUE2= FX_ISSUE2_FAIL= FX_CT= FX_CT_FAIL=
  FX_LABELS="$tmp/labels.txt" FX_LBLR_FAIL= FX_LBLW_FAIL=
  export FX_LABELS FX_LBLR_FAIL FX_LBLW_FAIL
  export FX_NWO FX_DEF FX_ISSUE FX_RESP FX_VLOGIN FX_VID FX_VIEW_FAIL FX_ISSUE_FAIL FX_VIEWER_FAIL FX_POST_FAIL FX_HOOK
  export FX_RX FX_RX_FAIL FX_ISSUE2 FX_ISSUE2_FAIL FX_CT FX_CT_FAIL
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
writes() { # every gh call that is not a known read (repo view, the issue GET, its reactions GET, the exact viewer query, the exact content-time query)
  grep -vxF -e "$CTLINE" "$glog" | grep -vc -e '^repo|view|' -e '^api|--hostname|github.com|repos/[^|]*/issues/[0-9]*|$' -e '^api|--hostname|github.com|repos/[^|]*/issues/[0-9]*/reactions|--paginate|--jq|' -e '^api|--hostname|github.com|graphql|-f|query={ viewer { login databaseId } }|--jq|' -e '^api|--hostname|github.com|repos/[^|]*/labels?per_page=100|--paginate|--jq|.\[\].name|' || true
}
# the content-time query text, read back from the script, and the argv line the stub logs for it
CTQ="$(sed -n "s/^  gh api --hostname github.com graphql -f query='\(.*\)' -f owner=.*/\1/p" "$script")"
assert_eq "the script carries one content-time query line" yes "$([ -n "$CTQ" ] && [ "$(printf '%s\n' "$CTQ" | wc -l)" -eq 1 ] && echo yes || echo no)"
CTLINE="api|--hostname|github.com|graphql|-f|query=$CTQ|-f|owner=acme|-f|name=backlog|-F|number=661|"
# the same text in spec-issue.sh: the two scripts query the content time identically
ISSUE_CTQ="$(sed -n "s/^  gh api graphql -f query='\(.*\)' -f owner=.*/\1/p" "$bindir/spec-issue.sh")"
assert_eq "the content-time query text is equal in spec-issue.sh and spec-post.sh" "$CTQ" "$ISSUE_CTQ"
# the content-time block (#890, WB-D32) is carried in both scripts' agent_path: held equal, but for the one --hostname on the query line
ctblock() { # ctblock <script> -- from the "# 3b." line through the i_updated line, inclusive, with --hostname github.com dropped from the query line
  awk '/# 3b\. the content time/ { on = 1 } on { print } on && $0 == "  i_updated=\"$ct_time\"" { exit }' "$1" |
    sed 's/^  gh api --hostname github\.com graphql /  gh api graphql /'
}
CTB_POST="$(ctblock "$script")"
CTB_ISSUE="$(ctblock "$bindir/spec-issue.sh")"
for _s in "$script" "$bindir/spec-issue.sh"; do
  _b="$(ctblock "$_s")"
  assert_eq "$(basename "$_s") carries exactly one # 3b. content-time line" 1 "$(grep -c '# 3b\. the content time' "$_s" || true)"
  assert_eq "$(basename "$_s") content-time block (found) starts at the # 3b. line" yes "$(printf '%s\n' "$_b" | head -n 1 | grep -q '^  # 3b\. the content time' && echo yes || echo no)"
  assert_eq "$(basename "$_s") content-time block (found) ends at the i_updated line" '  i_updated="$ct_time"' "$(printf '%s\n' "$_b" | tail -n 1)"
done
assert_eq "the content-time block is equal in spec-issue.sh and spec-post.sh" "$CTB_POST" "$CTB_ISSUE"
# self-check: one character changed inside ct_ts() of a copy makes the comparison differ
sed '/# 3b\. the content time/,/i_updated="\$ct_time"/ s/\]Z) : ;;/]z) : ;;/' "$script" >"$tmp/post-mutated.sh"
assert_eq "the mutation reached the copy" yes "$(cmp -s "$script" "$tmp/post-mutated.sh" && echo no || echo yes)"
assert_eq "a changed character inside ct_ts() is caught by the comparison" differ "$([ "$(ctblock "$tmp/post-mutated.sh")" = "$CTB_ISSUE" ] && echo equal || echo differ)"
# mkct <created> <updated> <lastEditedAt-json> [rename-createdAt ...] -- the query's response, to $tmp/ct.json
mkct() {
  _c="$1"; _u="$2"; _e="$3"; shift 3
  _nodes=
  for _n in "$@"; do _nodes="${_nodes:+$_nodes,}{\"createdAt\":\"$_n\"}"; done
  printf '{"data":{"repository":{"issue":{"createdAt":"%s","updatedAt":"%s","lastEditedAt":%s,"timelineItems":{"nodes":[%s]}}}}}\n' \
    "$_c" "$_u" "$_e" "$_nodes" >"$tmp/ct.json"
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
# A copy of spec-post.sh beside the real gh-identity.sh and spec-reaction.sh and a spec-shape.sh
# that always says ok: the real spec-shape.sh now refuses a marker line first (#831), so the
# cases that pin spec-post.sh's own has-marker check run against this copy.
stubshape="$tmp/stubshape"
mkdir -p "$stubshape"
cp "$script" "$stubshape/spec-post.sh"
cp "$bindir/gh-identity.sh" "$bindir/spec-reaction.sh" "$bindir/declared-ids.sh" "$stubshape/"
printf '#!/bin/sh\necho ok\n' >"$stubshape/spec-shape.sh"
chmod +x "$stubshape/spec-shape.sh"
# post <draft> <out-dir> -- the usual call
post() { run post 661 "$SHA" "$1" "$2"; }
esc() { run escalate 661 "$SHA" "$1" "$2"; }

stop_is() { # stop_is <stop-line> -- the full stop line (one word, or `leak <line> <shape>`), exit 1, nothing on stderr, no write, no label call
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
dre="$(newdir)"
mkesc "$dre/draft.md"
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
{ printf 'spec-task-escalated: issue=661 base=main sha=%s\n\n' "$SHA"; "$real_cat" "$dre/draft.md"; } >"$eexpect"
ehurl="https://github.com/acme/backlog/issues/661#issuecomment-777"

desc="escalate: pass under a map as the dev App"
o="$(newdir)"
esc "$dre/draft.md" "$o"
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
FX_LABELS="$tmp/labels.txt" esc "$dre/draft.md" "$o"
assert_eq "$desc (line)" "escalated 777 dev[bot] $ehurl label-absent" "$out"
assert_eq "$desc (rc)" 0 "$rc"
assert_eq "$desc (one label read)" 1 "$(lblcalls read)"
assert_eq "$desc (no label write)" 0 "$(lblcalls write)"
assert_eq "$desc (one write)" 1 "$(writes)"

desc="escalate: the label read fails"
o="$(newdir)"
FX_LBLR_FAIL=1 esc "$dre/draft.md" "$o"
assert_eq "$desc (line)" "escalated 777 dev[bot] $ehurl label-unreadable" "$out"
assert_eq "$desc (rc)" 0 "$rc"
assert_eq "$desc (one label read)" 1 "$(lblcalls read)"
assert_eq "$desc (no label write)" 0 "$(lblcalls write)"

desc="escalate: the label write fails, made once and never retried"
o="$(newdir)"
FX_LBLW_FAIL=1 esc "$dre/draft.md" "$o"
assert_eq "$desc (line)" "escalated 777 dev[bot] $ehurl label-failed" "$out"
assert_eq "$desc (rc)" 0 "$rc"
assert_eq "$desc (one label read)" 1 "$(lblcalls read)"
assert_eq "$desc (one label write)" 1 "$(lblcalls write)"

desc="escalate: post-unknown makes the comment POST and no label call"
o="$(newdir)"
FX_POST_FAIL=1 esc "$dre/draft.md" "$o"
assert_eq "$desc (word)" post-unknown "$out"
assert_eq "$desc (one write)" 1 "$(writes)"
assert_eq "$desc (no label call)" 0 "$(( $(lblcalls read) + $(lblcalls write) ))"
assert_eq "$desc (comment kept, escalated marker)" "spec-task-escalated: issue=661 base=main sha=$SHA" "$(head -n 1 "$o/comment.md")"

desc="escalate: posted-unreadable makes the comment POST and no label call"
mkresp 777 'maint' 100 661
o="$(newdir)"
esc "$dre/draft.md" "$o"
assert_eq "$desc (word)" posted-unreadable "$out"
assert_eq "$desc (one write)" 1 "$(writes)"
assert_eq "$desc (no label call)" 0 "$(( $(lblcalls read) + $(lblcalls write) ))"

desc="escalate hold: identities null"
setyml "$tmp/legacy.yml"
o="$(newdir)"
esc "$dre/draft.md" "$o"
held_is no-identities "$o" spec-task-escalated
setyml "$tmp/map.yml"

desc="escalate hold: the viewer is not the dev App"
o="$(newdir)"
FX_VLOGIN=maint FX_VID=100 esc "$dre/draft.md" "$o"
held_is not-dev-app "$o" spec-task-escalated

for m in post escalate; do
  for pre in 'spec-task: issue=1 base=main sha=x' 'spec-task-escalated: issue=1 base=main sha=x'; do
    desc="stop: has-marker in $m mode for a draft line '${pre%%:*}:'"
    d4="$(newdir)"
    if [ "$m" = escalate ]; then mkesc "$d4/draft.md" "$pre"; else mkdraft "$d4/draft.md" "$pre"; fi
    o="$(newdir)"
    SCRIPT="$stubshape/spec-post.sh" run "$m" 661 "$SHA" "$d4/draft.md" "$o"
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

# -- the critic line (#629) ----------------------------------------------------------------------
cl_case() { # cl_case <desc> <mode> <critic-line|-> [position: top|late] -- a draft with that line, expects no-critic-line
  desc="stop: no-critic-line, $1"
  dcl="$(newdir)"
  if [ "$3" = - ]; then
    _mk "$dcl/draft.md" 'A title line.' '' '' "$( [ "$2" = escalate ] && echo 'Finding.' || true )"
  elif [ "${4:-top}" = late ]; then
    _mk "$dcl/draft.md" 'A title line.' "$3" '' "$( [ "$2" = escalate ] && echo 'Finding.' || true )"
  else
    _mk "$dcl/draft.md" "$3" '' '' "$( [ "$2" = escalate ] && echo 'Finding.' || true )"
  fi
  o="$(newdir)"
  run "$2" 661 "$SHA" "$dcl/draft.md" "$o"
  stop_is no-critic-line
  assert_eq "$desc (out-dir empty)" "" "$(ls -A "$o")"
}
cl_case "post with no critic line" post -
cl_case "escalate with no critic line" escalate -
cl_case "a well-formed line after ### Goal" post 'Critic gate: architect; 2 rounds; converged.' late
cl_case "post with cap reached" post 'Critic gate: architect; 5 rounds; cap reached.'
cl_case "post with not converging" post 'Critic gate: architect; 2 rounds; not converging.'
cl_case "escalate with converged" escalate 'Critic gate: architect; 2 rounds; converged.'
cl_case "0 rounds" post 'Critic gate: architect; 0 rounds; converged.'
cl_case "1 rounds" post 'Critic gate: architect; 1 rounds; converged.'
cl_case "2 round" post 'Critic gate: architect; 2 round; converged.'
cl_case "a critic name starting with a dash" post 'Critic gate: -architect; 2 rounds; converged.'
cl_case "a missing final period" post 'Critic gate: architect; 2 rounds; converged'
cl_case "trailing text after the period" post 'Critic gate: architect; 2 rounds; converged. ok'
cl_case "an unknown stop word" post 'Critic gate: architect; 2 rounds; finished.'
cl_case "an empty critic list" post 'Critic gate: ; 2 rounds; converged.'

desc="stop: no-critic-line, two critic lines"
dcl="$(newdir)"
{ printf '%s\n%s\n' 'A title.' "$CL_OK"; printf '%s\n' "$CL_OK"; printf '\n### Goal\ng\n\n### Files touched\nf\n\n### Done when\nd\n\n### Tests\nt\n\n### Out of scope\no\n\n### Restated from the issue body\nr\n'; } >"$dcl/draft.md"
o="$(newdir)"
post "$dcl/draft.md" "$o"
stop_is no-critic-line

desc="stop: no-critic-line, escalate without an Open findings heading"
dcl="$(newdir)"
_mk "$dcl/draft.md" "$CL_ESC" '' '' ''
o="$(newdir)"
esc "$dcl/draft.md" "$o"
stop_is no-critic-line

desc="stop: no-critic-line, escalate with Open findings only before the restated section"
dcl="$(newdir)"
{ printf '%s\n%s\n' 'A title.' "$CL_ESC"; printf '\n### Open findings\nF.\n\n### Goal\ng\n\n### Files touched\nf\n\n### Done when\nd\n\n### Tests\nt\n\n### Out of scope\no\n\n### Restated from the issue body\nr\n'; } >"$dcl/draft.md"
o="$(newdir)"
esc "$dcl/draft.md" "$o"
stop_is no-critic-line

desc="stop: no-critic-line, escalate with an empty Open findings body"
dcl="$(newdir)"
_mk "$dcl/draft.md" "$CL_ESC" '' '' ''
printf '\n### Open findings\n\n   \n## Next\nx\n' >>"$dcl/draft.md"
o="$(newdir)"
esc "$dcl/draft.md" "$o"
stop_is no-critic-line

desc="stop: no-critic-line, post with an Open findings section"
dcl="$(newdir)"
_mk "$dcl/draft.md" "$CL_OK" '' '' 'A finding.'
o="$(newdir)"
post "$dcl/draft.md" "$o"
stop_is no-critic-line

desc="stop: no-critic-line, post with an Open findings heading before the restated section"
dcl="$(newdir)"
{ printf '%s\n%s\n' 'A title.' "$CL_OK"; printf '\n### Goal\ng\n\n## open Findings\nF.\n\n### Files touched\nf\n\n### Done when\nd\n\n### Tests\nt\n\n### Out of scope\no\n\n### Restated from the issue body\nr\n'; } >"$dcl/draft.md"
o="$(newdir)"
post "$dcl/draft.md" "$o"
stop_is no-critic-line

desc="order: a draft failing the shape and the critic line stops bad-shape"
dcl="$(newdir)"
printf 'A title.\n\n### Goal\nonly this\n' >"$dcl/draft.md"
o="$(newdir)"
post "$dcl/draft.md" "$o"
stop_is bad-shape

desc="order: no critic line and a marker line stops no-critic-line, not has-marker"
dcl="$(newdir)"
_mk "$dcl/draft.md" 'A title.' 'spec-task: issue=1 base=main sha=x' '' ''
o="$(newdir)"
SCRIPT="$stubshape/spec-post.sh" run post 661 "$SHA" "$dcl/draft.md" "$o"
stop_is no-critic-line

desc="pass: post with 1 round; converged."
dcl="$(newdir)"
_mk "$dcl/draft.md" 'Critic gate: architect; 1 round; converged.' '' '' ''
o="$(newdir)"
post "$dcl/draft.md" "$o"
assert_eq "$desc (posted)" posted "$(printf '%s' "$out" | cut -d' ' -f1)"
assert_eq "$desc (one POST)" 1 "$(writes)"

desc="pass: post with a draft that is CRLF throughout"
dcl="$(newdir)"
mkdraft "$dcl/lf.md"
sed 's/$/\r/' "$dcl/lf.md" >"$dcl/draft.md"
o="$(newdir)"
post "$dcl/draft.md" "$o"
assert_eq "$desc (posted)" posted "$(printf '%s' "$out" | cut -d' ' -f1)"
assert_eq "$desc (one POST)" 1 "$(writes)"

for stopw in 'cap reached:5 rounds' 'not converging:2 rounds'; do
  sw="${stopw%%:*}"
  rd_="${stopw#*:}"
  desc="pass: escalate with $rd_; $sw."
  dcl="$(newdir)"
  _mk "$dcl/draft.md" "Critic gate: architect, docs-consistency; $rd_; $sw." '' '' 'Open: a finding.'
  o="$(newdir)"
  esc "$dcl/draft.md" "$o"
  assert_eq "$desc (escalated)" escalated "$(printf '%s' "$out" | cut -d' ' -f1)"
  assert_eq "$desc (comment POST and label write)" 2 "$(writes)"
done

desc="stop: a draft with a line beginning with the marker prefix"
mkdraft "$d2/draft.md" 'spec-task: issue=1 base=main sha=x'
o="$(newdir)"
SCRIPT="$stubshape/spec-post.sh" run post 661 "$SHA" "$d2/draft.md" "$o"
stop_is has-marker
assert_eq "$desc (out-dir empty)" "" "$(ls -A "$o")"

desc="stop: the real spec-shape.sh refuses a marker title line first, as bad-shape"
dcl="$(newdir)"
mkdraft "$dcl/ok.md"
{ printf '%s\n' 'spec-task: issue=1 base=main sha=x'; tail -n +2 "$dcl/ok.md"; } >"$dcl/draft.md"
o="$(newdir)"
post "$dcl/draft.md" "$o"
stop_is bad-shape

tok='abcdefghijklmnopqrstuvwxyz0123'
for case_ in \
  'drive|C:/x' \
  'drive|see C:/Users/x and more' \
  'drive|path D:\work\y' \
  'users|at /Users/someone/file' \
  'home|at /home/someone/file' \
  'appdata|in AppData' \
  'token|ghp_'"$tok" \
  'token|gho_'"$tok" \
  'token|ghu_'"$tok" \
  'token|ghs_'"$tok" \
  'token|ghr_'"$tok" \
  'token|github_pat_'"$tok" \
  'pem|-----BEGIN PRIVATE KEY-----'; do
  shp="${case_%%|*}"
  extra="${case_#*|}"
  desc="stop: leak shape [$extra]"
  mkdraft "$d2/draft.md" "$extra"
  o="$(newdir)"
  post "$d2/draft.md" "$o"
  stop_is "leak 5 $shp"
  assert_eq "$desc (out-dir empty)" "" "$(ls -A "$o")"
done

desc="stop: a leak on a later line reports that line"
mkdraft "$d2/draft.md" '' 'at /home/someone/file'
o="$(newdir)"
post "$d2/draft.md" "$o"
stop_is "leak 15 home"
assert_eq "$desc (out-dir empty)" "" "$(ls -A "$o")"

desc="stop: the first shape wins over the first line"
mkdraft "$d2/draft.md" 'at /home/someone/file' 'then D:\work\y'
o="$(newdir)"
post "$d2/draft.md" "$o"
stop_is "leak 16 drive"
assert_eq "$desc (out-dir empty)" "" "$(ls -A "$o")"

desc="stop: escalate prints the same leak line and writes nothing"
mkesc "$d2/draft.md" 'at /Users/someone/file'
o="$(newdir)"
esc "$d2/draft.md" "$o"
stop_is "leak 5 users"
assert_eq "$desc (out-dir empty)" "" "$(ls -A "$o")"

desc="stop: a NUL byte on the leak line never prints a partial leak line"
{
  printf '%s\n' 'Spec for the thing. Drafted against main at abc1234.'
  printf '%s\n' "$CL_OK"
  printf '\n### Goal\n'
  printf 'at /home/some'
  printf '\000'
  printf 'one\n'
  printf '%s\n' 'Goal text.'
  printf '\n### Files touched\nOne file.\n'
  printf '\n### Done when\nIt runs.\n'
  printf '\n### Tests\nA test.\n'
  printf '\n### Out of scope\nNothing else.\n'
  printf '\n### Restated from the issue body\nnothing\n'
} >"$d2/draft.md"
o="$(newdir)"
post "$d2/draft.md" "$o"
stop_is unreadable
assert_eq "$desc (out-dir empty)" "" "$(ls -A "$o")"

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
assert_eq "$desc (no content-time query)" 0 "$(grep -c lastEditedAt "$glog" || true)"
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
cp "$bindir/gh-identity.sh" "$bindir/spec-shape.sh" "$bindir/declared-ids.sh" "$tmp/half2/"
SCRIPT="$tmp/half2/spec-post.sh" run post 661 "$SHA" "$dr/draft.md" "$o"
usage_is

desc="a copy of the script with gh-identity.sh, spec-shape.sh and spec-reaction.sh but no declared-ids.sh"
mkdir -p "$tmp/half3"
cp "$script" "$tmp/half3/spec-post.sh"
cp "$bindir/gh-identity.sh" "$bindir/spec-shape.sh" "$bindir/spec-reaction.sh" "$tmp/half3/"
SCRIPT="$tmp/half3/spec-post.sh" run post 661 "$SHA" "$dr/draft.md" "$o"
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
$CTLINE
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

desc="unreacted: the second copy's content time moved past the reaction (a never-edited issue created at its updated_at)"
mkrx "$RXF" "$RX_GOOD"
mkissue2 'dev[bot]' 200 '"NONE"' open false - 2026-10-17T20:10:46Z
mkissue 'dev[bot]' 200 '"NONE"'
o="$(newdir)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" post "$dr2/draft.md" "$o"
stop_is unreacted

# -- the content time (#890): a comment, a label or a milestone change moves updated_at, not the content time
ctissues() { # the App-filed issue and its second copy; every run resets the fixture to a maintainer's issue
  mkissue 'dev[bot]' 200 '"NONE"'
  mkissue2 'dev[bot]' 200 '"NONE"' open false - 2026-10-17T20:10:46Z '"second title"' '"second body"'
}
ctissues
desc="reacted pass: updated_at after the reaction, content time before it, the comment is posted"
mkct 2026-10-17T20:00:00Z 2026-10-17T20:10:46Z null
ctissues
o="$(newdir)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" FX_CT="$tmp/ct.json" post "$dr2/draft.md" "$o"
assert_eq "$desc (line)" "posted 777 dev[bot] https://github.com/acme/backlog/issues/661#issuecomment-777" "$out"

desc="reacted pass: an earlier body edit and an earlier rename"
mkct 2026-10-17T20:00:00Z 2026-10-17T20:10:46Z '"2026-10-17T20:05:00Z"' 2026-10-17T20:08:00Z
ctissues
o="$(newdir)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" FX_CT="$tmp/ct.json" post "$dr2/draft.md" "$o"
assert_eq "$desc (line)" "posted 777 dev[bot] https://github.com/acme/backlog/issues/661#issuecomment-777" "$out"

desc="unreacted: a body edit after the reaction"
mkct 2026-10-17T20:00:00Z 2026-10-17T20:10:46Z '"2026-10-17T20:10:46Z"'
ctissues
o="$(newdir)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" FX_CT="$tmp/ct.json" post "$dr2/draft.md" "$o"
stop_is unreacted
assert_eq "$desc (no write)" 0 "$(writes)"

desc="unreacted: a body edit after the reaction, with an older rename (the latest time wins, not the last read)"
mkct 2026-10-17T20:00:00Z 2026-10-17T20:10:46Z '"2026-10-17T20:10:46Z"' 2026-10-17T20:08:00Z
ctissues
o="$(newdir)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" FX_CT="$tmp/ct.json" post "$dr2/draft.md" "$o"
stop_is unreacted

desc="unreacted: a title rename after the reaction"
mkct 2026-10-17T20:00:00Z 2026-10-17T20:10:46Z null 2026-10-17T20:10:46Z
ctissues
o="$(newdir)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" FX_CT="$tmp/ct.json" post "$dr2/draft.md" "$o"
stop_is unreacted

desc="unreacted: a content time equal to the reaction's time (a body edit)"
mkct 2026-10-17T20:00:00Z 2026-10-17T20:10:46Z '"2026-10-17T20:10:39Z"'
ctissues
o="$(newdir)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" FX_CT="$tmp/ct.json" post "$dr2/draft.md" "$o"
stop_is unreacted

desc="unreacted: a content time equal to the reaction's time (a rename)"
mkct 2026-10-17T20:00:00Z 2026-10-17T20:10:46Z null 2026-10-17T20:10:39Z
ctissues
o="$(newdir)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" FX_CT="$tmp/ct.json" post "$dr2/draft.md" "$o"
stop_is unreacted

desc="a failed content-time query is unreachable"
ctissues
o="$(newdir)"
FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" FX_CT_FAIL=1 post "$dr2/draft.md" "$o"
stop_is unreachable

CTOK='"createdAt":"2026-10-17T20:00:00Z","updatedAt":"2026-10-17T20:10:46Z"'
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
  desc="content-time response with ${v%%|*} is unreadable"
  printf '%s\n' "${v#*|}" >"$tmp/ct.json"
  ctissues
  o="$(newdir)"
  FX_RX="$RXF" FX_ISSUE2="$tmp/issue2.json" FX_CT="$tmp/ct.json" post "$dr2/draft.md" "$o"
  stop_is unreadable
  assert_eq "$desc (no write)" 0 "$(writes)"
done

desc="no content-time query for a declared maintainer's issue"
setyml "$tmp/map.yml"
mkissue maint 100 '"OWNER"'
o="$(newdir)"
post "$dr2/draft.md" "$o"
assert_eq "$desc (posted)" "posted 777 dev[bot] https://github.com/acme/backlog/issues/661#issuecomment-777" "$out"
assert_eq "$desc (no content-time query)" 0 "$(grep -c lastEditedAt "$glog" || true)"

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

# A declared-ids.sh that fails or misprints stops a maintainer's issue `unreadable` at app_check (#1079),
# never a pass. Each stub gets its own copy directory.
si=0
for stub in 'exit 2' 'exit 1' 'echo unreadable' 'echo "ok 100"' 'echo "ok 100 - "' 'echo "ok 100 02001"' 'echo "ok 100 x"' 'echo "ok 100 - -"' 'printf "ok 100 -\\nok 100 -\\n"' ': # no output'; do
  si=$((si + 1))
  mkdir -p "$tmp/dstub$si"
  cp "$script" "$tmp/dstub$si/spec-post.sh"
  cp "$bindir/gh-identity.sh" "$bindir/spec-shape.sh" "$bindir/spec-reaction.sh" "$tmp/dstub$si/"
  printf '#!/bin/sh\n%s\n' "$stub" >"$tmp/dstub$si/declared-ids.sh"
  desc="a helper stub that does [$stub] stops a maintainer's issue unreadable"
  mkissue maint 100 '"OWNER"'
  o="$(newdir)"
  SCRIPT="$tmp/dstub$si/spec-post.sh" FX_RX="$RXF" post "$dr2/draft.md" "$o"
  stop_is unreadable
done

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
  mkissue 'dev[bot]' 200 '"NONE"' open false - 2026-10-17T20:10:28Z "$ttl" "$bdy"
  o="$(newdir)"
  FX_RX="$RXF" post "$dr2/draft.md" "$o"
  stop_is hidden
  noout
done

desc="hidden: a normal closing tag, a plain ampersand and a bracketed line indented four spaces pass"
mkissue 'dev[bot]' 200 '"NONE"' open false - 2026-10-17T20:10:28Z '"t &amp; u"' '"a </b> c &copy; d\n    [x]: y"'
o="$(newdir)"
FX_RX="$RXF" post "$dr2/draft.md" "$o"
assert_eq "$desc" posted "$(printf '%s' "$out" | cut -d' ' -f1)"

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
for k in HREF LDEF; do
  assert_eq "$k is spec-fresh.sh's line, byte for byte" "$(grep "^$k=" "$bindir/spec-fresh.sh")" "$(grep "^$k=" "$script")"
  assert_eq "$k is one line" 1 "$(grep -c "^$k=" "$script")"
done
desc="the hidden-screen awk program is spec-issue.sh's, byte for byte"
scrbody() { awk '/SI_HID="\$HID"/ { on = 1 } on { print } on && /stop unreadable$/ { exit }' "$1"; }
assert_eq "$desc" "$(scrbody "$bindir/spec-issue.sh")" "$(scrbody "$script")"
assert_eq "$desc (found)" yes "$([ -n "$(scrbody "$script")" ] && echo yes || echo no)"
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
