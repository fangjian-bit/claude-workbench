#!/bin/sh
# The deterministic predicate behind the `planning: kind: github_milestones` key
# (reference/project-schema.md § `planning`) -- whether a cursor's `plan_anchor`
# still names a live, open milestone, task issue, and spec comment.
# Mirrors cursor-drift.sh's shape and reasoning: a predicate with a correctness
# argument, not a judgment call, so /way-of-working:resume's auto-start test,
# /way-of-working:handoff's re-anchor check, and /way-of-working:archive-sprint's
# milestone-close check all call this script rather than recomputing the
# comparison in skill prose.
#
# Usage:
#   plan-anchor.sh write  <repo> <milestone> <N|-> [<comment-id|->]
#     Prints the anchor JSON (one line, compact, fixed key order) on stdout,
#     or `unreadable`.
#   plan-anchor.sh verify [--plan] [--loop-identity <login>] [--maintainer-ids <id,id,...>] [--dev-app-id <id>] <repo> <pointer-url> <anchor-json>
#     Prints exactly one of `match | drift | unreadable | untrusted | unreacted`.
#
# Both modes always exit 0 -- the verdict is stdout, exactly like
# cursor-drift.sh; the caller decides policy.
#
# `--loop-identity <login>` is the name rule (plan § 8.1, § 8.13d; `#235`): the
# loop's own login (`orchestration.loop_identity`, reference/project-schema.md §
# `orchestration`) is untrusted BY NAME, whatever `author_association` says -- a
# machine user's MEMBER or COLLABORATOR association would pass any association
# check, and a `loop_identity` left stale after the loop's login changed must not
# turn that into a trusted author. The login arrives as an ARGUMENT, never read here
# (this script forbids `yq`, and the caller already holds the value from the default
# branch's own copy -- the one a task cannot edit). When given, `verify` reads the
# author of the milestone (`creator`), and in full mode of `#N` and of the anchored
# spec comment, BEFORE any drift comparison, and prints `untrusted` when any of them
# equals the login, compared case-insensitively (GitHub logins are) and with a trailing
# `[bot]` ignored on both sides, so a bare-slug configuration still matches an App. A failed author
# read, or an empty author, is `unreadable`, never a pass. A caller whose
# `loop_identity` is `null` omits the flag; an EMPTY or malformed value is a caller
# bug and prints `unreadable` rather than silently disabling the rule. Everything
# else about the verdict is unchanged: without this flag and without `--maintainer-ids`
# no author is checked, and `untrusted` is never printed.
#
# `--maintainer-ids <id,id,...>` is the reaction rule (`WB-D24`, `#383`): a comment alone
# never approves a spec. When given, full-mode `verify` -- after every other check has
# passed -- also requires a spec comment to be anchored and a reaction on that
# exact comment (`reactions` of the comment id the anchor names, never another) that was
# made by a declared maintainer (matched on the numeric user `id`, never the login),
# whose `created_at` is STRICTLY after the comment's `updated_at` (a reaction does not
# move `updated_at` -- observed once, live, 2026-10-12, `#498`: a `rocket` added six seconds
# after a comment was created left its `updated_at` equal to `created_at`; were that ever to
# change, nothing would match, never a false match -- so an edit after the reaction leaves it stale), and whose content
# is an approving one (`+1`, `heart`, `hooray`, `rocket`; `-1`, `confused`, `eyes` and
# `laugh` never count). Otherwise it prints `unreacted`, which a caller treats as a wait,
# exactly like `drift`. Before the reactions are read, the anchored comment's own author
# (numeric `user.id`, never the login) must also be on the list (`#497`; or, with `--dev-app-id`, be the dev App, below), else `untrusted`:
# a reaction approves the text, not who wrote it. That check follows the drift checks. The ids arrive as an ARGUMENT, read by the caller from the
# default branch's `identities.maintainer` (this script forbids `yq`); an empty or
# non-numeric list is a caller bug and prints `unreadable`. A caller whose repo has not
# cut over (`identities: null`) omits the flag and keeps today's behavior. With the flag and
# NO spec comment anchored the verdict is `unreacted`: the issue body alone is editable text
# whose author stays the maintainer, so it is never an approval. `--plan` mode validates
# the list but otherwise ignores it, as it ignores the spec comment. A failed reactions read is `unreadable`. The rule itself is bin/spec-reaction.sh (an exit 2 from it, or a missing or slash-less sibling path, is `unreadable`), and the comment's updated_at is re-read after the reactions: a change prints `drift`.
#
# `--dev-app-id <id>` (`#660`) lets the declared dev App (`identities.dev_app.id`, read by the
# caller from the default branch's copy) author the spec comment. In full mode the `#497`
# author check then passes when the comment's numeric `user.id` is on the maintainer list OR
# equals this id (whole-string comparison). The reactions are still judged against the
# maintainer list only (spec-reaction.sh is called with the maintainer ids only), so the dev App's own reaction
# never approves: it can write a spec, never approve one. It needs `--maintainer-ids` and is a
# positive integer with no leading zero that is not itself a maintainer id (a dev App that is a
# maintainer could approve its own text); without `--maintainer-ids`, with no value, malformed
# or overlapping, `verify` prints `unreadable`. `--plan` validates it and ignores it. A caller
# whose `identities.dev_app` is `null` omits the flag.
#
# `verify` (full) checks: the milestone is open, its number equals the anchor's
# and the pointer's; `#N` is open, a true issue (no `pull_request` key), its
# `repository_url` names `<repo>` and its `number` is `N`, its `milestone.number`
# matches, and its `updated_at` equals the anchor's; the spec comment (when
# anchored) has `updated_at` equal to the anchor's and belongs to issue `#N`;
# nothing else.
#
# `verify --plan` checks only: milestone open and number equality. It ignores `task_issue` and `spec_comment` entirely -- the mode
# handoff's baseline re-anchor check uses, and archive-sprint's milestone-close
# check uses too, since `#N` is legitimately null or closed by the time a
# milestone closes.
#
# The anchor JSON's shape is fixed and produced only by this script's own
# `write` mode -- never hand-written -- so `verify` parses that one shape with
# a handful of anchored sed patterns rather than a general JSON parser. That is
# a deliberate, narrow choice (the same one entry-anchor.sh makes for ledger
# lines): a general parser needs a real interpreter, which the rest of this
# plugin's bin/ scripts are written to avoid requiring.
#
# The milestone's free-text body is not bound by this anchor (`WB-D27`, `#628`, `#637`):
# neither mode fetches it. An older anchor may still carry a `description_sha256` key;
# `verify` tolerates it and ignores its value.
#
# Permitted toolset: POSIX sh and `gh` (using only its own embedded --jq). No system `jq`, no `yq`, no python -- the
# same bar as cursor-drift.sh and entry-anchor.sh: this must run on any
# maintainer machine with nothing extra installed beyond `gh` itself, which
# the rest of this predicate's job already requires. The anchor parser below
# also avoids `sed`'s `\|` alternation deliberately -- it is a GNU extension,
# not POSIX BRE, and BSD/macOS sed (the default `sed` on a stock Mac) gives no
# output at all for it, which would silently break this script on exactly the
# "any maintainer machine" this header promises. Two independent `sed -n`
# passes (try the non-null shape, then try the literal `null`) do the same job
# with only single-alternative BRE patterns.
set -eu

tmp="$(mktemp -d)" || { echo unreadable; exit 0; }
trap 'rm -rf "$tmp"' EXIT

is_digits() { # is_digits <s> -- true iff <s> is one or more ASCII digits
  case "$1" in
    '' | *[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

tsv_field() { # tsv_field <n> <tsv-line> -- the nth tab-separated field
  printf '%s\n' "$2" | awk -F'\t' -v n="$1" '{print $n}'
}

# --- anchor JSON: a fixed shape parsed narrowly (see header) ----------------
#
#   {"milestone":<N>,"task_issue":<N|null>,
#    "task_issue_updated_at":<"<ts>"|null>,"spec_comment":<{"id":<N>,
#    "updated_at":"<ts>"}|null>}
#
# An older anchor also carries "description_sha256":"<64 hex>" after "milestone";
# `verify` never reads it. Every value here is either digits, "null", or a
# quote-free string (an ISO-8601 timestamp), so one pair of anchored sed patterns per key
# is enough -- there is never an escaped quote or a brace to worry about,
# because this script is the only writer of this shape. `[[:space:]]*` after
# the colon tolerates any run of spaces or tabs there (`"key":  value`),
# because `sed` matches per LINE, not across them. That covers a key and its
# value staying on one line, whatever else on the same line is reformatted --
# it does NOT cover a genuinely multi-line, pretty-printed anchor (`jq .`'s
# default output splits `"spec_comment"` from its object across several
# lines), which this parser cannot read at all and answers `unreadable` for,
# same as any other malformed shape. The caller is responsible for handing
# this script the anchor as a SINGLE LINE -- `jq -c` ("compact"), never plain
# `jq .` -- when extracting it from wherever it is stored; the calling skills
# say so at each call site.
#
# Every extractor returns empty ("") when the key is present but its value
# doesn't match the expected shape -- callers MUST check `anchor_has_key`
# first and treat "key present, value didn't parse" as unreadable. Treating
# that emptiness the same as "key legitimately absent" is exactly the bug a
# critic round caught here: a truncated or malformed `spec_comment` object
# read as `null` and `verify` answered `match` on an anchor it could not
# actually parse -- the one path to a false `match` in a script whose whole
# job is to fail closed.
anchor_has_key() { # anchor_has_key <key> <json> -- true (0) iff `"key":` occurs literally
  case "$2" in
    *'"'"$1"'":'*) return 0 ;;
    *) return 1 ;;
  esac
}
anchor_num() { # anchor_num <key> <json> -- digits, "null", or "" (malformed)
  v="$(printf '%s' "$2" | sed -n 's/.*"'"$1"'":[[:space:]]*\([0-9][0-9]*\).*/\1/p')"
  if [ -n "$v" ]; then printf '%s' "$v"; return; fi
  printf '%s' "$2" | sed -n 's/.*"'"$1"'":[[:space:]]*null.*/null/p'
}
anchor_str() { # anchor_str <key> <json> -- the string (unquoted), "null", or ""
  v="$(printf '%s' "$2" | sed -n 's/.*"'"$1"'":[[:space:]]*"\([^"]*\)".*/\1/p')"
  if [ -n "$v" ]; then printf '%s' "$v"; return; fi
  printf '%s' "$2" | sed -n 's/.*"'"$1"'":[[:space:]]*null.*/null/p'
}
anchor_obj() { # anchor_obj <key> <json> -- the raw {...} (one level deep), "null", or ""
  v="$(printf '%s' "$2" | sed -n 's/.*"'"$1"'":[[:space:]]*\({[^{}]*}\).*/\1/p')"
  if [ -n "$v" ]; then printf '%s' "$v"; return; fi
  printf '%s' "$2" | sed -n 's/.*"'"$1"'":[[:space:]]*null.*/null/p'
}

mode="${1:-}"
case "$mode" in
  write | verify) shift ;;
  *)
    echo "plan-anchor.sh: usage: plan-anchor.sh write <repo> <milestone> <N|-> [<comment-id|->]" >&2
    echo "                       plan-anchor.sh verify [--plan] [--loop-identity <login>] [--maintainer-ids <id,id,...>] [--dev-app-id <id>] <repo> <pointer-url> <anchor-json>" >&2
    echo unreadable
    exit 0
    ;;
esac

# =============================================================================
if [ "$mode" = write ]; then
  if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
    echo "plan-anchor.sh: write needs <repo> <milestone> <N|-> [<comment-id|->]" >&2
    echo unreadable
    exit 0
  fi
  repo="$1"; milestone="$2"; task="$3"; comment="${4:--}"

  if ! is_digits "$milestone"; then echo unreadable; exit 0; fi
  if [ "$task" != "-" ] && ! is_digits "$task"; then echo unreadable; exit 0; fi
  if [ "$comment" != "-" ] && ! is_digits "$comment"; then echo unreadable; exit 0; fi

  # A leading zero is rejected before any call: the comparison below is a string one and
  # must not depend on how GitHub answers `012`.
  case "$milestone" in 0*) echo unreadable; exit 0 ;; esac
  ms_number="$(gh api "repos/$repo/milestones/$milestone" --jq .number 2>/dev/null)" \
    && [ "$ms_number" = "$milestone" ] || { echo unreadable; exit 0; }

  task_field=null
  task_updated_field=null
  if [ "$task" != "-" ]; then
    task_updated="$(gh api "repos/$repo/issues/$task" --jq '.updated_at // empty' 2>/dev/null)" \
      && [ -n "$task_updated" ] || { echo unreadable; exit 0; }
    task_field="$task"
    task_updated_field="\"$task_updated\""
  fi

  comment_field=null
  if [ "$comment" != "-" ]; then
    comment_updated="$(gh api "repos/$repo/issues/comments/$comment" --jq '.updated_at // empty' 2>/dev/null)" \
      && [ -n "$comment_updated" ] || { echo unreadable; exit 0; }
    comment_field="{\"id\":$comment,\"updated_at\":\"$comment_updated\"}"
  fi

  printf '{"milestone":%s,"task_issue":%s,"task_issue_updated_at":%s,"spec_comment":%s}\n' \
    "$milestone" "$task_field" "$task_updated_field" "$comment_field"
  exit 0
fi

# =============================================================================
# mode = verify
plan_only=0
loop_login=
have_loop=0
maint_ids=
have_ids=0
dev_id=
have_dev=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --plan) plan_only=1; shift ;;
    --loop-identity)
      [ "$#" -ge 2 ] || { echo unreadable; exit 0; }
      have_loop=1; loop_login="$2"; shift 2 ;;
    --maintainer-ids)
      [ "$#" -ge 2 ] || { echo unreadable; exit 0; }
      have_ids=1; maint_ids="$2"; shift 2 ;;
    --dev-app-id)
      [ "$#" -ge 2 ] || { echo unreadable; exit 0; }
      have_dev=1; dev_id="$2"; shift 2 ;;
    *) break ;;
  esac
done

if [ "$#" -ne 3 ]; then
  echo "plan-anchor.sh: verify needs [--plan] [--loop-identity <login>] [--maintainer-ids <id,id,...>] [--dev-app-id <id>] <repo> <pointer-url> <anchor-json>" >&2
  echo unreadable
  exit 0
fi
repo="$1"; pointer="$2"; anchor="$3"

# The maintainer ids: comma-separated positive integers, no empty element.
if [ "$have_ids" -eq 1 ]; then
  [ -n "$maint_ids" ] || { echo unreadable; exit 0; }
  case "$maint_ids" in *[!0-9,]*) echo unreadable; exit 0 ;; esac
  oldifs="$IFS"; IFS=,
  # shellcheck disable=SC2086
  set -- $maint_ids
  IFS="$oldifs"
  for _id in "$@"; do
    is_digits "$_id" || { echo unreadable; exit 0; }
    case "$_id" in 0*) echo unreadable; exit 0 ;; esac
  done
  case "$maint_ids" in *,,* | ,* | *,) echo unreadable; exit 0 ;; esac
  set -- "$repo" "$pointer" "$anchor"
fi

# The dev App's id (`#660`): needs the maintainer ids, a positive integer with no leading zero,
# and must not be one of them -- a dev App that is also a maintainer could approve its own text.
# Checked after the flag loop, so flag order does not matter.
if [ "$have_dev" -eq 1 ]; then
  [ "$have_ids" -eq 1 ] || { echo unreadable; exit 0; }
  is_digits "$dev_id" || { echo unreadable; exit 0; }
  case "$dev_id" in 0*) echo unreadable; exit 0 ;; esac
  case ",$maint_ids," in *",$dev_id,"*) echo unreadable; exit 0 ;; esac
fi

# The pointer must be exactly https://github.com/<repo>/milestone/<digits> --
# an anchored match on <repo>, digits-only number (project-schema.md § `planning`).
prefix="https://github.com/$repo/milestone/"
case "$pointer" in
  "$prefix"*) num_pointer="${pointer#"$prefix"}" ;;
  *) echo unreadable; exit 0 ;;
esac
if ! is_digits "$num_pointer"; then echo unreadable; exit 0; fi

if ! anchor_has_key milestone "$anchor"; then
  echo unreadable; exit 0
fi
a_milestone="$(anchor_num milestone "$anchor")"
if [ -z "$a_milestone" ] || [ "$a_milestone" = null ]; then
  echo unreadable; exit 0
fi

# --- the name rule (see header): before ANY drift comparison -------------------
if [ "$have_loop" -eq 1 ]; then
  # A login is a stem of letters, digits and `-` (no leading or trailing `-`, at
  # most 39 characters) plus an optional `[bot]`; anything else is a caller bug.
  stem="${loop_login%\[bot\]}"
  case "$stem" in
    '' | -* | *- | *[!A-Za-z0-9-]*) echo unreadable; exit 0 ;;
  esac
  [ "${#stem}" -le 39 ] || { echo unreadable; exit 0; }
  # Case-folded AND `[bot]`-folded on both sides: REST reports an App as `<slug>[bot]`,
  # and a `loop_identity` configured as the bare slug (the schema's shape check allows
  # both) must not quietly match nothing. Over-refusing a human whose login is the slug
  # is the safe direction.
  fold() { printf '%s' "$1" | tr 'A-Z' 'a-z' | sed 's/\[bot\]$//'; }
  lc_loop="$(fold "$loop_login")"

  is_loop() { # is_loop <login> -- true iff it names the loop identity (folded)
    [ "$(fold "$1")" = "$lc_loop" ]
  }

  author="$(gh api "repos/$repo/milestones/$a_milestone" --jq '.creator.login // empty' 2>/dev/null)" \
    && [ -n "$author" ] || { echo unreadable; exit 0; }
  if is_loop "$author"; then echo untrusted; exit 0; fi

  if [ "$plan_only" -eq 0 ]; then
    n_task="$(anchor_num task_issue "$anchor")"
    case "$n_task" in
      '' | null) : ;;   # nothing anchored, or malformed -- the full checks below answer
      *)
        author="$(gh api "repos/$repo/issues/$n_task" --jq '.user.login // empty' 2>/dev/null)" \
          && [ -n "$author" ] || { echo unreadable; exit 0; }
        if is_loop "$author"; then echo untrusted; exit 0; fi
        ;;
    esac
    n_comment="$(anchor_obj spec_comment "$anchor")"
    case "$n_comment" in
      '' | null) : ;;
      *)
        n_cid="$(anchor_num id "$n_comment")"
        case "$n_cid" in
          '' | null) : ;;
          *)
            author="$(gh api "repos/$repo/issues/comments/$n_cid" --jq '.user.login // empty' 2>/dev/null)" \
              && [ -n "$author" ] || { echo unreadable; exit 0; }
            if is_loop "$author"; then echo untrusted; exit 0; fi
            ;;
        esac
        ;;
    esac
  fi
fi

if [ "$a_milestone" != "$num_pointer" ]; then echo drift; exit 0; fi

ms_state="$(gh api "repos/$repo/milestones/$a_milestone" --jq '.state // empty' 2>/dev/null)" \
  && [ -n "$ms_state" ] || { echo unreadable; exit 0; }
if [ "$ms_state" != open ]; then echo drift; exit 0; fi

if [ "$plan_only" -eq 1 ]; then
  echo match
  exit 0
fi

if ! anchor_has_key task_issue "$anchor"; then echo unreadable; exit 0; fi
a_task="$(anchor_num task_issue "$anchor")"
a_task_updated="$(anchor_str task_issue_updated_at "$anchor")"
if [ -z "$a_task" ]; then
  # The key is present but its value didn't parse as digits or `null` --
  # malformed, not the legitimate "no task anchored" shape below.
  echo unreadable; exit 0
fi
if [ "$a_task" = null ]; then
  # A planning cursor, or a milestone-close use, legitimately anchors no
  # task -- full verify has nothing to confirm live and therefore never
  # matches. Those callers use --plan instead; reaching here under full
  # verify with no task means the auto-start caller cannot proceed -- drift,
  # not unreadable.
  echo drift; exit 0
fi

issue_tsv="$(gh api "repos/$repo/issues/$a_task" --jq \
  '[.state, .updated_at, .repository_url, (.number|tostring),
    ((.milestone.number // "") | tostring),
    (if has("pull_request") then "1" else "0" end)] | @tsv' 2>/dev/null)" \
  && [ -n "$issue_tsv" ] || { echo unreadable; exit 0; }

i_state="$(tsv_field 1 "$issue_tsv")"
i_updated="$(tsv_field 2 "$issue_tsv")"
i_repo_url="$(tsv_field 3 "$issue_tsv")"
i_number="$(tsv_field 4 "$issue_tsv")"
i_milestone="$(tsv_field 5 "$issue_tsv")"
i_is_pr="$(tsv_field 6 "$issue_tsv")"

if [ "$i_state" != open ] || [ "$i_is_pr" = 1 ] || [ "$i_number" != "$a_task" ] \
   || [ "$i_repo_url" != "https://api.github.com/repos/$repo" ] \
   || [ "$i_milestone" != "$a_milestone" ] || [ "$i_updated" != "$a_task_updated" ]; then
  echo drift; exit 0
fi

if ! anchor_has_key spec_comment "$anchor"; then echo unreadable; exit 0; fi
a_comment="$(anchor_obj spec_comment "$anchor")"
if [ -z "$a_comment" ]; then
  # The key is present but its value is neither `null` nor a parseable
  # `{...}` -- malformed, never treated as "no comment anchored".
  echo unreadable; exit 0
fi
if [ "$a_comment" != null ]; then
  if ! anchor_has_key id "$a_comment" || ! anchor_has_key updated_at "$a_comment"; then
    echo unreadable; exit 0
  fi
  c_id="$(anchor_num id "$a_comment")"
  c_updated="$(anchor_str updated_at "$a_comment")"
  if [ -z "$c_id" ] || [ "$c_id" = null ] || [ -z "$c_updated" ] || [ "$c_updated" = null ]; then
    echo unreadable; exit 0
  fi
  comment_tsv="$(gh api "repos/$repo/issues/comments/$c_id" --jq \
    '[.updated_at, .issue_url, ((.user.id // "") | tostring)] | @tsv' 2>/dev/null)" \
    && [ -n "$comment_tsv" ] || { echo unreadable; exit 0; }
  cm_updated="$(tsv_field 1 "$comment_tsv")"
  cm_issue_url="$(tsv_field 2 "$comment_tsv")"
  cm_author_id="$(tsv_field 3 "$comment_tsv")"
  if [ "$cm_updated" != "$c_updated" ] \
     || [ "$cm_issue_url" != "https://api.github.com/repos/$repo/issues/$a_task" ]; then
    echo drift; exit 0
  fi

  if [ "$have_ids" -eq 1 ]; then
    # The author half (`#497`): a reaction approves the comment's text, not who wrote it, so
    # an outsider's comment a maintainer reacted to must not match. Numeric id against the
    # same list, never the login; an empty id is not on it. The declared dev App's id
    # (`--dev-app-id`, `#660`) may author too, compared as a whole string; the reactions below
    # are still judged against the maintainer list only, so its own reaction never approves.
    is_digits "$cm_author_id" || { echo untrusted; exit 0; }
    case ",$maint_ids," in
      *",$cm_author_id,"*) : ;;
      *) [ "$have_dev" -eq 1 ] && [ "$cm_author_id" = "$dev_id" ] || { echo untrusted; exit 0; } ;;
    esac
    # c_updated equals the live value (checked above), so it is the spec's last edit.
    case "$c_updated" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) : ;;
      *) echo unreadable; exit 0 ;;
    esac
    gh api "repos/$repo/issues/comments/$c_id/reactions" --paginate --jq \
      '.[] | [(.user.id|tostring), .content, .created_at] | @tsv' \
      >"$tmp/reactions" 2>/dev/null || { echo unreadable; exit 0; }
    # Re-read the comment's updated_at AFTER the reactions: an edit between the first read and
    # this one, then a maintainer's reaction to the new text, would otherwise approve text the
    # anchor never covered. The same check /way-of-working:architect-review's recipe makes.
    cm_after="$(gh api "repos/$repo/issues/comments/$c_id" --jq .updated_at 2>/dev/null)" \
      && [ -n "$cm_after" ] || { echo unreadable; exit 0; }
    [ "$cm_after" = "$c_updated" ] || { echo drift; exit 0; }
    # The one reaction rule lives in spec-reaction.sh (#613), shared with /way-of-working:architect-review.
    # Exit 2 (a bad argument) or any word but `approved` is never a match.
    # The sibling copy, and only the sibling (as review-sandbox.sh does for gh-identity.sh): a
    # slash-less `$0` (`sh plan-anchor.sh`) would resolve `dirname` to the current directory,
    # where a branch under review could supply a spec-reaction.sh that prints `approved`.
    case "$0" in
      */*) sr="$(dirname "$0")/spec-reaction.sh" ;;
      *) echo unreadable; exit 0 ;;
    esac
    [ -f "$sr" ] || { echo unreadable; exit 0; }
    verdict="$(sh "$sr" "$c_updated" "$maint_ids" <"$tmp/reactions")" \
      || { echo unreadable; exit 0; }
    if [ "$verdict" != approved ]; then echo unreacted; exit 0; fi
  fi
else
  # No spec comment anchored. With --maintainer-ids (identities map) there is no approved
  # spec -- the body's author can edit it with no maintainer reaction -- so: unreacted.
  # Without ids (identities: null, legacy) the body stays the task's spec: match.
  if [ "$have_ids" -eq 1 ]; then echo unreacted; exit 0; fi
fi

echo match
exit 0
