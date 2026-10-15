#!/bin/sh
# Reads one issue's confirmed `depends_on` marker back out of a milestone description's
# **Build order:** list -- the record /way-of-working:plan-sprint writes for a NEW milestone
# (its Sequence confirm step) so a reader, and later the orchestrator driver, can get the
# human-confirmed independence of a task without reading any issue body as an instruction.
#
# Usage:
#   plan-depends.sh read <description-file> <issue-number>
#     <description-file> holds the milestone description, fetched by the caller (the same
#     direct-redirection pattern plan-gather.sh's header names); <issue-number> is digits only.
#     Prints exactly one line, always exit 0 (the verdict is on stdout, like plan-anchor.sh):
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
#     A usage error (wrong argument count, a non-digit issue number) exits 1 with a stderr
#     message and no stdout.
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
  echo "plan-depends.sh: usage: plan-depends.sh read <description-file> <issue-number>" >&2
}

if [ "$#" -ne 3 ] || [ "$1" != read ]; then
  usage
  exit 1
fi
file="$2"
n="$3"
case "$n" in
  0* | '' | *[!0-9]*) echo "plan-depends.sh: <issue-number> must be digits only, no leading zero" >&2; exit 1 ;;
esac
if [ "${#n}" -gt 9 ]; then
  echo "plan-depends.sh: <issue-number> is longer than 9 digits" >&2
  exit 1
fi

if [ ! -r "$file" ] || [ -d "$file" ]; then
  echo "all-earlier unreadable"
  exit 0
fi

PD_N="$n" awk '
function unreadable() { print "all-earlier unreadable"; done = 1; exit 0 }
BEGIN { want = ENVIRON["PD_N"] + 0; state = 0; hdr = 0; k = 0; done = 0 }
{ sub(/\r$/, "") }
$0 == "**Build order:**" {
  hdr++
  if (hdr == 1) { state = 1; next }
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
  } else if (k > 0 && $0 ~ /^[ \t]+[^ \t]/) {
    c = $0; sub(/^[ \t]+/, "", c); sub(/[ \t]+$/, "", c)
    txt[k] = txt[k] " " c
  } else {
    if (k == 0) bad = 1
    state = 2
  }
  next
}
END {
  if (done) exit 0
  if (hdr != 1 || bad || k == 0) unreadable()
  t = 0
  for (i = 1; i <= k; i++) {
    if (pos[i] != i) unreadable()
    if (iss[i] in seen) unreadable()
    seen[iss[i]] = i
    if (iss[i] == want) t = i
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
