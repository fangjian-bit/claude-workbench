#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/milestone-desc.sh: the checked writer for one
# milestone's description (#638, child (b) of #628).
#
# The real script runs from a local checkout whose `origin` is a fixture URL. First on PATH, only
# while the script runs, are a stub `gh` and a logging `git` wrapper (it records its argv, then runs
# the real git). TMPDIR is a test directory, so the scratch rule is exercised for real. Needs git
# and yq (mikefarah v4); skips, loudly, when yq is absent.
#
# The stub `gh` is keyed on the shape of the call the script makes; this suite and the script are
# maintained together. It does not interpret --jq: it prints the plain value the filter would.
# Permitted toolset: POSIX sh.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/plugins/way-of-working/bin/milestone-desc.sh"

if ! command -v yq >/dev/null 2>&1; then
  echo "SKIP - yq not on PATH; milestone-desc.sh needs it" >&2
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
scratch="$tmp/scratch"
mkdir -p "$scratch" "$tmp/outside"
glog="$tmp/gh.log"
gitlog="$tmp/git.log"
store="$tmp/stored"
fakebin="$tmp/fakebin"
swapbin="$tmp/swapbin"
mkdir -p "$fakebin" "$swapbin"

cat >"$fakebin/gh" <<'FAKE_GH'
#!/bin/sh
# Log argv, one call per line, `|` after every argument.
line=
for a in "$@"; do line="$line$a|"; done
printf '%s\n' "$line" >>"$FX_GHLOG"
echo_marker() {
  if [ -n "${FX_ECHO:-}" ]; then
    echo "STUB-ECHO-9c1d $1"
    echo "STUB-ECHO-9c1d $1" >&2
  fi
}
case "$1 $2" in
  "repo view")
    [ -n "$3" ] || exit 1
    [ -z "${FX_VIEW_FAIL:-}" ] || { echo_marker "view"; exit 1; }
    case "$*" in
      *nameWithOwner*) printf '%s\n' "$FX_NWO" ;;
      *defaultBranchRef*) printf '%s\n' "$FX_DEF" ;;
      *) exit 1 ;;
    esac
    ;;
  "api -H")
    [ -f "$FX_YML" ] || exit 1
    "$FX_CAT" "$FX_YML"
    ;;
  "api -X")
    "$FX_CAT" >"$FX_STORE"
    echo_marker "$("$FX_CAT" "$FX_STORE")"
    exit "${FX_PATCH_RC:-0}"
    ;;
  "api repos/"*)
    case "${FX_BACK:-ok}" in
      ok) "$FX_CAT" "$FX_STORE"; echo ;;
      nonl) "$FX_CAT" "$FX_STORE" ;;
      alt) "$FX_CAT" "$FX_STORE"; printf 'x\n' ;;
      fail) echo_marker "$("$FX_CAT" "$FX_STORE" 2>/dev/null)"; exit 1 ;;
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
cat >"$swapbin/cat" <<'FAKE_CAT'
#!/bin/sh
if [ "${1:-}" = "$FX_SWAP_TARGET" ]; then
  if [ "${FX_SWAP_MODE:-}" = trunc ]; then
    : >"$FX_SWAP_TARGET"
  else
    printf 'swapped\n' >"$FX_SWAP_TARGET.new"
    mv "$FX_SWAP_TARGET.new" "$FX_SWAP_TARGET"
  fi
fi
exec "$FX_REAL_CAT" "$@"
FAKE_CAT
chmod +x "$fakebin/gh" "$fakebin/git" "$swapbin/cat"

export FX_GHLOG="$glog" FX_GITLOG="$gitlog" FX_STORE="$store" FX_REAL_GIT="$real_git" FX_REAL_CAT="$real_cat" FX_CAT="$real_cat"

cat >"$tmp/good.yml" <<'EOF'
repo: acme/repo
backlog:
  repo: acme/backlog
EOF
printf 'repo: acme/repo\nbacklog:\n  repo: null\n' >"$tmp/nullbacklog.yml"
printf 'repo: Acme/Repo\nbacklog:\n  repo: ACME/Backlog\n' >"$tmp/casebacklog.yml"
printf 'repo: acme/other\nbacklog:\n  repo: acme/backlog\n' >"$tmp/otherrepo.yml"
for b in a/b/c ../x owner other/backlog; do
  n="$(printf '%s' "$b" | tr '/.' '__')"
  printf 'repo: acme/repo\nbacklog:\n  repo: %s\n' "$b" >"$tmp/bl-$n.yml"
done

# A checkout whose origin is the fixture URL; its working tree names a different backlog.
mkco() { # mkco <dir>
  mkdir -p "$1/.ai"
  "$real_git" -C "$1" init -q
  "$real_git" -C "$1" remote add origin https://example.test/acme/repo.git
  printf 'repo: acme/repo\nbacklog:\n  repo: elsewhere/tree\n' >"$1/.ai/project.yml"
}
co="$tmp/co"
mkco "$co"
top="$("$real_git" -C "$co" rev-parse --show-toplevel)"

reset_fx() {
  FX_NWO=acme/repo FX_DEF=main FX_YML="$tmp/good.yml" FX_PATCH_RC=0 FX_BACK=ok FX_ECHO= FX_VIEW_FAIL=
  export FX_NWO FX_DEF FX_YML FX_PATCH_RC FX_BACK FX_ECHO FX_VIEW_FAIL
}
reset_fx

FILE_MARK="FILE-SECRET-7f3a"
newdir() { TMPDIR="$scratch" mktemp -d; }
# mkfile <dir> [milestone] [content]: write <dir>/description-m<N>.txt, print its path.
mkfile() {
  p="$1/description-m${2:-19}.txt"
  printf '%s' "${3:-"line one
$FILE_MARK
"}" >"$p"
  printf '%s' "$p"
}

# run <milestone> <file> [extra...]: sets rc, out, err, before, after.
run() {
  : >"$glog"; : >"$gitlog"; rm -f "$store"
  before="$(ls "$scratch")"
  export FX_SWAP_TARGET="${FX_SWAP_TARGET:-}"
  export FX_SWAP_MODE="${FX_SWAP_MODE:-}"
  rc=0
  out="$(cd "$co" && PATH="${XPATH:-$fakebin}:$PATH" TMPDIR="${XTMP:-$scratch}" sh "$script" write "$@" 2>"$tmp/err")" || rc=$?
  err="$("$real_cat" "$tmp/err")"
  after="$(ls "$scratch")"
  reset_fx; unset XPATH XTMP FX_SWAP_TARGET FX_SWAP_MODE
  case "$out$err" in
    *"$FILE_MARK"* | *STUB-ECHO-9c1d*) echo "FAIL - $desc: a marker reached the script's output" >&2; fail=1 ;;
  esac
}
calls() { # calls <log> -- the number of lines
  n=0
  while IFS= read -r _; do n=$((n + 1)); done <"$1"
  echo "$n"
}
patches() { grep -c '^api|-X|PATCH|' "$glog" || true; }

expect_ok() {
  assert_eq "$desc (word)" ok "$out"
  assert_eq "$desc (rc)" 0 "$rc"
  assert_eq "$desc (temp dir gone)" "$before" "$after"
}
expect_refused() { # [calls]  -- refused, and nothing sent
  assert_eq "$desc (word)" refused "$out"
  assert_eq "$desc (rc)" 1 "$rc"
  assert_eq "$desc (no PATCH)" 0 "$(patches)"
  assert_eq "$desc (temp dir gone)" "$before" "$after"
  if [ "${1:-}" = nocalls ]; then
    assert_eq "$desc (no gh call)" 0 "$(calls "$glog")"
    assert_eq "$desc (no git call)" 0 "$(calls "$gitlog")"
  fi
}
expect_mismatch() {
  assert_eq "$desc (word)" mismatch "$out"
  assert_eq "$desc (rc)" 1 "$rc"
  assert_eq "$desc (one PATCH)" 1 "$(patches)"
  assert_eq "$desc (one read-back after it)" 1 "$(grep -c '^api|repos/acme/backlog/milestones/19|--jq|' "$glog" || true)"
  assert_eq "$desc (read-back is the last call)" 1 "$(tail -n 1 "$glog" | grep -c '^api|repos/acme/backlog/milestones/19|--jq|' || true)"
  assert_eq "$desc (temp dir gone)" "$before" "$after"
}

# -- success -----------------------------------------------------------------------------
d="$(newdir)"
f="$(mkfile "$d")"
desc="valid call, file ends in a newline"
run 19 "$f"
expect_ok
assert_eq "$desc (exactly one PATCH)" 1 "$(patches)"
assert_eq "$desc (PATCH argv exact)" 'api|-X|PATCH|repos/acme/backlog/milestones/19|-F|description=@-|' "$(grep '^api|-X|PATCH|' "$glog")"
assert_eq "$desc (one read-back)" 1 "$(grep -c '^api|repos/acme/backlog/milestones/19|--jq|' "$glog" || true)"
assert_eq "$desc (no title, state or due_on)" 0 "$(grep -c 'title=\|state=\|due_on=' "$glog" || true)"
assert_eq "$desc (stored bytes equal the file)" yes "$(cmp -s "$f" "$store" && echo yes || echo no)"
assert_eq "$desc (git calls)" "rev-parse|--show-toplevel|
-C|$top|config|--get-all|remote.origin.url|
-C|$top|remote|get-url|origin|" "$("$real_cat" "$gitlog")"
assert_eq "$desc (full gh log)" "repo|view|https://example.test/acme/repo.git|--json|nameWithOwner|--jq|.nameWithOwner|
repo|view|https://example.test/acme/repo.git|--json|defaultBranchRef|--jq|.defaultBranchRef.name // \"\"|
api|-H|Accept: application/vnd.github.raw|repos/acme/repo/contents/.ai/project.yml?ref=main|
api|-X|PATCH|repos/acme/backlog/milestones/19|-F|description=@-|
api|repos/acme/backlog/milestones/19|--jq|.description // empty|" "$("$real_cat" "$glog")"

d="$(newdir)"
f="$(mkfile "$d" 19 'no trailing newline')"
desc="valid call, file without a trailing newline"
run 19 "$f"
expect_ok
assert_eq "$desc (stored bytes equal the file)" yes "$(cmp -s "$f" "$store" && echo yes || echo no)"

d="$(newdir)"
f="$(mkfile "$d" 7)"
desc="another milestone number"
run 7 "$f"
expect_ok
assert_eq "$desc (endpoint)" 1 "$(grep -c '^api|-X|PATCH|repos/acme/backlog/milestones/7|' "$glog" || true)"

d="$(newdir)"
f="$(mkfile "$d")"
desc="backlog.repo null targets the origin repository"
FX_YML="$tmp/nullbacklog.yml" run 19 "$f"
assert_eq "$desc (word)" ok "$out"
assert_eq "$desc (target)" 1 "$(grep -c '^api|-X|PATCH|repos/acme/repo/milestones/19|' "$glog" || true)"

d="$(newdir)"
f="$(mkfile "$d")"
desc="repo and backlog compare case-insensitively"
FX_YML="$tmp/casebacklog.yml" run 19 "$f"
assert_eq "$desc (word)" ok "$out"

desc="a working tree's own project.yml is ignored"
run 19 "$f"
assert_eq "$desc (target is the served copy's)" 2 "$(grep -c 'repos/acme/backlog/milestones/19' "$glog" || true)"
assert_eq "$desc (no tree target)" 0 "$(grep -c 'elsewhere' "$glog" || true)"
assert_eq "$desc (no fetch)" 0 "$(grep -c 'fetch' "$gitlog" || true)"

d="$(newdir)"
f="$(mkfile "$d")"
d2="$(newdir)"
f2="$(mkfile "$d2")"
desc="a .. path that resolves to a valid scratch file"
run 19 "$d/../$(basename "$d2")/description-m19.txt"
expect_ok

case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*)
    sm="$(cygpath -m "$scratch")"
    d="$(TMPDIR="$sm" mktemp -d)"
    f="$(mkfile "$d")"
    desc="Git Bash: a drive-letter path as mktemp -d prints it"
    XTMP="$sm" run 19 "$f"
    expect_ok
    ;;
  *) echo "SKIP - drive-letter path fixture is Git Bash only" ;;
esac

# -- refused, nothing sent, no call ------------------------------------------------------
d="$(newdir)"
f="$(mkfile "$d")"
for m in abc 0 012 -1 '' '19 ' "$(printf '1\n9')"; do
  desc="milestone [$(printf '%s' "$m" | tr '\n' '~')]"
  run "$m" "$f"
  expect_refused nocalls
done

desc="relative path"
run 19 "$(basename "$d")/description-m19.txt"
expect_refused nocalls

desc="a // path (a network share on MSYS)"
run 19 "/$f"
expect_refused nocalls
assert_eq "$desc (reason)" "milestone-desc.sh: refused: file path must be a plain absolute path" "$err"
desc="a path holding a backslash"
run 19 "$scratch/tmp.a\\b/description-m19.txt"
expect_refused nocalls

desc="a TMPDIR holding a backslash"
XTMP='C:\x' run 19 "C:\x/tmp.a/description-m19.txt"
expect_refused nocalls
assert_eq "$desc (reason)" "milestone-desc.sh: refused: file path must be a plain absolute path" "$err"

desc="a /proc/sys network-namespace path"
run 19 "/proc/sys/??/UNC/host/share/tmp.a/description-m19.txt"
expect_refused nocalls
assert_eq "$desc (reason)" "milestone-desc.sh: refused: file is not spelled under the scratch root" "$err"
desc="a path not spelled under the root string"
run 19 "$scratch/../scratch/$(basename "$d")/description-m19.txt"
expect_refused nocalls
assert_eq "$desc (reason)" "milestone-desc.sh: refused: file is not spelled under the scratch root" "$err"
desc="a .. segment before the scratch directory"
run 19 "$scratch/../proc/tmp.a/description-m19.txt"
expect_refused nocalls
assert_eq "$desc (reason)" "milestone-desc.sh: refused: file is not spelled under the scratch root" "$err"

d="$(newdir)"
if ln -s //nohost.invalid/share "$scratch/tmp.unc" 2>/dev/null && [ -L "$scratch/tmp.unc" ]; then
  desc="a tmp.* link spelled in the path is refused before any cd"
  run 19 "$scratch/tmp.unc/description-m19.txt"
  expect_refused nocalls
  assert_eq "$desc (the segment check refused it)" "milestone-desc.sh: refused: a scratch directory segment is a symbolic link" "$err"
  desc="a tmp.* link reached through a .. pair"
  run 19 "$d/../tmp.unc/description-m19.txt"
  expect_refused nocalls
  assert_eq "$desc (the segment check refused it)" "milestone-desc.sh: refused: a scratch directory segment is a symbolic link" "$err"
else
  echo "SKIP - link-before-cd fixture needs ln -s to make a real link"
fi
rm -f "$scratch/tmp.unc"

mkdir -p "$co/tmp.abc"
desc="file in the checkout"
run 19 "$(mkfile "$co/tmp.abc")"
expect_refused nocalls

desc="file directly in TMPDIR"
run 19 "$(mkfile "$scratch")"
expect_refused nocalls
rm -f "$scratch/description-m19.txt"

mkdir -p "$d/sub"
desc="file two directories down"
run 19 "$(mkfile "$d/sub")"
expect_refused nocalls

mkdir -p "$scratch/other" "$scratch/tmp.a-b"
desc="directory not named tmp.*"
run 19 "$(mkfile "$scratch/other")"
expect_refused nocalls
desc="directory named tmp. with a dash"
run 19 "$(mkfile "$scratch/tmp.a-b")"
expect_refused nocalls

d="$(newdir)"
f20="$(mkfile "$d" 20)"
desc="file named for another milestone"
run 19 "$f20"
expect_refused nocalls
printf 'x\n' >"$d/description-new1.txt"
desc="description-new1.txt"
run 19 "$d/description-new1.txt"
expect_refused nocalls
printf 'x\n' >"$d/read-milestone-19.txt"
desc="read-milestone-19.txt"
run 19 "$d/read-milestone-19.txt"
expect_refused nocalls

d="$(newdir)"
mkdir "$d/description-m19.txt"
desc="a directory"
run 19 "$d/description-m19.txt"
expect_refused nocalls

d="$(newdir)"
desc="missing file"
run 19 "$d/description-m19.txt"
expect_refused nocalls
: >"$d/description-m19.txt"
desc="empty file"
run 19 "$d/description-m19.txt"
expect_refused nocalls

d="$(newdir)"
target="$tmp/outside/real.txt"
printf 'text\n' >"$target"
if ln -s "$target" "$d/description-m19.txt" 2>/dev/null && [ -L "$d/description-m19.txt" ]; then
  desc="a correctly named symlink pointing elsewhere"
  run 19 "$d/description-m19.txt"
  expect_refused nocalls
else
  echo "SKIP - symlink fixture needs ln -s to make a real link (Git Bash copies)"
fi

mkdir -p "$tmp/outside/real"
printf 'text\n' >"$tmp/outside/real/description-m19.txt"
if ln -s "$tmp/outside/real" "$scratch/tmp.link" 2>/dev/null && [ -L "$scratch/tmp.link" ]; then
  desc="a tmp.* symlink resolving outside TMPDIR"
  run 19 "$scratch/tmp.link/description-m19.txt"
  expect_refused nocalls
else
  echo "SKIP - symlinked-directory fixture needs ln -s to make a real link (Git Bash copies)"
fi

mkdir -p "$tmp/outside/dotdot"
printf 'text\n' >"$tmp/outside/dotdot/description-m19.txt"
d="$(newdir)"
desc="a .. path resolving outside TMPDIR"
run 19 "$d/../../outside/dotdot/description-m19.txt"
expect_refused nocalls

d="$(newdir)"
f="$(mkfile "$d")"
if ln "$f" "$tmp/outside/second-link" 2>/dev/null && [ "$(find "$f" -links 2 2>/dev/null)" = "$f" ]; then
  desc="a hard link with two links"
  run 19 "$f"
  expect_refused nocalls
else
  echo "SKIP - hard-link fixture: the link count does not read 2 here"
fi

# -- refused after the repository reads --------------------------------------------------
d="$(newdir)"
f="$(mkfile "$d")"
desc="served copy names another repository"
FX_YML="$tmp/otherrepo.yml" run 19 "$f"
expect_refused
for n in a_b_c ___x owner other_backlog; do
  desc="backlog.repo shape $n"
  FX_YML="$tmp/bl-$n.yml" run 19 "$f"
  expect_refused
done
desc="empty nameWithOwner"
FX_NWO= run 19 "$f"
expect_refused
desc="failing repo view"
FX_VIEW_FAIL=1 FX_ECHO=1 run 19 "$f"
expect_refused
desc="empty default branch"
FX_DEF= run 19 "$f"
expect_refused
desc="default branch holding &"
FX_DEF='a&b' run 19 "$f"
expect_refused
desc="default branch holding #"
FX_DEF='a#b' run 19 "$f"
expect_refused
desc="failing contents read"
FX_YML="$tmp/missing.yml" run 19 "$f"
expect_refused

co="$tmp/co2"
mkco "$co"
"$real_git" -C "$co" config --add remote.origin.url https://example.test/acme/second.git
desc="second remote.origin.url value"
run 19 "$f"
expect_refused
assert_eq "$desc (no gh call)" 0 "$(calls "$glog")"

co="$tmp/co3"
mkco "$co"
"$real_git" -C "$co" config url.https://rewritten.test/.insteadOf https://example.test/
desc="url.<x>.insteadOf rewriting origin"
run 19 "$f"
expect_refused
assert_eq "$desc (no gh call)" 0 "$(calls "$glog")"

co="$tmp/co4"
mkco "$co"
"$real_git" -C "$co" config remote.origin.url -evil
desc="origin url beginning with a dash"
run 19 "$f"
expect_refused
assert_eq "$desc (no gh call)" 0 "$(calls "$glog")"
co="$tmp/co"

d="$(newdir)"
f="$(mkfile "$d")"
desc="a file swapped during the copy"
FX_SWAP_TARGET="$(cd -P "$d" && pwd -P)/description-m19.txt" XPATH="$swapbin:$fakebin" run 19 "$f"
expect_refused


desc="a [bot] suffix on .repo is folded away"
printf 'repo: acme/repo[bot]\nbacklog:\n  repo: acme/backlog\n' >"$tmp/bot.yml"
FX_YML="$tmp/bot.yml" run 19 "$f"
assert_eq "$desc (word)" ok "$out"
desc="served copy with no .repo"
printf 'backlog:\n  repo: acme/backlog\n' >"$tmp/norepo.yml"
FX_YML="$tmp/norepo.yml" run 19 "$f"
expect_refused
d="$(newdir)"
f="$(mkfile "$d")"
desc="a file emptied in place during the copy"
FX_SWAP_MODE=trunc FX_SWAP_TARGET="$(cd -P "$d" && pwd -P)/description-m19.txt" XPATH="$swapbin:$fakebin" run 19 "$f"
expect_refused

# -- mismatch ----------------------------------------------------------------------------
d="$(newdir)"
f="$(mkfile "$d")"
desc="a failing PATCH (bytes stored first)"
FX_PATCH_RC=1 FX_ECHO=1 run 19 "$f"
expect_mismatch
desc="a failing read-back"
FX_BACK=fail FX_ECHO=1 run 19 "$f"
expect_mismatch
desc="a read-back differing by one byte"
FX_BACK=alt run 19 "$f"
expect_mismatch
desc="a read-back missing the appended newline"
FX_BACK=nonl run 19 "$f"
expect_mismatch

# -- usage -------------------------------------------------------------------------------
d="$(newdir)"
f="$(mkfile "$d")"
urun() {
  : >"$glog"; : >"$gitlog"
  rc=0
  out="$(cd "$co" && PATH="$fakebin:$PATH" TMPDIR="$scratch" sh "$script" "$@" 2>/dev/null)" || rc=$?
  assert_eq "usage [$*] (rc)" 2 "$rc"
  assert_eq "usage [$*] (stdout empty)" "" "$out"
  assert_eq "usage [$*] (no gh call)" 0 "$(calls "$glog")"
  assert_eq "usage [$*] (no git call)" 0 "$(calls "$gitlog")"
}
urun
urun write 19
urun write 19 "$f" extra
urun read 19 "$f"

if [ "$fail" -eq 0 ]; then
  echo "all milestone-desc.sh tests passed"
else
  exit 1
fi
