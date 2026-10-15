#!/bin/sh
# A checked writer for ONE milestone's description: replace it with the contents of one scratch
# file, then read it back.
#
# Usage: milestone-desc.sh write <milestone> <file>
#
# Prints exactly one word on stdout:
#   ok        exit 0 -- the PATCH succeeded and the read-back equals what was sent
#   refused   exit 1 -- a check failed and nothing was sent
#   mismatch  exit 1 -- a PATCH was attempted and not confirmed: a non-zero PATCH exit (whatever
#                       the read-back shows), a failed read-back, or a read-back that differs
# `refused` and `mismatch` add a one-line reason on stderr, this script's own fixed text. Any
# other argument count, or a first argument other than `write`, prints a usage line on stderr and
# nothing on stdout, makes no `git` or `gh` call, and exits 2. The stdout and stderr of every
# `git` and `gh` call go to /dev/null or to a file in this script's own temp directory, so neither
# stream ever carries the file's content, the description, `gh`'s response or a remote URL.
#
# Who calls it: plan-sprint's Apply & stage step (#639). Why it exists: a description
# write made live is refused by an auto-mode classifier that refuses `gh api` writes to an org's
# repositories, and the plan anchor no longer binds the description (`WB-D27`, `#628`), so a live
# write is safe for the anchor. This is the one narrow, checked form for it.
#
# No allow rule names it, and none should be added without the decision `WB-D28` records: a rule
# on a command name runs whatever file of that name comes first on PATH, and would approve the
# call without the classifier or a human seeing the text or the PATCH.
#
# What the checks bound: the method (PATCH), the one field (`description`; never `title`, `state`
# or `due_on`), the endpoint's shape, the file's name and shape, and the target's owner. They do
# not bound the description's text, which is the caller's, or the token that acts, which is the
# caller's environment's. Residuals, each accepted:
#   - the text can be anything a session put in a correctly named scratch file;
#   - the target is the backlog of whichever checkout this runs in, limited to the owner of that
#     checkout's `origin`; a rewritten `remote.origin.url` redirects the repository read, and a
#     planted `insteadOf` or a second URL is refused, which also refuses a legitimate checkout
#     whose `origin` is rewritten by a system-wide `insteadOf`;
#   - a process already running can swap the file between the checks and the copy; the recheck
#     after the copy narrows that to a double swap and does not close it, and on a volume without
#     stable file IDs it may not see a swap at all;
#   - the scratch root comes from the caller's TMPDIR, so the root check is a convention filter,
#     not a boundary: the name, link and inode rules carry the weight;
#   - the GitHub host is not pinned: `gh repo view` takes it from the origin URL, while the other
#     `gh api` calls use the caller's default host or GH_HOST;
#   - callers should spell the file's path literally, since a permission rule may not cover a
#     command that expands a variable.
#
# <milestone> is a decimal number with no leading zero. <file> is absolute and is
# `<root>/<d>/description-m<milestone>.txt`: `<root>` is ${TMPDIR:-/tmp} and `<d>` is `tmp.` plus
# letters and digits, the shape a bare `mktemp -d` makes, both resolved with `cd -P`/`pwd -P`. It
# is spelled, before anything is opened, as the caller's own TMPDIR string, one such `<d>` segment and
# only `..`/`<d>` pairs after it; it is not a symbolic link, is a regular file, is not empty and has
# exactly one link. The scratch root itself is opened as given (TMPDIR is the caller's). Shape checks
# use `case`, never `grep`, so an embedded newline cannot pass a line-by-line match.
#
# The repository: the checkout's `origin` (one `remote.origin.url` value, equal to `git remote
# get-url origin`, not beginning with `-`) names `nameWithOwner`; the DEFAULT branch's committed
# `.ai/project.yml`, read over the API and never from an argument, the working tree or a fetch,
# must name that repository in `.repo`, and its `.backlog.repo` (null or absent means
# `nameWithOwner`) must be owner/name with the same owner. The PATCH goes to that backlog.
#
# There is no environment override of `gh`, `git` or `yq`; the tests put stubs first on PATH.
#
# Permitted toolset: POSIX sh, `git`, `gh` (only its embedded --jq), `yq` (mikefarah v4),
# `mktemp`, `cat`, `cmp`, `find`, `ls`, `tr`, `sed`, `uname`, `rm`, `pwd`. No system `jq`, no python.
set -eu

if [ "$#" -ne 3 ] || [ "$1" != write ]; then
  echo "usage: milestone-desc.sh write <milestone> <file>" >&2
  exit 2
fi
ms="$2"
file="$3"

tmp=
cleanup() { [ -z "$tmp" ] || rm -rf "$tmp"; }
trap cleanup EXIT

refuse() {
  echo "milestone-desc.sh: refused: $1" >&2
  echo refused
  exit 1
}
mismatch() {
  echo "milestone-desc.sh: mismatch: $1" >&2
  echo mismatch
  exit 1
}

# --- 1. the milestone ---------------------------------------------------------------
case "$ms" in
  '' | 0* | *[!0-9]*) refuse "milestone must be a decimal number with no leading zero" ;;
esac

# --- 2. the file ----------------------------------------------------------------------
case "$file" in
  # `//host/share` is a network share on MSYS, and a backslash is a path separator there:
  # refused on the raw string, before any `cd` could open either.
  //* | *\\*) refuse "file path must be a plain absolute path" ;;
  /*) : ;;
  [A-Za-z]:/*)
    case "$(uname -s 2>/dev/null | tr 'a-z' 'A-Z')" in
      MSYS* | MINGW* | CYGWIN*) : ;;
      *) refuse "file path must be absolute" ;;
    esac
    ;;
  *) refuse "file path must be absolute" ;;
esac
base="${file##*/}"
dir="${file%/*}"
[ -n "$dir" ] || dir=/
[ "$base" = "description-m$ms.txt" ] || refuse "file name must be description-m$ms.txt"
# The raw string is checked BEFORE any `cd` opens it: on MSYS a path such as
# `/proc/sys/??/UNC/<host>/<share>` is a network share that `cd -P` would open before any
# later check refused it. So the directory must be spelled as the caller's own root, then one
# `tmp.<alnum>` segment, then only `..` / `tmp.<alnum>` pairs. The resolved checks below still run.
rawroot="${TMPDIR:-/tmp}"
while :; do case "$rawroot" in ?*/) rawroot="${rawroot%/}" ;; *) break ;; esac; done
case "$dir" in
  "$rawroot"/tmp.*) rest="${dir#"$rawroot"/}" ;;
  *) refuse "file is not spelled under the scratch root" ;;
esac
while :; do
  seg="${rest%%/*}"
  case "$seg" in
    tmp.?*) case "${seg#tmp.}" in *[!A-Za-z0-9]*) refuse "scratch directory is not named like mktemp -d" ;; esac ;;
    *) refuse "file is not spelled under the scratch root" ;;
  esac
  [ ! -L "$rawroot/$seg" ] || refuse "a scratch directory segment is a symbolic link"
  [ "$rest" != "$seg" ] || break
  rest="${rest#*/}"
  case "$rest" in
    ../*) rest="${rest#../}" ;;
    *) refuse "file is not spelled under the scratch root" ;;
  esac
done
rd="$(cd -P "$dir" 2>/dev/null && pwd -P)" || refuse "file directory is not readable"
rroot="$(cd -P "${TMPDIR:-/tmp}" 2>/dev/null && pwd -P)" || refuse "scratch root is not readable"
[ -n "$rd" ] && [ -n "$rroot" ] || refuse "scratch directory unresolved"
case "$rd" in
  "$rroot"/tmp.*)
    d="${rd#"$rroot"/}"
    case "$d" in */*) refuse "file must be directly in a scratch directory" ;; esac
    case "${d#tmp.}" in '' | *[!A-Za-z0-9]*) refuse "scratch directory is not named like mktemp -d" ;; esac
    ;;
  *) refuse "file is not in a scratch directory under the scratch root" ;;
esac
canon="$rd/$base"
[ ! -L "$canon" ] || refuse "file is a symbolic link"
[ -f "$canon" ] || refuse "file is not a regular file"
[ -s "$canon" ] || refuse "file is empty"
[ "$(find "$canon" -links 1 2>/dev/null)" = "$canon" ] || refuse "file must have exactly one link"

tmp="$(mktemp -d)" || refuse "no temp directory"

# --- 3. the repository ----------------------------------------------------------------
git rev-parse --show-toplevel >"$tmp/top" 2>/dev/null || refuse "not in a git checkout"
IFS= read -r top <"$tmp/top" || [ -n "$top" ] || refuse "not in a git checkout"
[ -n "$top" ] || refuse "not in a git checkout"
git -C "$top" config --get-all remote.origin.url >"$tmp/urls" 2>/dev/null || refuse "origin has no single url"
git -C "$top" remote get-url origin >"$tmp/url" 2>/dev/null || refuse "origin has no url"
u1= u2= url=
{
  IFS= read -r u1 || [ -n "$u1" ] || true
  if IFS= read -r u2; then refuse "origin has more than one url"; fi
} <"$tmp/urls"
IFS= read -r url <"$tmp/url" || [ -n "$url" ] || true
[ -n "$u1" ] && [ "$u1" = "$url" ] || refuse "origin url is rewritten or absent"
case "$url" in -*) refuse "origin url begins with a dash" ;; esac

gh repo view "$url" --json nameWithOwner --jq .nameWithOwner >"$tmp/nwo" 2>/dev/null || refuse "repository not readable"
gh repo view "$url" --json defaultBranchRef --jq '.defaultBranchRef.name // ""' >"$tmp/def" 2>/dev/null || refuse "default branch not readable"
nwo= def=
IFS= read -r nwo <"$tmp/nwo" || [ -n "$nwo" ] || true
IFS= read -r def <"$tmp/def" || [ -n "$def" ] || true

valid_repo() { # valid_repo <s> -- owner/name, the rule spec-task's Fetch and check block applies
  case "$1" in
    '' | *[!A-Za-z0-9._/-]* | */*/* | /* | */ | ./* | ../* | */. | */..) return 1 ;;
    */*) return 0 ;;
    *) return 1 ;;
  esac
}
fold() { printf '%s' "$1" | tr 'A-Z' 'a-z' | sed 's/\[bot\]$//'; }

valid_repo "$nwo" || refuse "repository name is not owner/name"
case "$def" in '' | -* | *[!A-Za-z0-9._/-]*) refuse "default branch name is unusable" ;; esac

gh api -H 'Accept: application/vnd.github.raw' "repos/$nwo/contents/.ai/project.yml?ref=$def" >"$tmp/project.yml" 2>/dev/null \
  || refuse "default branch project.yml not readable"
yrepo="$(yq -r '.repo // ""' "$tmp/project.yml" 2>/dev/null)" || refuse "project.yml not readable"
[ -n "$yrepo" ] && [ "$(fold "$yrepo")" = "$(fold "$nwo")" ] || refuse "project.yml names another repository"
backlog="$(yq -r '.backlog.repo // ""' "$tmp/project.yml" 2>/dev/null)" || refuse "project.yml not readable"
[ -n "$backlog" ] || backlog="$nwo"
valid_repo "$backlog" || refuse "backlog repository is not owner/name"
[ "$(fold "${backlog%%/*}")" = "$(fold "${nwo%%/*}")" ] || refuse "backlog repository has another owner"

# --- 4. the copy ------------------------------------------------------------------------
ino1="$(ls -di "$canon" 2>/dev/null)" || refuse "file not readable"
ino1="${ino1%% *}"
cat "$canon" >"$tmp/desc" 2>/dev/null || refuse "file not readable"
ino2="$(ls -di "$canon" 2>/dev/null)" || refuse "file changed during the copy"
ino2="${ino2%% *}"
[ ! -L "$canon" ] && [ -f "$canon" ] && [ "$(find "$canon" -links 1 2>/dev/null)" = "$canon" ] \
  && [ -n "$ino1" ] && [ "$ino1" = "$ino2" ] && [ -s "$tmp/desc" ] || refuse "file changed during the copy"

# --- 5. the write and the read-back ----------------------------------------------------
patched=0
gh api -X PATCH "repos/$backlog/milestones/$ms" -F description=@- <"$tmp/desc" >"$tmp/patch.out" 2>"$tmp/patch.err" || patched=1
gh api "repos/$backlog/milestones/$ms" --jq '.description // empty' >"$tmp/back" 2>/dev/null \
  || mismatch "read-back failed"
[ "$patched" -eq 0 ] || mismatch "PATCH failed"
# `gh --jq` adds one newline to a string result; compare against the copy plus exactly one.
{ cat "$tmp/desc"; printf '\n'; } >"$tmp/want"
cmp -s "$tmp/want" "$tmp/back" || mismatch "read-back differs"
echo ok
