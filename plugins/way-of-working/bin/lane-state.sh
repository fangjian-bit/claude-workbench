#!/bin/sh
# Which lanes are live, derived from the layout and GitHub rather than recorded anywhere
# (#729). A lane is a git worktree at exactly <lanes dir>/<N> checked out on a branch, one per
# task issue N (project-schema.md § `lanes`). Its callers: /way-of-working:handoff (writes the
# array into the cursor's `lanes` field) and /way-of-working:resume (reports it on a `Lanes:`
# line and compares it with the recorded one).
#
# Usage: lane-state.sh list  <dir> <project.yml>
#        lane-state.sh check <dir> <project.yml> <state.json>
#
#   <dir>          `lanes.dir`, read by the caller from the DEFAULT branch's copy
#   <project.yml>  the DEFAULT branch's committed copy (the callers' $DEF_YML_FILE), never the
#                  working tree's, which a branch under review can edit
#   <state.json>   `check` only: the cursor, .ai/state.json
#
# <dir> must be an absolute path of A-Za-z0-9._/- with no //, no . or .. component and no
# trailing slash (scripts/lanes/lane.sh's lanes_shape_ok), a directory, not a link, owned by
# this user, and its resolved path (cd -P) must pass the same rule; the resolved path is what
# worktrees are matched against. A <dir> that does not exist is no lanes: `[]`.
#
# `list` prints one compact JSON array on one line, `[]` for none, ordered by issue. Each
# element: {"issue":N,"branch":"TYPE/SLUG","worktree":"<dir>/N","spec":S,"pr":P}.
#   spec  {"id":ID,"updated_at":"YYYY-MM-DDTHH:MM:SSZ"} when the sibling spec-find.sh says
#         `found`; otherwise the finder's first word as a string (`unreacted <ids>` is
#         "unreacted"). A finder `unreadable` is that one lane's value, not the whole output's.
#   pr    {"number":N,"state":"OPEN"|"CLOSED"|"MERGED"} for exactly one same-repository PR on
#         the branch, null for none, "ambiguous" for more than one. Cross-repository PRs are
#         dropped inside gh's own --jq.
# `check` runs the same derivation. Line 1 is `same` or `differs` (the recorded `lanes` against
# the live array), or `no-record` (the file is absent, has no `lanes` field, or it is null);
# line 2 is the live array. The recorded value is only compared, never printed.
#
# Either mode prints only `unreadable` (exit 0) when one of its own reads fails or a value falls
# outside its shape: `repo` or `backlog.repo` (null means `repo`) not owner/name; a branch that
# is not TYPE/SLUG (the nine commit types, then a slug of a-z, 0-9 and - not starting with -); a
# worktree path outside the <dir> rule; a PR number or state outside the forms above; a found id
# or timestamp outside the finder's own forms; a finder that exits non-zero or prints other than
# one known line; a <dir> that fails the rule above; a gh, git or yq failure.
#
# Exits 2, printing nothing to stdout, for a usage error: the wrong count, an unknown mode, an
# unreadable <project.yml>, a slash-less $0, or a spec-find.sh not beside this script. It uses only the SIBLING spec-find.sh, found
# through $0 as spec-find.sh finds its own siblings: a slash-less $0 would resolve to the current
# directory, where a branch under review could supply a finder that prints `found`. It names no
# lanes directory of its own.
#
# The caller's GIT_DIR, GIT_WORK_TREE and GIT_COMMON_DIR are cleared, so the worktree list is the
# current directory's repository.
# Every gh and git call's stderr goes to /dev/null and stdin to /dev/null. Branch names, paths
# and ids are shape-checked before they are printed, so the JSON is built without escaping.
# Nothing is evaluated; no comment or issue text is read.
#
# Permitted toolset: POSIX sh plus `test -O`, git 2.36 or later (worktree list -z), gh (with its own
# --jq), yq (mikefarah v4), awk, sort, tr, dirname, rm, mktemp. Runs under LC_ALL=C.
set -eu
set -f
LC_ALL=C
export LC_ALL
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR

usage() {
  echo "usage: lane-state.sh list <dir> <project.yml> | lane-state.sh check <dir> <project.yml> <state.json>" >&2
  exit 2
}

[ "$#" -ge 1 ] || usage
mode=$1
case "$mode" in
  list) [ "$#" -eq 3 ] || usage ;;
  check) [ "$#" -eq 4 ] || usage ;;
  *) usage ;;
esac
dir=$2
yml=$3
state=
[ "$mode" = check ] && state=$4

if [ ! -f "$yml" ] || ! yq -o=yaml '.' "$yml" >/dev/null 2>&1; then
  echo "lane-state.sh: unreadable project.yml" >&2
  exit 2
fi
case "$0" in
  */*) sf="$(dirname "$0")/spec-find.sh" ;;
  *) echo "lane-state.sh: must be run by path (a slash-less \$0 cannot locate its siblings)" >&2; exit 2 ;;
esac
[ -f "$sf" ] || { echo "lane-state.sh: spec-find.sh not beside this script" >&2; exit 2; }

tmp=
trap '[ -z "$tmp" ] || rm -rf "$tmp"' EXIT
trap 'exit 1' INT TERM HUP

out() {
  printf '%s\n' "$*"
  exit 0
}

num_ok() { # digits with no leading zero
  case "$1" in
    '' | 0* | *[!0-9]*) return 1 ;;
  esac
  return 0
}

branch_ok() { # TYPE/SLUG, as lane.sh has it
  case "$1" in
    */*) ;;
    *) return 1 ;;
  esac
  b_type=${1%%/*}
  b_slug=${1#*/}
  case "$b_type" in
    feat | fix | docs | test | refactor | perf | chore | ci | revert) ;;
    *) return 1 ;;
  esac
  case "$b_slug" in
    '' | -* | *[!a-z0-9-]*) return 1 ;;
  esac
  return 0
}

dir_shape_ok() { # an absolute path of A-Za-z0-9._/-, no //, no . or .. component, no trailing /
  case "$1" in
    /*) ;;
    *) return 1 ;;
  esac
  case "$1" in
    *[!A-Za-z0-9._/-]* | *// | */) return 1 ;;
  esac
  case "$1/" in
    *//* | */./* | */../*) return 1 ;;
  esac
  return 0
}

repo_ok() { # owner/name in spec-find.sh's charset
  case "$1" in
    '' | *[!A-Za-z0-9._/-]* | */*/* | /* | */ | ./* | ../* | */. | */..) return 1 ;;
    */*) return 0 ;;
    *) return 1 ;;
  esac
}

ts_ok() { # YYYY-MM-DDTHH:MM:SSZ
  case "$1" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) return 0 ;;
  esac
  return 1
}

# --- the configuration ---------------------------------------------------------------------
repo=$(yq -r 'explode(.) | .repo | select(tag == "!!str")' "$yml" 2>/dev/null) || out unreadable
backlog=$(yq -r 'explode(.) | (.backlog.repo // .repo) | select(tag == "!!str")' "$yml" 2>/dev/null) || out unreadable
repo_ok "$repo" || out unreadable
repo_ok "$backlog" || out unreadable

# --- the lanes directory -------------------------------------------------------------------
live=
derive() {
  dir_shape_ok "$dir" || { live=unreadable; return; }
  [ ! -L "$dir" ] || { live=unreadable; return; }
  if [ ! -e "$dir" ]; then live='[]'; return; fi
  [ -d "$dir" ] && [ -O "$dir" ] || { live=unreadable; return; }
  res=$(cd -P "$dir" 2>/dev/null && pwd -P) || { live=unreadable; return; }
  dir_shape_ok "$res" || { live=unreadable; return; }

  tmp=$(mktemp -d) || { live=unreadable; return; }
  # git's -z output, with a newline inside a path turned into \001 (which fails the shape rule)
  # and each NUL into a newline, reads as the plain porcelain.
  git worktree list --porcelain -z 2>/dev/null </dev/null | tr '\n\0' '\001\n' >"$tmp/wt" || { live=unreadable; return; }
  [ -s "$tmp/wt" ] || { live=unreadable; return; }

  : >"$tmp/elems"
  wt_path=
  wt_branch=
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "worktree "*) wt_path=${line#worktree }; wt_branch= ;;
      "branch refs/heads/"*) wt_branch=${line#branch refs/heads/} ;;
      '') # end of one worktree's block
        if [ -n "$wt_path" ]; then
          lane_one || return 0
        fi
        wt_path=
        wt_branch=
        ;;
    esac
  done <"$tmp/wt"
  [ -z "$wt_path" ] || lane_one || return 0

  if [ -s "$tmp/elems" ]; then
    body=$(sort -n "$tmp/elems" | awk -F '\t' 'NR > 1 { printf "," } { printf "%s", $2 }') || { live=unreadable; return; }
    live="[$body]"
  else
    live='[]'
  fi
}

# lane_one: judge the worktree in wt_path/wt_branch; append "<N>\t<json>" to elems. Sets
# live=unreadable and returns 1 on a failure that voids the whole output.
lane_one() {
  case "$wt_path" in
    "$res"/*) ;;
    *) return 0 ;;
  esac
  l_n=${wt_path#"$res"/}
  num_ok "$l_n" || return 0
  [ -n "$wt_branch" ] || return 0   # detached, or bare: not a lane
  dir_shape_ok "$wt_path" || { live=unreadable; return 1; }
  branch_ok "$wt_branch" || { live=unreadable; return 1; }

  f=$("$sf" find "$l_n" "$yml" 2>/dev/null </dev/null) || { live=unreadable; return 1; }
  case "$f" in
    *'
'*) live=unreadable; return 1 ;;
  esac
  set -- $f
  case "${1:-}" in
    found)
      [ "$#" -eq 3 ] && num_ok "$2" && ts_ok "$3" || { live=unreadable; return 1; }
      spec="{\"id\":$2,\"updated_at\":\"$3\"}"
      ;;
    none | unreacted | escalated | ambiguous | moved | unreadable) spec="\"$1\"" ;;
    *) live=unreadable; return 1 ;;
  esac

  gh pr list -R "$repo" --head "$wt_branch" --state all --json number,state,isCrossRepository \
    --jq '.[] | select(.isCrossRepository == false) | [(.number | tostring), .state] | @tsv' \
    >"$tmp/pr" 2>/dev/null </dev/null || { live=unreadable; return 1; }
  pr_n=0
  pr_num=
  pr_state=
  while IFS='	' read -r p_num p_state extra; do
    num_ok "$p_num" || { live=unreadable; return 1; }
    case "$p_state" in OPEN | CLOSED | MERGED) ;; *) live=unreadable; return 1 ;; esac
    [ -z "$extra" ] || { live=unreadable; return 1; }
    pr_n=$((pr_n + 1))
    pr_num=$p_num
    pr_state=$p_state
  done <"$tmp/pr"
  case "$pr_n" in
    0) pr=null ;;
    1) pr="{\"number\":$pr_num,\"state\":\"$pr_state\"}" ;;
    *) pr='"ambiguous"' ;;
  esac
  printf '%s\t{"issue":%s,"branch":"%s","worktree":"%s","spec":%s,"pr":%s}\n' \
    "$l_n" "$l_n" "$wt_branch" "$wt_path" "$spec" "$pr" >>"$tmp/elems"
  return 0
}

derive
[ "$live" != unreadable ] || out unreadable

if [ "$mode" = list ]; then
  out "$live"
fi

# --- check: the recorded value against the live one ----------------------------------------
[ -f "$state" ] || out "no-record
$live"
rec_tag=$(yq -p=json -r '.lanes | tag' "$state" 2>/dev/null) || out unreadable
[ "$rec_tag" != '!!null' ] || out "no-record
$live"
[ -n "$tmp" ] || tmp=$(mktemp -d) || out unreadable
rec=$(yq -p=json -o=json -I=0 '.lanes | sort_keys(..)' "$state" 2>/dev/null) || out unreadable
printf '%s\n' "$live" >"$tmp/live.json"
now=$(yq -p=json -o=json -I=0 'sort_keys(..)' "$tmp/live.json" 2>/dev/null) || out unreadable
if [ "$rec" = "$now" ]; then
  out "same
$live"
fi
out "differs
$live"
