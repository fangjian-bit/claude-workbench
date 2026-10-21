#!/bin/sh
# Does a drafted spec comment have the fixed shape? (#611, WB-D26, WB-D29)
#
# /way-of-working:spec-task drafts a task's spec comment, then posts or holds it once this says `ok`: a maintainer
# reacts, and the readers find it under a map (WB-D30; in a legacy repo /way-of-working:handoff anchors it). The drafter is a model writing prose, so the
# shape is checked here, not trusted, and the skill posts only on `ok`.
#
# Usage: spec-shape.sh check <file>
# Prints exactly one of, and exits 0 (the caller decides policy):
#   ok                          -- every required section heading is present, in order, every
#                                  section has at least one non-blank line (`nothing` counts: it
#                                  is text), and no line begins with either marker prefix
#   has-marker                  -- a line begins with `spec-task:` or `spec-task-escalated:` (after
#                                  a trailing carriage return is stripped), the rule spec-post.sh
#                                  applies at the post, after the critic gate (it now stops such a
#                                  draft `bad-shape`, since it runs this script first); it takes
#                                  precedence over `missing`
#   missing <section>[,<section>...]
#                               -- the headings (comma-joined, in the required order) that are
#                                  absent, first appear before an earlier required heading, or
#                                  have an empty body
#   unreadable                  -- the file does not exist, is not a regular file, is empty, or
#                                  cannot be read
#
# Required headings, in order, each a level-3 line (`### Goal`) -- the first line of a draft is
# free-form (a title line) except that it, like every line, never begins with a marker prefix
# (spec-post.sh writes the marker line itself), and the prose between a heading and the next heading of any level
# (`#` through `######`) is that section's body:
#   Goal | Files touched | Done when | Tests | Out of scope | Restated from the issue body
#
# A heading counts only as a whole line, `### ` followed by exactly the name and optional
# trailing blanks; `### Goal and more` is not `Goal`. A heading that first appears before an
# earlier required one is reported missing: order is part of the shape, because the maintainer
# reads the draft top-down and a reaction approves the whole comment.
# A section is non-empty when its first occurrence has at least one non-blank line before the
# next heading or the end of the file. Fenced code blocks are not understood: a `#` line inside
# one reads as a heading.
#
# Exit 2 on a usage error only. The file is data: it is only read, never evaluated or passed
# to another command.
#
# Permitted toolset: POSIX sh + awk.
set -eu

if [ "$#" -ne 2 ] || [ "$1" != check ]; then
  echo "usage: spec-shape.sh check <file>" >&2
  exit 2
fi

f="$2"
if [ ! -f "$f" ] || [ ! -r "$f" ] || [ ! -s "$f" ]; then
  echo unreadable
  exit 0
fi

awk '
  BEGIN {
    n = split("Goal|Files touched|Done when|Tests|Out of scope|Restated from the issue body", want, "|")
    for (i = 1; i <= n; i++) idx[want[i]] = i
    last_body = 0
    marker = 0
  }
  {
    line = $0
    sub(/\r$/, "", line)
    if (line ~ /^spec-task:/ || line ~ /^spec-task-escalated:/) marker = 1
    if (line ~ /^#+ /) {
      cur = 0
      if (line ~ /^### /) {
        name = substr(line, 5)
        sub(/[ \t]+$/, "", name)
        cur = (name in idx) ? idx[name] : 0
        if (cur && !pos[cur]) { pos[cur] = NR; first[cur] = 1 } else if (cur) first[cur] = 0
      }
      next
    }
    if (cur && first[cur] && line ~ /[^ \t]/) body[cur]++
  }
  END {
    if (marker) { print "has-marker"; exit }
    out = ""
    maxpos = 0
    for (i = 1; i <= n; i++) {
      if (!pos[i] || pos[i] < maxpos || !body[i]) { out = out (out == "" ? "" : ",") want[i]; continue }
      maxpos = pos[i]
    }
    if (out == "") print "ok"; else print "missing " out
  }
' <"$f"
