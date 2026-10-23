#!/bin/sh
# Screen a file for obvious local-path and secret shapes, printing one verdict line.
#
# Usage: leak-screen.sh FILE
#
# Who calls it: /way-of-working:retro, over the transcript-reader's report (written to a file by the
# session) before any of the report is used (#914). The reader can Read any path, so text injected
# into a transcript could steer it to a credentials file and into its paraphrase; this is the filter
# between that paraphrase and anything retro then does with it. A filter on obvious shapes, not a boundary: a
# secret in any form other than the raw shape (spelled out, escaped, split across lines) passes.
#
# Output is exactly one line on stdout, and never any matched text, on either stream:
#   ok                 exit 0   no shape matches any line
#   leak LINE SHAPE    exit 1   LINE is the 1-based number of the first line SHAPE matches (grep -n skips a
#                               line holding an invalid byte under a UTF-8 locale, so LINE can then be later)
#   unreadable         exit 1   the file is missing or unreadable, a grep exits with an error, or
#                               the line number cannot be read back (a NUL byte, as in spec-post.sh)
# A wrong argument count prints a usage line on stderr, nothing on stdout, and exits 2.
#
# The shapes run in this order, and the first that matches any line wins, whatever its line order:
# the six of spec-post.sh's leak filter (drive, users, home, appdata, pem, token), copied byte for
# byte and pinned by tests/leak-screen.test.sh, then anthropic (an sk-ant- key, the fragment
# review-outbox.sh's secret check uses), tilde (a home-relative path) and abspath (slash-led text
# with a second slash, the usual form of an absolute path, or any text holding three slashes in a
# row after a colon, which also drops a non-file URL with an empty host). Abspath is a filter on
# that one shape, not a guarantee.
# Known misses:
#   - a single-segment path
#   - a path with a space in its first segment
#   - a path written straight after an ASCII letter or digit, a dot, an underscore, a star, a
#     hyphen or a slash (so a home path written as a bare environment variable)
#   - under a UTF-8 locale, a path written straight after an invalid byte, or a first segment
#     holding one
#   - a file URL with a host
#   - a relative climb
#   - a backslash path with no drive letter
# Known false drops: any line with a slash not written straight after an ASCII letter or digit, a
# dot, an underscore, a star, a hyphen or a slash, then non-slash non-space text, then a second
# slash:
#   - a site-relative link
#   - an API route
#   - a URL query with a slash after an equals sign
#   - a path segment in braces or brackets
#   - two slash commands joined by a slash
# It runs under the caller's locale, as spec-post.sh does.
#
# Permitted toolset: POSIX sh, grep, sed, cut, mktemp, rm.

if [ "$#" -ne 1 ]; then
  echo "usage: leak-screen.sh FILE" >&2
  exit 2
fi
file="$1"

tmp=""
cleanup() {
  [ -z "$tmp" ] || rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 1' INT TERM HUP

stop() {
  echo "$1"
  case "$1" in ok) exit 0 ;; *) exit 1 ;; esac
}

[ -f "$file" ] && [ -r "$file" ] || stop unreadable
tmp="$(mktemp -d 2>/dev/null)" && [ -n "$tmp" ] || {
  tmp=""
  stop unreadable
}

# match <grep-args...> -- 0 when the file has a matching line, 1 when not; any other status is a stop
match() {
  _rc=0
  grep -q "$@" -- "$file" >/dev/null 2>&1 || _rc=$?
  case "$_rc" in
    0) return 0 ;;
    1) return 1 ;;
    *) stop unreadable ;;
  esac
}
# leak <shape> <grep-args...> -- stops `leak <line> <shape>` when the file has a matching line. The
# decision is match()'s; only after a match does the same grep run once more as `grep -n`, to a file
# (never piped: sh has no pipefail) with its stderr discarded, and the first line's number is read back.
leak() {
  _shape="$1"
  shift
  if match "$@"; then
    _nrc=0
    grep -n "$@" -- "$file" >"$tmp/leakn" 2>/dev/null || _nrc=$?
    [ "$_nrc" -eq 0 ] || stop unreadable
    _ln="$(sed -n 1p "$tmp/leakn" | cut -d: -f1)" || stop unreadable
    case "$_ln" in '' | 0* | *[!0-9]*) stop unreadable ;; esac
    stop "leak $_ln $_shape"
  fi
}
leak drive -E -e '(^|[^A-Za-z0-9])[A-Za-z]:[/\\]'
leak users -F -e '/Users/'
leak home -F -e '/home/'
leak appdata -F -e 'AppData'
leak pem -F -e '-----BEGIN'
leak token -E -e '(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}' -e 'github_pat_[A-Za-z0-9]{20,}'
leak anthropic -E -e 'sk-ant-[A-Za-z0-9_-]{20,}'
leak tilde -F -e '~/'
leak abspath -E -e '(^|[^A-Za-z0-9._*/-])/[^/[:space:]]+/' -e ':///'

stop ok
