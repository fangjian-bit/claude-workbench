#!/bin/sh
# Has a declared maintainer reacted to a spec comment since its last edit? One rule, one
# implementation, for the callers that ask it: plan-anchor.sh's `verify` (resume's auto-start
# check), /way-of-working:architect-review's *Task spec* paragraph (Map branch), which labels the spec it loaded (#613),
# spec-comment.sh, for a comment by any author under an identities map (#660, #678), spec-find.sh
# (#662), the loop's dispatch preflight (#666), and spec-issue.sh and spec-post.sh, which ask it
# the same question of a task issue the dev or reviewer App filed (#664, WB-D32): there the
# "comment" is the issue and its `updated_at` is the issue's, which a reaction does not move.
# Before this, plan-anchor.sh carried the rule inline and /way-of-working:architect-review could only say
# "approval not re-verified".
#
# Usage: spec-reaction.sh <comment-updated_at> <maintainer-ids> < reactions-file
#
#   <comment-updated_at>  the comment's `updated_at`, YYYY-MM-DDTHH:MM:SSZ -- its last edit.
#   <maintainer-ids>      comma-separated numeric user ids (identities.maintainer[].id from the
#                         DEFAULT branch's copy, never the working tree's).
#
# stdin is one reaction per line, TAB-separated -- the projection plan-anchor.sh already uses:
#
#   gh api "repos/{backlog.repo}/issues/comments/<id>/reactions" --paginate \
#     --jq '.[] | [(.user.id|tostring), .content, .created_at] | @tsv' >"$T/reactions.tsv"
#
# The caller writes that to a FILE and redirects it in, never pipes `gh` into this: a failed
# fetch through a pipe reads as an empty list, which this script answers `unreacted` -- a
# fail-open reading of a failure (invariants check 11).
#
# Prints exactly one word to stdout and exits 0:
#   approved   -- some row has a user_id on the list, content `+1`, `heart`, `hooray` or
#                 `rocket`, and a well-formed created_at STRICTLY after <comment-updated_at>
#   unreacted  -- no row qualifies, an empty stdin included. A malformed row is skipped, never
#                 fatal: it cannot approve, so skipping is the closed direction.
# Exits 2, printing NOTHING to stdout, when an argument is bad (wrong count, an id list that
# is empty or is not comma-separated digits, a malformed timestamp). The caller decides what
# 2 means; every caller treats it as "not approved" (unreadable, unreacted, no spec or a stop), never as approved.
#
# Strictly after, because an edit made in the same second as the reaction cannot be ordered
# against it, and an unordered reaction does not approve text it may not have seen. The
# timestamps are fixed-width UTC, so string order is time order.
#
# No network, no files, no jq/yq. POSIX sh + awk, like review-gate-state.sh.
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: spec-reaction.sh <comment-updated_at> <maintainer-ids> < reactions-file" >&2
  exit 2
fi
updated="$1"
ids="$2"

case "$updated" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) : ;;
  *) echo "spec-reaction.sh: malformed comment updated_at" >&2; exit 2 ;;
esac
# Digits and single commas only: not empty, no leading, trailing or doubled comma.
case "$ids" in
  '' | *[!0-9,]* | ,* | *, | *,,*) echo "spec-reaction.sh: maintainer ids must be comma-separated digits" >&2; exit 2 ;;
esac

# Values travel through ENVIRON, not `-v`, which runs escape processing on its value.
SR_UPDATED="$updated" SR_IDS="$ids" awk -F '\t' '
  BEGIN { updated = ENVIRON["SR_UPDATED"]; ids = "," ENVIRON["SR_IDS"] ","; ok = 0 }
  NF != 3 { next }
  index(ids, "," $1 ",") == 0 { next }
  !($2 == "+1" || $2 == "heart" || $2 == "hooray" || $2 == "rocket") { next }
  $3 !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/ { next }
  $3 > updated { ok = 1; exit }
  END { print (ok ? "approved" : "unreacted") }
'
