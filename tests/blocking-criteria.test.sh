#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/blocking-criteria.sh (#640).
#
# The script projects a milestone description down to its BLOCKING: criteria. Each fixture
# asserts the exact output and the exit status. Every fixture is wrapped in a sentinel line
# before and after (each set off by a blank line), and the sentinel must never appear in the
# output: a description line outside a criterion must not reach the session.
#
# Permitted toolset: POSIX sh + awk (what the script itself uses).
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/plugins/way-of-working/bin/blocking-criteria.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
SENT="SENTINEL-OUTSIDE-LINE"
NL='
'

# <desc> <expected-rc> <expected-stdout> <input>   (input and expected are printf %b strings;
# the expected text omits the final newline, which the check adds back)
check() {
  desc="$1"; erc="$2"; eout="$3"; input="$4"
  { printf '%s\n\n' "$SENT"; printf '%b' "$input"; printf '\n\n%s\n' "$SENT"; } >"$tmp/in"
  rc=0
  "$script" "$tmp/in" >"$tmp/out" 2>"$tmp/err" || rc=$?
  printf '%b\n' "$eout" >"$tmp/want"
  if [ "$rc" -ne "$erc" ]; then
    echo "FAIL - $desc: expected exit $erc, got $rc" >&2; fail=1; return
  fi
  if grep -qF "$SENT" "$tmp/out"; then
    echo "FAIL - $desc: the sentinel reached the output" >&2; fail=1; return
  fi
  if cmp -s "$tmp/out" "$tmp/want"; then
    echo "ok - $desc"
  else
    echo "FAIL - $desc: output differs" >&2
    echo "--- expected" >&2; cat "$tmp/want" >&2
    echo "--- got" >&2; cat "$tmp/out" >&2
    fail=1
  fi
}

# Same, but the input file is written as-is (no sentinel wrapper, no added newline).
check_raw() {
  desc="$1"; erc="$2"; eout="$3"; input="$4"
  printf '%b' "$input" >"$tmp/in"
  rc=0
  "$script" "$tmp/in" >"$tmp/out" 2>"$tmp/err" || rc=$?
  printf '%b\n' "$eout" >"$tmp/want"
  if [ "$rc" -eq "$erc" ] && cmp -s "$tmp/out" "$tmp/want"; then
    echo "ok - $desc"
  else
    echo "FAIL - $desc: exit $rc (want $erc), output:" >&2; cat "$tmp/out" >&2; fail=1
  fi
}

NONE='[blocking-criteria.sh: none]'
TRUNC='[blocking-criteria.sh: truncated]'

# --- shapes kept whole ---------------------------------------------------------------
check "conventions shape: the item and its gates line" 0 \
  '| - BLOCKING: backup verified\n|   \0342\0200\0224 gates: first apply' \
  '- BLOCKING: backup verified\n  \0342\0200\0224 gates: first apply'

check "plan-sprint one-line BLOCKING" 0 \
  '| **BLOCKING:** snapshot off-host before the transfer' \
  '**BLOCKING:** snapshot off-host before the transfer'

check "paragraph with an unindented wrapped line, stopping at the blank" 0 \
  '| **BLOCKING:** the snapshot is copied\n| off-host and restored once.' \
  '**BLOCKING:** the snapshot is copied\noff-host and restored once.\n\nunrelated text'

check "build-order item with an inline BLOCKING, stopping at the next item" 0 \
  '| 2. #7: move the data **BLOCKING:** backup first\n|    \0342\0200\0224 gates: the move' \
  '1. #6: earlier\n2. #7: move the data **BLOCKING:** backup first\n   \0342\0200\0224 gates: the move\n3. #8: later'

check "item header: BLOCKING on the indented next line" 0 \
  '| 3. #9: third.\n|    **BLOCKING:** not yet.' \
  '1. #7: first.\n2. #8: second.\n3. #9: third.\n   **BLOCKING:** not yet.\n4. #10: fourth.'

check "two criteria; the second starts at its own line and carries no gates line" 0 \
  '| - BLOCKING: backup verified\n|   \0342\0200\0224 gates: migration\n--\n|   **BLOCKING:** snapshot off-host' \
  '- BLOCKING: backup verified\n  \0342\0200\0224 gates: migration\n  **BLOCKING:** snapshot off-host'

check "an item whose reason wraps over six lines keeps the item and the BLOCKING line" 3 \
  "| 3. #9: third.\n|    **BLOCKING:** not yet.\n$TRUNC" \
  '3. #9: third.\n   one\n   two\n   three\n   four\n   five\n   **BLOCKING:** not yet.'

check "BLOCKING alone on a line keeps a column-0 list that follows it" 0 \
  '| **BLOCKING:**\n| - backup verified\n| - snapshot off-host' \
  '**BLOCKING:**\n- backup verified\n- snapshot off-host'

# --- stops ---------------------------------------------------------------------------
check "a second BLOCKING line starts a new criterion after a -- line" 0 \
  '| BLOCKING: one\n--\n| BLOCKING: two' \
  'BLOCKING: one\nBLOCKING: two'

check "a heading stops the criterion; a wrapped line starting #14 does not" 0 \
  '| BLOCKING: one\n| #14 is the issue' \
  'BLOCKING: one\n#14 is the issue\n## Next section\nmore'

check "list-item criterion: a same-indent item stops it, a deeper one is included" 0 \
  '| - BLOCKING: one\n|   - detail\n|     - deeper' \
  '- BLOCKING: one\n  - detail\n    - deeper\n- another item'

check "a loose-list gates line after a blank line is dropped" 0 \
  '| - BLOCKING: backup verified' \
  '- BLOCKING: backup verified\n\n  \0342\0200\0224 gates: migration'

# --- sanitizing ----------------------------------------------------------------------
check "CRLF input prints no CR" 0 \
  '| BLOCKING: one\n| two' \
  'BLOCKING: one\r\ntwo\r\n'
if grep -q "$(printf '\r')" "$tmp/out"; then echo "FAIL - CR in the output" >&2; fail=1; fi

check "a bare CR and U+2028 print as ? inside one line" 0 \
  '| BLOCKING: a?b?c' \
  'BLOCKING: a\rb\0342\0200\0250c'

check "tag-character payload bytes never appear" 0 \
  '| BLOCKING: x?????y' \
  'BLOCKING: x\0363\0240\0201\0211\0363\0240\0201\0212\0363\0240\0201\0213\0363\0240\0201\0214\0363\0240\0201\0215y'
if LC_ALL=C grep -qF "$(printf '\363')" "$tmp/out"; then echo "FAIL - tag bytes in the output" >&2; fail=1; fi

check "the em dash survives" 0 \
  '| BLOCKING: one\n|   \0342\0200\0224 gates: the step' \
  'BLOCKING: one\n  \0342\0200\0224 gates: the step'

check "ESC, DEL, zero-width, BOM and a bad byte become ?" 0 \
  '| BLOCKING: a?b?c?d?e?f' \
  'BLOCKING: a\0033b\0177c\0342\0200\0213d\0357\0273\0277e\0377f'

check "a C1 control and a soft hyphen become one ? each" 0 \
  '| BLOCKING: a?b?c' \
  'BLOCKING: a\0302\0205b\0302\0255c'

# --- caps ----------------------------------------------------------------------------
check "seven lines of one criterion print six, then the truncation line" 3 \
  "| BLOCKING: 1\n| 2\n| 3\n| 4\n| 5\n| 6\n$TRUNC" \
  'BLOCKING: 1\n2\n3\n4\n5\n6\n7'

check "exactly six lines is not truncated" 0 \
  '| BLOCKING: 1\n| 2\n| 3\n| 4\n| 5\n| 6' \
  'BLOCKING: 1\n2\n3\n4\n5\n6'

check "after the line cap a later BLOCKING still starts the next criterion" 3 \
  "| BLOCKING: 1\n| 2\n| 3\n| 4\n| 5\n| 6\n--\n| BLOCKING: next\n$TRUNC" \
  'BLOCKING: 1\n2\n3\n4\n5\n6\n7\n8\nBLOCKING: next'

twenty=""; i=1
while [ "$i" -le 20 ]; do twenty="${twenty}BLOCKING: c$i\n"; i=$((i + 1)); done
want20="| BLOCKING: c1"; i=2
while [ "$i" -le 20 ]; do want20="${want20}\n--\n| BLOCKING: c$i"; i=$((i + 1)); done
check "20 criteria print whole" 0 "$want20" "$twenty"
check "21 criteria print 20, then the truncation line" 3 "$want20\n$TRUNC" "${twenty}BLOCKING: c21\n"

long="$(awk 'BEGIN { s = "BLOCKING: "; while (length(s) < 10240) s = s "x"; printf "%s", s }')"
cut300="$(printf '%s' "$long" | cut -c1-300)"
check "a 10 KB BLOCKING line prints 300 bytes ending [cut], then truncates" 3 \
  "| $cut300 [cut]\n$TRUNC" "$long"

# 300 bytes ending mid-sequence: the sequence is dropped whole, not split.
cutmb="BLOCKING: $(awk 'BEGIN { for (i = 0; i < 100; i++) printf "a"; for (i = 0; i < 100; i++) printf "\303\251" }')"
# 10 + 100 + 2*95 = 300 exactly fits 95 two-byte characters; the 96th does not.
want95="BLOCKING: $(awk 'BEGIN { for (i = 0; i < 100; i++) printf "a"; for (i = 0; i < 95; i++) printf "\303\251" }')"
check "a cut never splits a UTF-8 sequence" 3 "| $want95 [cut]\n$TRUNC" "$cutmb"

# Six-thousand-byte total: 50-byte lines, 6 per criterion, make a long run of criteria.
many=""; i=1
while [ "$i" -le 20 ]; do
  many="${many}BLOCKING: c$i $(awk 'BEGIN { for (j = 0; j < 280; j++) printf "y" }')\nm\nm\nm\nm\nm\n\n"
  i=$((i + 1))
done
{ printf '%b' "$many"; } >"$tmp/in"
rc=0; "$script" "$tmp/in" >"$tmp/out" || rc=$?
bytes_out="$(sed '$d' "$tmp/out" | wc -c | tr -d ' ')"
last="$(tail -n 1 "$tmp/out")"
if [ "$rc" -eq 3 ] && [ "$last" = "$TRUNC" ] && [ "$bytes_out" -le 6000 ] && [ "$bytes_out" -gt 5600 ]; then
  echo "ok - output past 6000 bytes is truncated on a whole line ($bytes_out bytes)"
else
  echo "FAIL - 6000-byte cap: rc=$rc bytes=$bytes_out last=[$last]" >&2; fail=1
fi
if sed '$d' "$tmp/out" | grep -qv '^\(| \|--$\)'; then
  echo "FAIL - 6000-byte cap: an unprefixed line before the truncation line" >&2; fail=1
fi
if [ "$(sed '$d' "$tmp/out" | tail -n 1)" = "--" ]; then
  echo "FAIL - a -- line sits right before the truncation line" >&2; fail=1
fi

# --- none and errors -----------------------------------------------------------------
check "no criteria prints none" 0 "$NONE" 'just a goal\n\n## Build order\n1. #1: a\n'
check_raw "an empty file prints none" 0 "$NONE" ''
check_raw "a file with no final newline still works" 0 '| BLOCKING: x' 'BLOCKING: x'

rc=0; out="$("$script" "$tmp/does-not-exist" 2>/dev/null)" || rc=$?
if [ "$rc" -eq 2 ] && [ -z "$out" ]; then echo "ok - a missing file exits 2 with empty stdout"
else echo "FAIL - missing file: rc=$rc out=[$out]" >&2; fail=1; fi
rc=0; out="$("$script" 2>/dev/null)" || rc=$?
if [ "$rc" -eq 2 ] && [ -z "$out" ]; then echo "ok - no argument exits 2 with empty stdout"
else echo "FAIL - no argument: rc=$rc out=[$out]" >&2; fail=1; fi
rc=0; out="$("$script" "$tmp/in" extra 2>/dev/null)" || rc=$?
if [ "$rc" -eq 2 ] && [ -z "$out" ]; then echo "ok - two arguments exit 2 with empty stdout"
else echo "FAIL - two arguments: rc=$rc out=[$out]" >&2; fail=1; fi
rc=0; out="$("$script" "$tmp" 2>/dev/null)" || rc=$?
if [ "$rc" -eq 2 ] && [ -z "$out" ]; then echo "ok - a directory exits 2 with empty stdout"
else echo "FAIL - directory: rc=$rc out=[$out]" >&2; fail=1; fi

# --- forging -------------------------------------------------------------------------
check "an input line equal to the truncation line prints prefixed and sets no exit 3" 0 \
  "| BLOCKING: one\n| $TRUNC" \
  "BLOCKING: one\n$TRUNC"

check "an input line equal to the none line prints prefixed" 0 \
  "| BLOCKING: one\n| $NONE" \
  "BLOCKING: one\n$NONE"

check "an input -- line prints prefixed" 0 \
  '| BLOCKING: one\n| --' \
  'BLOCKING: one\n--'

# --- the worked example in conventions.md --------------------------------------------
conv="$root_dir/plugins/way-of-working/reference/conventions.md"
extract() { # <marker-kind> : the lines inside the fence that follows the marker
  awk -v m="<!-- blocking-criteria example: $1 -->" '
    $0 == m { want = 1; next }
    want && /^```/ { if (infence) exit; infence = 1; next }
    want && infence { print }
  ' "$conv"
}
extract input >"$tmp/ex-in"
extract output >"$tmp/ex-want"
if [ ! -s "$tmp/ex-in" ] || [ ! -s "$tmp/ex-want" ]; then
  echo "FAIL - the worked example is missing from conventions.md" >&2; fail=1
else
  grep -qxF '<!-- blocking-criteria example: end -->' "$conv" || { echo "FAIL - the example end marker is missing" >&2; fail=1; }
  rc=0; "$script" "$tmp/ex-in" >"$tmp/ex-out" || rc=$?
  if [ "$rc" -eq 0 ] && cmp -s "$tmp/ex-out" "$tmp/ex-want"; then
    echo "ok - the worked example in conventions.md is exactly what the script prints"
  else
    echo "FAIL - the worked example drifted from the script (exit $rc)" >&2
    diff "$tmp/ex-want" "$tmp/ex-out" >&2 || true
    fail=1
  fi
  if ! grep -q 'BLOCKING:\*\*' "$tmp/ex-in" || ! grep -q 'gates:' "$tmp/ex-in"; then
    echo "FAIL - the example input lacks one of the two documented shapes" >&2; fail=1
  fi
fi

[ "$fail" -eq 0 ]
