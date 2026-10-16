#!/bin/sh
# Compose and post ONE spec comment on a task issue, as the declared dev App, or hold the
# composed comment for a human to post.
#
# Usage: spec-post.sh post <N> <sha> <draft-file> <out-dir>
#
# Who calls it: spec-task's *Post or hold* stage, after spec-shape.sh said `ok`. Why it exists:
# the skill used to hand its draft to the maintainer to post (WB-D26). It now posts it itself
# when the session acts as the declared dev App (WB-D29), and the composing, the marker and the
# one write live here, in one tested command, instead of in prose a model retypes. Approval does
# not move: a declared maintainer reacts to the posted comment on GitHub, and every reader of a
# dev-App spec already refuses it without that reaction. The marker line is a locator, never
# authority.
#
# Output. A pass is exactly one line on stdout and exit 0:
#   posted <id> <login> <html_url>
# A stop is exactly one word on stdout and exit 1, the first that applies, in the order the
# stages below run:
#   unreadable          a read, a check or a copy failed, or a value was not the shape expected
#   repo-mismatch       the default branch's project.yml `.repo` is not the origin's repository
#   bad-backlog         `backlog.repo` (null or absent means the origin's repository) is not owner/name
#   bad-base            `pr_base` is empty, begins with `-` or holds an unusual character
#   bad-sha             <sha> is not a commit on the tip of origin/<base> or behind it
#   bad-shape           spec-shape.sh check did not say `ok`
#   has-marker          a line of the draft begins with the marker's own prefix
#   leak                a line matches an obvious local-path or secret shape (a filter, not a boundary)
#   too-long            the composed body is over 65536 bytes
#   unreachable         the issue fetch failed
#   not-an-issue        the response has a `pull_request` key
#   closed              the issue is not open
#   locked              the issue is locked
#   loop-identity       the issue's author is `orchestration.loop_identity`
#   untrusted           the issue's author is not trusted (also a config gh-identity.sh could not judge)
#   post-unknown        the POST failed; it was made once and is never retried, so the comment may exist
#   posted-unreadable   the POST answered, but the response is not one this run can vouch for;
#                       the comment exists
# A hold is one line, `held <reason> <path>`, and exit 1; <path> is `<out-dir>/comment.md`, the
# composed comment, for a human to post verbatim. Reasons: `no-identities` (the default branch's
# `identities` is not a map), `actor-unreadable` (the viewer read failed) and `not-dev-app` (the
# acting account is not the declared dev App, or gh-identity.sh could not say). Nothing is
# written to stderr on a stop or a hold. A bad argument, a slash-less $0 or a missing sibling
# script prints a usage line (or a one-line diagnostic) on stderr and nothing on stdout, and
# exits 2, before any `gh` call.
#
# Stages, run in this order:
#   arguments    <N> matches ^[1-9][0-9]*$; <sha> is exactly 40 lowercase hex characters;
#                <draft-file> is absolute (`/...`, or, only when uname reports MSYS, MINGW or
#                CYGWIN, `[A-Za-z]:/...`), a regular, non-empty file and not a symbolic link, in
#                a directory that resolves (cd -P / pwd -P) outside the work tree; <out-dir> is
#                absolute in the same sense, an existing empty directory that is not a symbolic
#                link, outside the work tree.
#   copy         the draft is copied into this script's own mktemp directory; every later stage
#                reads only that copy, so a swap of the caller's file after this point changes nothing
#   default      the origin, default branch, committed project.yml, repo, backlog and base reads
#   commit       after a fetch of origin/<base>, <sha> must be a commit that `git merge-base
#                --is-ancestor` places on it. An ancestor is accepted, not only the tip, so a merge
#                during drafting does not force a redraft
#   content      shape, marker prefix, leak shapes and length, each on the copy
#   issue        the issue is fetched to a file and its author judged as spec-issue.sh judges it
#   compose      the body is the marker line, one empty line, then the copy byte for byte; it is
#                renamed into <out-dir>/comment.md. This is the only place the marker is written
#   hold         the comment is posted only when `identities` is a map and the acting account is
#                the declared dev App; otherwise it is held
#   post         the one write, with the body on standard input so gh is handed no path
#   response     the response is read back and must name this comment, this author and this issue
#
# What it never prints: the draft, the body, or `gh`'s output or error text. The POST is never
# retried.
#
# Residuals, each accepted:
#   - the default-branch reads (`gh repo view`) take the host from the origin URL; the issue
#     read, the viewer read and the write pin github.com, so those three share one host and one
#     credential;
#   - a `gh` call has no per-call timeout. A hang ends with no word, which the caller treats as
#     `post-unknown`;
#   - the leak shapes are a filter, not a boundary;
#   - the work-tree checks compare lowercased paths on every platform, so a differently cased alias is refused (it
#     fails closed); an 8.3 short name is not recognised. A <draft-file> or <out-dir> must be the
#     caller's own fresh mktemp -d: a planted entry or a linked worktree's git data is not checked;
#   - text paraphrased from an issue body whose author is trusted can have been edited by an
#     account with write access, and is posted.
#
# There is no environment override of `gh`, `git` or `yq`; the tests put stubs first on PATH.
# spec-shape.sh and gh-identity.sh are found as `$(dirname "$0")/<name>` only, and run as `sh`.
#
# Permitted toolset: POSIX sh, `git`, `gh` (its embedded --jq allowed), `yq` (mikefarah v4, always
# `-p=json` on JSON), `tr`, `sed`, `mktemp`, `cp`, `mv`, `rm`, `dirname`, `uname`, `ls`, `grep`,
# `wc`, `cat` and `cut`. No system `jq` and no `eval`. A missing `yq` is `unreadable`.
set -eu

usage() {
  echo "usage: spec-post.sh post <N> <sha> <draft-file> <out-dir>" >&2
  exit 2
}
[ "$#" -eq 5 ] && [ "$1" = post ] || usage
n="$2"
sha="$3"
draft="$4"
out="$5"

case "$n" in
  '' | 0* | *[!0-9]*) usage ;;
esac
case "$sha" in
  '' | *[!0-9a-f]*) usage ;;
esac
[ "${#sha}" -eq 40 ] || usage

case "$0" in
  */*)
    here="$(dirname "$0")"
    gi="$here/gh-identity.sh"
    shape="$here/spec-shape.sh"
    ;;
  *)
    echo "spec-post.sh: must be run by path (a slash-less \$0 cannot locate its sibling scripts)" >&2
    exit 2
    ;;
esac
[ -f "$gi" ] && [ -f "$shape" ] || {
  echo "spec-post.sh: gh-identity.sh or spec-shape.sh not beside this script" >&2
  exit 2
}

# absolute <path> -- an absolute path, a drive-letter form only under MSYS, MINGW or CYGWIN
absolute() {
  case "$1" in
    //* | *\\*) return 1 ;;
    /*) return 0 ;;
    [A-Za-z]:/*)
      case "$(uname -s 2>/dev/null | tr 'a-z' 'A-Z')" in
        MSYS* | MINGW* | CYGWIN*) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

gtop="$(git rev-parse --show-toplevel 2>/dev/null)" || usage
[ -n "$gtop" ] || usage
top="$(cd -P "$gtop" 2>/dev/null && pwd -P)" || usage
[ -n "$top" ] || usage
ltop="$(printf '%s' "$top" | tr 'A-Z' 'a-z')"

# --- the draft file ------------------------------------------------------------------------
absolute "$draft" || usage
[ ! -L "$draft" ] || usage
ddir="$(dirname "$draft")"
[ -n "$ddir" ] || usage
ddir="$(cd -P "$ddir" 2>/dev/null && pwd -P)" || usage
[ -n "$ddir" ] || usage
lddir="$(printf '%s' "$ddir" | tr 'A-Z' 'a-z')"
case "$lddir" in
  "$ltop" | "$ltop"/*) usage ;;
esac
draft="$ddir/${draft##*/}"
[ -f "$draft" ] && [ ! -L "$draft" ] && [ -s "$draft" ] || usage

# --- the out-dir ---------------------------------------------------------------------------
absolute "$out" || usage
[ -d "$out" ] && [ ! -L "$out" ] || usage
ls -A "$out" >/dev/null 2>&1 || usage
[ -z "$(ls -A "$out" 2>/dev/null)" ] || usage
out="$(cd -P "$out" 2>/dev/null && pwd -P)" || usage
[ -n "$out" ] || usage
lout="$(printf '%s' "$out" | tr 'A-Z' 'a-z')"
case "$lout" in
  "$ltop" | "$ltop"/*) usage ;;
esac

# --- from here, a stop is a word -----------------------------------------------------------
tmp=
ctmp=
cleanup() {
  [ -z "$ctmp" ] || rm -f "$ctmp"
  [ -z "$tmp" ] || rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 1' INT TERM HUP
stop() {
  echo "$1"
  exit 1
}
held() {
  printf 'held %s %s\n' "$1" "$out/comment.md"
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

# the copy
cp "$draft" "$tmp/draft.md" 2>/dev/null || stop unreadable

# the origin's URL
git -C "$gtop" remote get-url origin >"$tmp/url" 2>/dev/null || stop unreadable
url="$(rd "$tmp/url")"
[ -n "$url" ] || stop unreadable
case "$url" in -*) stop unreadable ;; esac

# the repository and its default branch
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

# the default branch's committed project.yml; the working tree's copy is never read
git -C "$gtop" fetch -q origin "+refs/heads/$def:refs/remotes/origin/$def" >/dev/null 2>&1 || stop unreadable
git -C "$gtop" show "refs/remotes/origin/$def:./.ai/project.yml" >"$tmp/def.yml" 2>/dev/null || stop unreadable

# the repo it names
yrepo="$(yq -r '.repo // ""' "$tmp/def.yml" 2>/dev/null)" || stop unreadable
[ "$(fold "$yrepo")" = "$(fold "$nwo")" ] || stop repo-mismatch

# the backlog repo: null or absent is the origin's repository
backlog="$(yq -r '.backlog.repo // ""' "$tmp/def.yml" 2>/dev/null)" || stop unreadable
backlog="${backlog:-$nwo}"
case "$backlog" in
  '' | *[!A-Za-z0-9._/-]* | */*/* | /* | */ | ./* | ../* | */. | */..) stop bad-backlog ;;
  */*) : ;;
  *) stop bad-backlog ;;
esac

# the base
base="$(yq -r '.pr_base // ""' "$tmp/def.yml" 2>/dev/null)" || stop unreadable
case "$base" in '' | -* | *[!A-Za-z0-9._/-]*) stop bad-base ;; esac

# the commit the draft was checked on
git -C "$gtop" fetch -q origin "+refs/heads/$base:refs/remotes/origin/$base" >/dev/null 2>&1 || stop unreadable
git -C "$gtop" cat-file -e "$sha^{commit}" >/dev/null 2>&1 || stop bad-sha
git -C "$gtop" merge-base --is-ancestor "$sha" "refs/remotes/origin/$base" >/dev/null 2>&1 || stop bad-sha

# the content, on the copy
sh "$shape" check "$tmp/draft.md" >"$tmp/shape" 2>/dev/null || stop bad-shape
[ "$(rd "$tmp/shape")" = ok ] || stop bad-shape

# match <grep-args...> -- 0 when the copy has a matching line, 1 when not; any other status is a stop
match() {
  _rc=0
  grep -q "$@" "$tmp/draft.md" >/dev/null 2>&1 || _rc=$?
  case "$_rc" in
    0) return 0 ;;
    1) return 1 ;;
    *) stop unreadable ;;
  esac
}
if match -e '^spec-task:'; then stop has-marker; fi
if match -E -e '(^|[^A-Za-z0-9])[A-Za-z]:[/\\]'; then stop leak; fi
if match -F -e '/Users/' -e '/home/' -e 'AppData' -e '-----BEGIN'; then stop leak; fi
if match -E -e '(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}' -e 'github_pat_[A-Za-z0-9]{20,}'; then stop leak; fi

# the composed body
{
  printf 'spec-task: issue=%s base=%s sha=%s\n\n' "$n" "$base" "$sha"
  cat "$tmp/draft.md"
} >"$tmp/body.md" 2>/dev/null || stop unreadable
size="$(wc -c <"$tmp/body.md")" || stop unreadable
[ "$size" -le 65536 ] || stop too-long

# the issue
gh api --hostname github.com "repos/$backlog/issues/$n" >"$tmp/issue.json" 2>/dev/null || stop unreachable

J() { yq -p=json -o=yaml "$1" "$tmp/issue.json" 2>/dev/null; }
tags="$(J '[(.user.login | tag), (.user.id | tag), (.author_association | tag), (.state | tag), (.locked | tag)] | join(",")')" || stop unreadable
[ "$tags" = '!!str,!!int,!!str,!!str,!!bool' ] || stop unreadable
login="$(J '.user.login')" || stop unreadable
uid="$(J '.user.id')" || stop unreadable
assoc="$(J '.author_association')" || stop unreadable
state="$(J '.state')" || stop unreadable
locked="$(J '.locked')" || stop unreadable
case "$login" in '' | *[!]A-Za-z0-9_[-]*) stop unreadable ;; esac
case "$uid" in '' | *[!0-9]*) stop unreadable ;; esac
case "$assoc" in '' | *[!ABCDEFGHIJKLMNOPQRSTUVWXYZ_]*) stop unreadable ;; esac

haspr="$(J 'has("pull_request")')" || stop unreadable
case "$haspr" in
  true) stop not-an-issue ;;
  false) : ;;
  *) stop unreadable ;;
esac
[ "$state" = open ] || stop closed
case "$locked" in
  true) stop locked ;;
  false) : ;;
  *) stop unreadable ;;
esac

# the loop's own login, before any trust check
loopid="$(yq -r '.orchestration.loop_identity // ""' "$tmp/def.yml" 2>/dev/null)" || stop unreadable
if [ -n "$loopid" ] && [ "$(fold "$login")" = "$(fold "$loopid")" ]; then stop loop-identity; fi

# the author
rc=0
sh "$gi" author "$login" "$uid" "$tmp/def.yml" >"$tmp/verdict" 2>/dev/null || rc=$?
[ "$rc" -eq 0 ] || stop untrusted
verdict="$(rd "$tmp/verdict")"
case "$verdict/$assoc" in
  trusted/* | legacy/OWNER | legacy/MEMBER | legacy/COLLABORATOR) : ;;
  *) stop untrusted ;;
esac

# compose: a rename within the out-dir
[ ! -e "$out/comment.md" ] && [ ! -L "$out/comment.md" ] || stop unreadable
ctmp="$(mktemp "$out/.comment.XXXXXX" 2>/dev/null)" && [ -n "$ctmp" ] || {
  ctmp=
  stop unreadable
}
cp "$tmp/body.md" "$ctmp" 2>/dev/null || stop unreadable
mv "$ctmp" "$out/comment.md" 2>/dev/null || {
  rm -f "$out/comment.md"
  stop unreadable
}
ctmp=
[ -f "$out/comment.md" ] && [ ! -L "$out/comment.md" ] || stop unreadable

# hold: only a map, and only the declared dev App, posts
yq -r 'has("identities"), (.identities | tag)' "$tmp/def.yml" >"$tmp/ident" 2>/dev/null || stop unreadable
ident="$(tr '\n' ' ' <"$tmp/ident")"
[ "$ident" = 'true !!map ' ] || held no-identities
gh api --hostname github.com graphql -f query='{ viewer { login databaseId } }' --jq '[.data.viewer.login, .data.viewer.databaseId] | @tsv' >"$tmp/viewer" 2>/dev/null || held actor-unreadable
vlogin="$(cut -f1 <"$tmp/viewer")"
vid="$(cut -f2 <"$tmp/viewer")"
rc=0
sh "$gi" role "$vlogin" "$vid" "$tmp/def.yml" >"$tmp/role" 2>/dev/null || rc=$?
[ "$rc" -eq 0 ] || held not-dev-app
[ "$(rd "$tmp/role")" = dev_app ] || held not-dev-app

# post: the one write
gh api --hostname github.com --method POST "repos/$backlog/issues/$n/comments" -F body=@- <"$tmp/body.md" >"$tmp/resp.json" 2>/dev/null || stop post-unknown

# the response
R() { yq -p=json -o=yaml "$1" "$tmp/resp.json" 2>/dev/null; }
rtags="$(R '[(.id | tag), (.user.login | tag), (.user.id | tag), (.issue_url | tag), (.html_url | tag)] | join(",")')" || stop posted-unreadable
[ "$rtags" = '!!int,!!str,!!int,!!str,!!str' ] || stop posted-unreadable
cid="$(R '.id')" || stop posted-unreadable
clogin="$(R '.user.login')" || stop posted-unreadable
cuid="$(R '.user.id')" || stop posted-unreadable
iurl="$(R '.issue_url')" || stop posted-unreadable
hurl="$(R '.html_url')" || stop posted-unreadable
case "$cid" in '' | 0* | *[!0-9]*) stop posted-unreadable ;; esac
[ "$clogin" = "$vlogin" ] && [ "$cuid" = "$vid" ] || stop posted-unreadable
[ "$(fold "$iurl")" = "$(fold "https://api.github.com/repos/$backlog/issues/$n")" ] || stop posted-unreadable
[ "$(fold "$hurl")" = "$(fold "https://github.com/$backlog/issues/$n#issuecomment-$cid")" ] || stop posted-unreadable
printf 'posted %s %s %s\n' "$cid" "$clogin" "$hurl"
