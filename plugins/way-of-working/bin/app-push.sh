#!/bin/sh
# The one place a skill's App-mode `git push` is spelled.
#
# WB-D24 (#478): in App mode (`gh api user` refused to an installation token) a push made
# with whatever credential `git` holds is made by the maintainer's own stored login, not by
# the dev App that opens the PR. On a base whose approval rule sets
# `require_last_push_approval`, GitHub then counts the human as the last pusher and does not
# count the human's own approval -- with one code owner nobody else can approve, so the PR
# cannot merge (found live, #464 PR 2). Pinning `git` to `gh`'s token makes the App the
# pusher. The pin used to be copied prose in `ship`; it lives here so `ship`, `handoff`,
# `archive-sprint` and `resume`'s schema interview cannot drift apart, and
# tests/app-push.test.sh holds every pushing skill to calling this rather than spelling a
# push itself.
#
# Usage: app-push.sh [-u|--set-upstream] [-n|--dry-run] <remote> <refspec>...
#        e.g.  app-push.sh -u origin <branch>      app-push.sh --dry-run origin <branch>
# Runs `git push` with the host-configured credential helper cleared, `gh` as the only
# helper, and the generic `http.extraHeader` cleared. Exit status is git's. Not for user
# mode: there `git push` with the user's own credential is correct, and a skill says so. This
# script makes no decision about the mode; the caller has already named the actor.
#
# An allow-list, not a deny-list: git accepts abbreviated long options, bundled short flags
# and empty-source refspecs, so a list of forbidden spellings cannot be complete. Exit 2,
# nothing run, unless the arguments are:
#   - only the options above (none of `--force`, `--delete`, `--mirror`, `--prune`,
#     `--receive-pack`, `--exec`, `--repo` or a bundle like `-uf` is on it);
#   - a <remote> NAME (not a URL) followed by at least one <refspec>, so no push refspec or
#     `remote.<name>.mirror` from ambient config decides what is sent. A refspec that starts
#     with `+` or `:` (force, delete) or contains `^` or whitespace is refused;
#   - and the pin can actually work: every fetch-side and push-side URL of the remote
#     (`git remote get-url --push --all`, so `pushurl` and `pushInsteadOf` count) starts with
#     `https://github.com/` -- over SSH no credential helper is consulted at all, and the
#     human's key would push -- and no URL-scoped `http.<url>.extraheader` is set for it,
#     which the generic reset below cannot clear and which would supply credentials before
#     the helper is asked.
# A refspec containing `*` is refused too (it would push every matching local ref), and so is a
# remote with `remote.<name>.vcs` set (a helper would receive the pinned credential config).
# It cannot refuse a push to the PR base: it may not name one (the coupling rule). That
# stays a skill rule, and the base's ruleset (`pull_request`, `deletion`,
# `non_fast_forward`) is the control behind it.
#
# Permitted toolset: POSIX sh and git.
set -eu

die() {
  echo "app-push.sh: $1" >&2
  exit 2
}

upstream=
dry=
remote=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -u|--set-upstream) upstream="$1"; shift ;;
    -n|--dry-run) dry="$1"; shift ;;
    -*) die "refusing option '$1' -- only -u/--set-upstream and -n/--dry-run are allowed" ;;
    '') die "empty remote name" ;;
    *://*|*@*:*|/*|./*|../*) die "'$1' is a URL or path; name a configured remote" ;;
    *) remote="$1"; shift; break ;;
  esac
done

[ -n "$remote" ] || die "usage: app-push.sh [-u] [-n] <remote> <refspec>..."
[ "$#" -ge 1 ] || die "name at least one refspec (a push with none is decided by ambient config)"
for r in "$@"; do
  case "$r" in
    +*|:*|*'^'*|*'*'*|-*|''|*[[:space:]]*) die "refusing refspec '$r'" ;;
  esac
done

[ -z "$(git config --get "remote.$remote.vcs" 2>/dev/null || true)" ] || die "remote '$remote' sets a remote helper (remote.$remote.vcs); the pin would not apply"
set -f
urls=$( { git remote get-url --all "$remote"; git remote get-url --push --all "$remote"; } 2>/dev/null ) \
  || die "cannot read the URLs of remote '$remote'"
[ -n "$urls" ] || die "remote '$remote' has no URL"
for u in $urls; do
  case "$u" in
    https://github.com/*) ;;
    *) die "remote '$remote' URL '$u' is not https://github.com/ -- the credential pin would not apply" ;;
  esac
  hdr=$(git -c http.extraHeader= config --get-urlmatch http.extraheader "$u" 2>/dev/null || true)
  [ -z "$hdr" ] || die "a URL-scoped http.extraheader is set for '$u' and would be sent ahead of the helper"
done

# shellcheck disable=SC2086
exec git -c credential.helper= -c credential.helper='!gh auth git-credential' \
  -c http.extraHeader= push $upstream $dry "$remote" "$@"
