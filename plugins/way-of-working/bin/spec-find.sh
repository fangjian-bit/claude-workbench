#!/bin/sh
# Which comment on a task issue is its approved spec? One implementation of the selection
# WB-D29's binding rules for marker readers set out, so the readers do not each carry it in
# prose (#662). Its callers: /way-of-working:resume, the coder agent,
# scripts/lanes/lane.sh, bin/lane-state.sh, bin/lane-groups.sh, /way-of-working:architect-review and
# /way-of-working:spec-task (the `answer` mode, #790); each runs it in the Bash call that uses its result.
#
# Usage: spec-find.sh find <issue> <project.yml>
#        spec-find.sh pending <issue> <project.yml> <after-id>
#        spec-find.sh answer <issue> <project.yml>
#
#   <issue>        the task issue number, digits with no leading zero
#   <project.yml>  the DEFAULT branch's committed copy (the callers' $DEF_YML_FILE), never the
#                  working tree's, which a branch under review can edit
#   <after-id>     `pending` only: a comment id, digits with no leading zero (the found CID)
#
# `pending` (#663) uses the same configuration reads, the same one listing and the same static,
# role, reaction and `moved` logic as `find`. It answers whether an unreacted draft, or an
# escalated comment, newer than the approved spec is already posted, so resume does not post a
# duplicate. Its words are, in order: `unreadable`, `moved <id>`, `pending <id>[,<id>...]` (the
# `spec-task:` rows that passed the role check, are not approved candidates and have an id greater
# than <after-id>, plus the role-passed escalated rows with an id greater than <after-id>, compared
# as digit strings: the longer is larger, equal lengths compare as strings) or `pending none`.
#
# `answer` (#790, WB-D39) finds the declared maintainer's answer to the newest escalated comment, under
# the same configuration reads, the same one listing and the same static and role checks. The listing's
# regex alternates a third first-line grammar, `spec-task-answer: escalated=<id> choice=apply|amend`; an
# answer row is projected with a ninth field (its `created_at`), so the `NF != 8` rule keeps it out of
# `find` and `pending`, whose words do not change. Its words, the first that applies winning:
# `unreadable` (as for `find`), `moved <id>` (as for `find`), `ignored <id>[,<id>...]` or `not-escalated`
# (the word `find` would print on this listing is not `escalated`: `ignored` when the listing holds
# answer-shaped rows, comma-joined in listing order, which passed only the static filters and the
# declared-maintainer author-id filter, no target, time or role check, no reactions and no comment
# text read; `not-escalated` when it holds none), `none` (no answer row qualifies), `ambiguous <id>,<id>[,...]`
# (two or more qualify) and `answer <esc-id> <esc-updated_at> <ans-id> <ans-updated_at> <choice>`. The
# target is the role-passed escalated row with the largest id. An answer qualifies only when its
# `escalated=` is the target's id, its `issue_url` is the backlog repo's URL for <issue>, its author's
# numeric id is a declared maintainer's (never the dev App's), `gh-identity.sh role` says `maintainer`
# for it (anything else is `unreadable`), its `created_at` equals its `updated_at` and is strictly later
# than the target's `updated_at` (YYYY-MM-DDTHH:MM:SSZ, compared as strings). The author-id filter runs
# before the role check. No reactions are read for an answer row.
#
# It makes its own `gh` calls: one paginated listing of the issue's comments, then, for each
# `spec-task:` comment that clears the static and role checks, that comment's reactions and a second
# read of its `updated_at`. An escalated comment gets the role check only (#746). Every `gh` call's stderr goes to /dev/null. It never prints comment text,
# on stdout or stderr, and it writes only its own fixed diagnostics to stderr.
#
# A comment is a candidate only when ALL of these hold:
#   - its first line is exactly the spec-task marker (`spec-task: issue=N base=B sha=<40 hex>`),
#     or the escalated marker (`spec-task-escalated: ...`, the same fields; such a comment is
#     never a candidate whatever its reactions, see `escalated` below), matched inside gh's own --jq on the raw first line, so the check and the use see the same
#     bytes. A body that breaks lines with CR alone, or carries a character the pattern does
#     not allow, does not match. `sha=` is checked for shape only and never passed to git.
#   - the marker's `issue=` is <issue> and its `base=` is the project file's `pr_base`, and the
#     comment's `issue_url` is the backlog repo's URL for <issue>
#   - its author's numeric id is a declared maintainer's or the declared dev App's, compared
#     before any other process runs, so an outsider's marker comments never reach the role or
#     reaction checks
#   - gh-identity.sh `role` says `maintainer` for a maintainer id and `dev_app` for the dev-App id
#   - spec-reaction.sh says `approved` on the comment's listed `updated_at`, the maintainer ids
#     (never the dev App's) and the comment's reactions. The comment's `updated_at` is read
#     again after the reactions; a changed value is `moved`.
# Rows are de-duplicated on id first (pagination can repeat one), keeping the first.
#
# Read from <project.yml> with yq, aliases expanded: `pr_base` (a plain branch name) and the
# backlog repo (`backlog.repo`, or `repo` when that is null; owner/name). The rest, which declared-ids.sh
# reads (#1079) and which is where its rules live, is: `identities` (a map;
# under null, the legacy shape, the finder does not apply), `identities.maintainer` (at least
# one entry, each a map with an !!int `id` above 0 that is canonical decimal and a string `login`) and
# `identities.dev_app`, `identities.reviewer_app` and `identities.loop_app` (each null or
# missing: no check for that key here, and a missing key is a declared residual (WB-D30
# residual 7), though resume waits on it; otherwise a map of the same shape, whose id is not on the maintainer list (#708), and whose id is
# canonical decimal: digits, no leading zero, no sign or prefix, so `+2001`, `0x7D1`
# and `02001` are `unreadable` as `spec-comment.sh` has it, #707).
# A value failing its shape is `unreadable`.
#
# Prints exactly one line to stdout and exits 0. Every row is judged before anything prints,
# and the first word in this order wins:
#   unreadable                   -- a config value, a fetch, a read or a lookup failed, or a
#                                   value was not the shape expected
#   moved <id>                   -- the first row, in listing order, whose `updated_at` changed
#                                   between the listing and the second read
#   ambiguous <id>,<id>[,...]    -- two or more candidates; the finder never picks one
#   found <id> <updated_at>      -- exactly one candidate
#   unreacted <id>[,<id>...]     -- no candidate, but these `spec-task:` rows passed the role check
#   escalated <id>[,<id>...]     -- no `spec-task:` row passed the role check, but these
#                                   `spec-task-escalated:` rows did (listing order); no reactions
#                                   are read for them, and a reaction never makes one a spec
#   none                         -- no row passed the role check
# Before `found` prints, the id is re-checked as digits and `updated_at` as
# YYYY-MM-DDTHH:MM:SSZ; a failure prints `unreadable`.
#
# Exits 2, printing nothing to stdout, when an argument is bad (the wrong count, a mode other
# than `find`, `pending` or `answer`, an issue or <after-id> that is not digits with no leading zero),
# <project.yml> is unreadable,
# `$0` has no slash, or a sibling gh-identity.sh, spec-reaction.sh or declared-ids.sh is not beside this script.
# Like spec-comment.sh it uses only the SIBLING copies: a slash-less `$0` would resolve
# `dirname` to the current directory, where a branch under review could supply one that
# prints `maintainer` or `approved`.
#
# Permitted toolset: POSIX sh, gh, yq (mikefarah v4), awk and mktemp. Runs under LC_ALL=C.
set -eu
LC_ALL=C
export LC_ALL

usage() {
  echo "usage: spec-find.sh find <issue> <project.yml> | spec-find.sh pending <issue> <project.yml> <after-id> | spec-find.sh answer <issue> <project.yml>" >&2
  exit 2
}
[ "$#" -ge 1 ] || usage
mode="$1"
case "$mode" in
  find | answer) [ "$#" -eq 3 ] || usage ;;
  pending) [ "$#" -eq 4 ] || usage ;;
  *) usage ;;
esac
issue="$2" yml="$3" after=
case "$issue" in '' | 0* | *[!0-9]*) echo "spec-find.sh: issue must be digits with no leading zero" >&2; exit 2 ;; esac
if [ "$mode" = pending ]; then
  after="$4"
  case "$after" in '' | 0* | *[!0-9]*) echo "spec-find.sh: after-id must be digits with no leading zero" >&2; exit 2 ;; esac
fi
if [ ! -f "$yml" ] || ! yq -o=yaml '.' "$yml" >/dev/null 2>&1; then
  echo "spec-find.sh: unreadable project.yml" >&2
  exit 2
fi
case "$0" in
  */*) gi="$(dirname "$0")/gh-identity.sh" sr="$(dirname "$0")/spec-reaction.sh" di="$(dirname "$0")/declared-ids.sh" ;;
  *) echo "spec-find.sh: must be run by path (a slash-less \$0 cannot locate its siblings)" >&2; exit 2 ;;
esac
[ -f "$gi" ] || { echo "spec-find.sh: gh-identity.sh not beside this script" >&2; exit 2; }
[ -f "$sr" ] || { echo "spec-find.sh: spec-reaction.sh not beside this script" >&2; exit 2; }
[ -f "$di" ] || { echo "spec-find.sh: declared-ids.sh not beside this script" >&2; exit 2; }

tmp="$(mktemp -d)" || { echo "spec-find.sh: no temp directory" >&2; exit 2; }
trap 'rm -rf "$tmp"' EXIT

out() {
  printf '%s\n' "$*"
  exit 0
}

# --- the configuration -------------------------------------------------------------------
base="$(yq -r 'explode(.) | .pr_base | select(tag == "!!str")' "$yml" 2>/dev/null)" || out unreadable
case "$base" in '' | -* | *[!A-Za-z0-9._/-]*) out unreadable ;; esac

backlog="$(yq -r 'explode(.) | (.backlog.repo // .repo) | select(tag == "!!str")' "$yml" 2>/dev/null)" || out unreadable
case "$backlog" in
  '' | *[!A-Za-z0-9._/-]* | */*/* | /* | */ | ./* | ../* | */. | */..) out unreadable ;;
  */*) : ;;
  *) out unreadable ;;
esac

# The declared ids come from declared-ids.sh (#1079), whose line is held to its shape here: exactly
# `ok <ids> <dev>`, three fields, a non-empty list, a dev id of `-` or digits with no leading zero.
# One of five copies of the declared-ids.sh ok-line parser (spec-find, spec-comment, spec-answer, spec-issue, spec-post); a change to that line edits all five (declared-ids.sh header, #1105).
di_line="$(sh "$di" "$yml" </dev/null 2>/dev/null)" || out unreadable
case "$di_line" in
  *"
"*) out unreadable ;;
  "ok "*) : ;;
  *) out unreadable ;;
esac
di_rest="${di_line#ok }"
case "$di_rest" in *" "*" "* | " "* | *" " | "") out unreadable ;; *" "*) : ;; *) out unreadable ;; esac
maint_ids="${di_rest%% *}"
dev_id="${di_rest#* }"
case "$dev_id" in
  -) dev_id= ;;
  '' | 0* | *[!0-9]*) out unreadable ;;
esac

# --- the one listing ---------------------------------------------------------------------
gh api --paginate "repos/$backlog/issues/$issue/comments" --jq '.[] | (((.body // "") + "\n") | split("\n")[0] | rtrimstr("\r")) as $l | select($l | test("^(spec-task(-escalated)?: issue=[1-9][0-9]* base=[A-Za-z0-9._/][A-Za-z0-9._/-]* sha=[0-9a-f]{40}|spec-task-answer: escalated=[1-9][0-9]* choice=(apply|amend))$")) | ($l | split(" ")) as $f | [(.id|tostring), .updated_at, .issue_url, .user.login, (.user.id|tostring), ($f[1] | ltrimstr("issue=") | ltrimstr("escalated=")), ($f[2] | ltrimstr("base=") | ltrimstr("choice=")), ($f[0] | rtrimstr(":"))] + (if $f[0] == "spec-task-answer:" then [.created_at] else [] end) | @tsv' >"$tmp/list.tsv" 2>/dev/null || out unreadable

# --- the static rules --------------------------------------------------------------------
# Rows are de-duplicated on id (first kept), then each must have exactly 8 fields, one of the two
# kinds (`spec-task`, `spec-task-escalated`), digit ids, the asked-for issue and base, the backlog
# repo's issue URL and a declared author id. Output is id, login, user id, kind, updated_at, separated by US (0x1f), which is not whitespace to `read`.
# updated_at is last, so a malformed value cannot shift the others.
SF_ISSUE="$issue" SF_BASE="$base" SF_URL="https://api.github.com/repos/$backlog/issues/$issue" \
  SF_MAINT=",$maint_ids," SF_DEV="$dev_id" awk -F '\t' '
  BEGIN {
    issue = ENVIRON["SF_ISSUE"]; base = ENVIRON["SF_BASE"]; url = ENVIRON["SF_URL"]
    maint = ENVIRON["SF_MAINT"]; dev = ENVIRON["SF_DEV"]; us = sprintf("%c", 31)
  }
  seen[$1]++ { next }
  NF != 8 { next }
  $8 "" != "spec-task" && $8 "" != "spec-task-escalated" { next }
  $1 !~ /^[0-9]+$/ || $5 !~ /^[0-9]+$/ { next }
  $6 "" != issue "" || $3 "" != url "" || $7 "" != base "" { next }
  !(index(maint, "," $5 ",") > 0 || (dev != "" && $5 "" == dev "")) { next }
  { print $1 us $4 us $5 us $8 us $2 }
' "$tmp/list.tsv" >"$tmp/rows" 2>/dev/null || out unreadable

# --- the role, reactions and approval of each remaining row ------------------------------
US="$(printf '\037')"
moved_id=
cand_ids=
cand_n=0
cand_updated=
role_ids=
esc_ids=
esc_target=
esc_target_updated=
pend_ids=
n=0
# gt <a> <b> -- yes when digit string a is larger than b: the longer is larger, equal lengths compare as
# strings. awk, since POSIX test has no string order.
gt() {
  SF_A="$1" SF_B="$2" awk 'BEGIN { a = ENVIRON["SF_A"]; b = ENVIRON["SF_B"]; print (length(a) > length(b) || (length(a) == length(b) && a "" > b "")) ? "yes" : "no" }'
}
while IFS="$US" read -r c_id c_login c_uid c_kind c_updated; do
  n=$((n + 1))
  case "$c_id" in '' | *[!0-9]*) out unreadable ;; esac
  case "$c_uid" in '' | *[!0-9]*) out unreadable ;; esac
  case ",$maint_ids," in *",$c_uid,"*) want=maintainer ;; *) want=dev_app ;; esac
  got="$(sh "$gi" role "$c_login" "$c_uid" "$yml" 2>/dev/null </dev/null)" || out unreadable
  [ "$got" = "$want" ] || out unreadable
  if [ "$c_kind" = spec-task-escalated ]; then
    esc_ids="${esc_ids:+$esc_ids,}$c_id"
    if [ -z "$esc_target" ] || [ "$(gt "$c_id" "$esc_target")" = yes ]; then
      esc_target="$c_id" esc_target_updated="$c_updated"
    fi
    if [ "$mode" = pending ] && [ "$(gt "$c_id" "$after")" = yes ]; then
      pend_ids="${pend_ids:+$pend_ids,}$c_id"
    fi
    continue
  fi
  role_ids="${role_ids:+$role_ids,}$c_id"

  rx="$tmp/rx.$n"
  gh api "repos/$backlog/issues/comments/$c_id/reactions" --paginate --jq '.[] | [(.user.id|tostring), .content, .created_at] | @tsv' >"$rx" 2>/dev/null </dev/null || out unreadable
  again="$(gh api "repos/$backlog/issues/comments/$c_id" --jq .updated_at 2>/dev/null </dev/null)" || out unreadable
  if [ "$again" != "$c_updated" ]; then
    [ -n "$moved_id" ] || moved_id="$c_id"
    continue
  fi
  verdict="$(sh "$sr" "$c_updated" "$maint_ids" <"$rx" 2>/dev/null)" || out unreadable
  if [ "$verdict" = approved ]; then
    cand_ids="${cand_ids:+$cand_ids,}$c_id"
    cand_n=$((cand_n + 1))
    cand_updated="$c_updated"
  elif [ "$mode" = pending ]; then
    if [ "$(gt "$c_id" "$after")" = yes ]; then
      pend_ids="${pend_ids:+$pend_ids,}$c_id"
    fi
  fi
done <"$tmp/rows"

# --- the word ----------------------------------------------------------------------------
[ -z "$moved_id" ] || out "moved $moved_id"
if [ "$mode" = answer ]; then
  # `find` prints `escalated` only with no candidate, no role-passed spec-task row and an escalated row.
  if ! { [ "$cand_n" -eq 0 ] && [ -z "$role_ids" ] && [ -n "$esc_target" ]; }; then
    # The answer branch does not apply. Name the maintainer's answer-shaped rows (static and author-id
    # filters only: no target, time or role check) so the skill can say they are not used (#1078).
    SF_URL="https://api.github.com/repos/$backlog/issues/$issue" SF_MAINT=",$maint_ids," awk -F '\t' '
      BEGIN { url = ENVIRON["SF_URL"]; maint = ENVIRON["SF_MAINT"] }
      seen[$1]++ { next }
      NF != 9 || $8 "" != "spec-task-answer" { next }
      $1 !~ /^[0-9]+$/ || $5 !~ /^[0-9]+$/ { next }
      $3 "" != url "" || index(maint, "," $5 ",") == 0 { next }
      $7 "" != "apply" && $7 "" != "amend" { next }
      { print $1 }
    ' "$tmp/list.tsv" >"$tmp/ignored" 2>/dev/null || out unreadable
    ign_ids=
    while read -r i_id; do
      case "$i_id" in '' | *[!0-9]*) out unreadable ;; esac
      ign_ids="${ign_ids:+$ign_ids,}$i_id"
    done <"$tmp/ignored"
    [ -z "$ign_ids" ] || out "ignored $ign_ids"
    out not-escalated
  fi
  case "$esc_target_updated" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) : ;;
    *) out unreadable ;;
  esac
  # Answer rows (nine fields): dedupe on id, the author id a declared maintainer's (never the dev App's),
  # digit ids, the target's id, the backlog repo's URL, a choice, created_at equal to updated_at and later
  # than the target's updated_at. Output is id, login, user id, updated_at, choice, US-separated.
  SF_URL="https://api.github.com/repos/$backlog/issues/$issue" SF_MAINT=",$maint_ids," SF_TARGET="$esc_target" awk -F '\t' '
    BEGIN {
      url = ENVIRON["SF_URL"]; maint = ENVIRON["SF_MAINT"]; target = ENVIRON["SF_TARGET"]
      us = sprintf("%c", 31)
    }
    seen[$1]++ { next }
    NF != 9 || $8 "" != "spec-task-answer" { next }
    $1 !~ /^[0-9]+$/ || $5 !~ /^[0-9]+$/ { next }
    $3 "" != url "" || $6 "" != target "" { next }
    index(maint, "," $5 ",") == 0 { next }
    $7 "" != "apply" && $7 "" != "amend" { next }
    { print $1 us $4 us $5 us $2 us $9 us $7 }
  ' "$tmp/list.tsv" >"$tmp/arows" 2>/dev/null || out unreadable
  ans_n=0 ans_ids= ans_line=
  while IFS="$US" read -r a_id a_login a_uid a_updated a_created a_choice; do
    case "$a_id" in '' | *[!0-9]*) out unreadable ;; esac
    case "$a_uid" in '' | *[!0-9]*) out unreadable ;; esac
    got="$(sh "$gi" role "$a_login" "$a_uid" "$yml" 2>/dev/null </dev/null)" || out unreadable
    [ "$got" = maintainer ] || out unreadable
    for ts in "$a_updated" "$a_created"; do
      case "$ts" in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) : ;;
        *) out unreadable ;;
      esac
    done
    [ "$a_created" = "$a_updated" ] || continue
    [ "$(SF_A="$a_created" SF_B="$esc_target_updated" awk 'BEGIN { print (ENVIRON["SF_A"] "" > ENVIRON["SF_B"] "") ? "yes" : "no" }')" = yes ] || continue
    ans_n=$((ans_n + 1))
    ans_ids="${ans_ids:+$ans_ids,}$a_id"
    ans_line="answer $esc_target $esc_target_updated $a_id $a_updated $a_choice"
  done <"$tmp/arows"
  [ "$ans_n" -gt 0 ] || out none
  [ "$ans_n" -lt 2 ] || out "ambiguous $ans_ids"
  out "$ans_line"
fi
if [ "$mode" = pending ]; then
  out "pending ${pend_ids:-none}"
fi
[ "$cand_n" -lt 2 ] || out "ambiguous $cand_ids"
if [ "$cand_n" -eq 1 ]; then
  case "$cand_ids" in '' | *[!0-9]*) out unreadable ;; esac
  case "$cand_updated" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) : ;;
    *) out unreadable ;;
  esac
  out "found $cand_ids $cand_updated"
fi
[ -z "$role_ids" ] || out "unreacted $role_ids"
[ -z "$esc_ids" ] || out "escalated $esc_ids"
out none
