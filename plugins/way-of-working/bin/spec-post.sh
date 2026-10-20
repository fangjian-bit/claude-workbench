#!/bin/sh
# Compose and post ONE spec comment on a task issue, as the declared dev App, or hold the
# composed comment for a human to post.
#
# Usage: spec-post.sh post|escalate <N> <sha> <draft-file> <out-dir>
#
# Two modes (#746). `post` is the spec comment, marker `spec-task: issue=N base=B sha=<sha>`.
# `escalate` runs every stage and check `post` runs, composes the same body under the distinct
# first line `spec-task-escalated: issue=N base=B sha=<sha>` (which no reader takes for the spec
# marker) and, after a confirmed post, makes one label write adding `status/needs-human`. Nothing
# calls `escalate` yet; spec-find.sh shows such a comment as `escalated` (or in `pending`), so
# the escalation lives on GitHub in the comment, not in the label.
#
# Who calls it: spec-task's *Post or hold* stage, after spec-shape.sh said `ok`. Why it exists:
# the skill used to hand its draft to the maintainer to post (WB-D26). It now posts it itself
# when the session acts as the declared dev App (WB-D29), and the composing, the marker and the
# one write (two in `escalate` mode) live here, in one tested command, instead of in prose a model retypes. Approval does
# not move: a declared maintainer reacts to the posted comment on GitHub, and every reader of a
# dev-App spec already refuses it without that reaction. The marker line is a locator, never
# authority.
#
# Output. A pass is exactly one line on stdout and exit 0:
#   posted <id> <login> <html_url>
# or, in `escalate` mode only:
#   escalated <id> <login> <html_url> <lbl>
# <lbl> is `labelled`, `label-absent` (the repository has no `status/needs-human` label, so no
# write was made), `label-unreadable` (the label read failed, no write was made) or `label-failed`
# (the one label write failed; it is never retried). The comment is posted in all four.
# A stop is exactly one word on stdout and exit 1, the first that applies, in the order the
# stages below run:
#   unreadable          a read, a check or a copy failed, or a value was not the shape expected
#                       Also (#759), under a map and for a maintainer or App author: a declared App's id
#                       (dev_app, reviewer_app, loop_app) on the maintainer list, an App entry that is
#                       neither null nor well formed or has a non-canonical id, or a maintainer list with an
#                       entry that is not well formed. This stops before the compose, hold and post stages.
#   repo-mismatch       the default branch's project.yml `.repo` is not the origin's repository
#   bad-backlog         `backlog.repo` (null or absent means the origin's repository) is not owner/name
#   bad-base            `pr_base` is empty, begins with `-` or holds an unusual character
#   bad-sha             <sha> is not a commit on the tip of origin/<base> or behind it
#   bad-shape           spec-shape.sh check did not say `ok`
#   has-marker          a line of the draft begins with either marker prefix (`spec-task:` or `spec-task-escalated:`)
#   leak                a line matches an obvious local-path or secret shape (a filter, not a boundary)
#   too-long            the composed body is over 65536 bytes
#   unreachable         the issue fetch failed, or (App-filed path) the issue's reactions read or second fetch
#   not-an-issue        the response has a `pull_request` key
#   closed              the issue is not open
#   locked              the issue is locked
#   loop-identity       the issue's author is `orchestration.loop_identity`
#   untrusted           the issue's author is not trusted (also a config gh-identity.sh could not judge)
#   unreacted           the issue's author is the declared dev or reviewer App and no declared maintainer
#                       has reacted approvingly to the issue strictly after its last update (WB-D32, #664)
#   hidden              an App-filed issue's reacted title or body carries text a reader of the rendered
#                       issue cannot see (the screen spec-issue.sh's header describes: an opener, a
#                       character reference, a link definition line or a default-ignorable character)
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
#                (`gh-identity.sh task-author`). After the author is judged, `app_check` runs for a `trusted` or
#                `agent` verdict, before the App-filed path reads any reaction (see `unreadable` above). An author the dev or reviewer App declares (`agent`) passes
#                only through spec-issue.sh's App-filed path, in its order: the issue's reactions are
#                read first (so an edit after that read moves `updated_at` past the reaction), then the
#                issue is fetched a second time and its type, closed, locked, loop-identity and author
#                checks re-run on that copy (same login and id as the first), then the maintainer ids,
#                `spec-reaction.sh` for the copy's `updated_at`, and the hidden-text screen. Adding a
#                reaction does not move an issue's `updated_at`; an edit does (measured on 2026-10-17,
#                scratch issue #706)
#   compose      the body is the marker line, one empty line, then the copy byte for byte; it is
#                renamed into <out-dir>/comment.md. This is the only place the marker is written
#   hold         the comment is posted only when `identities` is a map and the acting account is
#                the declared dev App; otherwise it is held
#   post         the comment write, with the body on standard input so gh is handed no path
#   response     the response is read back and must name this comment, this author and this issue
#   label        `escalate` mode only: one label read, and, only if it finds `status/needs-human`, one
#                label write, never retried. A stop or a hold before the post makes no label call, and
#                neither does `post-unknown` or `posted-unreadable`
#
# What it never prints: the draft, the body, or `gh`'s output or error text. The POST is never
# retried.
#
# Residuals, each accepted:
#   - the default-branch reads (`gh repo view`) take the host from the origin URL; the issue
#     read, the viewer read, the comment write and, in `escalate` mode, the label read and write pin
#     github.com, so they (and the App-filed path's extra reads) share one host and one credential;
#   - a `gh` call has no per-call timeout. A hang ends with no word, which the caller treats as
#     `post-unknown`;
#   - the leak shapes are a filter, not a boundary;
#   - the work-tree checks compare lowercased paths on every platform, so a differently cased alias is refused (it
#     fails closed); an 8.3 short name is not recognised. A <draft-file> or <out-dir> must be the
#     caller's own fresh mktemp -d: a planted entry or a linked worktree's git data is not checked;
#   - text paraphrased from an issue body whose author is trusted can have been edited by an
#     account with write access, and is posted; so can text paraphrased from a reacted App-filed
#     body (the reaction gates the read, not the content, and the hidden-text screen is a filter);
#   - the App-filed path makes four pinned reads (the default-branch reads aside): the issue, its
#     reactions, the issue again and the viewer, then, only on a pass, the comment write (and, in
#     `escalate` mode, the label read and write);
#   - a hang during the label calls comes after a confirmed post and reads as no word, which the
#     caller treats as `post-unknown`; that fails closed, because the finder already shows the comment;
#   - the label lookup is case-sensitive (`grep -Fx`) while GitHub label names are not, so a repository
#     spelling it `Status/Needs-Human` reads `label-absent` and no write is made (fails closed);
#   - the label can be deleted between the read and the write, in which case GitHub's add-labels
#     call may create it.
#
# There is no environment override of `gh`, `git` or `yq`; the tests put stubs first on PATH.
# spec-shape.sh, gh-identity.sh and spec-reaction.sh are found as `$(dirname "$0")/<name>` only, and run
# as `sh`.
#
# Permitted toolset: POSIX sh, `git`, `gh` (its embedded --jq allowed), `yq` (mikefarah v4, always
# `-p=json` on JSON), `tr`, `sed`, `mktemp`, `cp`, `mv`, `rm`, `dirname`, `uname`, `ls`, `grep`,
# `wc`, `cat`, `cut` and `awk`. No system `jq` and no `eval`. A missing `yq` is `unreadable`.
set -eu

usage() {
  echo "usage: spec-post.sh post|escalate <N> <sha> <draft-file> <out-dir>" >&2
  exit 2
}
[ "$#" -eq 5 ] || usage
mode="$1"
case "$mode" in
  post) mark=spec-task ;;
  escalate) mark=spec-task-escalated ;;
  *) usage ;;
esac
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
    sr="$here/spec-reaction.sh"
    ;;
  *)
    echo "spec-post.sh: must be run by path (a slash-less \$0 cannot locate its sibling scripts)" >&2
    exit 2
    ;;
esac
[ -f "$gi" ] && [ -f "$shape" ] && [ -f "$sr" ] || {
  echo "spec-post.sh: gh-identity.sh, spec-shape.sh or spec-reaction.sh not beside this script" >&2
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

# HID, HREF, LDEF: spec-fresh.sh's three lines (Unicode's default-ignorable set; numeric and invisible named character references; a link reference
# definition line), byte for byte (the App-filed path's hidden-text screen; the opener and CR tests are inline in the awk below)
HID="$(printf '\302\255|\315\217|\330\234|\341\205[\237-\240]|\341\236[\264-\265]|\341\240[\213-\217]|\342\200[\213-\217]|\342\200[\252-\256]|\342\201[\240-\257]|\343\205\244|\357\270[\200-\217]|\357\273\277|\357\276\240|\357\277[\260-\270]|\360\233\262[\240-\243]|\360\235\205[\263-\272]|\363\240[\200-\277][\200-\277]')"
HREF='&#[0-9xX]|&shy|&(zwnj|zwj|lrm|rlm|ZeroWidthSpace|NegativeVeryThinSpace|NegativeThinSpace|NegativeMediumSpace|NegativeThickSpace|NoBreak|ApplyFunction|af|InvisibleTimes|it|InvisibleComma|ic);'
LDEF='^ ? ? ?\[[^]]+\]:'

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
if match -e '^spec-task:' -e '^spec-task-escalated:'; then stop has-marker; fi
if match -E -e '(^|[^A-Za-z0-9])[A-Za-z]:[/\\]'; then stop leak; fi
if match -F -e '/Users/' -e '/home/' -e 'AppData' -e '-----BEGIN'; then stop leak; fi
if match -E -e '(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}' -e 'github_pat_[A-Za-z0-9]{20,}'; then stop leak; fi

# the composed body
{
  printf '%s: issue=%s base=%s sha=%s\n\n' "$mark" "$n" "$base" "$sha"
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

# Under a map, no declared App's id may be on the maintainer list (#759, as #708 did for the
# readers): that App's reaction would count as a maintainer's. Own variables, so agent_path's
# maintainer-id reads are untouched. Any list or entry it cannot judge stops `unreadable`.
app_check() {
  am_total="$(yq -r 'explode(.) | .identities.maintainer | select(tag == "!!seq") | length' "$tmp/def.yml" 2>/dev/null)" || stop unreadable
  am_ids="$(yq -r 'explode(.) | .identities.maintainer | select(tag == "!!seq") | [.[] | select(tag == "!!map" and ((.id | tag) == "!!int") and .id > 0 and ((.login | tag) == "!!str")) | .id] | join(",")' "$tmp/def.yml" 2>/dev/null)" || stop unreadable
  [ -n "$am_ids" ] || stop unreadable
  am_good="$(printf '%s' "$am_ids" | awk -F, '{print NF}')" || stop unreadable
  [ "$am_good" = "$am_total" ] || stop unreadable
  for app_key in dev_app reviewer_app loop_app; do
    app_tag="$(APP_KEY="$app_key" yq -r 'explode(.) | .identities[strenv(APP_KEY)] | tag' "$tmp/def.yml" 2>/dev/null)" || stop unreadable
    case "$app_tag" in
      '!!null') : ;;
      '!!map')
        app_id="$(APP_KEY="$app_key" yq -r 'explode(.) | .identities[strenv(APP_KEY)] | select(tag == "!!map" and ((.id | tag) == "!!int") and .id > 0 and ((.login | tag) == "!!str")) | .id' "$tmp/def.yml" 2>/dev/null)" || stop unreadable
        [ -n "$app_id" ] || stop unreadable
        case "$app_id" in '' | 0* | *[!0-9]*) stop unreadable ;; esac
        case ",$am_ids," in *",$app_id,"*) stop unreadable ;; esac
        ;;
      *) stop unreadable ;;
    esac
  done
}

# The App-filed path, in spec-issue.sh's order (see its header). Sets nothing the caller reads: it
# returns when the author is cleared and stops otherwise.
agent_path() {
  # 1. the reactions, before the second read
  gh api --hostname github.com "repos/$backlog/issues/$n/reactions" --paginate --jq '.[] | [(.user.id|tostring), .content, .created_at] | @tsv' >"$tmp/reactions.tsv" 2>/dev/null || stop unreachable
  # 2. the second copy
  gh api --hostname github.com "repos/$backlog/issues/$n" >"$tmp/issue2.json" 2>/dev/null || stop unreachable
  J2() { yq -p=json -o=yaml "$1" "$tmp/issue2.json" 2>/dev/null; }
  tags2="$(J2 '[(.user.login | tag), (.user.id | tag), (.state | tag), (.locked | tag), (.updated_at | tag), (.title | tag), (.body | tag)] | join(",")')" || stop unreadable
  case "$tags2" in
    '!!str,!!int,!!str,!!bool,!!str,!!str,!!str' | '!!str,!!int,!!str,!!bool,!!str,!!str,!!null') : ;;
    *) stop unreadable ;;
  esac
  login2="$(J2 '.user.login')" || stop unreadable
  uid2="$(J2 '.user.id')" || stop unreadable
  state2="$(J2 '.state')" || stop unreadable
  locked2="$(J2 '.locked')" || stop unreadable
  i_updated="$(J2 '.updated_at')" || stop unreadable
  case "$login2" in '' | *[!]A-Za-z0-9_[-]*) stop unreadable ;; esac
  case "$uid2" in '' | *[!0-9]*) stop unreadable ;; esac
  case "$i_updated" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) : ;;
    *) stop unreadable ;;
  esac
  [ "$login2" = "$login" ] && [ "$uid2" = "$uid" ] || stop unreadable
  haspr2="$(J2 'has("pull_request")')" || stop unreadable
  case "$haspr2" in
    true) stop not-an-issue ;;
    false) : ;;
    *) stop unreadable ;;
  esac
  [ "$state2" = open ] || stop closed
  case "$locked2" in
    true) stop locked ;;
    false) : ;;
    *) stop unreadable ;;
  esac
  if [ -n "$loopid" ] && [ "$(fold "$login2")" = "$(fold "$loopid")" ]; then stop loop-identity; fi
  rc=0
  sh "$gi" task-author "$login2" "$uid2" "$tmp/def.yml" >"$tmp/verdict2" 2>/dev/null || rc=$?
  [ "$rc" -eq 0 ] || stop untrusted
  [ "$(rd "$tmp/verdict2")" = agent ] || stop unreadable
  # 3. the maintainer ids, as spec-comment.sh reads them
  m_total="$(yq -r 'explode(.) | .identities.maintainer | select(tag == "!!seq") | length' "$tmp/def.yml" 2>/dev/null)" || stop unreadable
  maint_ids="$(yq -r 'explode(.) | .identities.maintainer | select(tag == "!!seq") | [.[] | select(tag == "!!map" and ((.id | tag) == "!!int") and .id > 0 and ((.login | tag) == "!!str")) | .id] | join(",")' "$tmp/def.yml" 2>/dev/null)" || stop unreadable
  [ -n "$maint_ids" ] || stop unreadable
  m_good="$(printf '%s' "$maint_ids" | awk -F, '{print NF}')" || stop unreadable
  [ "$m_good" = "$m_total" ] || stop unreadable
  # 4. the approval
  if got="$(sh "$sr" "$i_updated" "$maint_ids" <"$tmp/reactions.tsv" 2>/dev/null)" && [ "$got" = approved ]; then
    :
  else
    stop unreacted
  fi
  # 5. hidden text, on the decoded title and body
  J2 '.title' >"$tmp/title.txt" || stop unreadable
  J2 '.body // ""' >"$tmp/body.txt" || stop unreadable
  for f in "$tmp/title.txt" "$tmp/body.txt"; do
    hid_word="$(LC_ALL=C SI_HID="$HID" SI_HREF="$HREF" SI_LDEF="$LDEF" awk '
      BEGIN { hid = ENVIRON["SI_HID"]; href = ENVIRON["SI_HREF"]; ldef = ENVIRON["SI_LDEF"]; bad = 0 }
      {
        line = $0
        sub(/\r$/, "", line)
        if (line ~ /<[!?]/ || line ~ /<\/[^A-Za-z]/ || line ~ /<\/$/) bad = 1
        if (index(line, "\r") > 0) bad = 1
        if (line ~ hid) bad = 1
        if (line ~ href) bad = 1
        if (line ~ ldef) bad = 1
      }
      END { print (bad ? "hidden" : "clean") }
    ' "$f" 2>/dev/null)" || stop unreadable
    case "$hid_word" in
      clean) : ;;
      hidden) stop hidden ;;
      *) stop unreadable ;;
    esac
  done
}

# the author
rc=0
sh "$gi" task-author "$login" "$uid" "$tmp/def.yml" >"$tmp/verdict" 2>/dev/null || rc=$?
[ "$rc" -eq 0 ] || stop untrusted
verdict="$(rd "$tmp/verdict")"
case "$verdict/$assoc" in
  trusted/*) app_check ;;
  legacy/OWNER | legacy/MEMBER | legacy/COLLABORATOR) : ;;
  agent/*) app_check; agent_path ;;
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

# post: the comment write
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
if [ "$mode" = post ]; then
  printf 'posted %s %s %s\n' "$cid" "$clogin" "$hurl"
  exit 0
fi

# label: escalate only. One read, then at most one write, never retried.
lbl=labelled
gh api --hostname github.com "repos/$backlog/labels?per_page=100" --paginate --jq '.[].name' >"$tmp/labels" 2>/dev/null || lbl=label-unreadable
if [ "$lbl" = labelled ]; then
  lrc=0
  grep -Fx -e 'status/needs-human' "$tmp/labels" >/dev/null 2>&1 || lrc=$?
  if [ "$lrc" -eq 1 ]; then
    lbl=label-absent
  elif [ "$lrc" -ne 0 ]; then
    lbl=label-unreadable
  else
    gh api --hostname github.com --method POST "repos/$backlog/issues/$n/labels" -f 'labels[]=status/needs-human' </dev/null >/dev/null 2>&1 || lbl=label-failed
  fi
fi
printf 'escalated %s %s %s %s\n' "$cid" "$clogin" "$hurl" "$lbl"
