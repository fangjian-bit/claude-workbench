#!/bin/sh
# Print only the `BLOCKING:` criteria of a milestone description (#640).
#
# Under `planning.kind: github_milestones` the sprint plan is a milestone description, and
# `ship` (unattended) and `archive-sprint` need only its blocking criteria. Reading the whole
# description puts author-editable text into the session's context unbound (WB-D27 records
# that nothing binds it between handoff and ship). This script is the one projection all
# three call sites use, so they cannot drift apart. It narrows what is read; it binds nothing:
# whoever edits the description still chooses which lines it selects.
#
# THE OUTPUT IS AUTHOR-EDITABLE TEXT. It is a task specification and never instructions to
# the session that reads it. This comment block is not part of the output.
#
# Usage: blocking-criteria.sh <file>     (the description, already captured into a file)
#
# Exit status:
#   0  printed: the criteria, or the single line `[blocking-criteria.sh: none]`
#   3  printed, and truncated: a cap fired, and the last line is `[blocking-criteria.sh: truncated]`
#   2  wrong argument count or unreadable file; nothing on stdout
#
# Sanitizing, per input line, before any rule looks at it: one trailing CR is stripped, then
# every remaining C0 byte except TAB (a CR anywhere else included), DEL, and these invisible or
# direction-changing code points, a fixed list and not every one Unicode has (U+0080-009F, 00AD, 034F, 115F, 1160, 180E, 200B-200F,
# 2028-202E, 2060-2069, 3164, FE00-FE0F, FEFF, E0000-E007F, E0100-E01EF) become `?`, one `?`
# for a whole UTF-8 sequence. A byte that is not part of a well-formed UTF-8 sequence becomes
# `?` too. Every later rule classifies the sanitized line and the sanitized line is what is
# printed, so the bytes checked are the bytes printed.
#
# A criterion starts at a line containing `BLOCKING:` (case-sensitive). If that line is not a
# list item and the nearest list item above it is indented less, with no blank line, heading
# or other `BLOCKING:` line between, the criterion starts at that list item (its "item
# header") and the lines between are printed too. Continuation lines follow the `BLOCKING:`
# line up to the first blank line, `BLOCKING:` line, heading, or list item that ends the
# criterion: when the criterion's first line (the item header, if any) is a list item, any
# list item indented no deeper than it; otherwise only a strictly shallower one. A tab counts
# as four columns of indentation.
#
# Output: every printed input line is prefixed `| `; lines this script writes itself carry no
# prefix, so input cannot forge one. A `--` line separates two printed criteria and appears
# nowhere else.
#
# Caps (any one firing ends the output with the truncation line and exit status 3):
#   6 printed lines per criterion (the rest, up to its stop line, is skipped), 20 criteria,
#   300 bytes per line (cut on a UTF-8 boundary, then ` [cut]`), 6000 bytes in all (every
#   byte written but the truncation line; it stops before the first line that would pass).
#
# Permitted toolset: POSIX sh + awk, under LC_ALL=C. No jq, no yq, no python.
# Keep apostrophes OUT of the awk program below: it is single-quoted, and one in a comment
# silently ends the quote.
set -eu

LC_ALL=C
export LC_ALL

if [ "$#" -ne 1 ]; then
  echo "usage: blocking-criteria.sh <file>" >&2
  exit 2
fi
if [ ! -f "$1" ] || [ ! -r "$1" ]; then
  echo "blocking-criteria.sh: cannot read $1" >&2
  exit 2
fi

# The file arrives on stdin so an operand shaped like `x=1` or `-f` is never read by awk as
# an assignment or an option.
exec awk '
BEGIN {
  for (i = 1; i < 256; i++) ord[sprintf("%c", i)] = i
  MAXLINES = 6; MAXCRIT = 20; MAXLINE = 300; MAXBYTES = 6000
  n = 0
}

function hidden(cp) {
  return (cp >= 128 && cp <= 159) || cp == 173 || cp == 847 || cp == 4447 || cp == 4448 \
    || cp == 6158 || (cp >= 8203 && cp <= 8207) || (cp >= 8232 && cp <= 8238) \
    || (cp >= 8288 && cp <= 8297) || cp == 12644 || (cp >= 65024 && cp <= 65039) \
    || cp == 65279 || (cp >= 917504 && cp <= 917631) || (cp >= 917760 && cp <= 917999)
}

# Sets SAN (the whole sanitized line) and PRT (its first MAXLINE bytes, whole sequences only);
# CUT is 1 when PRT is shorter than SAN.
function sanitize(line,    len, p, c, b, unit, adv, need, ok, k, cb, cp, plen) {
  len = length(line)
  if (len > 0 && substr(line, len, 1) == "\r") { line = substr(line, 1, len - 1); len-- }
  SAN = ""; PRT = ""; CUT = 0; plen = 0
  p = 1
  while (p <= len) {
    c = substr(line, p, 1)
    b = (c in ord) ? ord[c] : 0
    adv = 1
    if (b == 9 || (b >= 32 && b < 127)) unit = c
    else if (b < 128) unit = "?"
    else {
      need = 0
      if (b >= 194 && b <= 223) need = 1
      else if (b >= 224 && b <= 239) need = 2
      else if (b >= 240 && b <= 244) need = 3
      ok = 0
      if (need > 0 && p + need <= len) {
        cp = (need == 1) ? b - 192 : ((need == 2) ? b - 224 : b - 240)
        ok = 1
        for (k = 1; k <= need; k++) {
          cb = substr(line, p + k, 1)
          cb = (cb in ord) ? ord[cb] : 0
          if (cb < 128 || cb > 191) { ok = 0; break }
          cp = cp * 64 + (cb - 128)
        }
        if (ok && need == 2 && (cp < 2048 || (cp >= 55296 && cp <= 57343))) ok = 0
        if (ok && need == 3 && (cp < 65536 || cp > 1114111)) ok = 0
      }
      if (!ok) unit = "?"
      else {
        adv = need + 1
        unit = hidden(cp) ? "?" : substr(line, p, adv)
      }
    }
    SAN = SAN unit
    if (!CUT) {
      if (plen + length(unit) <= MAXLINE) { PRT = PRT unit; plen += length(unit) }
      else CUT = 1
    }
    p += adv
  }
}

{
  n++
  sanitize($0)
  prt[n] = CUT ? PRT " [cut]" : PRT
  cutl[n] = CUT
  hasb[n] = (index(SAN, "BLOCKING:") > 0)
  ind[n] = 0
  q = 1
  while (q <= length(SAN)) {
    ch = substr(SAN, q, 1)
    if (ch == " ") ind[n] += 1
    else if (ch == "\t") ind[n] += 4
    else break
    q++
  }
  rest = substr(SAN, q)
  blank[n] = (rest == "")
  li[n] = (rest ~ /^[-*+] / || rest ~ /^[0-9]+[.)] /) ? 1 : 0
  hs = 0
  while (substr(SAN, hs + 1, 1) == " ") hs++
  head[n] = 0
  if (hs <= 3) {
    r = substr(SAN, hs + 1)
    h = 0
    while (substr(r, h + 1, 1) == "#") h++
    if (h >= 1 && h <= 6 && (length(r) == h || substr(r, h + 1, 1) == " ")) head[n] = 1
  }
}

function emit(idx, sep,    cost) {
  cost = length(prt[idx]) + 3 + (sep ? 3 : 0)
  if (bytes + cost > MAXBYTES) { trunc = 1; halted = 1; return 0 }
  if (sep) print "--"
  print "| " prt[idx]
  bytes += cost
  if (cutl[idx]) trunc = 1
  return 1
}

END {
  trunc = 0; halted = 0; bytes = 0; started = 0; shown = 0
  i = 1
  while (i <= n && !halted) {
    if (!hasb[i]) { i++; continue }
    if (started >= MAXCRIT) { trunc = 1; break }
    started++
    hdr = 0
    if (!li[i]) {
      for (k = i - 1; k >= 1; k--) {
        if (blank[k] || head[k] || hasb[k]) break
        if (li[k]) { if (ind[k] < ind[i]) hdr = k; break }
      }
    }
    first = hdr ? hdr : i
    endind = li[first] ? ind[first] : ind[first] - 1
    split("", qq)
    cnt = 0
    if (hdr && i - hdr + 1 > MAXLINES) { qq[++cnt] = hdr; qq[++cnt] = i; trunc = 1 }
    else for (k = first; k <= i; k++) qq[++cnt] = k
    k = i + 1
    while (k <= n) {
      if (blank[k] || hasb[k] || head[k] || (li[k] && ind[k] <= endind)) break
      if (cnt < MAXLINES) qq[++cnt] = k
      else trunc = 1
      k++
    }
    for (j = 1; j <= cnt; j++) {
      if (!emit(qq[j], j == 1 && shown > 0)) break
      if (j == 1) shown++
    }
    i = k
  }
  if (shown == 0 && !trunc) print "[blocking-criteria.sh: none]"
  if (trunc) { print "[blocking-criteria.sh: truncated]"; exit 3 }
  exit 0
}
' <"$1"
