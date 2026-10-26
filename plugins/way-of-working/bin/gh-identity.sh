#!/bin/sh
# Which identity is acting: a human's login (user mode) or this repo's declared dev App
# (App mode)? One place that says so (WB-D24, #379), so no skill guesses it from a token
# prefix or from `gh auth status`, which reports scope, not who is acting. The same lookup
# also answers whether an issue, comment or PR AUTHOR is trusted (`author`, #382).
#
# Trust is by DECLARED identity, never by name alone (WB-D24 item 6): the acting account
# is matched against `identities` in .ai/project.yml on its numeric `id`, which a login
# rename cannot move. This script is a pure predicate. It calls no `gh`; the caller
# captures `gh` output first, with `&&`, and passes the values, so a failed call breaks
# the chain before this script runs and can never read as "no identity".
#
# Usage:
#   gh-identity.sh classify <login> <id> <project.yml>
#   gh-identity.sh author <login> <id> <project.yml>
#   gh-identity.sh role <login> <id> <project.yml>
#   gh-identity.sh pr-actor <login> <id> <project.yml>
#   <records> | gh-identity.sh reach <owner/repo>
#
#   LU=$(gh api user --jq '[.login, .id] | @tsv') &&
#   LOGIN=$(printf '%s' "$LU" | cut -f1) && ID=$(printf '%s' "$LU" | cut -f2) &&
#   gh-identity.sh classify "$LOGIN" "$ID" "$DEF_YML_FILE"
#
# That recipe is the USER-token source and is the only one this task measured. GitHub
# refuses `GET /user` to an installation token, so under an installation token it fails and the
# chain stops: App mode is then unreachable by this source, and fails closed. Where the
# {login, id} of an App actor comes from is the caller's to establish (for example the
# `user` object of a write response, MEASURED in #380: an issue or PR the dev App token created
# reported its `user` as the App's `[bot]` login and numeric id, which `classify` returned as `app`);
# classify is source-agnostic and only compares what it is given. That source arrives only AFTER a
# write, so it cannot gate the first one. A source that precedes any write is GraphQL
# `{ viewer { login databaseId } }`, which an installation token may call (measured, #476: it
# read the dev App's `<slug>[bot]` login and the App's bot user id, the one apps.json calls
# bot_user_id); ship feeds it to `pr-actor` before its first push. A GitHub App USER-to-server token is different: it may
# call `GET /user` and returns the human it acts for, so it classifies as that human.
#
# `user` is a MODE, never a trust grant. With identities null it is printed for any plain
# account (the pre-cutover model trusts by author_association, not by this word); with a map
# it means a declared maintainer. A reader that gates TRUST on a maintainer must run against
# a map and must not treat `user` from a null file as one.
#
# classify prints exactly one word to stdout and exits 0:
#   user  -- identities is null (the repo has not cut over) and the login is a plain
#            account, OR the id and login match an `identities.maintainer` entry
#   app   -- the id and login match `identities.dev_app`
# It exits 2, printing NOTHING to stdout, when it cannot say; one stderr line gives the
# reason. The CALLER decides policy for 2: treat it as neither mode, and wait. Unsure is:
#   - login or id missing, or not the shape GitHub reports (login: letters, digits, `-`,
#     optional `[bot]`; id: a positive integer)
#   - .ai/project.yml unreadable, no `identities` key (absent is the unanswered question),
#     or `identities` neither null nor a map
#   - identities is null and the login ends `[bot]` -- an App with no declared identity is
#     never assumed to be the user model
#   - the id matches reviewer_app or loop_app -- a declared identity, but not one of the
#     two modes this predicate answers; those Apps do not run the dev flow
#   - the account is not declared at all, or the id matches an entry whose login differs
#     (a rename or a stale declaration: do not guess which side is right)
#   - an entry is malformed. A malformed entry (not a map, a non-integer or non-positive
#     `id`, a non-string `login`) matches nothing -- never by login alone -- so a file whose
#     only matching entry is malformed reads as undeclared. `identities.maintainer` must be a
#     sequence; a map there is malformed. YAML aliases inside `identities` are expanded before matching; `identities` itself must not be an alias (that reads as not a map).
#   - one id is declared more than once, under one role or several: do not guess which.
#   - an id under any role is not in canonical decimal (digits only, no leading zero): yq tags `0x3E9`,
#     `1_001`, `01001` and `+1001` as `!!int` but prints them as written, so a text comparison with
#     GitHub's decimal id would match nobody. The rule declared-ids.sh applies (#1096, #1114, #1130).
# Login comparison is case-insensitive (GitHub logins are); the id is exact.
#
# author is the TRUST predicate (WB-D24, #382): is the author of an issue, a comment or a PR
# one this repo trusts? `author_association` is viewer-relative -- read through an App token,
# the maintainer's own issue reads CONTRIBUTOR -- so a repo that has cut over trusts by
# declared {login, id} instead. It shares classify's lookup and so its exit-2 cases for bad
# input (a bad login or id, an unreadable or absent file or key, a non-map `identities`, an
# id declared twice or under another login, an id in identities not in canonical decimal) -- but NOT classify's refusals of an undeclared
# account, a reviewer or loop App, or a `[bot]` under null, which are `untrusted` / `legacy`
# here. It prints exactly one word:
#   trusted    -- the id and login match an `identities.maintainer` entry. Only a maintainer's
#                 authorship is trusted by this predicate, which also judges issue and PR authors.
#                 The dev App's text is not trusted by `author`; a dev-App spec comment is
#                 accepted only by spec-comment.sh (through `role`), plan-anchor.sh (through
#                 `--dev-app-id`), spec-find.sh and the loop preflight, and only with a fresh maintainer reaction, so an agent can
#                 write the spec it obeys but never approve it (#660).
#   untrusted  -- identities is a map and the account is the dev, reviewer or loop App, or is
#                 not declared at all. A hostile account is a normal input, not an error.
#   legacy     -- identities is null: this repo has not cut over, and the CALLER falls back
#                 to its pre-WB-D24 `author_association` allowlist. Never a trust grant.
# A caller that gets exit 2 treats it as neither trusted nor untrusted, and waits.
#
# task-author (WB-D32, #664) judges the author of a TASK issue only: spec-issue.sh, spec-post.sh,
# the author checks of resume, the coder agent and /way-of-working:architect-review, and
# plan-gather.sh authors (plan-sprint's author display, which gates nothing). It shares `author`'s
# lookup and exit-2 cases, and prints exactly one word:
#   trusted    -- a declared maintainer
#   agent      -- the declared dev_app or reviewer_app. The caller must not read the issue body on
#                 this word alone: spec-issue.sh and spec-post.sh require a declared maintainer's
#                 fresh approving reaction on the issue first (spec-reaction.sh); the builders read
#                 no body under a map and take the spec comment's own reaction as the approval.
#   untrusted  -- the loop_app, or an account identities does not declare
#   legacy     -- identities is null: the caller falls back to its author_association allowlist
# `author` is unchanged and still judges comment and PR authors. The preflight's jq
# (scripts/loop/preflight.sh) is the one reader that cannot call this verb; it mirrors the table
# and its fixtures hold it to it.
#
# role is the lookup itself, for a caller that needs WHICH declared account is acting
# (token-check.sh, #436; spec-comment.sh, #660). It prints maintainer, dev_app, reviewer_app or loop_app; undeclared
# when identities is a map and the account is not in it; legacy when identities is null.
# Exit 2 only on bad input (the cases author shares: a bad login or id, an unreadable or absent
# file or key, a non-map identities, an id declared twice or under another login, an id in
# identities not in canonical decimal). Unlike
# classify it does NOT refuse an undeclared account, a reviewer or loop App, or a [bot] under null.
#
# pr-actor is the check ship runs in App mode (#464, #476): is this the dev App? The caller passes
# the `viewer` {login, databaseId} before the first push, and the `user` {login, id} of the PR
# response after it (the backstop). It
# prints exactly one word:
#   match     -- the id and login are the declared `identities.dev_app`
#   mismatch  -- anything else the lookup can read: another App (reviewer, loop), a maintainer's
#                user login, an undeclared account, `dev_app` null or absent, or `identities`
#                null (no dev App is declared, so none can be proven)
# It exits 2, printing nothing, when it cannot say (the cases `role` shares: a missing or
# malformed login or id, i.e. an unreadable response; an unreadable or absent file or key; a
# non-map identities; an id declared twice or under another login; an id in identities not in canonical
# decimal). The CALLER stops on
# anything but `match`, exit 2 included: only `match` clears.
#
# reach is the App-mode probe: is the token in use an installation token that can reach
# <owner/repo>? Feed it one `full_name` per line from
#   gh api --paginate installation/repositories --jq '.repositories[].full_name'
# captured to a file first. A user token cannot call that endpoint, so a failed call is the
# caller's "not an App token", and must not reach this script as empty input.
#   reached    -- <owner/repo> is listed (compared case-insensitively)
#   unreached  -- records arrived, none is <owner/repo>
# Exits 2, nothing on stdout, for empty input (a call that returned nothing is not "an
# installation with no access"), a malformed <owner/repo> or record. A reached probe says
# the token is an installation token with access; WHICH App it is stays the answer of `role` (token-check.sh) or `classify`.
#
# The caller reads `.ai/project.yml` from the DEFAULT branch's committed copy, never the
# working tree (the same stance as `orchestration` and the review gate): a PR under review
# can edit its own `identities`.
#
# Permitted toolset: POSIX sh, tr(1), yq (mikefarah v4) for classify, author, task-author, role and pr-actor.
set -eu

die() { echo "gh-identity.sh: $1" >&2; exit 2; }

lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

valid_login() {
  case "$1" in
    ''|-*|*-|*--*) return 1 ;;
  esac
  rest="${1%\[bot\]}"
  case "$rest" in
    ''|*[!A-Za-z0-9-]*) return 1 ;;
  esac
  return 0
}

valid_id() {
  case "$1" in
    ''|0*|*[!0-9]*) return 1 ;;
  esac
  return 0
}

# find_role <login> <id> <project.yml> -- the lookup classify, author, role and pr-actor share. Sets ROLE to
# maintainer, dev_app, reviewer_app, loop_app, or empty (undeclared); LEGACY=1 when identities
# is null. Dies (exit 2) only on bad input (login or id shape, file or key, a
# non-map identities, an id declared twice or under another login, an id in identities not in canonical
# decimal, which would match nobody); classify does the refusing.
find_role() {
  login="$1" id="$2" yml="$3"
  ROLE= LEGACY=0
  valid_login "$login" || die "login is not an account name"
  valid_id "$id" || die "id is not a positive integer"
  [ -f "$yml" ] || die "project file unreadable"
  command -v yq >/dev/null 2>&1 || die "yq is not on PATH"

  has=$(yq -r 'has("identities")' "$yml" 2>/dev/null) || die "project file unparseable"
  [ "$has" = true ] || die "no identities key -- the question is unanswered"
  tag=$(yq -r '.identities | tag' "$yml" 2>/dev/null) || die "project file unparseable"
  want=$(lower "$login")

  case "$tag" in
    '!!null') LEGACY=1; return 0 ;;
    '!!map') ;;
    *) die "identities is neither null nor a map" ;;
  esac

  # Each role is read on its own; a malformed entry prints nothing and so matches nothing.
  tab=$(printf '\t')
  for r in maintainer dev_app reviewer_app loop_app; do
    if [ "$r" = maintainer ]; then
      rows=$(yq -r 'explode(.) | (.identities.maintainer | select(tag == "!!seq") | .[]) | select(tag == "!!map" and ((.id | tag) == "!!int") and .id > 0 and ((.login | tag) == "!!str")) | [.login, .id] | @tsv' "$yml" 2>/dev/null) || die "identities.maintainer unreadable"
    else
      rows=$(yq -r "explode(.) | .identities.$r | select(tag == \"!!map\" and ((.id | tag) == \"!!int\") and .id > 0 and ((.login | tag) == \"!!str\")) | [.login, .id] | @tsv" "$yml" 2>/dev/null) || die "identities.$r unreadable"
    fi
    [ -n "$rows" ] || continue
    while IFS="$tab" read -r l i; do
      valid_id "$i" || die "identities.$r has an id not in canonical decimal: $i"
      [ "$i" = "$id" ] || continue
      if [ "$(lower "$l")" != "$want" ]; then
        die "id $id is declared under a different login; will not guess"
      fi
      [ -z "$ROLE" ] || die "id $id is declared more than once; will not guess"
      ROLE="$r"
    done <<EOF
$rows
EOF
  done

}

classify() {
  [ "$#" -eq 3 ] || { echo "usage: gh-identity.sh classify <login> <id> <project.yml>" >&2; exit 2; }
  find_role "$1" "$2" "$3"
  if [ "$LEGACY" = 1 ]; then
    case "$1" in
      *'[bot]') die "identities is null and the actor is a [bot]; an undeclared App is not user mode" ;;
    esac
    echo user
    return 0
  fi
  case "$ROLE" in
    maintainer) echo user ;;
    dev_app) echo app ;;
    reviewer_app|loop_app) die "the acting identity is the declared $ROLE, not a user or the dev App" ;;
    *) die "the acting identity is not declared in identities" ;;
  esac
}

author() {
  [ "$#" -eq 3 ] || { echo "usage: gh-identity.sh author <login> <id> <project.yml>" >&2; exit 2; }
  find_role "$1" "$2" "$3"
  if [ "$LEGACY" = 1 ]; then echo legacy; return 0; fi
  if [ "$ROLE" = maintainer ]; then echo trusted; else echo untrusted; fi
}

task_author() {
  [ "$#" -eq 3 ] || { echo "usage: gh-identity.sh task-author <login> <id> <project.yml>" >&2; exit 2; }
  find_role "$1" "$2" "$3"
  if [ "$LEGACY" = 1 ]; then echo legacy; return 0; fi
  case "$ROLE" in
    maintainer) echo trusted ;;
    dev_app|reviewer_app) echo agent ;;
    *) echo untrusted ;;
  esac
}

role() {
  [ "$#" -eq 3 ] || { echo "usage: gh-identity.sh role <login> <id> <project.yml>" >&2; exit 2; }
  find_role "$1" "$2" "$3"
  if [ "$LEGACY" = 1 ]; then echo legacy; return 0; fi
  if [ -n "$ROLE" ]; then echo "$ROLE"; else echo undeclared; fi
}

pr_actor() {
  [ "$#" -eq 3 ] || { echo "usage: gh-identity.sh pr-actor <login> <id> <project.yml>" >&2; exit 2; }
  find_role "$1" "$2" "$3"
  if [ "$LEGACY" != 1 ] && [ "$ROLE" = dev_app ]; then echo match; else echo mismatch; fi
}

reach() {
  [ "$#" -eq 1 ] || { echo "usage: <records> | gh-identity.sh reach <owner/repo>" >&2; exit 2; }
  repo="$1"
  case "$repo" in
    */*/*|/*|*/|*[!A-Za-z0-9._/-]*|'') die "repo is not owner/name" ;;
    */*) ;;
    *) die "repo is not owner/name" ;;
  esac
  want=$(lower "$repo")
  seen=0
  found=0
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%"$(printf '\r')"}
    [ -n "$line" ] || continue
    case "$line" in
      */*/*|/*|*/|*[!A-Za-z0-9._/-]*) die "malformed record" ;;
      */*) ;;
      *) die "malformed record" ;;
    esac
    seen=1
    [ "$(lower "$line")" != "$want" ] || found=1
  done
  [ "$seen" -eq 1 ] || die "no records -- a call that returned nothing is not a probe result"
  if [ "$found" -eq 1 ]; then echo reached; else echo unreached; fi
}

case "${1:-}" in
  classify) shift; classify "$@" ;;
  author) shift; author "$@" ;;
  task-author) shift; task_author "$@" ;;
  role) shift; role "$@" ;;
  pr-actor) shift; pr_actor "$@" ;;
  reach) shift; reach "$@" ;;
  *) echo "usage: gh-identity.sh classify|author|task-author|role|pr-actor <login> <id> <project.yml> | reach <owner/repo>" >&2; exit 2 ;;
esac
