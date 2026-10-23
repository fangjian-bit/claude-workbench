#!/bin/sh
# Which open tasks on a milestone can run as parallel lanes now (#896). Two tasks can run
# together when the paths their approved spec comments list under *Files touched* are disjoint
# (a bullet marked (append) does not count, except under .github/) and no `depends_on` from the
# milestone's Build order holds between them. The output is display only: nothing gates on it,
# and the driver uses it to update the milestone description's Lanes line through
# milestone-desc.sh by hand. Nothing here writes a description, an issue or a comment.
#
# Usage: lane-groups.sh <milestone> <project.yml>
#
#   <milestone>    the milestone number, digits with no leading zero
#   <project.yml>  the DEFAULT branch's committed copy (the callers' $DEF_YML_FILE), never the
#                  working tree's, which a branch under review can edit
#
# Run it from inside a checkout of the repository: each `spec-fresh.sh check` it runs fetches the
# base into that checkout. The caller's GIT_DIR, GIT_WORK_TREE and GIT_COMMON_DIR are cleared.
# It reads the backlog repo (`backlog.repo`, or `repo` when that is null; owner/name) from
# <project.yml> with yq, aliases expanded.
#
# Two `gh` reads of the milestone, each to a file with its exit status checked: its open issues in
# the backlog repo, pull requests dropped and only the number projected inside gh's own --jq,
# paginated; and its description, projected to that one field. It never reads an issue body, a
# title or a comment listing. For each open issue it runs the sibling `spec-find.sh find`:
#   found    the one comment is fetched by id to a file (exit status checked); its `.id` and
#            `.updated_at` are read with yq (never `.body`) and compared with the finder's line
#            (either one differing is state `moved`; a malformed finder line, a failed fetch or a
#            failed yq read is `unreadable`); then `spec-fresh.sh check` on the file: `fresh` is state
#            `found`, a first word of `stale` is `stale`, any other output is `unreadable`
#   others   the finder's first word is the state (`none`, `unreacted`, `escalated`, `ambiguous`,
#            `moved`, `unreadable`) and no comment is fetched; a finder that exits non-zero or
#            prints anything else is `unreadable` for that row only
# Paths come from `spec-fresh.sh paths` on the same file, for the `found` and `stale` states only.
# They are used only when that is one line whose first word is `paths` and whose other words each
# pass the path rule (A-Za-z0-9._/-, not starting with - or /, no empty, . or .. segment);
# otherwise that row's paths are unknown. Comment text never reaches stdout: the only text taken
# from a comment is a path from an approved spec, after that rule.
#
# Two issues share a path when a path of one equals a path of the other, or either begins with
# the other followed by a slash.
#
# Waits come from the description through the sibling `plan-depends.sh order` and `read`:
# `independent` waits for nothing; `after` waits for the named issues still open on the milestone;
# `all-earlier` waits for every earlier build-order issue still open; an issue not in the list
# (`all-earlier not-listed`) waits for every listed issue still open. Any `read` output other than
# one `independent`, `after` or `all-earlier` line reads as `all-earlier`. When `order` exits
# non-zero or prints anything but an `order` line, every row's waits field is `order-unreadable`.
# A dependency that is not an open issue on the milestone is read as met; that includes an issue
# that is still open but was moved off the milestone.
#
# Output, one TSV row per open issue, ascending by number:
#   <number> TAB <state> TAB <paths> TAB <shared> TAB <waits>
#   state   found, stale, moved, unreadable, or the finder's other first word
#   paths   space-separated; `-` when none outside (append) bullets (.github/ ones count); `?` unknown
#   shared  open issues it shares a path with (`#a,#b`), `-`, or `?` for a row with unknown paths
#   waits   `#a,#b`, `-` or `order-unreadable`
# then one line per group: `group` TAB <group number from 1> TAB `#a #b`; or the single line
# `group none`. An issue is ready when its state is `found`, its paths are known and its waits
# field is `-`. Ready issues are taken in build-order position, then the unlisted ones ascending by
# number, and each goes into the first group none of whose issues it shares a path with. A stale
# spec is listed with its paths and is in no group. Live lanes are not consulted.
# A config read, the milestone listing, the description fetch or the final pass that builds the
# rows and groups failing prints only `unreadable` (exit 0), as does a listed number with a
# leading zero. That pass writes to a file under the script's own temp directory, printed only
# when it exits 0, so no partial row reaches stdout; a `cat` that fails while printing it is not
# covered.
#
# Exits 2, printing nothing to stdout, for a usage error: the wrong count, a bad milestone number,
# an unreadable <project.yml>, a slash-less $0, or a spec-find.sh, spec-fresh.sh or plan-depends.sh
# not beside this script. It runs only those SIBLING copies, found through $0 as lane-state.sh
# finds its finder: a slash-less $0 would resolve to the current directory, where a branch under
# review could supply a finder that prints `found`.
#
# Every gh, git and yq call's stderr goes to /dev/null and stdin to /dev/null. Nothing is
# evaluated; no fetched value is run.
#
# Permitted toolset: POSIX sh, gh (with its own --jq), yq (mikefarah v4), awk, sort, basename,
# dirname, rm, mktemp, cat. Runs under LC_ALL=C with pathname expansion off.
set -eu
set -f
LC_ALL=C
export LC_ALL
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR

usage() {
  echo "usage: lane-groups.sh <milestone> <project.yml>" >&2
  exit 2
}

[ "$#" -eq 2 ] || usage
ms=$1
yml=$2
case "$ms" in
  '' | 0* | *[!0-9]*) usage ;;
esac
if [ ! -f "$yml" ] || ! yq -o=yaml '.' "$yml" >/dev/null 2>&1 </dev/null; then
  echo "lane-groups.sh: unreadable project.yml" >&2
  exit 2
fi
case "$0" in
  */*) here=$(dirname "$0") ;;
  *) echo "lane-groups.sh: must be run by path (a slash-less \$0 cannot locate its siblings)" >&2; exit 2 ;;
esac
sf="$here/spec-find.sh"
sfr="$here/spec-fresh.sh"
pd="$here/plan-depends.sh"
for s in "$sf" "$sfr" "$pd"; do
  [ -f "$s" ] || { echo "lane-groups.sh: $(basename "$s") not beside this script" >&2; exit 2; }
done

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

ts_ok() { # YYYY-MM-DDTHH:MM:SSZ
  case "$1" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) return 0 ;;
  esac
  return 1
}

repo_ok() { # owner/name in spec-find.sh's charset
  case "$1" in
    '' | *[!A-Za-z0-9._/-]* | */*/* | /* | */ | ./* | ../* | */. | */..) return 1 ;;
    */*) return 0 ;;
    *) return 1 ;;
  esac
}

path_ok() { # the Shape stage's path rule
  case "$1" in
    '' | -* | /* | *[!A-Za-z0-9._/-]*) return 1 ;;
  esac
  case "/$1/" in
    *//* | */./* | */../*) return 1 ;;
  esac
  return 0
}

# --- the configuration ---------------------------------------------------------------------
backlog=$(yq -r 'explode(.) | (.backlog.repo // .repo) | select(tag == "!!str")' "$yml" 2>/dev/null </dev/null) || out unreadable
repo_ok "$backlog" || out unreadable

tmp=$(mktemp -d) || out unreadable

# --- the milestone -------------------------------------------------------------------------
gh api --paginate "repos/$backlog/issues?milestone=$ms&state=open" --jq \
  '.[] | select(has("pull_request") | not) | .number' \
  >"$tmp/list" 2>/dev/null </dev/null || out unreadable
gh api "repos/$backlog/milestones/$ms" --jq '.description // ""' \
  >"$tmp/desc" 2>/dev/null </dev/null || out unreadable
while IFS= read -r n || [ -n "$n" ]; do
  num_ok "$n" || out unreadable
done <"$tmp/list"
sort -nu "$tmp/list" >"$tmp/nums" 2>/dev/null || out unreadable

# --- the build order -----------------------------------------------------------------------
order_ok=0
order_list=
if o=$("$pd" order "$tmp/desc" 2>/dev/null </dev/null); then
  case "$o" in
    *'
'*) ;;
    "order "*)
      order_list=${o#order }
      order_ok=1
      for w in $order_list; do num_ok "$w" || order_ok=0; done
      [ "$order_ok" -eq 1 ] || order_list=
      ;;
  esac
fi

# --- one row per open issue ----------------------------------------------------------------
: >"$tmp/rows"
while IFS= read -r n || [ -n "$n" ]; do
  state=unreadable
  paths='?'
  have=0

  if f=$("$sf" find "$n" "$yml" 2>/dev/null </dev/null); then
    case "$f" in
      *'
'*) ;;
      *)
        set -- $f
        case "${1:-}" in
          found)
            if [ "$#" -eq 3 ] && num_ok "$2" && ts_ok "$3"; then
              cid=$2
              cup=$3
              if gh api "repos/$backlog/issues/comments/$cid" >"$tmp/c.json" 2>/dev/null </dev/null \
                && gid=$(yq -p=json -r '.id' "$tmp/c.json" 2>/dev/null </dev/null) \
                && gup=$(yq -p=json -r '.updated_at' "$tmp/c.json" 2>/dev/null </dev/null); then
                if [ "$gid" != "$cid" ] || [ "$gup" != "$cup" ]; then
                  state=moved
                elif fr=$("$sfr" check "$tmp/c.json" "$n" "$yml" 2>/dev/null </dev/null); then
                  case "$fr" in
                    fresh) state=found; have=1 ;;
                    stale\ *) state=stale; have=1 ;;
                  esac
                fi
              fi
            fi
            ;;
          none | unreacted | escalated | ambiguous | moved | unreadable) state=$1 ;;
        esac
        ;;
    esac
  fi

  if [ "$have" -eq 1 ]; then
    if pp=$("$sfr" paths "$tmp/c.json" "$n" "$yml" 2>/dev/null </dev/null); then
      case "$pp" in
        *'
'*) ;;
        paths | paths\ *)
          ok=1
          clean=
          for w in ${pp#paths}; do
            path_ok "$w" || ok=0
            clean="$clean${clean:+ }$w"
          done
          if [ "$ok" -eq 1 ]; then
            if [ -n "$clean" ]; then paths=$clean; else paths=-; fi
          fi
          ;;
      esac
    fi
  fi

  # the wait kind: ind, after <list> or all
  wkind=all
  wlist=
  if [ "$order_ok" -eq 1 ]; then
    if r=$("$pd" read "$tmp/desc" "$n" 2>/dev/null </dev/null); then
      case "$r" in
        *'
'*) ;;
        independent) wkind=ind ;;
        after\ *)
          wkind=after
          wlist=${r#after }
          for w in $wlist; do num_ok "$w" || { wkind=all; wlist=; break; }; done
          ;;
      esac
    fi
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$state" "$paths" "$wkind" "$wlist" >>"$tmp/rows"
done <"$tmp/nums"

# --- shared paths, waits and groups ----------------------------------------------------------
if ! LG_ORDER="$order_list" LG_ORDER_OK="$order_ok" awk -F '\t' '
  function overlap(a, b,    i, j, na, nb, qa, qb, x, y) {
    na = split(a, qa, " "); nb = split(b, qb, " ")
    for (i = 1; i <= na; i++) for (j = 1; j <= nb; j++) {
      x = qa[i]; y = qb[j]
      if (x == y || substr(x, 1, length(y) + 1) == y "/" || substr(y, 1, length(x) + 1) == x "/") return 1
    }
    return 0
  }
  function join(s, sep,    r, k, n, w) {
    n = split(s, w, " "); r = ""
    for (k = 1; k <= n; k++) r = r (k > 1 ? sep : "") "#" w[k]
    return r
  }
  BEGIN {
    no = split(ENVIRON["LG_ORDER"], ord, " ")
    for (i = 1; i <= no; i++) pos[ord[i]] = i
    ok = ENVIRON["LG_ORDER_OK"] + 0
  }
  { n++; num[n] = $1; st[n] = $2; pa[n] = $3; kind[n] = $4; wl[n] = $5; open[$1] = 1 }
  END {
    for (i = 1; i <= n; i++) {
      known = (pa[i] != "?")
      sh = "?"
      if (known) {
        sh = ""
        for (j = 1; j <= n; j++) {
          if (j == i || pa[j] == "?") continue
          if (pa[i] != "-" && pa[j] != "-" && overlap(pa[i], pa[j])) sh = sh (sh == "" ? "" : ",") "#" num[j]
        }
        if (sh == "") sh = "-"
      }
      shared[i] = sh
      if (!ok) w = "order-unreadable"
      else {
        lst = ""
        if (kind[i] == "after") {
          m = split(wl[i], t, " ")
          for (k = 1; k <= m; k++) if (t[k] in open) lst = lst (lst == "" ? "" : " ") t[k]
        } else if (kind[i] == "all") {
          lim = (num[i] in pos) ? pos[num[i]] : no + 1
          for (k = 1; k < lim && k <= no; k++) if (ord[k] in open) lst = lst (lst == "" ? "" : " ") ord[k]
        }
        w = (lst == "") ? "-" : join(lst, ",")
      }
      waits[i] = w
      printf "%s\t%s\t%s\t%s\t%s\n", num[i], st[i], pa[i], sh, w
    }
    # ready issues: build-order position first, then the unlisted ones ascending
    nr = 0
    for (k = 1; k <= no; k++) for (i = 1; i <= n; i++) if (num[i] == ord[k]) cand[++nr] = i
    for (i = 1; i <= n; i++) if (!(num[i] in pos)) cand[++nr] = i
    ng = 0
    for (c = 1; c <= nr; c++) {
      i = cand[c]
      if (st[i] != "found" || pa[i] == "?" || waits[i] != "-") continue
      placed = 0
      for (g = 1; g <= ng && !placed; g++) {
        clash = 0
        for (m = 1; m <= gn[g]; m++) {
          j = gm[g, m]
          if (pa[i] != "-" && pa[j] != "-" && overlap(pa[i], pa[j])) { clash = 1; break }
        }
        if (!clash) { gm[g, ++gn[g]] = i; placed = 1 }
      }
      if (!placed) { ng++; gn[ng] = 1; gm[ng, 1] = i }
    }
    if (ng == 0) print "group none"
    for (g = 1; g <= ng; g++) {
      s = ""
      for (m = 1; m <= gn[g]; m++) s = s (m > 1 ? " " : "") "#" num[gm[g, m]]
      printf "group\t%d\t%s\n", g, s
    }
  }
' "$tmp/rows" >"$tmp/out" 2>/dev/null; then
  out unreadable
fi
cat "$tmp/out"
