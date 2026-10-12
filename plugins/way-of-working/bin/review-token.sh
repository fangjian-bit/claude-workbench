#!/bin/sh
# Request and discard the short-lived reviewer token the Compose-and-post step posts with
# (WB-D24, #389). The host broker, `wow-review-mint`, is asked only AFTER the review sandbox
# for this PR is gone, so no reviewer token file exists on this host while sandboxed PR code
# runs, and the file is deleted once the post has been attempted. The mint command and its
# token layout are host config (scripts/identity/wow-review-mint, wow-common.sh), never read
# from the repo.
#
# What this does NOT close: the sandbox runs PR code as this user (review-sandbox.sh's own
# "does NOT close" list). That code can read the reviewer App's unencrypted key in $WOW_HOME,
# leave a process or a PATH plant that survives `destroy`, and so reach a token minted
# afterwards or mint its own. The order keeps the token FILE from existing during `run`; it is
# not a credential boundary. The real boundary is a separate uid or container (#158).
#
# Usage:
#   review-token.sh request <owner/repo>
#   review-token.sh discard <owner/repo>
#
# request  refuses (exit 2, nothing minted) while ANY review sandbox exists on this host:
#          anything at all under ${REVIEW_SANDBOX_ROOT:-${TMPDIR:-/tmp}/review-sandbox}, where
#          review-sandbox.sh builds them, so "destroy, then mint" is mechanical and one PR's
#          token file never sits beside another PR's sandboxed code. It takes no path from the
#          caller, and the check is only as good as the REVIEW_SANDBOX_ROOT the sandbox was
#          built under matching the one in this call's environment.
#          It removes any earlier token file for the repo first, so a stale file can never be read as this
#          request's, then runs `wow-review-mint <repo-name>` from PATH. The broker is given
#          only the bare repo name derived here, never --out or anything the sandbox supplied.
#          The result must pass `token-check.sh file` (a live ghs_ installation token);
#          anything else is removed and exits 2. On success it prints the token file's path on
#          stdout and nothing else; the token itself is never printed. The caller reads it
#          with `token-check.sh token <path>` and proves the App with `token-check.sh verify`.
# discard  removes the repo's reviewer-token file and prints `discarded`; exit 2 if it
#          is still there afterwards. Run it whether or not the post succeeded. A missing
#          file is already discarded.
#
# The token file is $WOW_HOME/review-tokens/<repo-name>/reviewer-token, where wow-review-mint
# writes by default. $WOW_HOME is REQUIRED and absolute: the host's identity directory is host
# config, so this plugin script names no default for it. A reviewer token lives its hour on
# GitHub whatever happens here (no revoke, wow-review-mint's header); discard only removes this
# host's copy. Exit 0 / 2. Permitted toolset: POSIX sh.
set -eu
LC_ALL=C; export LC_ALL

die() { echo "review-token.sh: $1" >&2; exit 2; }

here=$(CDPATH= cd -P -- "$(dirname -- "$0")" && pwd)

# name_of <owner/repo>: the bare repo name, plain characters only.
name_of() {
  case "$1" in */*/*|*/|/*|'') die "repository must be owner/name" ;; */*) ;; *) die "repository must be owner/name" ;; esac
  n=${1#*/}
  case "$n" in ''|.|..|-*|*[!A-Za-z0-9._-]*) die "repository name must be letters, digits, . _ - only" ;; esac
  printf '%s\n' "$n"
}

token_path() {
  case "${WOW_HOME:-}" in /*) ;; *) die "WOW_HOME must be set to the host identity directory (an absolute path)" ;; esac
  printf '%s/review-tokens/%s/reviewer-token\n' "$WOW_HOME" "$1"
}

case "${1:-}" in
  request)
    [ "$#" -eq 2 ] || die "usage: review-token.sh request <owner/repo>"
    root=${REVIEW_SANDBOX_ROOT:-${TMPDIR:-/tmp}/review-sandbox}
    if [ -L "$root" ]; then die "the sandbox root $root is a symlink; point REVIEW_SANDBOX_ROOT at the real directory"; fi
    if [ -e "$root" ] && { [ ! -d "$root" ] || ! ls=$(ls -A "$root" 2>/dev/null) || [ -n "$ls" ]; }; then
      die "a review sandbox still exists under $root; destroy it before requesting a reviewer token"
    fi
    name=$(name_of "$2")
    command -v wow-review-mint >/dev/null 2>&1 || die "wow-review-mint is not on PATH (the host broker)"
    f=$(token_path "$name")
    rm -f -- "$f"
    if ! wow-review-mint "$name" >/dev/null; then
      rm -f -- "$f"
      die "the broker did not mint a reviewer token"
    fi
    if ! sh "$here/token-check.sh" file "$f" >/dev/null; then
      rm -f -- "$f"
      die "the minted reviewer token failed the fail-closed check"
    fi
    printf '%s\n' "$f"
    ;;
  discard)
    [ "$#" -eq 2 ] || die "usage: review-token.sh discard <owner/repo>"
    name=$(name_of "$2")
    f=$(token_path "$name")
    rm -f -- "$f"
    [ ! -e "$f" ] && [ ! -L "$f" ] || die "the reviewer token file is still there"
    echo discarded
    ;;
  *) die "usage: review-token.sh request <owner/repo> | discard <owner/repo>" ;;
esac
