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
# matches it (the same stop or pass), now as a word. Symlink cases skip, loudly, where `ln -s`
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
      */issues/*)
        [ -z "${FX_ISSUE_FAIL:-}" ] || fail_with
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

mkissue() { # mkissue <login> <id-json> <assoc-json> [pr]
  pr=
  [ "${4:-}" != pr ] || pr=',"pull_request":{"url":"x"}'
  printf '{"number":611,"title":"%s title","body":"%s body","user":{"login":"%s","id":%s},"author_association":%s%s}\n' \
    "$MARK" "$MARK" "$1" "$2" "$3" "$pr" >"$tmp/issue.json"
}

reset_fx() {
  FX_NWO=acme/repo FX_DEF=main FX_ISSUE="$tmp/issue.json" FX_ECHO=1
  FX_VIEW_FAIL= FX_PERM_FAIL= FX_ISSUE_FAIL= FX_PLANT= FX_OUT= FX_LINK_TARGET=
  export FX_NWO FX_DEF FX_ISSUE FX_ECHO FX_VIEW_FAIL FX_PERM_FAIL FX_ISSUE_FAIL FX_PLANT FX_OUT FX_LINK_TARGET
}
reset_fx
mkissue maint 100 '"OWNER"'

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

# -- legacy allowlist (today: legacy/OWNER|MEMBER|COLLABORATOR pass, anything else stops) ------
setyml "$tmp/legacy.yml"
for a in OWNER MEMBER COLLABORATOR; do
  desc="identities null, $a passes"
  mkissue someone 7 "\"$a\""
  o="$(newout)"
  run fetch 611 "$o"
  assert_eq "$desc (line)" "ok B=acme/backlog BASE=main VERDICT=legacy ASSOC=$a" "$out"
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
for who in 'stranger 9' 'dev[bot] 200' 'rev[bot] 300' 'loop[bot] 400'; do
  set -- $who
  desc="map, loop_identity another login: $1 is untrusted"
  mkissue "$1" "$2" '"MEMBER"'
  o="$(newout)"
  run fetch 611 "$o"
  stop_is untrusted "$o"
done
setyml "$tmp/mapnoloop.yml"
for who in 'stranger 9' 'dev[bot] 200' 'rev[bot] 300' 'loop[bot] 400'; do
  set -- $who
  desc="map, loop_identity null: $1 is untrusted"
  mkissue "$1" "$2" '"MEMBER"'
  o="$(newout)"
  run fetch 611 "$o"
  stop_is untrusted "$o"
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
assert_eq "every gh call is a GET" 0 "$(grep -c -e '|-X|' -e '|--method|' -e '|-f|' -e '|-F|' -e '|--field|' -e '|--raw-field|' -e '|--input|' -e 'graphql' "$gall" || true)"

exit "$fail"
