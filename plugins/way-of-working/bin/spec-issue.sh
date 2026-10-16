#!/bin/sh
# Fetch ONE task issue for spec-task and decide whether its author is trusted, before anything of
# the issue's text is read.
#
# Usage: spec-issue.sh fetch <N> <out-dir>
#
# Who calls it: spec-task's *Fetch and check* step. Why it exists: that step was about thirty
# lines of shell inside SKILL.md, retyped by a model on every run and tested by nothing (#627
# item 7, child (a) is #659). It is now one tested command, with fixtures, like the other bin/
# predicates. The trust decisions did not change: the same reads, a stop on every input the
# block stopped on, and a pass for every author GitHub can return that the block passed.
#
# Output. On a pass, exactly one line on stdout and exit 0:
#   ok B=<backlog-repo> BASE=<base> VERDICT=<verdict> ASSOC=<association>
# and `<out-dir>/issue.json` holds the issue. On a stop, exactly one word on stdout and exit 1,
# the first that applies:
#   unreadable     a read, a check or a copy failed, or a value was not the shape expected
#   repo-mismatch  the default branch's project.yml `.repo` is not the origin's repository
#   bad-backlog    `backlog.repo` (null or absent means the origin's repository) is not owner/name
#   bad-base       `pr_base` is empty, begins with `-` or holds an unusual character
#   unreachable    the backlog's `.permissions` read or the issue fetch failed
#   not-an-issue   the response has a `pull_request` key
#   loop-identity  the author is `orchestration.loop_identity`, before any trust check
#   untrusted      the author is not trusted. It also covers a config `gh-identity.sh` could not
#                  judge (exit 2: a malformed `identities`, an id declared twice), so the word can
#                  mean a broken config, not only a hostile author.
# Nothing is written to stderr on a stop. Any other argument count, a first argument other than
# `fetch`, a bad <N> or <out-dir>, a slash-less $0 or a missing sibling gh-identity.sh prints a
# usage line (or, for the last two, a one-line diagnostic) on stderr and nothing on stdout, and exits 2,
# before any `gh` call. So does a run outside
# a git work tree, where `git rev-parse --show-toplevel` fails.
#
# Three changes from the old block, each in the safe direction: the stop reasons are fixed words
# (the skill prints `stopped: <word>`); the `.permissions` JSON and `gh`'s own error text no
# longer reach the transcript; and some inputs the block read unchecked are validated -- the
# origin URL beginning with `-`, the default branch name, and the response's field types and
# association -- and a malformed response stops as `unreadable` before any other word, so a pull
# request with a malformed `user` reads `unreadable` where it read `not-an-issue`; both stop.
#
# Arguments. <N> matches ^[1-9][0-9]*$. <out-dir> is absolute (`/...`, or, only when uname reports
# MSYS, MINGW or CYGWIN, `[A-Za-z]:/...`), exists, is a directory, is not itself a symbolic link
# and is empty; it is resolved with `cd -P`/`pwd -P` and the resolved path is used from there on.
# That path must not be the repository's top level or inside it (both in `pwd -P` form). The
# contract is that <out-dir> is the CALLER'S OWN PRIVATE directory, a fresh `mktemp -d`: this
# script does not check ownership or mode, which Git Bash on NTFS does not report reliably.
#
# What it never prints: the issue body or title, `gh` responses or error text, `yq` or
# `gh-identity.sh` stderr, and remote URLs. Every `git`, `gh`, `yq` and `gh-identity.sh` call's
# output goes to /dev/null or to a file in this script's own temp directory. No `gh` output is
# piped into a predicate: it is captured to a file first and a failed call stops before the
# predicate runs (the rule invariants check 11 enforces in skills; it does not scan bin/, so this
# header states it as part of the script's contract). `gh api` is GET only: no -X, -f, -F, --field,
# --raw-field or --input, and no graphql.
#
# `issue.json` appears only through the final rename, after every check passed, so no stop leaves
# one. A signal landing between the rename and the `ok` line leaves a passing author's file with no
# `ok` line, which the caller never reads, since it reads issue.json only after `ok`.
#
# Residuals, each accepted:
#   - on NTFS `pwd -P` keeps the caller's letter case, so an in-repo <out-dir> spelled in other
#     case passes the inside-the-repo check; not reachable from a fresh `mktemp -d`;
#   - something able to write in <out-dir> could plant a directory, or a symlink to one, at `issue.json`
#     (a symlink makes `mv` move the issue JSON into its target, outside <out-dir>) between the final
#     check and the `mv`; not reachable from a fresh `mktemp -d`;
#   - <out-dir> is checked against the work tree's top level only, so in a linked worktree an empty
#     directory under git's own data would pass; not reachable from a fresh `mktemp -d`;
#   - the GitHub host is not pinned: `gh repo view` takes it from the origin URL, while `gh api`
#     uses the default host or GH_HOST (the residual milestone-desc.sh records).
#
# There is no environment override of `gh`, `git` or `yq`; the tests put stubs first on PATH.
# gh-identity.sh is found as `$(dirname "$0")/gh-identity.sh` only, and run as `sh`.
#
# Permitted toolset: POSIX sh, `git`, `gh` (its embedded --jq allowed), `yq` (mikefarah v4, always
# `-p=json` on JSON), `tr`, `sed`, `mktemp`, `cp`, `mv`, `rm`, `dirname`, `uname` and `ls`. No
# system `jq`. A missing `yq` is `unreadable`.
set -eu

usage() {
  echo "usage: spec-issue.sh fetch <N> <out-dir>" >&2
  exit 2
}
[ "$#" -eq 3 ] && [ "$1" = fetch ] || usage
n="$2"
out="$3"

case "$n" in
  '' | 0* | *[!0-9]*) usage ;;
esac

case "$0" in
  */*) gi="$(dirname "$0")/gh-identity.sh" ;;
  *)
    echo "spec-issue.sh: must be run by path (a slash-less \$0 cannot locate gh-identity.sh)" >&2
    exit 2
    ;;
esac
[ -f "$gi" ] || {
  echo "spec-issue.sh: gh-identity.sh not beside this script" >&2
  exit 2
}

# --- the out-dir --------------------------------------------------------------------------
case "$out" in
  //* | *\\*) usage ;;
  /*) : ;;
  [A-Za-z]:/*)
    case "$(uname -s 2>/dev/null | tr 'a-z' 'A-Z')" in
      MSYS* | MINGW* | CYGWIN*) : ;;
      *) usage ;;
    esac
    ;;
  *) usage ;;
esac
[ -d "$out" ] && [ ! -L "$out" ] || usage
ls -A "$out" >/dev/null 2>&1 || usage
[ -z "$(ls -A "$out" 2>/dev/null)" ] || usage
out="$(cd -P "$out" 2>/dev/null && pwd -P)" || usage
[ -n "$out" ] || usage
gtop="$(git rev-parse --show-toplevel 2>/dev/null)" || usage
[ -n "$gtop" ] || usage
top="$(cd -P "$gtop" 2>/dev/null && pwd -P)" || usage
[ -n "$top" ] || usage
case "$out" in
  "$top" | "$top"/*) usage ;;
esac

# --- from here, a stop is a word ----------------------------------------------------------
tmp=
itmp=
cleanup() {
  [ -z "$itmp" ] || rm -f "$itmp"
  [ -z "$tmp" ] || rm -rf "$tmp"
}
trap cleanup EXIT
stop() {
  echo "$1"
  exit 1
}

tmp="$(mktemp -d 2>/dev/null)" && [ -n "$tmp" ] || {
  tmp=
  stop unreadable
}
command -v yq >/dev/null 2>&1 || stop unreadable

fold() { printf '%s' "$1" | tr 'A-Z' 'a-z' | sed 's/\[bot\]$//'; }
# rd <file> -- the first line of a file, or nothing.
rd() { _l=; IFS= read -r _l <"$1" || [ -n "$_l" ] || true; printf '%s' "$_l"; }

# 1. the origin's URL
git -C "$gtop" remote get-url origin >"$tmp/url" 2>/dev/null || stop unreadable
url="$(rd "$tmp/url")"
[ -n "$url" ] || stop unreadable
case "$url" in -*) stop unreadable ;; esac

# 2. the repository and its default branch
gh repo view "$url" --json nameWithOwner --jq .nameWithOwner >"$tmp/nwo" 2>/dev/null || stop unreadable
gh repo view "$url" --json defaultBranchRef --jq '.defaultBranchRef.name // ""' >"$tmp/def" 2>/dev/null || stop unreadable
nwo="$(rd "$tmp/nwo")"
def="$(rd "$tmp/def")"
case "$nwo" in
  '' | *[!A-Za-z0-9._/-]* | */*/* | /* | */ | ./* | ../* | */. | */.. | -*) stop unreadable ;;
  */*) : ;;
  *) stop unreadable ;;
esac
case "$def" in '' | -* | *[!A-Za-z0-9._/-]*) stop unreadable ;; esac

# 3. the default branch's committed project.yml; the working tree's copy is never read
git -C "$gtop" fetch -q origin "+refs/heads/$def:refs/remotes/origin/$def" >/dev/null 2>&1 || stop unreadable
git -C "$gtop" show "refs/remotes/origin/$def:./.ai/project.yml" >"$tmp/def.yml" 2>/dev/null || stop unreadable

# 4. the repo it names
yrepo="$(yq -r '.repo // ""' "$tmp/def.yml" 2>/dev/null)" || stop unreadable
[ "$(fold "$yrepo")" = "$(fold "$nwo")" ] || stop repo-mismatch

# 5. the backlog repo: null or absent is the origin's repository (gh's nameWithOwner)
backlog="$(yq -r '.backlog.repo // ""' "$tmp/def.yml" 2>/dev/null)" || stop unreadable
backlog="${backlog:-$nwo}"
case "$backlog" in
  '' | *[!A-Za-z0-9._/-]* | */*/* | /* | */ | ./* | ../* | */. | */..) stop bad-backlog ;;
  */*) : ;;
  *) stop bad-backlog ;;
esac

# 6. the base
base="$(yq -r '.pr_base // ""' "$tmp/def.yml" 2>/dev/null)" || stop unreadable
case "$base" in '' | -* | *[!A-Za-z0-9._/-]*) stop bad-base ;; esac

# 7. reach: the permissions read, to a file and never printed
gh api "repos/$backlog" --jq .permissions >"$tmp/perm" 2>/dev/null || stop unreachable

# 8. the issue
gh api "repos/$backlog/issues/$n" >"$tmp/issue.json" 2>/dev/null || stop unreachable

# 9. type-check the response before any other word
J() { yq -p=json -o=yaml "$1" "$tmp/issue.json" 2>/dev/null; }
tags="$(J '[(.user.login | tag), (.user.id | tag), (.author_association | tag)] | join(",")')" || stop unreadable
[ "$tags" = '!!str,!!int,!!str' ] || stop unreadable
login="$(J '.user.login')" || stop unreadable
uid="$(J '.user.id')" || stop unreadable
assoc="$(J '.author_association')" || stop unreadable
case "$login" in '' | *[!]A-Za-z0-9_[-]*) stop unreadable ;; esac
case "$uid" in '' | *[!0-9]*) stop unreadable ;; esac
case "$assoc" in '' | *[!ABCDEFGHIJKLMNOPQRSTUVWXYZ_]*) stop unreadable ;; esac

# 10. a pull request: the key's presence, not its truthiness
haspr="$(J 'has("pull_request")')" || stop unreadable
case "$haspr" in
  true) stop not-an-issue ;;
  false) : ;;
  *) stop unreadable ;;
esac

# 11. the loop's own login, before any trust check
loopid="$(yq -r '.orchestration.loop_identity // ""' "$tmp/def.yml" 2>/dev/null)" || stop unreadable
if [ -n "$loopid" ] && [ "$(fold "$login")" = "$(fold "$loopid")" ]; then stop loop-identity; fi

# 12. the author
rc=0
sh "$gi" author "$login" "$uid" "$tmp/def.yml" >"$tmp/verdict" 2>/dev/null || rc=$?
[ "$rc" -eq 0 ] || stop untrusted
verdict="$(rd "$tmp/verdict")"
case "$verdict/$assoc" in
  trusted/* | legacy/OWNER | legacy/MEMBER | legacy/COLLABORATOR) : ;;
  *) stop untrusted ;;
esac

# 13. only now write issue.json: a rename within the out-dir
if [ -e "$out/issue.json" ] || [ -L "$out/issue.json" ]; then stop unreadable; fi
itmp="$(mktemp "$out/.issue.XXXXXX" 2>/dev/null)" && [ -n "$itmp" ] || {
  itmp=
  stop unreadable
}
cp "$tmp/issue.json" "$itmp" 2>/dev/null || stop unreadable
mv "$itmp" "$out/issue.json" 2>/dev/null || {
  rm -f "$out/issue.json"
  stop unreadable
}
itmp=
[ -f "$out/issue.json" ] && [ ! -L "$out/issue.json" ] || stop unreadable
printf 'ok B=%s BASE=%s VERDICT=%s ASSOC=%s\n' "$backlog" "$base" "$verdict" "$assoc"
