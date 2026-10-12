#!/bin/sh
# The deterministic predicate behind the `planning: kind: github_milestones` key
# (reference/project-schema.md § `planning`) -- whether a cursor's `plan_anchor`
# still describes the LIVE milestone description, task issue, and spec comment.
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
#   plan-anchor.sh verify [--plan] [--loop-identity <login>] [--maintainer-ids <id,id,...>] <repo> <pointer-url> <anchor-json>
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
# else about the verdict is unchanged: without the flag no author is read at all,
# and `untrusted` is never printed.
#
# `--maintainer-ids <id,id,...>` is the reaction rule (`WB-D24`, `#383`): a comment alone
# never approves a spec. When given, full-mode `verify` -- after every other check has
# passed -- also requires a spec comment to be anchored and a reaction on that
# exact comment (`reactions` of the comment id the anchor names, never another) that was
# made by a declared maintainer (matched on the numeric user `id`, never the login),
# whose `created_at` is STRICTLY after the comment's `updated_at` (a reaction does not
# move `updated_at` -- assumed, not yet measured live; if wrong, nothing ever matches, never a
# false match -- so an edit after the reaction leaves it stale), and whose content
# is an approving one (`+1`, `heart`, `hooray`, `rocket`; `-1`, `confused`, `eyes` and
# `laugh` never count). Otherwise it prints `unreacted`, which a caller treats as a wait,
# exactly like `drift`. The ids arrive as an ARGUMENT, read by the caller from the
# default branch's `identities.maintainer` (this script forbids `yq`); an empty or
# non-numeric list is a caller bug and prints `unreadable`. A caller whose repo has not
# cut over (`identities: null`) omits the flag and keeps today's behavior. With the flag and
# NO spec comment anchored the verdict is `unreacted`: the issue body alone is editable text
# whose author stays the maintainer, so it is never an approval. `--plan` mode validates
# the list but otherwise ignores it, as it ignores the spec comment. A failed reactions read is `unreadable`.
#
# `verify` (full) checks: the milestone is open, its number equals the anchor's
# and the pointer's; `#N` is open, a true issue (no `pull_request` key), its
# `repository_url` names `<repo>` and its `number` is `N`, its `milestone.number`
# matches, and its `updated_at` equals the anchor's; the spec comment (when
# anchored) has `updated_at` equal to the anchor's and belongs to issue `#N`;
# the description hash matches.
#
# `verify --plan` checks only: milestone open, number equality, description
# hash. It ignores `task_issue` and `spec_comment` entirely -- the mode
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
# Hashing: description bytes are read into a FILE by direct redirection
# (`gh api ... > file`), never captured through `$(...)`, which strips
# trailing newlines and would make `write`'s hash and `verify`'s recomputed
# hash diverge on content that legitimately ends in one. An empty or missing
# description hashes like any other content gh and jq agree on -- `unreadable`
# is tied to a FAILED call, never to empty content, so a failed read on both
# sides can never accidentally compare equal.
#
# Permitted toolset: POSIX sh, `gh` (using only its own embedded --jq), and
# `sha256sum` or `shasum -a 256`. No system `jq`, no `yq`, no python -- the
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

hash_file() { # hash_file <path> -- prints the hex sha256 of its bytes
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    return 1
  fi
}

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
#   {"milestone":<N>,"description_sha256":"<64 hex>","task_issue":<N|null>,
#    "task_issue_updated_at":<"<ts>"|null>,"spec_comment":<{"id":<N>,
#    "updated_at":"<ts>"}|null>}
#
# Every value here is either digits, "null", or a quote-free string (a hex
# hash or an ISO-8601 timestamp), so one pair of anchored sed patterns per key
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
    echo "                       plan-anchor.sh verify [--plan] [--loop-identity <login>] <repo> <pointer-url> <anchor-json>" >&2
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

  if ! gh api "repos/$repo/milestones/$milestone" --jq '.description // empty' \
       >"$tmp/desc" 2>/dev/null; then
    echo unreadable; exit 0
  fi
  desc_hash="$(hash_file "$tmp/desc")" || { echo unreadable; exit 0; }

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

  printf '{"milestone":%s,"description_sha256":"%s","task_issue":%s,"task_issue_updated_at":%s,"spec_comment":%s}\n' \
    "$milestone" "$desc_hash" "$task_field" "$task_updated_field" "$comment_field"
  exit 0
fi

# =============================================================================
# mode = verify
plan_only=0
loop_login=
have_loop=0
maint_ids=
have_ids=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --plan) plan_only=1; shift ;;
    --loop-identity)
      [ "$#" -ge 2 ] || { echo unreadable; exit 0; }
      have_loop=1; loop_login="$2"; shift 2 ;;
    --maintainer-ids)
      [ "$#" -ge 2 ] || { echo unreadable; exit 0; }
      have_ids=1; maint_ids="$2"; shift 2 ;;
    *) break ;;
  esac
done

if [ "$#" -ne 3 ]; then
  echo "plan-anchor.sh: verify needs [--plan] [--loop-identity <login>] [--maintainer-ids <id,id,...>] <repo> <pointer-url> <anchor-json>" >&2
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

# The pointer must be exactly https://github.com/<repo>/milestone/<digits> --
# an anchored match on <repo>, digits-only number (project-schema.md § `planning`).
prefix="https://github.com/$repo/milestone/"
case "$pointer" in
  "$prefix"*) num_pointer="${pointer#"$prefix"}" ;;
  *) echo unreadable; exit 0 ;;
esac
if ! is_digits "$num_pointer"; then echo unreadable; exit 0; fi

if ! anchor_has_key milestone "$anchor" || ! anchor_has_key description_sha256 "$anchor"; then
  echo unreadable; exit 0
fi
a_milestone="$(anchor_num milestone "$anchor")"
a_hash="$(anchor_str description_sha256 "$anchor")"
if [ -z "$a_milestone" ] || [ "$a_milestone" = null ] || [ -z "$a_hash" ] || [ "$a_hash" = null ]; then
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

if ! gh api "repos/$repo/milestones/$a_milestone" --jq '.description // empty' \
     >"$tmp/desc" 2>/dev/null; then
  echo unreadable; exit 0
fi
live_hash="$(hash_file "$tmp/desc")" || { echo unreadable; exit 0; }
if [ "$live_hash" != "$a_hash" ]; then echo drift; exit 0; fi

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
    '[.updated_at, .issue_url] | @tsv' 2>/dev/null)" \
    && [ -n "$comment_tsv" ] || { echo unreadable; exit 0; }
  cm_updated="$(tsv_field 1 "$comment_tsv")"
  cm_issue_url="$(tsv_field 2 "$comment_tsv")"
  if [ "$cm_updated" != "$c_updated" ] \
     || [ "$cm_issue_url" != "https://api.github.com/repos/$repo/issues/$a_task" ]; then
    echo drift; exit 0
  fi

  if [ "$have_ids" -eq 1 ]; then
    # c_updated equals the live value (checked above), so it is the spec's last edit.
    case "$c_updated" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) : ;;
      *) echo unreadable; exit 0 ;;
    esac
    gh api "repos/$repo/issues/comments/$c_id/reactions" --paginate --jq \
      '.[] | [(.user.id|tostring), .content, .created_at] | @tsv' \
      >"$tmp/reactions" 2>/dev/null || { echo unreadable; exit 0; }
    reacted=0
    tab="$(printf '\t')"
    while IFS="$tab" read -r r_uid r_content r_created || [ -n "$r_uid" ]; do
      case ",$maint_ids," in *",$r_uid,"*) : ;; *) continue ;; esac
      case "$r_content" in '+1' | heart | hooray | rocket) : ;; *) continue ;; esac
      case "$r_created" in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) : ;;
        *) continue ;;
      esac
      [ "$r_created" != "$c_updated" ] || continue
      latest="$(printf '%s\n%s\n' "$c_updated" "$r_created" | sort | tail -n 1)"
      if [ "$latest" = "$r_created" ]; then reacted=1; break; fi
    done <"$tmp/reactions"
    if [ "$reacted" -ne 1 ]; then echo unreacted; exit 0; fi
  fi
else
  # No spec comment anchored: the issue body is the whole spec, and editing it leaves
  # its author unchanged -- with the reaction rule on, that is never an approval.
  if [ "$have_ids" -eq 1 ]; then echo unreacted; exit 0; fi
fi

echo match
exit 0
