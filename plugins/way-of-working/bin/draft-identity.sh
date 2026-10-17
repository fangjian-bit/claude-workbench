#!/bin/sh
# May this environment draft a spec unattended? (#663, WB-D31)
#
# /way-of-working:resume drafts and posts a spec, with no human in the loop, only when it runs
# as the declared dev App and nothing else could be acting in its place. This script answers
# that with reads only. Its caller: /way-of-working:resume (the `Drafting identity:` line of the
# *Read the cursor* step's verify call, and the stale branch).
#
# Usage: draft-identity.sh check <project.yml>
#
#   <project.yml>  the DEFAULT branch's committed copy (the callers' $DEF_YML_FILE), never the
#                  working tree's, which a branch under review can edit
#
# Prints exactly one line to stdout and exits 0:
#   dev_app       -- all three steps below pass
#   not-dev-app   -- `identities` is not a map with a `dev_app` entry, or the viewer is not the
#                    declared dev App (or gh-identity.sh could not say)
#   stored-login  -- with the token variables removed, `gh` still reads a viewer that is not the
#                    dev App: a stored login a lost token would fall back to
#   unreadable    -- the first viewer read failed
# The steps run in order; the first that fails prints its word and no later step runs.
#   1. identities is a map and has a dev_app entry that is a map.
#   2. The viewer: spec-post.sh's exact call, `gh api --hostname github.com graphql -f
#      query='{ viewer { login databaseId } }' --jq '[.data.viewer.login, .data.viewer.databaseId]
#      | @tsv'`, to a file; then `gh-identity.sh role <login> <id> <project.yml>` must print
#      `dev_app`.
#   3. The fallback: the same read again under `env -u GH_TOKEN -u GITHUB_TOKEN
#      -u GH_ENTERPRISE_TOKEN -u GITHUB_ENTERPRISE_TOKEN`, the account `gh` would act as if the
#      token were lost. Made twice: once with GH_CONFIG_DIR and XDG_CONFIG_HOME left as they are,
#      once with both also unset, so the configured store and the default store are both tested.
#      Each read passes when it fails (there is no fallback) or when it succeeds and `role` says
#      `dev_app` (the dev container, whose `gh` wrapper supplies the dev App's token on every
#      call). Any other result is `stored-login`.
#
# It exits 2 with a usage line on stderr and nothing on stdout for a bad argument, an unreadable
# file, a slash-less $0 or a missing sibling gh-identity.sh, before any `gh` call.
#
# It never prints a token, a login or `gh`'s output, and every `gh` call's stderr goes to
# /dev/null. It makes reads only. Residual: it sees only `gh`'s own store as this environment
# configures it, not a git credential manager, a token file a host hook reads, or a `gh` reached
# through wsl.exe or cmd.exe. The real precondition is the dev container (WB-D31).
#
# Permitted toolset: POSIX sh, env, gh (reads only, with its own --jq), yq, cut, dirname and mktemp.
set -eu
LC_ALL=C
export LC_ALL

usage() {
  echo "usage: draft-identity.sh check <project.yml>" >&2
  exit 2
}
[ "$#" -eq 2 ] || usage
[ "$1" = check ] || usage
yml="$2"
if [ ! -f "$yml" ] || ! yq -o=yaml '.' "$yml" >/dev/null 2>&1; then
  echo "draft-identity.sh: unreadable project.yml" >&2
  exit 2
fi
case "$0" in
  */*) gi="$(dirname "$0")/gh-identity.sh" ;;
  *) echo "draft-identity.sh: must be run by path (a slash-less \$0 cannot locate its sibling)" >&2; exit 2 ;;
esac
[ -f "$gi" ] || { echo "draft-identity.sh: gh-identity.sh not beside this script" >&2; exit 2; }

tmp="$(mktemp -d)" || { echo "draft-identity.sh: no temp directory" >&2; exit 2; }
trap 'rm -rf "$tmp"' EXIT

out() {
  printf '%s\n' "$*"
  exit 0
}

# --- 1. the declared dev App -------------------------------------------------------------
shape="$(yq -r 'explode(.) | [(.identities | tag), (.identities.dev_app | tag)] | join(",")' "$yml" 2>/dev/null)" || out not-dev-app
[ "$shape" = '!!map,!!map' ] || out not-dev-app

# --- the viewer read, as a function so the three steps make the same call -----------------
Q='{ viewer { login databaseId } }'
J='[.data.viewer.login, .data.viewer.databaseId] | @tsv'
role_of() { # <viewer-file>: prints the role word, or fails
  vl="$(cut -f1 <"$1")" && vi="$(cut -f2 <"$1")" && sh "$gi" role "$vl" "$vi" "$yml" 2>/dev/null </dev/null
}

# --- 2. the viewer -----------------------------------------------------------------------
gh api --hostname github.com graphql -f query="$Q" --jq "$J" >"$tmp/v0" 2>/dev/null </dev/null || out unreadable
r0="$(role_of "$tmp/v0")" || out not-dev-app
[ "$r0" = dev_app ] || out not-dev-app

# --- 3. the fallback ---------------------------------------------------------------------
if env -u GH_TOKEN -u GITHUB_TOKEN -u GH_ENTERPRISE_TOKEN -u GITHUB_ENTERPRISE_TOKEN \
  gh api --hostname github.com graphql -f query="$Q" --jq "$J" >"$tmp/v1" 2>/dev/null </dev/null; then
  r1="$(role_of "$tmp/v1")" || out stored-login
  [ "$r1" = dev_app ] || out stored-login
fi
if env -u GH_TOKEN -u GITHUB_TOKEN -u GH_ENTERPRISE_TOKEN -u GITHUB_ENTERPRISE_TOKEN -u GH_CONFIG_DIR -u XDG_CONFIG_HOME \
  gh api --hostname github.com graphql -f query="$Q" --jq "$J" >"$tmp/v2" 2>/dev/null </dev/null; then
  r2="$(role_of "$tmp/v2")" || out stored-login
  [ "$r2" = dev_app ] || out stored-login
fi
out dev_app
