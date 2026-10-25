#!/bin/sh
# Which critics does /way-of-working:critic-gate's diff mode run on this diff, by rule? (#1109, WB-D41)
#
# The diff mode proposes a critic list and waits on a pick-list (WB-D16). A repo that sets
# `agents.diff_rule` to a list instead has the set computed here, from the diff's paths and the
# default branch's committed config, so the choice is not a session's to make. Its caller:
# /way-of-working:critic-gate's *Propose the applicable critics* step, in the Bash call that uses
# its result.
#
# Usage: critic-select.sh <project.yml> [<critic>...]
#
#   <project.yml>  an absolute path to the DEFAULT branch's committed copy (the caller's read of it into a temp file),
#                  never the working tree's, which the branch under review can edit. This is the only
#                  config the script reads.
#   <critic>       a critic name the session holds (an invocation line, a lane prompt, a driver
#                  message), `^[a-z][a-z0-9-]*$`. A name is unioned with the rule's set: a list can add
#                  a critic and never drop one.
#
# It clears GIT_DIR, GIT_WORK_TREE, GIT_COMMON_DIR and GIT_INDEX_FILE and changes to the repository's
# top level before any other read, so the session's working directory never narrows the paths. It
# reads `pr_base`, `agents.enabled`, `agents.diff_rule`, `code_paths` and `load_bearing_docs` from
# <project.yml> with yq. It fetches `pr_base` into refs/remotes/origin/<pr_base>, takes the merge base
# of that ref and HEAD, and collects the changed paths as the union of
# `git diff --no-relative --no-renames --name-only -z` against the merge base (committed, staged and
# unstaged changes, deletions, both sides of a rename; the index is read as well, so a change staged and
# then reverted in the working tree still counts) and `git ls-files --others --exclude-standard -z`
# (untracked files), the NUL-separated lists turned into lines with `tr`.
#
# The rule: a path ending in `.md`, or matching a `load_bearing_docs` entry (exactly, or as a shell
# glob), selects `docs-consistency`; a path under a `code_paths` entry or an `agents.diff_rule` entry
# (prefix match) selects `architect` and `security-critic`.
#
# It prints exactly one line and exits 0:
#   propose                    -- `agents.diff_rule` is null: the diff mode proposes and the human picks
#   critics <name>[,<name>...] -- the fixed order architect, security-critic, docs-consistency, then the
#                                 argument names in the order given, deduplicated, each kept only when it
#                                 is in `agents.enabled` and is not `coder`
#   none                       -- that list is empty
#   unreadable                 -- the file, a key or yq cannot be read; `agents.diff_rule` is absent or
#                                 neither null nor a list; any other key is not the expected shape; or the
#                                 fetch, the merge base or a git read failed
# It never prints a path or any text read from the diff or the file.
#
# Exits 2, with a usage line on stderr and nothing on stdout, for no argument, a <project.yml> that is not
# an absolute path, or a critic argument that does not match the pattern above. A `code_paths` or
# `agents.diff_rule` entry the prefix match cannot honour (a glob character, a leading `/` or `./`, a `..`
# segment) reads `unreadable`, as the review gate's trigger check treats such an entry.
#
# Permitted toolset: POSIX sh, git (2.28 or later), yq (mikefarah v4), grep, cat, tr, rm, mktemp. Runs under LC_ALL=C.
set -eu
LC_ALL=C
export LC_ALL

usage() {
  echo "usage: critic-select.sh <project.yml> [<critic>...]" >&2
  exit 2
}
[ "$#" -ge 1 ] || usage
yml="$1"
shift
case "$yml" in /*) : ;; *) usage ;; esac
for n in "$@"; do
  case "$n" in
    '' | [!a-z]* | *[!a-z0-9-]*) usage ;;
  esac
done

unreadable() {
  echo unreadable
  exit 0
}

unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
top=$(git rev-parse --show-toplevel 2>/dev/null) || unreadable
[ -n "$top" ] || unreadable
cd "$top" 2>/dev/null || unreadable
[ -f "$yml" ] && [ -r "$yml" ] || unreadable

tmp=$(mktemp -d) || unreadable
trap 'rm -rf "$tmp"' EXIT

# list_of <expr> -- the list at <expr>, one string per line; refuses a non-list, a non-string item,
# an empty item or one with a control character. Prints nothing for an empty list.
list_of() {
  [ "$(yq -r "$1 | tag" "$yml" 2>/dev/null)" = '!!seq' ] || return 1
  bad=$(yq -r "[$1[] | select(tag != \"!!str\" or . == \"\" or test(\"[\\\\x00-\\\\x1f]\"))] | length" "$yml" 2>/dev/null) || return 1
  [ "$bad" = 0 ] || return 1
  yq -r "$1[]" "$yml" 2>/dev/null
}

base=$(yq -r '.pr_base // ""' "$yml" 2>/dev/null) || unreadable
case "$base" in '' | -* | *[!A-Za-z0-9._/-]*) unreadable ;; esac

[ "$(yq -r '.agents | has("diff_rule")' "$yml" 2>/dev/null)" = true ] || unreadable
enabled=$(list_of .agents.enabled) || unreadable
code=$(list_of .code_paths) || unreadable
docs=$(list_of .load_bearing_docs) || unreadable
case "$(yq -r '.agents.diff_rule | tag' "$yml" 2>/dev/null)" in
  '!!null')
    echo propose
    exit 0
    ;;
  '!!seq') rule=$(list_of .agents.diff_rule) || unreadable ;;
  *) unreadable ;;
esac
# An entry the prefix match cannot honour would drop critics silently.
while IFS= read -r e; do
  [ -n "$e" ] || continue
  case "$e" in
    /* | ./* | ../* | */../* | */.. | .. | *[*?[\]{}!]*) unreadable ;;
  esac
done <<EOF
$code
$rule
EOF

git fetch -q origin "+refs/heads/$base:refs/remotes/origin/$base" >/dev/null 2>&1 || unreadable
mb=$(git merge-base "refs/remotes/origin/$base" HEAD 2>/dev/null) || unreadable
[ -n "$mb" ] || unreadable
git diff --no-relative --no-renames --name-only -z "$mb" >"$tmp/d" 2>/dev/null || unreadable
git diff --cached --no-relative --no-renames --name-only -z "$mb" >"$tmp/c" 2>/dev/null || unreadable
git ls-files --others --exclude-standard -z >"$tmp/u" 2>/dev/null || unreadable
cat "$tmp/d" "$tmp/c" "$tmp/u" | tr '\0' '\n' >"$tmp/paths"

want_code=false
want_docs=false
while IFS= read -r p; do
  [ -n "$p" ] || continue
  case "$p" in *.md) want_docs=true ;; esac
  if [ "$want_docs" = false ]; then
    while IFS= read -r g; do
      [ -n "$g" ] || continue
      # shellcheck disable=SC2254 -- the entry is a glob by design
      case "$p" in $g) want_docs=true; break ;; esac
    done <<EOF
$docs
EOF
  fi
  if [ "$want_code" = false ]; then
    while IFS= read -r c; do
      [ -n "$c" ] || continue
      case "$p" in "$c"*) want_code=true; break ;; esac
    done <<EOF
$code
$rule
EOF
  fi
done <"$tmp/paths"

cands=""
[ "$want_code" = true ] && cands="architect
security-critic"
[ "$want_docs" = true ] && cands="$cands
docs-consistency"
for n in "$@"; do
  cands="$cands
$n"
done

# The rule's three in their fixed order when selected (by the rule or by a name), then the names.
ordered=""
for f in architect security-critic docs-consistency; do
  if printf '%s\n' "$cands" | grep -Fxq -e "$f"; then ordered="$ordered
$f"; fi
done
ordered="$ordered
$cands"

out=""
while IFS= read -r c; do
  [ -n "$c" ] || continue
  [ "$c" != coder ] || continue
  printf '%s\n' "$enabled" | grep -Fxq -e "$c" || continue
  case ",$out," in *",$c,"*) continue ;; esac
  out="${out:+$out,}$c"
done <<EOF
$ordered
EOF

if [ -z "$out" ]; then echo none; else echo "critics $out"; fi
