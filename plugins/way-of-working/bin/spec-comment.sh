#!/bin/sh
# Is the spec comment the one a declared maintainer or the declared dev App wrote, on the task it claims, unedited
# since the pair the caller holds (the anchor's, or under a map the finder's `found` pair)? One implementation of those checks, shared by the three readers that print
# the comment: /way-of-working:resume's *body read (TOCTOU closure)* rule, the coder agent's *fetch the task once* step and
# /way-of-working:architect-review's *Load context lean* step (#614). Before this each carried the checks in its
# own prose, and a reader that skipped one (or fetched the comment to the transcript before
# checking it) put unchecked text in context with nothing to say so.
#
# Usage: spec-comment.sh check|body <comment.json> <backlog-repo> <issue> <comment-id> <updated_at> <project.yml> [<reactions.tsv>]
#
#   <comment.json>   the caller's own fetch of the ONE spec comment, to a file:
#                      gh api repos/{backlog.repo}/issues/comments/<id> >"$T/c.json"
#                    never to the transcript and never piped in: a failed fetch through a pipe
#                    reads as an empty file, and the caller must stop on its non-zero exit
#                    before this script runs. This script makes NO network call.
#   <backlog-repo>   owner/name of {backlog.repo}
#   <issue>          the task issue number (plan_anchor.task_issue), digits
#   <comment-id>     the spec comment's id, digits: under a map the finder's `found` id (CID); in
#                    legacy plan_anchor.spec_comment.id
#   <updated_at>     its updated_at, YYYY-MM-DDTHH:MM:SSZ: the finder's (CUP) or, in legacy,
#                    plan_anchor.spec_comment.updated_at
#   <project.yml>    the DEFAULT branch's committed copy (the callers' $DEF_YML_FILE), never the
#                    working tree's, which a branch under review can edit
#   <reactions.tsv>  optional, read under a map for every declared author (a maintainer's and the dev App's): the caller's own capture of
#                      gh api "repos/<backlog-repo>/issues/comments/<comment-id>/reactions" --paginate \
#                        --jq '.[] | [(.user.id|tostring), .content, .created_at] | @tsv' >"$T/rx.tsv"
#                    the projection plan-anchor.sh uses, to a file with its exit status checked.
#                    A file from a fetch that failed is never passed: --paginate can write a
#                    first page before failing. It is fetched BEFORE the comment file, by the same
#                    comment id, in the same Bash call. This script cannot see which file was
#                    fetched first; it RELIES on that order, and every caller's prose must keep
#                    it. Then an edit after the reactions read moves the comment's `updated_at`
#                    off the <updated_at> argument, which is reported as `moved`. A legacy author ignores
#                    the argument.
#
# check prints exactly one word to stdout and exits 0 -- the FIRST failing check, in this order:
#   ok           -- all of the below hold
#   wrong-id     -- `.id` is not <comment-id>
#   moved        -- `.updated_at` is not <updated_at>: the comment was edited since that pair was read
#   wrong-issue  -- `.issue_url` is not https://api.github.com/repos/<backlog-repo>/issues/<issue>
#   untrusted    -- the author is not trusted. `gh-identity.sh role` on `.user.login` and
#                   `.user.id`: `maintainer` and `dev_app` go on to the reaction check below; `legacy`
#                   (identities null, the repo has not cut over) passes only when
#                   `.author_association` is OWNER, MEMBER or COLLABORATOR; `reviewer_app`,
#                   `loop_app`, `undeclared`, an exit of 2 and any other word fail
#   unreacted    -- under a map, the author is a declared maintainer or the declared dev App and no
#                   declared maintainer has approved the text. A spec is never used, by any of the three readers above,
#                   without a declared maintainer's approving reaction (the four spec-reaction.sh
#                   accepts) created strictly after its last edit (WB-D24 item 6, WB-D30): the dev
#                   App can write a spec but cannot approve one, since an App cannot react as another
#                   user, and a maintainer's own reaction approves their own comment. The rule is
#                   spec-reaction.sh, run on the comment's
#                   `updated_at`, the maintainer ids read from <project.yml> (only under a map,
#                   `identities.maintainer`, aliases expanded, every `id` an !!int above 0 and canonical decimal, at
#                   least one; anything else is `unreacted`) and the reactions file. Only
#                   `approved` passes. No file, a missing or unreadable file, an exit 2 from
#                   spec-reaction.sh and any other word are `unreacted`, never `unreadable`, which
#                   still covers the comment file only. A legacy comment (identities null) carries
#                   no such condition. The id of the dev App, the reviewer App or the loop App
#                   (`identities.dev_app`, `.reviewer_app`, `.loop_app`) on the approver list, or an
#                   entry of one of them that is neither null nor well formed (a map with a canonical
#                   decimal !!int `id` above 0 and a string `login`), makes a maintainer or dev-App
#                   author's comment `unreacted` too (#708): the dev App and the reviewer App have
#                   Issues write and could edit the text and then approve it, and the loop App is
#                   treated as the same class. The dev App's own id on the list, as an author,
#                   is refused earlier as `untrusted` when the id is spelled canonically (a
#                   non-canonical spelling, `+2001` or `0x7D1`, reads the colliding account as a
#                   maintainer in gh-identity.sh, and this check refuses it). For a reviewer or loop
#                   App id on the list, a maintainer or dev-App author reaches this check and reads
#                   `unreacted`, as does a non-canonical spelling (`+2002`, `0x7D2`) of its id; the colliding account itself is refused earlier as `untrusted` only
#                   when the App's id is spelled canonically (gh-identity.sh `role` dies on an id
#                   declared more than once, or under another login). No reaction clears it; the
#                   config has to change. A missing App key means no check, as in spec-find.sh.
#                   Otherwise a maintainer author is approved by any declared maintainer's
#                   reaction, their own included, as in spec-find.sh and plan-anchor.sh.
#   unreadable  -- the file is missing, is not JSON, or lacks a field (or has one of the wrong
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
# gh-identity.sh (a slash-less $0, or none beside it), or, for a declared author under a map, its
# siblings spec-reaction.sh and declared-ids.sh: a broken install must not read as "waiting for a maintainer
# reaction", so that is exit 2 with nothing on stdout, never `unreacted`. (An exit 2 FROM
# spec-reaction.sh, a bad argument, is `unreacted`.) The caller treats any non-zero exit as a
# stop, never as ok.
#
# `.id` and `.updated_at` are compared as exact strings against validated arguments, and the
# author goes through gh-identity.sh, which validates the login and id shape itself.
# gh-identity.sh, spec-reaction.sh and declared-ids.sh are the SIBLING copies and only those: a slash-less `$0`
# would resolve `dirname` to the current directory, where a branch under review could supply
# one that prints `dev_app` or `approved` (plan-anchor.sh does the same for spec-reaction.sh).
# spec-reaction.sh and declared-ids.sh (#1079, which holds the `identities` rules) are looked for only
# when the author is a declared maintainer or the dev App (a map), so a legacy author's word never
# depends on them.
#
# Permitted toolset: POSIX sh and yq (mikefarah v4, which reads JSON), the toolset gh-identity.sh
# already needs. No system jq, no python.
set -eu

usage() {
  echo "usage: spec-comment.sh check|body <comment.json> <backlog-repo> <issue> <comment-id> <updated_at> <project.yml> [<reactions.tsv>]" >&2
  exit 2
}
[ "$#" -eq 7 ] || [ "$#" -eq 8 ] || usage
mode="$1" file="$2" repo="$3" issue="$4" cid="$5" updated="$6" yml="$7" rx="${8:-}"

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
  */*) gi="$(dirname "$0")/gh-identity.sh" sr="$(dirname "$0")/spec-reaction.sh" di="$(dirname "$0")/declared-ids.sh" ;;
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

  if who="$(sh "$gi" role "$f_login" "$f_uid" "$yml" 2>/dev/null)"; then
    case "$who" in
      maintainer | dev_app) reaction_word "$who"; return ;;
      legacy)
        assoc="$(J '.author_association | select(tag == "!!str")')" || assoc=
        case "$assoc" in OWNER | MEMBER | COLLABORATOR) echo ok; return ;; esac
        echo untrusted; return ;;
    esac
  fi
  echo untrusted
}

# A declared author (maintainer or dev App) needs a declared maintainer's fresh approving
# reaction. A missing sibling exits 2 (out of verdict()'s command substitution, nothing on
# stdout); everything else that is not `approved` is `unreacted`.
reaction_word() {
  [ -f "$sr" ] || { echo "spec-comment.sh: spec-reaction.sh not beside this script" >&2; exit 2; }
  [ -f "$di" ] || { echo "spec-comment.sh: declared-ids.sh not beside this script" >&2; exit 2; }
  [ -n "$rx" ] && [ -f "$rx" ] && [ -r "$rx" ] || { echo unreacted; return; }
  # declared-ids.sh holds the identities rules (#1079): the maintainer list is well formed, and no declared
  # App's entry is malformed, non-canonical or on the list (#708). No declared App is an approver: its id on
  # the maintainer list could approve its own text (the dev App and the reviewer App have Issues write; the
  # loop App is treated as the same class). A maintainer author is approved by any declared maintainer's
  # reaction, their own included. Anything but an `ok` line of three fields is unreacted.
  di_line="$(sh "$di" "$yml" </dev/null 2>/dev/null)" || { echo unreacted; return; }
  case "$di_line" in
    *"
"*) echo unreacted; return ;;
    "ok "*) : ;;
    *) echo unreacted; return ;;
  esac
  di_rest="${di_line#ok }"
  case "$di_rest" in *" "*" "* | " "* | *" " | "") echo unreacted; return ;; *" "*) : ;; *) echo unreacted; return ;; esac
  ids="${di_rest%% *}"
  case "${di_rest#* }" in
    -) : ;;
    '' | 0* | *[!0-9]*) echo unreacted; return ;;
  esac
  if [ "$1" = dev_app ]; then
    case ",$ids," in *",$f_uid,"*) echo unreacted; return ;; esac
  fi
  if got="$(sh "$sr" "$updated" "$ids" <"$rx" 2>/dev/null)" && [ "$got" = approved ]; then
    echo ok
  else
    echo unreacted
  fi
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
