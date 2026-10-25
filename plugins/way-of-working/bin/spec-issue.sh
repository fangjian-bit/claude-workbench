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
# block stopped on, and a pass for every author GitHub can return that the block passed (except
# the #759 `app_check` stops below, which the old block never had).
#
# Output. On a pass, exactly one line on stdout and exit 0:
#   ok B=<backlog-repo> BASE=<base> VERDICT=<verdict> ASSOC=<association>
# and `<out-dir>/issue.json` holds the issue. On a stop, exactly one word on stdout and exit 1,
# the first that applies:
#   unreadable     a read, a check or a copy failed, or a value was not the shape expected
#                  Also (#759), under a map and for a maintainer or App author: a declared App's id
#                  (dev_app, reviewer_app, loop_app) on the maintainer list, an App entry that is
#                  neither null nor well formed or has a non-canonical id, or a maintainer list with an
#                  entry that is not well formed (which passed as `trusted` before).
#   repo-mismatch  the default branch's project.yml `.repo` is not the origin's repository
#   bad-backlog    `backlog.repo` (null or absent means the origin's repository) is not owner/name
#   bad-base       `pr_base` is empty, begins with `-` or holds an unusual character
#   unreachable    the backlog's `.permissions` read or the issue fetch failed, or (App-filed path) the
#                  reactions read, the second fetch or the content-time query failed
#   not-an-issue   the response has a `pull_request` key
#   loop-identity  the author is `orchestration.loop_identity`, before any trust check
#   untrusted      the author is not trusted (`gh-identity.sh task-author`: not a declared maintainer,
#                  dev App or reviewer App, or the loop App). It also covers a config `gh-identity.sh`
#                  could not judge (exit 2: a malformed `identities`, an id declared twice), so the
#                  word can mean a broken config, not only a hostile author.
#   unreacted      the author is the declared dev or reviewer App (`agent`, WB-D32, #664) and no
#                  declared maintainer has reacted approvingly to the issue strictly after the time its
#                  content last changed (spec-reaction.sh, the rule spec comments follow; #890)
#   hidden         an `agent` author's reacted title or body carries text a reader of the rendered
#                  issue cannot see: an opener, a character reference, a link definition line or a
#                  default-ignorable character (see below)
# Nothing is written to stderr on a stop. Any other argument count, a first argument other than
# `fetch`, a bad <N> or <out-dir>, a slash-less $0 or a missing sibling gh-identity.sh,
# spec-reaction.sh or declared-ids.sh prints a usage line (or, for the siblings, a one-line diagnostic) on stderr and nothing on stdout, and exits 2,
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
# --raw-field or --input, and no graphql -- except the one content-time query below (#890), a read-only
# GraphQL query that `gh` sends as a POST with -f/-F variables.
#
# The App-filed path (WB-D32, #664). `gh-identity.sh task-author` says `trusted` for a declared
# maintainer, `legacy` under `identities: null` (`legacy` as before; `trusted` now first needs
# `app_check`, #759) and `agent` for the declared dev or
# reviewer App. `app_check` runs first, in the author switch (the `case` on the verdict), for a `trusted` or `agent` author: it
# stops `unreadable` (the four causes under `unreadable` above), before any reaction is read.
# An `agent` author passes only through these steps, in this order, and its
# VERDICT is `reacted`:
#   1. the issue's reactions are read (GET `issues/<N>/reactions`, `--paginate`, to a file);
#   2. the issue is fetched a SECOND time, to a fresh file; the type, pull-request, loop-identity
#      and task-author checks are re-run on that copy, which must name the same login and id, and
#      its `updated_at`, `title` and `body` must have the shapes a string-or-null field has;
#   3. the maintainer ids are read from the default branch's copy by declared-ids.sh (#1079), as the readers read them;
#   4. `spec-reaction.sh` says `approved` for the issue's content time (else `unreacted`): the latest
#      of its creation time, its body's last edit (GraphQL `lastEditedAt`, null when never edited) and
#      its newest title rename (a `RenamedTitleEvent`), read by one GraphQL query after the second
#      copy and checked to carry the second copy's `updated_at`, so the time and the kept text are
#      one state (#890; a change between the two reads stops `unreadable`, and a rerun judges afresh). A failed
#      call, which includes a response `gh` reports as an error, stops `unreachable`; a null issue or
#      any other shape stops `unreadable`;
#   5. the second copy's title and body are screened for text a reader of the rendered issue
#      cannot see (else `hidden`);
#   6. the second copy is the one renamed to `issue.json`, and `ASSOC` is taken from it.
# The reactions are read FIRST, so an edit to the title or body after that read moves the content time
# past the reaction and reads `unreacted`. A comment, a label or a milestone change moves `updated_at`
# but not the content time, so it leaves the reaction standing. Measured on 2026-10-17 (scratch issue
# #706): adding a reaction does not move an issue's `updated_at` (a reaction at 20:10:39 left it at
# 20:10:28, on two reads); a body edit moved it (20:10:46) and so did a title edit (20:10:52).
# Measured on 2026-10-22 (scratch issue #909): a comment, a label add and a milestone set each moved
# `updated_at` and left the content time at the creation time; a body edit moved `lastEditedAt` and
# the content time (14:09:45, then 14:09:50), a title edit moved the rename event's time and the
# content time (14:09:55); deleting an earlier body revision in the browser changed neither. plan-anchor.sh's
# header records the same for comments (#498). The `hidden` screen decodes the JSON first (`yq -p=json` into a file, matched with
# `awk` under LC_ALL=C, the patterns passed through ENVIRON), so a JSON escape cannot hide a match. It
# refuses an opener (`<!` or `<?`, an HTML comment, declaration, CDATA section or processing instruction opener, or a `<` and a
# slash followed by a character that is not an ASCII letter or by the end of the line, a bogus closing tag), a CR that is not the last character of its line (a browser-edited
# CRLF body passes, as in spec-fresh.sh), a numeric character reference or one of the seventeen named references that decode only to
# an invisible character (HREF), a character from spec-fresh.sh's HID set (Unicode's Default_Ignorable_Code_Point set;
# HID, HREF and LDEF are copied byte for byte) and a line that is a Markdown link reference definition (renders as
# nothing). It is a filter, not a boundary. The reaction gates this script's read of the body, never
# a build: a builder reads no body under a map.
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
# gh-identity.sh, spec-reaction.sh and declared-ids.sh are found as `$(dirname "$0")/<name>` only, and run as `sh`.
#
# Permitted toolset: POSIX sh, `git`, `gh` (its embedded --jq allowed), `yq` (mikefarah v4, always
# `-p=json` on JSON), `tr`, `sed`, `awk`, `mktemp`, `cp`, `mv`, `rm`, `dirname`, `uname` and `ls`. No
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
  */*)
    gi="$(dirname "$0")/gh-identity.sh"
    sr="$(dirname "$0")/spec-reaction.sh"
    di="$(dirname "$0")/declared-ids.sh"
    ;;
  *)
    echo "spec-issue.sh: must be run by path (a slash-less \$0 cannot locate gh-identity.sh)" >&2
    exit 2
    ;;
esac
[ -f "$gi" ] || {
  echo "spec-issue.sh: gh-identity.sh not beside this script" >&2
  exit 2
}
[ -f "$sr" ] || {
  echo "spec-issue.sh: spec-reaction.sh not beside this script" >&2
  exit 2
}
[ -f "$di" ] || {
  echo "spec-issue.sh: declared-ids.sh not beside this script" >&2
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

# HID, HREF, LDEF: spec-fresh.sh's three lines (Unicode's default-ignorable set; numeric and invisible named character references; a link reference
# definition line), byte for byte (the agent path's hidden-text screen; the opener and CR tests are inline in the awk below)
HID="$(printf '\302\255|\315\217|\330\234|\341\205[\237-\240]|\341\236[\264-\265]|\341\240[\213-\217]|\342\200[\213-\217]|\342\200[\252-\256]|\342\201[\240-\257]|\343\205\244|\357\270[\200-\217]|\357\273\277|\357\276\240|\357\277[\260-\270]|\360\233\262[\240-\243]|\360\235\205[\263-\272]|\363\240[\200-\277][\200-\277]')"
HREF='&#[0-9xX]|&shy|&(zwnj|zwj|lrm|rlm|ZeroWidthSpace|NegativeVeryThinSpace|NegativeThinSpace|NegativeMediumSpace|NegativeThickSpace|NoBreak|ApplyFunction|af|InvisibleTimes|it|InvisibleComma|ic);'
LDEF='^ ? ? ?\[[^]]+\]:'

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

# The declared ids come from declared-ids.sh (#1079), which holds every `identities` rule, a declared
# App's id on the maintainer list (#759, as #708 did for the readers) included: that App's reaction would
# count as a maintainer's. Sets maint_ids, or stops `unreadable` unless the helper exits 0 with exactly
# `ok <ids> <dev>`: three fields, a non-empty list, a dev id of `-` or digits with no leading zero.
declared_ids() {
  di_line="$(sh "$di" "$tmp/def.yml" </dev/null 2>/dev/null)" || stop unreadable
  case "$di_line" in
    *"
"*) stop unreadable ;;
    "ok "*) : ;;
    *) stop unreadable ;;
  esac
  di_rest="${di_line#ok }"
  case "$di_rest" in *" "*" "* | " "* | *" " | "") stop unreadable ;; *" "*) : ;; *) stop unreadable ;; esac
  maint_ids="${di_rest%% *}"
  case "${di_rest#* }" in
    -) : ;;
    '' | 0* | *[!0-9]*) stop unreadable ;;
  esac
}

# Under a map no declared App's id may be on the maintainer list; any list or entry the helper cannot
# judge stops `unreadable`.
app_check() {
  declared_ids
}

# The App-filed path: see the header. Sets src, verdict and assoc, or stops.
agent_path() {
  # 1. the reactions, before the second read
  gh api "repos/$backlog/issues/$n/reactions" --paginate --jq '.[] | [(.user.id|tostring), .content, .created_at] | @tsv' >"$tmp/reactions.tsv" 2>/dev/null || stop unreachable
  # 2. the second copy
  gh api "repos/$backlog/issues/$n" >"$tmp/issue2.json" 2>/dev/null || stop unreachable
  J2() { yq -p=json -o=yaml "$1" "$tmp/issue2.json" 2>/dev/null; }
  tags2="$(J2 '[(.user.login | tag), (.user.id | tag), (.author_association | tag), (.updated_at | tag), (.title | tag), (.body | tag)] | join(",")')" || stop unreadable
  case "$tags2" in
    '!!str,!!int,!!str,!!str,!!str,!!str' | '!!str,!!int,!!str,!!str,!!str,!!null') : ;;
    *) stop unreadable ;;
  esac
  login2="$(J2 '.user.login')" || stop unreadable
  uid2="$(J2 '.user.id')" || stop unreadable
  assoc2="$(J2 '.author_association')" || stop unreadable
  i_updated="$(J2 '.updated_at')" || stop unreadable
  case "$login2" in '' | *[!]A-Za-z0-9_[-]*) stop unreadable ;; esac
  case "$uid2" in '' | *[!0-9]*) stop unreadable ;; esac
  case "$assoc2" in '' | *[!ABCDEFGHIJKLMNOPQRSTUVWXYZ_]*) stop unreadable ;; esac
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
  if [ -n "$loopid" ] && [ "$(fold "$login2")" = "$(fold "$loopid")" ]; then stop loop-identity; fi
  rc=0
  sh "$gi" task-author "$login2" "$uid2" "$tmp/def.yml" >"$tmp/verdict2" 2>/dev/null || rc=$?
  [ "$rc" -eq 0 ] || stop untrusted
  [ "$(rd "$tmp/verdict2")" = agent ] || stop unreadable
  # 3. the maintainer ids, from declared-ids.sh as the readers read them
  declared_ids
  # 3b. the content time (#890, WB-D32): the latest of the issue's creation, its body's last edit and its
  # newest title rename, so a comment, a label or a milestone change leaves a reaction standing
  gh api graphql -f query='query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){issue(number:$number){createdAt updatedAt lastEditedAt timelineItems(itemTypes:[RENAMED_TITLE_EVENT],last:1){nodes{... on RenamedTitleEvent{createdAt}}}}}}' -f owner="${backlog%%/*}" -f name="${backlog#*/}" -F number="$n" >"$tmp/ct.json" 2>/dev/null || stop unreachable
  CT() { yq -p=json -o=yaml "$1" "$tmp/ct.json" 2>/dev/null; }
  ct_ts() {
    case "$1" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) : ;;
      *) stop unreadable ;;
    esac
  }
  [ "$(CT 'has("errors")')" = false ] || stop unreadable
  [ "$(CT '.data.repository.issue | tag')" = '!!map' ] || stop unreadable
  [ "$(CT '.data.repository.issue | has("lastEditedAt")')" = true ] || stop unreadable
  [ "$(CT '.data.repository.issue.timelineItems.nodes | tag')" = '!!seq' ] || stop unreadable
  ct_created="$(CT '.data.repository.issue.createdAt')" || stop unreadable
  ct_upd="$(CT '.data.repository.issue.updatedAt')" || stop unreadable
  [ "$(CT '[(.data.repository.issue.createdAt | tag), (.data.repository.issue.updatedAt | tag)] | join(",")')" = '!!str,!!str' ] || stop unreadable
  ct_ts "$ct_created"
  ct_ts "$ct_upd"
  [ "$ct_upd" = "$i_updated" ] || stop unreadable
  ct_time="$ct_created"
  case "$(CT '.data.repository.issue.lastEditedAt | tag')" in
    '!!null') : ;;
    '!!str')
      ct_edit="$(CT '.data.repository.issue.lastEditedAt')" || stop unreadable
      ct_ts "$ct_edit"
      ct_time="$(printf '%s\n%s\n' "$ct_time" "$ct_edit" | LC_ALL=C awk '$0 > m { m = $0 } END { print m }')" || stop unreadable
      ;;
    *) stop unreadable ;;
  esac
  case "$(CT '.data.repository.issue.timelineItems.nodes | length')" in
    0) : ;;
    1)
      [ "$(CT '.data.repository.issue.timelineItems.nodes[0].createdAt | tag')" = '!!str' ] || stop unreadable
      ct_ren="$(CT '.data.repository.issue.timelineItems.nodes[0].createdAt')" || stop unreadable
      ct_ts "$ct_ren"
      ct_time="$(printf '%s\n%s\n' "$ct_time" "$ct_ren" | LC_ALL=C awk '$0 > m { m = $0 } END { print m }')" || stop unreadable
      ;;
    *) stop unreadable ;;
  esac
  i_updated="$ct_time"
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
  # 6. the second copy is the one kept
  src="$tmp/issue2.json"
  verdict=reacted
  assoc="$assoc2"
}

# 12. the author
rc=0
sh "$gi" task-author "$login" "$uid" "$tmp/def.yml" >"$tmp/verdict" 2>/dev/null || rc=$?
[ "$rc" -eq 0 ] || stop untrusted
verdict="$(rd "$tmp/verdict")"
src="$tmp/issue.json"
case "$verdict/$assoc" in
  trusted/*) app_check ;;
  legacy/OWNER | legacy/MEMBER | legacy/COLLABORATOR) : ;;
  agent/*) app_check; agent_path ;;
  *) stop untrusted ;;
esac

# 13. only now write issue.json: a rename within the out-dir
if [ -e "$out/issue.json" ] || [ -L "$out/issue.json" ]; then stop unreadable; fi
itmp="$(mktemp "$out/.issue.XXXXXX" 2>/dev/null)" && [ -n "$itmp" ] || {
  itmp=
  stop unreadable
}
cp "$src" "$itmp" 2>/dev/null || stop unreadable
mv "$itmp" "$out/issue.json" 2>/dev/null || {
  rm -f "$out/issue.json"
  stop unreadable
}
itmp=
[ -f "$out/issue.json" ] && [ ! -L "$out/issue.json" ] || stop unreadable
printf 'ok B=%s BASE=%s VERDICT=%s ASSOC=%s\n' "$backlog" "$base" "$verdict" "$assoc"
