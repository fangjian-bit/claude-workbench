#!/bin/sh
# Is a `hitl_gate` value closed? One predicate for every reader (#557).
#
# /way-of-working:resume (before auto-starting), :unpark-sprint (deciding whether a gate is
# worth carrying) and :plan-sprint (replace vs. append) each tested "closed" in their own
# words -- a bare `NONE OPEN` prefix in two, "begins NONE OPEN and nothing open after it" in
# the third, the last half a model judgment. Real values differ (`NONE OPEN — next gate: …`,
# `NONE OPEN — milestone 13's anchor re-verified … Next gate: …`), so two readers could
# reach different answers on one cursor. Both failed toward waiting, so it was inconsistent,
# not unsafe. This is the single definition; the skills call it.
#
# Usage: hitl-gate-closed.sh <hitl_gate value>
# Prints exactly one of, and exits 0 (the caller decides policy):
#   closed -- the value is exactly `NONE OPEN — next gate: <prose>` (em dash), <prose> has at
#             least one non-space character, is printable ASCII only and never contains the
#             letters "open" in any case, and the value is one line with no `;` anywhere.
#             `/way-of-working:handoff` writes this form and no other.
#   open   -- everything else: `OPEN …`, `parked …`, a bare `NONE OPEN`, a different
#             closed-looking shape, any `;` clause (a carried gate such as
#             `; parked with gate open: …` is an open gate that still begins NONE OPEN),
#             a newline or control character, non-ASCII or the word "open" in the prose, and an empty or missing value. "Couldn't tell"
#             is open.
# A ledger line (`**HITL Gate: NONE OPEN** — next gate: …`) is tested on the text after
# `HITL Gate:`. `*` characters are dropped and surrounding blanks trimmed here, so the bold
# markers do not matter; the caller flattens a wrapped line to one first.
#
# Exit 2 on a usage error only (no argument, or more than one). The value is data: it is
# only compared, never evaluated or passed to another command.
#
# Permitted toolset: POSIX sh + grep. No jq, no yq, no python.
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: hitl-gate-closed.sh <hitl_gate value>" >&2
  exit 2
fi

v="$1"

# One line, no control characters (tab, CR, ESC, ...): grep counts the lines of the value
# and flags any control byte.
if [ "$(printf '%s\n' "$v" | grep -c '')" -ne 1 ] ||
   printf '%s' "$v" | LC_ALL=C grep -q '[[:cntrl:]]'; then
  echo open
  exit 0
fi

v=$(printf '%s' "$v" | tr -d '*')
v=${v#"${v%%[![:space:]]*}"}
v=${v%"${v##*[![:space:]]}"}

case "$v" in
  *\;*) echo open; exit 0 ;;
esac

prose=${v#'NONE OPEN — next gate:'}
if [ "$prose" = "$v" ]; then
  echo open
  exit 0
fi

# The prose is plain printable ASCII and never says "open": a note appended after the dash
# (`x -- OPEN: approve the re-anchor`) is an open gate that merely avoids a `;`, and a
# lookalike (U+037E, U+FF1B, U+2028, a zero-width space) would otherwise slip past the checks
# above. Only `;` was ever a safe signal, so the prose is held to a shape that carries none.
if printf '%s' "$prose" | LC_ALL=C grep -q '[^ -~]' ||
   printf '%s' "$prose" | grep -qi open; then
  echo open
  exit 0
fi

# The prefix is followed by a blank and then at least one non-space character.
case "$prose" in
  ' '*[![:space:]]*) echo closed ;;
  *) echo open ;;
esac
