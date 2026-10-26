#!/bin/sh
# Fail closed on a minted App token before anything acts with it (WB-D24, #436).
#
# The incident (#376 session 1): a reviewer token came out empty, `gh` treats an empty
# GH_TOKEN as unset, and four calls meant for the reviewer App ran as a human code owner
# with write access, from the host's stored login. Every consumer of a minted token (a
# review sandbox reading a reviewer token, a container reading an admin token, a broker, a
# loop driver) MUST run this check first, and go no further on a non-zero exit. (#436 ships
# the check; wiring each consumer is the task that adds that consumer, e.g. #389.) The check
# does not talk to GitHub: like gh-identity.sh it is a pure predicate, and the caller
# captures what GitHub said, with `&&`, so a failed call breaks the chain before this
# runs and can never read as "nothing wrong".
#
# Usage:
#   token-check.sh file <token-file>
#   token-check.sh token <token-file>
#   token-check.sh verify <role> <owner/repo> <token-file> <installation-file> <project.yml>
#                         [<actor-login> <actor-id>]
#
# The token file is what mint.sh writes: the token on line 1, its expires_at on line 2
# (YYYY-MM-DDTHH:MM:SSZ), nothing else.
#
# file   prints `live` and exits 0 when the file is a regular file (not a link), holds exactly
#        those two lines, line 1 is a ghs_ installation token (ghs_ then 36 or more of
#        [A-Za-z0-9._-]) and line 2 is later than now. It exits 2, printing nothing to stdout,
#        for an empty, unreadable, malformed or expired file; one stderr line gives the reason
#        and never the token. A user token (ghp_, gho_, ghu_, github_pat_) is refused here by
#        shape, before any call is made with it.
#
# token  runs `file`, then prints line 1 and nothing else: the one place a consumer gets the
#        secret, in a variable, never on a command line or in a log:
#          TOK=$(token-check.sh token "$f") && [ -n "$TOK" ] || exit 1
#        The `&&` and the `[ -n ]` are the point. After this, hand the token to a child as
#        GH_TOKEN="$TOK" (or to curl through a stdin config, as mint.sh does), never as an
#        unset or empty variable: `gh` reads an empty GH_TOKEN as unset and falls back to the
#        stored login, which on a host is a human's. Inside a dev container there is none.
#
# verify proves the token is an installation token for the expected App, on top of `file`:
#   <role>              dev_app, reviewer_app or loop_app (a key of `identities`): the actor
#                       is REQUIRED. admin or any: no identity is declared for it (identities
#                       has no admin App), so only the installation proof applies and no actor
#                       may be given. Use `any` to accept, knowingly, that another App on the
#                       same repo is not told apart.
#   <installation-file> `GET /installation/repositories` made WITH THIS TOKEN, one full_name per
#                       line. Nothing here ties the file to the token, so the caller must make
#                       the call from the very value it will act with, in one chain, and act
#                       with that same $TOK:
#                         TOK=$(token-check.sh token "$f") && [ -n "$TOK" ] &&
#                         GH_TOKEN="$TOK" gh api --hostname github.com --paginate \
#                           installation/repositories --jq '.repositories[].full_name' >"$inst" &&
#                         token-check.sh verify <role> <owner/repo> "$f" "$inst" <yml> ...
#                       with GH_HOST and GH_ENTERPRISE_TOKEN unset. (A GITHUB_TOKEN from Actions is also
#                       ghs_ and would pass: this check is for the tokens mint.sh writes.) A user
#                       token cannot call that endpoint, so a caller whose call failed has no
#                       file, or an empty one, and this refuses (`gh-identity.sh reach` exits 2
#                       on no records). <owner/repo> must be listed, case-insensitively.
#   <actor-login> <actor-id>  the numeric id and login the token acts as. They MUST come from a
#                       GitHub response obtained with $TOK, never from `identities`, the mint
#                       config or any other statement of intent: a value copied from the thing it
#                       is compared with proves nothing. GET /user is refused to an installation
#                       token; the measured sources are GraphQL `viewer { login databaseId }`
#                       (#476), which needs no write, and the `user` object of a write response
#                       the token made (an issue or PR it created, #380). They must match the declared
#                       `identities.<role>` entry, via `gh-identity.sh role`: a token of another
#                       App, a maintainer, or an account declared nowhere all fail. `identities`
#                       null cannot declare an actor, so a supplied actor then fails too.
#   prints `app`          installation token reaching <owner/repo>, actor is the declared <role>.
#   prints `installation` installation token reaching <owner/repo>; role admin or any, so WHICH App
#                         it is was not checked. Enough to refuse a user or empty token; NOT enough
#                         where another App is installed on the same repo.
#   exits 2, nothing on stdout, for everything else: a failed `file`, unreached or empty
#   installation records, a dev_app/reviewer_app/loop_app role without an actor, an actor that is
#   not the declared role, an actor given with admin or any, an unknown role, a wrong argument
#   count, and (only when an actor is given) an unreadable <project.yml>. The
#   caller treats 2 as "do not act", and does not retry with another credential.
#
# Assumed, not checked: the token directory is not writable by a less-privileged process (the
# file is read in several steps, and only its last path component is tested for a link).
#
# The caller reads <project.yml> from the DEFAULT branch's committed copy, never the working
# tree (a PR can edit its own `identities`). Expiry is compared with `date -u` at call time;
# the caller re-runs the check if it holds a token for long. Permitted toolset: POSIX sh, date,
# sed, tr, wc, dirname, and what gh-identity.sh needs (yq).
#
# A slash-less $0 (`sh token-check.sh` from this directory) is refused, in every mode, with exit
# 2: `here` would be the current directory, and a gh-identity.sh planted there would decide
# `verify`'s lookups. Run it by path, or by command name through PATH.
set -eu
LC_ALL=C; export LC_ALL

die() { echo "token-check.sh: $1" >&2; exit 2; }

case "$0" in
  */*) here=$(CDPATH= cd -P -- "$(dirname -- "$0")" && pwd) ;;
  *) die "must be run by path or through PATH (a slash-less \$0 cannot locate gh-identity.sh)" ;;
esac

# file_check <path>: dies unless the file holds a live installation token. Sets TOKEN_LINE.
file_check() {
  f="$1"
  [ -n "$f" ] || die "no token file named"
  [ -f "$f" ] && [ ! -L "$f" ] || die "token file is missing, a link, or not a regular file"
  [ -r "$f" ] || die "token file is unreadable"
  [ -s "$f" ] || die "token file is empty"
  [ "$(tr -d '\n' <"$f" | tr -d '[:print:]' | wc -c | tr -d ' ')" = 0 ] || die "token file holds a control character, NUL or carriage return"
  [ "$(wc -l <"$f" | tr -d ' ')" = 2 ] && [ "$(sed -n '$=' "$f")" = 2 ] || die "token file is not exactly two newline-terminated lines"
  TOKEN_LINE=$(sed -n 1p "$f")
  exp=$(sed -n 2p "$f")
  case "$TOKEN_LINE" in
    ghs_*) body=${TOKEN_LINE#ghs_} ;;
    *) die "line 1 is not an installation token (ghs_)" ;;
  esac
  case "$body" in *[!A-Za-z0-9._-]*) die "line 1 is not token-shaped" ;; esac
  [ "${#body}" -ge 36 ] || die "line 1 is not token-shaped"
  case "$exp" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;;
    *) die "line 2 is not an expires_at timestamp" ;;
  esac
  mo=${exp#????-}; mo=${mo%%-*}
  dy=${exp#????-??-}; dy=${dy%%T*}
  hm=${exp#*T}; hh=${hm%%:*}
  case "$mo" in 0[1-9]|1[0-2]) ;; *) die "line 2 is not a real time" ;; esac
  case "$dy" in 0[1-9]|[12][0-9]|3[01]) ;; *) die "line 2 is not a real time" ;; esac
  case "$hh" in [01][0-9]|2[0-3]) ;; *) die "line 2 is not a real time" ;; esac
  case "${hm#??:}" in [0-5][0-9]:[0-5][0-9]Z|[0-5][0-9]:60Z) ;; *) die "line 2 is not a real time" ;; esac
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ) || die "cannot read the clock"
  [ "$exp" \> "$now" ] || die "the token expired at $exp"
}

cmd_file() {
  [ "$#" -eq 1 ] || die "usage: token-check.sh file <token-file>"
  file_check "$1"
  echo live
}

cmd_token() {
  [ "$#" -eq 1 ] || die "usage: token-check.sh token <token-file>"
  file_check "$1"
  printf '%s\n' "$TOKEN_LINE"
}

cmd_verify() {
  [ "$#" -eq 5 ] || [ "$#" -eq 7 ] || die "usage: token-check.sh verify <role> <owner/repo> <token-file> <installation-file> <project.yml> [<actor-login> <actor-id>]"
  role="$1" repo="$2" tokfile="$3" instfile="$4" yml="$5"
  case "$role" in dev_app|reviewer_app|loop_app|admin|any) ;; *) die "role is not dev_app, reviewer_app, loop_app, admin or any" ;; esac
  file_check "$tokfile"
  [ -f "$instfile" ] && [ -r "$instfile" ] || die "installation records are missing or unreadable"
  reached=$(sh "$here/gh-identity.sh" reach "$repo" <"$instfile") || die "installation records could not be read (a user token, or a failed call, has none)"
  [ "$reached" = reached ] || die "the token's installation does not list $repo"
  case "$role" in
    admin|any)
      [ "$#" -eq 5 ] || die "role $role declares no identity; do not pass an actor"
      echo installation
      return 0 ;;
  esac
  [ "$#" -eq 7 ] || die "role $role needs the acting identity; without one the App cannot be told apart from another App on the repo (use role any to accept that)"
  got=$(sh "$here/gh-identity.sh" role "$6" "$7" "$yml") || die "the acting identity could not be looked up in identities"
  [ "$got" = "$role" ] || die "the acting identity is $got, not the declared $role"
  echo app
}

case "${1:-}" in
  file) shift; cmd_file "$@" ;;
  token) shift; cmd_token "$@" ;;
  verify) shift; cmd_verify "$@" ;;
  *) die "usage: token-check.sh file|token|verify ..." ;;
esac
