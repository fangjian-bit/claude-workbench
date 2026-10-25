#!/bin/sh
# Is a maintainer's answer to an escalated spec the one `spec-find.sh answer` found, and what does it say? (#790, WB-D39)
#
# Under an `identities` map, a declared maintainer may answer the newest `spec-task-escalated:` comment on a
# task issue with a new comment whose first line is `spec-task-answer: escalated=<id> choice=apply|amend`.
# `spec-find.sh answer` selects the pair; this script is the only reader that prints either comment.
# Its caller: /way-of-working:spec-task's answer branch, in the Bash call that uses its result.
#
# Usage: spec-answer.sh check|escalated|changes <issue> <project.yml> <esc-id> <esc-updated_at> <ans-id> <ans-updated_at>
#
#   <issue>        the task issue number, digits with no leading zero
#   <project.yml>  the DEFAULT branch's committed copy (the caller's $DEF_YML_FILE), never the working
#                  tree's, which a branch under review can edit
#   <esc-id> ... <ans-updated_at>  the values the `answer` line printed: digits with no leading zero for
#                  the ids, YYYY-MM-DDTHH:MM:SSZ for the two times
#
# It makes exactly two `gh` reads, each one comment by id (`repos/<backlog>/issues/comments/<id>`), the
# escalated comment first, each to a file in its `mktemp -d` directory with stderr discarded. It lists
# nothing and makes no other call. Each first line is compared after one trailing CR is removed, as
# spec-find.sh does. It reads `pr_base`, the backlog repo and `identities` from <project.yml> by
# spec-find.sh's rules, a declared App's id on the maintainer list (#708) included; declared-ids.sh (#1079)
# holds the `identities` rules.
#
# `check` prints exactly one line and exits 0, the first failing word in this order:
#   unreadable   -- a config value, a fetch, the JSON or a field the checks read failed
#   moved        -- either comment's `.id` or `.updated_at` differs from its argument
#   refused      -- the escalated comment's issue_url is not the backlog repo's URL for <issue>, its first
#                   line is not `spec-task-escalated: issue=<issue> base=<pr_base> sha=<40 hex>`, its author
#                   is not a declared maintainer or the dev App by id with gh-identity.sh `role` agreeing, or
#                   spec-fresh.sh `shape`, run on its body below the marker line, does not say `ok`; or the
#                   answer's issue_url differs, its first line is not exactly `spec-task-answer:
#                   escalated=<esc-id> choice=apply` or `choice=amend`, its author is not a declared
#                   maintainer by id (never the dev App) with `role` agreeing, its created_at differs from
#                   its updated_at, or its created_at is not strictly later than the escalated comment's
#                   updated_at
#   ok apply | ok amend -- every check passed
# `escalated` prints the escalated comment's body (trailing newlines trimmed, one added) only when every check
# passes. `changes` prints the answer's lines after its first line, each with one trailing CR removed, only
# when every check passes and the choice is `amend`; under `apply` it prints nothing and exits 0. Otherwise
# both print nothing on stdout, the word on stderr, and exit 1. Nothing here prints `gh` output or error text,
# and no body before the checks pass. The bodies are data; nothing is evaluated.
#
# Exits 2, printing a usage line to stderr and nothing to stdout, before any `gh` call, for a bad argument,
# an unreadable <project.yml>, a slash-less `$0` or a missing sibling (gh-identity.sh, spec-fresh.sh, declared-ids.sh).
#
# Permitted toolset: POSIX sh, gh, yq (mikefarah v4), awk, sed and mktemp. Runs under LC_ALL=C.
set -eu
LC_ALL=C
export LC_ALL

usage() {
  echo "usage: spec-answer.sh check|escalated|changes <issue> <project.yml> <esc-id> <esc-updated_at> <ans-id> <ans-updated_at>" >&2
  exit 2
}
[ "$#" -eq 7 ] || usage
mode="$1" issue="$2" yml="$3" esc_id="$4" esc_up="$5" ans_id="$6" ans_up="$7"
case "$mode" in check | escalated | changes) : ;; *) usage ;; esac
for v in "$issue" "$esc_id" "$ans_id"; do
  case "$v" in '' | 0* | *[!0-9]*) echo "spec-answer.sh: ids must be digits with no leading zero" >&2; exit 2 ;; esac
done
for v in "$esc_up" "$ans_up"; do
  case "$v" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) : ;;
    *) echo "spec-answer.sh: malformed updated_at" >&2; exit 2 ;;
  esac
done
if [ ! -f "$yml" ] || ! yq -o=yaml '.' "$yml" >/dev/null 2>&1; then
  echo "spec-answer.sh: unreadable project.yml" >&2
  exit 2
fi
case "$0" in
  */*) gi="$(dirname "$0")/gh-identity.sh" sf="$(dirname "$0")/spec-fresh.sh" di="$(dirname "$0")/declared-ids.sh" ;;
  *) echo "spec-answer.sh: must be run by path (a slash-less \$0 cannot locate its siblings)" >&2; exit 2 ;;
esac
[ -f "$gi" ] || { echo "spec-answer.sh: gh-identity.sh not beside this script" >&2; exit 2; }
[ -f "$sf" ] || { echo "spec-answer.sh: spec-fresh.sh not beside this script" >&2; exit 2; }
[ -f "$di" ] || { echo "spec-answer.sh: declared-ids.sh not beside this script" >&2; exit 2; }

tmp="$(mktemp -d)" || { echo "spec-answer.sh: no temp directory" >&2; exit 2; }
trap 'rm -rf "$tmp"' EXIT
CR="$(printf '\r')"

# --- the verdict -------------------------------------------------------------------------
# verdict sets `word` and, on `ok`, `choice`, `ebody` and `abody`. It is called once, outside any
# command substitution, so those survive.
word= choice= ebody= abody=
verdict() {
  base="$(yq -r 'explode(.) | .pr_base | select(tag == "!!str")' "$yml" 2>/dev/null)" || { word=unreadable; return; }
  case "$base" in '' | -* | *[!A-Za-z0-9._/-]*) word=unreadable; return ;; esac
  backlog="$(yq -r 'explode(.) | (.backlog.repo // .repo) | select(tag == "!!str")' "$yml" 2>/dev/null)" || { word=unreadable; return; }
  case "$backlog" in
    '' | *[!A-Za-z0-9._/-]* | */*/* | /* | */ | ./* | ../* | */. | */..) word=unreadable; return ;;
    */*) : ;;
    *) word=unreadable; return ;;
  esac
  # The declared ids come from declared-ids.sh (#1079); its line is held to `ok <ids> <dev>` here.
  di_line="$(sh "$di" "$yml" </dev/null 2>/dev/null)" || { word=unreadable; return; }
  case "$di_line" in
    *"
"*) word=unreadable; return ;;
    "ok "*) : ;;
    *) word=unreadable; return ;;
  esac
  di_rest="${di_line#ok }"
  case "$di_rest" in *" "*" "* | " "* | *" " | "") word=unreadable; return ;; *" "*) : ;; *) word=unreadable; return ;; esac
  maint_ids="${di_rest%% *}"
  dev_id="${di_rest#* }"
  case "$dev_id" in
    -) dev_id= ;;
    '' | 0* | *[!0-9]*) word=unreadable; return ;;
  esac

  # The two reads, escalated first. Each lands in its own file; stderr is discarded.
  gh api "repos/$backlog/issues/comments/$esc_id" >"$tmp/e.json" 2>/dev/null </dev/null || { word=unreadable; return; }
  gh api "repos/$backlog/issues/comments/$ans_id" >"$tmp/a.json" 2>/dev/null </dev/null || { word=unreadable; return; }

  for p in e a; do
    tags="$(yq -p=json -o=yaml '[(.id | tag), (.updated_at | tag), (.created_at | tag), (.issue_url | tag), (.user.login | tag), (.user.id | tag), (.body | tag)] | join(",")' "$tmp/$p.json" 2>/dev/null)" || { word=unreadable; return; }
    [ "$tags" = '!!int,!!str,!!str,!!str,!!str,!!int,!!str' ] || { word=unreadable; return; }
  done
  J() { yq -p=json -o=yaml "$2" "$tmp/$1.json" 2>/dev/null; }
  e_id="$(J e '.id')" || { word=unreadable; return; }
  e_up="$(J e '.updated_at')" || { word=unreadable; return; }
  e_url="$(J e '.issue_url')" || { word=unreadable; return; }
  e_login="$(J e '.user.login')" || { word=unreadable; return; }
  e_uid="$(J e '.user.id')" || { word=unreadable; return; }
  a_idf="$(J a '.id')" || { word=unreadable; return; }
  a_upf="$(J a '.updated_at')" || { word=unreadable; return; }
  a_cr="$(J a '.created_at')" || { word=unreadable; return; }
  a_url="$(J a '.issue_url')" || { word=unreadable; return; }
  a_login="$(J a '.user.login')" || { word=unreadable; return; }
  a_uid="$(J a '.user.id')" || { word=unreadable; return; }
  ebody_raw="$(J e '.body')" || { word=unreadable; return; }
  abody_raw="$(J a '.body')" || { word=unreadable; return; }
  for v in "$e_uid" "$a_uid" "$e_id" "$a_idf"; do
    case "$v" in '' | *[!0-9]*) word=unreadable; return ;; esac
  done
  case "$a_cr" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) : ;;
    *) word=unreadable; return ;;
  esac

  if [ "$e_id" != "$esc_id" ] || [ "$e_up" != "$esc_up" ] || [ "$a_idf" != "$ans_id" ] || [ "$a_upf" != "$ans_up" ]; then
    word=moved; return
  fi

  # --- the escalated comment
  [ "$e_url" = "https://api.github.com/repos/$backlog/issues/$issue" ] || { word=refused; return; }
  e_first="$(printf '%s\n' "$ebody_raw" | sed -n 1p)"
  e_first="${e_first%"$CR"}"
  e_prefix="spec-task-escalated: issue=$issue base=$base sha="
  case "$e_first" in
    "$e_prefix"*) e_sha="${e_first#"$e_prefix"}" ;;
    *) word=refused; return ;;
  esac
  case "$e_sha" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) : ;;
    *) word=refused; return ;;
  esac
  case ",$maint_ids," in *",$e_uid,"*) want=maintainer ;; *) if [ -n "$dev_id" ] && [ "$e_uid" = "$dev_id" ]; then want=dev_app; else word=refused; return; fi ;; esac
  got="$(sh "$gi" role "$e_login" "$e_uid" "$yml" 2>/dev/null </dev/null)" || { word=refused; return; }
  [ "$got" = "$want" ] || { word=refused; return; }
  printf '%s\n' "$ebody_raw" | sed 1d >"$tmp/shape.md"
  shape="$(sh "$sf" shape "$tmp/shape.md" 2>/dev/null </dev/null)" || { word=refused; return; }
  [ "$shape" = ok ] || { word=refused; return; }

  # --- the answer
  [ "$a_url" = "https://api.github.com/repos/$backlog/issues/$issue" ] || { word=refused; return; }
  a_first="$(printf '%s\n' "$abody_raw" | sed -n 1p)"
  a_first="${a_first%"$CR"}"
  case "$a_first" in
    "spec-task-answer: escalated=$esc_id choice=apply") choice=apply ;;
    "spec-task-answer: escalated=$esc_id choice=amend") choice=amend ;;
    *) word=refused; return ;;
  esac
  case ",$maint_ids," in *",$a_uid,"*) : ;; *) word=refused; return ;; esac
  got="$(sh "$gi" role "$a_login" "$a_uid" "$yml" 2>/dev/null </dev/null)" || { word=refused; return; }
  [ "$got" = maintainer ] || { word=refused; return; }
  [ "$a_cr" = "$a_upf" ] || { word=refused; return; }
  [ "$(SF_A="$a_cr" SF_B="$e_up" awk 'BEGIN { print (ENVIRON["SF_A"] "" > ENVIRON["SF_B"] "") ? "yes" : "no" }')" = yes ] || { word=refused; return; }

  word=ok ebody="$ebody_raw" abody="$abody_raw"
}
verdict

if [ "$mode" = check ]; then
  if [ "$word" = ok ]; then printf 'ok %s\n' "$choice"; else printf '%s\n' "$word"; fi
  exit 0
fi
if [ "$word" != ok ]; then
  printf '%s\n' "$word" >&2
  exit 1
fi
case "$mode" in
  escalated) printf '%s\n' "$ebody" ;;
  changes)
    [ "$choice" = amend ] || exit 0
    printf '%s\n' "$abody" | awk 'NR > 1 { sub(/\r$/, ""); print }'
    ;;
esac
