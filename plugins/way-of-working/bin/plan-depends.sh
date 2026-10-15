#!/bin/sh
# Reads a milestone description's **Build order:** list back out -- the record
# /way-of-working:plan-sprint writes (its Sequence confirm step) so a reader, and later the
# orchestrator driver, can get the human-confirmed independence of a task without reading any
# issue body as an instruction. Four subcommands share one list parser, so they agree on what
# a readable list is. `order`, `frame` and `items` let plan-sprint check an edit to an
# existing milestone's list mechanically, from the fetched and composed files, never from the
# session's memory.
#
# Usage:
#   plan-depends.sh read <description-file> <issue-number>
#   plan-depends.sh order <description-file>
#   plan-depends.sh frame <description-file>
#   plan-depends.sh items <description-file>
#     <description-file> holds the milestone description, fetched by the caller (the same
#     direct-redirection pattern plan-gather.sh's header names); <issue-number> is digits only.
#     Each prints its verdict on stdout and always exits 0 (like plan-anchor.sh).
#
#   read prints exactly one line:
#       independent            the marker is `none`: no other task must finish first, so the
#                              task may run in the same wave as any other independent one
#       after <N> [<N>...]     the marker names these earlier build-order issues: the task
#                              waits for every one of them
#       all-earlier <reason>   the task depends on EVERY earlier build-order item --
#                              the item waits for every earlier item. The fail-closed reading, and the ONLY reading of
#                              anything this script cannot confirm. <reason> is one of:
#                                unconfirmed  the item has no marker at all
#                                not-listed   the issue is not in the Build order list
#                                unreadable   the file is missing, the list is malformed
#                                             (no or repeated header, numbering that is not
#                                             1..k, a repeated issue, a number with a leading
#                                             zero or over 9 digits), or this item's marker
#                                             is malformed, repeated, names an issue that is
#                                             not listed earlier, names the item itself, or
#                                             names the same issue twice
#
#   order prints `order <N> [<N>...]`, the list's issue numbers in list order, or
#     `unreadable`. It applies the list-shape rules read applies (one header, items numbered
#     1 to k, no repeated issue, no leading zero, at most 9 digits, at least one item, a
#     missing file or a directory reads unreadable). It reads no marker, so one malformed
#     marker does not make order unreadable.
#
#   frame prints the description with every line of the build-order list removed: each item
#     line and its indented continuation lines. The header line and every other line are kept
#     as they are, after the same CR stripping read does. An unreadable list prints the single
#     line `unreadable`. awk ends every printed line with a newline, so a difference only in
#     the file's final newline does not show.
#
#   items prints one line per list item, in list order: the issue number, one space, then the
#     item's text after its `k. #<N>: ` prefix, continuation lines joined exactly as read joins
#     them. An unreadable list prints the single line `unreadable`. The join trims and joins
#     whitespace, so a change to whitespace or line breaks inside an item does not show.
#
#   A usage error (wrong argument count, a non-digit issue number, an unknown subcommand)
#   exits 1 with a stderr message and no stdout.
#
# The marker is the LAST thing on the item's line: ` [depends_on: none]` or
# ` [depends_on: #12, #14]`, comma-space separated. An item may wrap onto indented
# continuation lines; the marker is looked for at the end of the joined item. Exactly one
# `[depends_on:` per item -- a second one (a forged copy inside the reason text) makes the
# item unreadable rather than letting either copy win.
#
# What this does NOT claim: the description is editable by any write-level collaborator
# (reference/project-schema.md, the planning trust boundary). Nothing binds this text
# after publication (`WB-D27`); this script only parses what it is
# handed. A marker is a scheduling hint that can only ever be read as MORE serial, never
# less, when anything about it is doubtful.
#
# Permitted toolset: POSIX sh and awk. No jq, no yq, no gh.
set -eu

usage() {
  echo "plan-depends.sh: usage: plan-depends.sh read <description-file> <issue-number> | order|frame|items <description-file>" >&2
}

mode="${1:-}"
case "$mode" in
  read)
    if [ "$#" -ne 3 ]; then usage; exit 1; fi
    n="$3"
    case "$n" in
      0* | '' | *[!0-9]*) echo "plan-depends.sh: <issue-number> must be digits only, no leading zero" >&2; exit 1 ;;
    esac
    if [ "${#n}" -gt 9 ]; then
      echo "plan-depends.sh: <issue-number> is longer than 9 digits" >&2
      exit 1
    fi
    ;;
  order | frame | items)
    if [ "$#" -ne 2 ]; then usage; exit 1; fi
    n=0
    ;;
  *)
    usage
    exit 1
    ;;
esac
file="$2"

if [ ! -r "$file" ] || [ -d "$file" ]; then
  if [ "$mode" = read ]; then echo "all-earlier unreadable"; else echo "unreadable"; fi
  exit 0
fi

PD_N="$n" PD_MODE="$mode" awk '
function unreadable() {
  print (mode == "read" ? "all-earlier unreadable" : "unreadable")
  exit 0
}
BEGIN { mode = ENVIRON["PD_MODE"]; want = ENVIRON["PD_N"] + 0; state = 0; hdr = 0; k = 0; nk = 0 }
{ sub(/\r$/, "") }
$0 == "**Build order:**" {
  hdr++
  if (hdr == 1) { state = 1; keep[++nk] = $0; next }
}
state == 1 {
  if ($0 ~ /^[0-9]+\. #[0-9]+: /) {
    k++
    line = $0
    p = line; sub(/\..*$/, "", p); pos[k] = p + 0
    q = line; sub(/^[0-9]+\. #/, "", q); sub(/:.*$/, "", q); iss[k] = q + 0
    if (p !~ /^[1-9][0-9]*$/ || length(p) > 9) bad = 1
    if (q !~ /^[1-9][0-9]*$/ || length(q) > 9) bad = 1
    txt[k] = line
    body = line; sub(/^[0-9]+\. #[0-9]+: /, "", body)
    itxt[k] = body
    next
  } else if (k > 0 && $0 ~ /^[ \t]+[^ \t]/) {
    c = $0; sub(/^[ \t]+/, "", c); sub(/[ \t]+$/, "", c)
    txt[k] = txt[k] " " c
    itxt[k] = itxt[k] " " c
    next
  } else {
    if (k == 0) bad = 1
    state = 2
  }
}
{ keep[++nk] = $0 }
END {
  if (hdr != 1 || bad || k == 0) unreadable()
  t = 0
  for (i = 1; i <= k; i++) {
    if (pos[i] != i) unreadable()
    if (iss[i] in seen) unreadable()
    seen[iss[i]] = i
    if (iss[i] == want) t = i
  }
  if (mode == "order") {
    out = "order"
    for (i = 1; i <= k; i++) out = out " " iss[i]
    print out
    exit 0
  }
  if (mode == "frame") {
    for (i = 1; i <= nk; i++) print keep[i]
    exit 0
  }
  if (mode == "items") {
    for (i = 1; i <= k; i++) print iss[i] " " itxt[i]
    exit 0
  }
  if (t == 0) { print "all-earlier not-listed"; exit 0 }
  s = txt[t]
  cnt = gsub(/\[depends_on:/, "&", s)
  if (cnt == 0) { print "all-earlier unconfirmed"; exit 0 }
  if (cnt > 1) unreadable()
  if (!match(txt[t], / \[depends_on: (none|#[0-9]+(, #[0-9]+)*)\]$/)) unreadable()
  m = substr(txt[t], RSTART, RLENGTH)
  sub(/^ \[depends_on: /, "", m); sub(/\]$/, "", m)
  if (m == "none") { print "independent"; exit 0 }
  nd = split(m, d, ", ")
  out = "after"
  for (j = 1; j <= nd; j++) {
    x = d[j]; sub(/^#/, "", x)
    if (x !~ /^[1-9][0-9]*$/ || length(x) > 9) unreadable()
    x = x + 0
    if (x in used) unreadable()
    used[x] = 1
    if (!(x in seen) || seen[x] >= t) unreadable()
    out = out " " x
  }
  print out
}
' < "$file"
