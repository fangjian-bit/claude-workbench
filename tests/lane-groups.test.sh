#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/lane-groups.sh (#896).
#
# Runs a COPY of the real script beside a stub spec-find.sh, a real copy of plan-depends.sh and a
# WRAPPER spec-fresh.sh (the script finds its siblings through $0): the wrapper answers `check`
# from a canned file and delegates every other mode to a real copy of spec-fresh.sh, so the
# `paths` mode under test is the real one. The last section runs the real `check` through the script
# against a scratch repository with a local bare origin. A stub `gh` on PATH
# serves canned milestone listings, descriptions and comment JSON and applies the caller's own
# --jq with jq, so the pull-request filter and the description projection under test are the real
# ones.
#
# Permitted toolset: POSIX sh, jq, yq (mikefarah v4) and git; the suite skips whole, loudly, without
# jq or yq, and skips only its scratch-repository section, loudly, without git.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
bin_src="$root_dir/plugins/way-of-working/bin"

for tool in jq yq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "skip - lane-groups.sh fixtures: no $tool on PATH" >&2
    exit 0
  fi
done

tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

fail=0
assert_eq() {
  desc="$1"; expected="$2"; actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "ok - $desc"
  else
    echo "FAIL - $desc: expected [$expected], got [$actual]" >&2
    fail=1
  fi
}

bin="$tmp/bin"; stubs="$tmp/stubs"
mkdir -p "$bin" "$stubs"
cp "$bin_src/lane-groups.sh" "$bin/lane-groups.sh"
cp "$bin_src/plan-depends.sh" "$bin/plan-depends.sh"
cp "$bin_src/spec-fresh.sh" "$bin/spec-fresh-real.sh"
chmod 755 "$bin"/*.sh

# The stub finder: prints $STUBS/finder.<N> (default `none`), or exits $STUBS/finder.<N>.rc.
cat >"$bin/spec-find.sh" <<'STUB'
#!/bin/sh
n=$2
[ ! -f "$STUBS/finder.$n.rc" ] || exit "$(cat "$STUBS/finder.$n.rc")"
if [ -f "$STUBS/finder.$n" ]; then cat "$STUBS/finder.$n"; else echo none; fi
STUB
# The wrapper: `check` prints $STUBS/fresh.<N> (default `fresh`); other modes run the real copy.
cat >"$bin/spec-fresh.sh" <<'STUB'
#!/bin/sh
here=$(dirname "$0")
if [ "$1" = check ]; then
  if [ -f "$STUBS/fresh.$3" ]; then cat "$STUBS/fresh.$3"; else echo fresh; fi
  exit 0
fi
exec sh "$here/spec-fresh-real.sh" "$@"
STUB
chmod 755 "$bin/spec-find.sh" "$bin/spec-fresh.sh"

# The stub gh. `api ... issues?milestone=M ...` runs the --jq over $STUBS/list.M.json;
# `api repos/R/milestones/M` over $STUBS/ms.M.json; `api repos/R/issues/comments/ID` prints
# $STUBS/comment.ID.json. A $STUBS/<file>.rc makes that call fail. Every call is logged.
mkdir -p "$tmp/ghbin"
cat >"$tmp/ghbin/gh" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$STUBS/gh.log"
[ "$1" = api ] || exit 9
shift
url=; jqf=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --paginate) shift ;;
    --jq) jqf=$2; shift 2 ;;
    *) url=$1; shift ;;
  esac
done
case "$url" in
  repos/acme/widgets/issues?milestone=*)
    m=${url#*milestone=}; m=${m%%&*}
    f="list.$m.json" ;;
  repos/acme/widgets/milestones/*) f="ms.${url##*/}.json" ;;
  repos/acme/widgets/issues/comments/*) f="comment.${url##*/}.json" ;;
  *) exit 9 ;;
esac
[ ! -f "$STUBS/$f.rc" ] || exit "$(cat "$STUBS/$f.rc")"
[ -f "$STUBS/$f" ] || exit 1
if [ -n "$jqf" ]; then jq -r "$jqf" "$STUBS/$f"; else cat "$STUBS/$f"; fi
STUB
chmod 755 "$tmp/ghbin/gh"
PATH="$tmp/ghbin:$PATH"
STUBS="$stubs"
export PATH STUBS

yml="$tmp/project.yml"
printf 'repo: acme/widgets\npr_base: main\nbacklog:\n  repo: null\n' >"$yml"

SHA=0123456789abcdef0123456789abcdef01234567
TS=2026-10-23T10:00:00Z

reset() { rm -rf "$stubs"; mkdir -p "$stubs"; : >"$stubs/gh.log"; }

# list <milestone> <n>...: the open listing, with a pull request among the issues
list() {
  m=$1; shift
  { printf '['; sep=; for n in "$@"; do printf '%s{"number":%s}' "$sep" "$n"; sep=,; done
    printf '%s{"number":9999,"pull_request":{}}]' "$sep"; } >"$stubs/list.$m.json"
}
# desc <milestone>: the description from stdin
desc() { jq -Rs '{description: .}' >"$stubs/ms.$1.json"; }
# spec <issue> <comment-id> <path-lines>: a found, approved spec with these Files touched bullets
spec() {
  n=$1; cid=$2; bullets=$3
  body=$(printf 'spec-task: issue=%s base=main sha=%s\n\n### Goal\n\nx\n\n### Files touched\n\n%s\n\n### Done when\n\nx\n' "$n" "$SHA" "$bullets")
  jq -n --argjson id "$cid" --arg ts "$TS" --arg body "$body" '{id: $id, updated_at: $ts, body: $body}' >"$stubs/comment.$cid.json"
  printf 'found %s %s\n' "$cid" "$TS" >"$stubs/finder.$n"
}

run() { (cd "$tmp" && "$bin/lane-groups.sh" "$@" 2>/dev/null); }
run_rc() { (cd "$tmp" && "$bin/lane-groups.sh" "$@" >/dev/null 2>&1) && echo 0 || echo $?; }
tab=$(printf '\t')
row() { # row <n> <state> <paths> <shared> <waits>
  printf '%s\t%s\t%s\t%s\t%s' "$1" "$2" "$3" "$4" "$5"
}
nl='
'

echo "# usage"

reset; list 5 1
assert_eq "no arguments: exit 2" "2" "$(run_rc)"
assert_eq "one argument: exit 2" "2" "$(run_rc 5)"
assert_eq "three arguments: exit 2" "2" "$(run_rc 5 "$yml" extra)"
assert_eq "milestone 0: exit 2" "2" "$(run_rc 0 "$yml")"
assert_eq "milestone 012: exit 2" "2" "$(run_rc 012 "$yml")"
assert_eq "milestone abc: exit 2" "2" "$(run_rc abc "$yml")"
assert_eq "an unreadable project file: exit 2" "2" "$(run_rc 5 "$tmp/none.yml")"
assert_eq "a bad milestone prints nothing" "" "$(run 012 "$yml")"
: >"$tmp/empty.yml"
printf 'a: [\n' >"$tmp/broken.yml"
assert_eq "a project file yq cannot parse: exit 2" "2" "$(run_rc 5 "$tmp/broken.yml")"
assert_eq "a slash-less \$0: exit 2" "2" "$(cd "$bin" && sh lane-groups.sh 5 "$yml" >/dev/null 2>&1 && echo 0 || echo $?)"
for sib in spec-find.sh spec-fresh.sh plan-depends.sh; do
  mkdir -p "$tmp/nosib"
  cp "$bin"/*.sh "$tmp/nosib/"
  rm "$tmp/nosib/$sib"
  assert_eq "a missing $sib: exit 2" "2" "$( (cd "$tmp" && "$tmp/nosib/lane-groups.sh" 5 "$yml" >/dev/null 2>&1) && echo 0 || echo $?)"
  assert_eq "a missing $sib prints nothing" "" "$( (cd "$tmp" && "$tmp/nosib/lane-groups.sh" 5 "$yml" 2>/dev/null) )"
  rm -rf "$tmp/nosib"
done

echo "# disjoint specs share one group"

reset; list 5 11 12
printf '**Build order:**\n1. #11: a. [depends_on: none]\n2. #12: b. [depends_on: none]\n' | desc 5
spec 11 101 '- `plugins/a.sh`
- `tests/a.test.sh`'
spec 12 102 '- `plugins/b.sh`'
want="$(row 11 found 'plugins/a.sh tests/a.test.sh' - -)$nl$(row 12 found plugins/b.sh - -)${nl}group${tab}1${tab}#11 #12"
assert_eq "two disjoint independent specs: one group" "$want" "$(run 5 "$yml")"
assert_eq "the pull request in the listing is not a row" "0" "$(run 5 "$yml" | grep -c 9999 || true)"
assert_eq "no comment listing or issue body was read" "0" "$(grep -c 'issues/[0-9]' "$stubs/gh.log" || true)"

echo "# shared paths"

spec 12 102 '- `plugins/a.sh`'
want="$(row 11 found 'plugins/a.sh tests/a.test.sh' '#12' -)$nl$(row 12 found plugins/a.sh '#11' -)${nl}group${tab}1${tab}#11${nl}group${tab}2${tab}#12"
assert_eq "the same path: shown and in different groups" "$want" "$(run 5 "$yml")"

spec 11 101 '- `plugins`'
spec 12 102 '- `plugins/b.sh`'
want="$(row 11 found plugins '#12' -)$nl$(row 12 found plugins/b.sh '#11' -)${nl}group${tab}1${tab}#11${nl}group${tab}2${tab}#12"
assert_eq "a directory and a file under it: shared" "$want" "$(run 5 "$yml")"
spec 11 101 '- `plugins/b.sh`'
spec 12 102 '- `plugins/`'
want="$(row 11 found plugins/b.sh '#12' -)$nl$(row 12 found plugins '#11' -)${nl}group${tab}1${tab}#11${nl}group${tab}2${tab}#12"
assert_eq "a file and its directory, the other order: shared" "$want" "$(run 5 "$yml")"
spec 11 101 '- `plugins/a`'
spec 12 102 '- `plugins/ab`'
want="$(row 11 found plugins/a - -)$nl$(row 12 found plugins/ab - -)${nl}group${tab}1${tab}#11 #12"
assert_eq "a name prefix that is not a directory prefix: not shared" "$want" "$(run 5 "$yml")"

spec 11 101 '- `CHANGELOG.md` **(append)**
- `plugins/a.sh`'
spec 12 102 '- `CHANGELOG.md` **(append)**
- `plugins/b.sh`'
want="$(row 11 found plugins/a.sh - -)$nl$(row 12 found plugins/b.sh - -)${nl}group${tab}1${tab}#11 #12"
assert_eq "a common file marked append in both: shared nothing" "$want" "$(run 5 "$yml")"

spec 11 101 '- `CHANGELOG.md` **(append)**'
spec 12 102 '- `plugins/b.sh`'
want="$(row 11 found - - -)$nl$(row 12 found plugins/b.sh - -)${nl}group${tab}1${tab}#11 #12"
assert_eq "only append bullets: paths are -" "$want" "$(run 5 "$yml")"

spec 11 101 '- `.github/workflows/x.yml` **(append)**'
spec 12 102 '- `.github/workflows/x.yml` **(append)**'
want="$(row 11 found .github/workflows/x.yml '#12' -)$nl$(row 12 found .github/workflows/x.yml '#11' -)${nl}group${tab}1${tab}#11${nl}group${tab}2${tab}#12"
assert_eq "an append path under .github/ is shared" "$want" "$(run 5 "$yml")"

echo "# waits"

spec 11 101 '- `plugins/a.sh`'
spec 12 102 '- `plugins/b.sh`'
printf '**Build order:**\n1. #11: a. [depends_on: none]\n2. #12: b. [depends_on: #11]\n' | desc 5
want="$(row 11 found plugins/a.sh - -)$nl$(row 12 found plugins/b.sh - '#11')${nl}group${tab}1${tab}#11"
assert_eq "a depends_on on an open issue: shown, in no group" "$want" "$(run 5 "$yml")"

list 5 12
want="$(row 12 found plugins/b.sh - -)${nl}group${tab}1${tab}#12"
assert_eq "the named issue no longer open: met" "$want" "$(run 5 "$yml")"

list 5 11 12 13
spec 13 103 '- `plugins/c.sh`'
printf '**Build order:**\n1. #11: a. [depends_on: none]\n2. #12: b. [depends_on: none]\n' | desc 5
want="$(row 11 found plugins/a.sh - -)$nl$(row 12 found plugins/b.sh - -)$nl$(row 13 found plugins/c.sh - '#11,#12')${nl}group${tab}1${tab}#11 #12"
assert_eq "an issue missing from the build order waits for every listed open issue" "$want" "$(run 5 "$yml")"

printf '**Build order:**\n1. #11: a. [depends_on: none]\n2. #12: b.\n3. #13: c. [depends_on: none]\n' | desc 5
want="$(row 11 found plugins/a.sh - -)$nl$(row 12 found plugins/b.sh - '#11')$nl$(row 13 found plugins/c.sh - -)${nl}group${tab}1${tab}#11 #13"
assert_eq "an unconfirmed marker waits for every earlier issue" "$want" "$(run 5 "$yml")"

printf 'no build order here\n' | desc 5
want="$(row 11 found plugins/a.sh - order-unreadable)$nl$(row 12 found plugins/b.sh - order-unreadable)$nl$(row 13 found plugins/c.sh - order-unreadable)${nl}group none"
assert_eq "an unreadable build order: order-unreadable and group none" "$want" "$(run 5 "$yml")"

printf '**Build order:**\n1. #13: c. [depends_on: none]\n2. #11: a. [depends_on: none]\n3. #12: b. [depends_on: none]\n' | desc 5
spec 11 101 '- `plugins/x.sh`'
spec 12 102 '- `plugins/x.sh`'
spec 13 103 '- `plugins/x.sh`'
want="$(row 11 found plugins/x.sh '#12,#13' -)$nl$(row 12 found plugins/x.sh '#11,#13' -)$nl$(row 13 found plugins/x.sh '#11,#12' -)${nl}group${tab}1${tab}#13${nl}group${tab}2${tab}#11${nl}group${tab}3${tab}#12"
assert_eq "groups are filled in build-order position" "$want" "$(run 5 "$yml")"

echo "# the finder's words"

list 5 11 12
printf '**Build order:**\n1. #11: a. [depends_on: none]\n2. #12: b. [depends_on: none]\n' | desc 5
spec 12 102 '- `plugins/b.sh`'
for w in none unreacted escalated ambiguous moved; do
  : >"$stubs/gh.log"
  printf '%s\n' "$w" >"$stubs/finder.11"
  want="$(row 11 "$w" '?' '?' -)$nl$(row 12 found plugins/b.sh - -)${nl}group${tab}1${tab}#12"
  assert_eq "finder $w: unknown paths, no group" "$want" "$(run 5 "$yml")"
  assert_eq "finder $w: no comment fetch for it" "0" "$(grep -c 'issues/comments/101' "$stubs/gh.log" || true)"
done
printf 'unreacted 5,6\n' >"$stubs/finder.11"
assert_eq "finder unreacted <ids> shows only the word" "unreacted" "$(run 5 "$yml" | cut -f2 | sed -n 1p)"
printf 'surprise\n' >"$stubs/finder.11"
assert_eq "an unknown finder word reads unreadable for that row" "unreadable" "$(run 5 "$yml" | cut -f2 | sed -n 1p)"
printf '3\n' >"$stubs/finder.11.rc"
assert_eq "a failing finder reads unreadable for that row only" "unreadable${nl}found" "$(run 5 "$yml" | cut -f2 | sed -n 1,2p)"
rm -f "$stubs/finder.11.rc"

echo "# a stale spec, a moved comment, a failed fetch"

spec 11 101 '- `plugins/a.sh`'
printf 'stale 2\n' >"$stubs/fresh.11"
want="$(row 11 stale plugins/a.sh - -)$nl$(row 12 found plugins/b.sh - -)${nl}group${tab}1${tab}#12"
assert_eq "a stale spec lists its paths and is in no group" "$want" "$(run 5 "$yml")"
printf 'bad-sha\n' >"$stubs/fresh.11"
assert_eq "any other check word reads unreadable" "unreadable${tab}?" "$(run 5 "$yml" | sed -n 1p | cut -f2,3)"
rm -f "$stubs/fresh.11"

printf 'found 101 2026-10-23T11:00:00Z\n' >"$stubs/finder.11"
assert_eq "a fetched updated_at that differs reads moved" "moved${tab}?" "$(run 5 "$yml" | sed -n 1p | cut -f2,3)"
printf 'found 777 %s\n' "$TS" >"$stubs/finder.11"
cp "$stubs/comment.101.json" "$stubs/comment.777.json"
assert_eq "a fetched id that differs reads moved" "moved" "$(run 5 "$yml" | sed -n 1p | cut -f2)"
rm -f "$stubs/comment.777.json"
spec 11 101 '- `plugins/a.sh`'
printf '1\n' >"$stubs/comment.101.json.rc"
want="$(row 11 unreadable '?' '?' -)$nl$(row 12 found plugins/b.sh - -)${nl}group${tab}1${tab}#12"
assert_eq "a failed comment fetch reads unreadable for that row only" "$want" "$(run 5 "$yml")"
rm -f "$stubs/comment.101.json.rc"

printf 'found 0101 %s\n' "$TS" >"$stubs/finder.11"
assert_eq "a found id with a leading zero reads unreadable" "unreadable" "$(run 5 "$yml" | sed -n 1p | cut -f2)"
spec 11 101 '- `plugins/a.sh`'

echo "# unusable paths"

spec 11 101 '- `../etc/passwd`'
assert_eq "a spec the shape check refuses has unknown paths" "found${tab}?${tab}?" "$(run 5 "$yml" | sed -n 1p | cut -f2,3,4)"
spec 11 101 '- `plugins/a.sh`'

echo "# whole-output failures"

: >"$stubs/gh.log"
echo 1 >"$stubs/list.5.json.rc"
assert_eq "a failed milestone listing prints only unreadable" "unreadable|0" "$(run 5 "$yml")|$(run_rc 5 "$yml")"
rm -f "$stubs/list.5.json.rc"
echo 1 >"$stubs/ms.5.json.rc"
assert_eq "a failed description fetch prints only unreadable" "unreadable|0" "$(run 5 "$yml")|$(run_rc 5 "$yml")"
rm -f "$stubs/ms.5.json.rc"
printf '[{"number":"011"},{"number":12}]' >"$stubs/list.5.json"
assert_eq "a listed number with a leading zero prints only unreadable" "unreadable" "$(run 5 "$yml")"
list 5 11 12
printf 'repo: not a repo\n' >"$tmp/bad.yml"
assert_eq "a repo outside owner/name prints only unreadable" "unreadable" "$(run 5 "$tmp/bad.yml")"

echo "# a repeated issue in the listing"

printf '[{"number":11},{"number":12},{"number":11}]' >"$stubs/list.5.json"
printf '**Build order:**\n1. #11: a. [depends_on: none]\n2. #12: b. [depends_on: none]\n' | desc 5
spec 11 101 '- `plugins/a.sh`'
spec 12 102 '- `plugins/b.sh`'
assert_eq "a repeated number is one row" "2" "$(run 5 "$yml" | grep -c "^[0-9]")"

echo "# an empty milestone"

list 6
printf 'x\n' | desc 6
assert_eq "no open issues: group none" "group none" "$(run 6 "$yml")"

echo "# the final pass failing"

# A stub awk first on PATH, for this one run: its -F call (the script's final pass) logs, prints a
# row and fails; any other call runs the real awk.
real_awk="$(command -v awk)"
mkdir -p "$tmp/awkbin"
cat >"$tmp/awkbin/awk" <<STUB
#!/bin/sh
if [ "\$1" = -F ]; then
  echo awk >>"\$STUBS/awk.log"
  printf '11\tfound\tplugins/a.sh\t-\t-\n'
  exit 1
fi
exec "$real_awk" "\$@"
STUB
chmod 755 "$tmp/awkbin/awk"
reset; list 5 11 12
printf '**Build order:**\n1. #11: a. [depends_on: none]\n2. #12: b. [depends_on: none]\n' | desc 5
spec 11 101 '- `plugins/a.sh`'
spec 12 102 '- `plugins/b.sh`'
: >"$stubs/awk.log"
got=$( (PATH="$tmp/awkbin:$PATH"; run 5 "$yml") )
calls=$(wc -l <"$stubs/awk.log" | tr -d ' ')
rc=$( (PATH="$tmp/awkbin:$PATH"; run_rc 5 "$yml") )
assert_eq "a failing final pass prints only unreadable" "unreadable" "$got"
assert_eq "a failing final pass exits 0" "0" "$rc"
assert_eq "the stub awk final pass was called once" "1" "$calls"

if ! command -v git >/dev/null 2>&1; then
  echo "SKIP - the real spec-fresh.sh check in a scratch repository: git not on PATH; section not run" >&2
else
  echo "# the real spec-fresh.sh check, in a scratch repository"

  bin2="$tmp/bin2"
  mkdir -p "$bin2"
  cp "$bin_src/lane-groups.sh" "$bin_src/spec-fresh.sh" "$bin_src/plan-depends.sh" "$bin/spec-find.sh" "$bin2/"
  chmod 755 "$bin2"/*.sh
  O="$tmp/origin.git"; W="$tmp/work"
  git init -q --bare "$O"
  git -C "$O" symbolic-ref HEAD refs/heads/main
  git init -q "$W"
  git -C "$W" symbolic-ref HEAD refs/heads/main
  git -C "$W" config user.name t
  git -C "$W" config user.email t@example.invalid
  git -C "$W" config commit.gpgsign false
  git -C "$W" remote add origin "$O"
  mkdir -p "$W/plugins"
  printf 'a1\n' >"$W/plugins/a.sh"; printf 'b1\n' >"$W/plugins/b.sh"
  git -C "$W" add -A && git -C "$W" commit -q -m a && git -C "$W" push -q origin refs/heads/main:refs/heads/main
  commit_a="$(git -C "$W" rev-parse HEAD)"
  printf 'a2\n' >"$W/plugins/a.sh"
  git -C "$W" add -A && git -C "$W" commit -q -m b && git -C "$W" push -q origin refs/heads/main:refs/heads/main

  run2() { (cd "$W" && "$bin2/lane-groups.sh" "$@" 2>/dev/null); }
  reset; list 5 11 12
  printf '**Build order:**\n1. #11: a. [depends_on: none]\n2. #12: b. [depends_on: none]\n' | desc 5
  orig_sha=$SHA
  SHA=$commit_a
  spec 11 101 '- `plugins/a.sh`'
  spec 12 102 '- `plugins/b.sh`'
  want="$(row 11 stale plugins/a.sh - -)$nl$(row 12 found plugins/b.sh - -)${nl}group${tab}1${tab}#12"
  assert_eq "real check: a changed listed path is stale, an unchanged one found" "$want" "$(run2 5 "$yml")"

  SHA=$orig_sha
  spec 11 101 '- `plugins/a.sh`'
  SHA=$commit_a
  want="$(row 11 unreadable '?' '?' -)$nl$(row 12 found plugins/b.sh - -)${nl}group${tab}1${tab}#12"
  assert_eq "real check: a sha= that is not a commit reads unreadable for that row only" "$want" "$(run2 5 "$yml")"

  spec 11 101 '- `plugins/a.sh`'
  mkdir -p "$tmp/nocheckout"
  got=$( (cd "$tmp/nocheckout" && GIT_CEILING_DIRECTORIES="$tmp" "$bin2/lane-groups.sh" 5 "$yml" 2>/dev/null) )
  want="$(row 11 unreadable '?' '?' -)$nl$(row 12 unreadable '?' '?' -)${nl}group none"
  assert_eq "real check: a run from outside a checkout reads unreadable for both rows" "$want" "$got"
  SHA=$orig_sha
fi


[ "$fail" -eq 0 ]
