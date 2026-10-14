#!/bin/sh
# Is the anchored spec comment the one a maintainer wrote, on the task it claims, unedited
# since the anchor? One implementation of those checks, shared by the three readers that print
# the comment: /way-of-working:resume's *body read (TOCTOU closure)* rule, the coder agent's *fetch the task once* step and
# /way-of-working:architect-review's *Load context lean* step (#614). Before this each carried the checks in its
# own prose, and a reader that skipped one (or fetched the comment to the transcript before
# checking it) put unchecked text in context with nothing to say so.
#
# Usage: spec-comment.sh check|body <comment.json> <backlog-repo> <issue> <comment-id> <updated_at> <project.yml>
#
#   <comment.json>   the caller's own fetch of the ONE anchored comment, to a file:
#                      gh api repos/{backlog.repo}/issues/comments/<id> >"$T/c.json"
#                    never to the transcript and never piped in: a failed fetch through a pipe
#                    reads as an empty file, and the caller must stop on its non-zero exit
#                    before this script runs. This script makes NO network call.
#   <backlog-repo>   owner/name of {backlog.repo}
#   <issue>          the task issue number (plan_anchor.task_issue), digits
#   <comment-id>     plan_anchor.spec_comment.id, digits
#   <updated_at>     plan_anchor.spec_comment.updated_at, YYYY-MM-DDTHH:MM:SSZ
#   <project.yml>    the DEFAULT branch's committed copy (the callers' $DEF_YML_FILE), never the
#                    working tree's, which a branch under review can edit
#
# check prints exactly one word to stdout and exits 0 -- the FIRST failing check, in this order:
#   ok           -- all of the below hold
#   wrong-id     -- `.id` is not <comment-id>
#   moved        -- `.updated_at` is not <updated_at>: the comment was edited after the anchor
#   wrong-issue  -- `.issue_url` is not https://api.github.com/repos/<backlog-repo>/issues/<issue>
#   untrusted    -- the author is not trusted. `gh-identity.sh author` on `.user.login` and
#                   `.user.id`: `trusted` passes; `legacy` (identities null, the repo has not cut
#                   over) passes only when `.author_association` is OWNER, MEMBER or
#                   COLLABORATOR; anything else fails, an exit of 2 included
#   unreadable   -- the file is missing, is not JSON, or lacks a field (or has one of the wrong
#                   type) the checks read. Decided before any other word.
# It never prints `.body`.
#
# body runs the same checks. All pass: prints `.body` raw -- trailing newlines trimmed, then
# exactly one added -- and exits 0.
# Otherwise it prints NOTHING to stdout, prints the check word on stderr and exits 1. It is the
# only sanctioned way to print the body: the callers never `jq .body` the file themselves.
#
# Exits 2, printing nothing to stdout, when an argument is bad: the wrong argument count, an
# unknown mode, a repo that is not owner/name, an issue or comment id that is not digits, a
# malformed <updated_at>, or an unreadable <project.yml> -- and when it cannot find its sibling
# gh-identity.sh (a slash-less $0, or none beside it). The caller treats any non-zero exit as a
# stop, never as ok.
#
# `.id` and `.updated_at` are compared as exact strings against validated arguments, and the
# author goes through gh-identity.sh, which validates the login and id shape itself.
# gh-identity.sh is the SIBLING copy and only that: a slash-less `$0` would resolve `dirname`
# to the current directory, where a branch under review could supply one that prints `trusted`
# (plan-anchor.sh does the same for spec-reaction.sh).
#
# Permitted toolset: POSIX sh and yq (mikefarah v4, which reads JSON), the toolset gh-identity.sh
# already needs. No system jq, no python.
set -eu

usage() {
  echo "usage: spec-comment.sh check|body <comment.json> <backlog-repo> <issue> <comment-id> <updated_at> <project.yml>" >&2
  exit 2
}
[ "$#" -eq 7 ] || usage
mode="$1" file="$2" repo="$3" issue="$4" cid="$5" updated="$6" yml="$7"

case "$mode" in check | body) : ;; *) usage ;; esac
case "$repo" in
  */*/* | */ | /* | '' | *[!A-Za-z0-9._/-]*) echo "spec-comment.sh: backlog-repo must be owner/name" >&2; exit 2 ;;
  */*) : ;;
  *) echo "spec-comment.sh: backlog-repo must be owner/name" >&2; exit 2 ;;
esac
case "$issue" in '' | *[!0-9]*) echo "spec-comment.sh: issue must be digits" >&2; exit 2 ;; esac
case "$cid" in '' | *[!0-9]*) echo "spec-comment.sh: comment-id must be digits" >&2; exit 2 ;; esac
case "$updated" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) : ;;
  *) echo "spec-comment.sh: malformed updated_at" >&2; exit 2 ;;
esac
if [ ! -f "$yml" ] || ! yq -o=yaml '.' "$yml" >/dev/null 2>&1; then
  echo "spec-comment.sh: unreadable project.yml" >&2
  exit 2
fi

case "$0" in
  */*) gi="$(dirname "$0")/gh-identity.sh" ;;
  *) echo "spec-comment.sh: must be run by path (a slash-less $0 cannot locate gh-identity.sh)" >&2; exit 2 ;;
esac
[ -f "$gi" ] || { echo "spec-comment.sh: gh-identity.sh not beside this script" >&2; exit 2; }

J() { yq -p=json -o=yaml "$1" "$file" 2>/dev/null; }

verdict() {
  [ -f "$file" ] || { echo unreadable; return; }
  tags="$(J '[(.id | tag), (.updated_at | tag), (.issue_url | tag), (.user.login | tag), (.user.id | tag), (.body | tag)] | join(",")')" || { echo unreadable; return; }
  [ "$tags" = '!!int,!!str,!!str,!!str,!!int,!!str' ] || { echo unreadable; return; }
  f_id="$(J '.id')" || { echo unreadable; return; }
  f_updated="$(J '.updated_at')" || { echo unreadable; return; }
  f_url="$(J '.issue_url')" || { echo unreadable; return; }
  f_login="$(J '.user.login')" || { echo unreadable; return; }
  f_uid="$(J '.user.id')" || { echo unreadable; return; }

  [ "$f_id" = "$cid" ] || { echo wrong-id; return; }
  [ "$f_updated" = "$updated" ] || { echo moved; return; }
  [ "$f_url" = "https://api.github.com/repos/$repo/issues/$issue" ] || { echo wrong-issue; return; }

  if who="$(sh "$gi" author "$f_login" "$f_uid" "$yml" 2>/dev/null)"; then
    case "$who" in
      trusted) echo ok; return ;;
      legacy)
        assoc="$(J '.author_association | select(tag == "!!str")')" || assoc=
        case "$assoc" in OWNER | MEMBER | COLLABORATOR) echo ok; return ;; esac
        echo untrusted; return ;;
    esac
  fi
  echo untrusted
}

word="$(verdict)"
if [ "$mode" = check ]; then
  printf '%s\n' "$word"
  exit 0
fi
if [ "$word" != ok ]; then
  printf '%s\n' "$word" >&2
  exit 1
fi
# Captured first: a yq failure here must not leave half a body on stdout.
body="$(J '.body')" || { echo unreadable >&2; exit 1; }
printf '%s\n' "$body"
