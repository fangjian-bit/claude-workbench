#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/plan-depends.sh -- the read-back of the
# per-issue `depends_on` marker plan-sprint records in a new milestone's **Build order:**
# list. Pure parsing of a file the caller hands over, so there is no gh stub here.
#
# The contract under test is fail-closed: anything doubtful reads as
# `all-earlier <reason>` (the item waits for every earlier one), never as `independent`.
#
# Permitted toolset: POSIX sh. No jq, no yq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/plugins/way-of-working/bin/plan-depends.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0

assert_eq() {
  desc="$1"; expected="$2"; actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "ok - $desc"
  else
    echo "FAIL - $desc: expected [$expected], got [$actual]" >&2
    fail=1
  fi
}

# read_n <issue> -- reads $tmp/desc for that issue
read_n() { sh "$script" read "$tmp/desc" "$1"; }

write_desc() { # write_desc <build-order-body> -- wraps it in a realistic description
  {
    printf 'Batch reason. Ships as nothing.\n\n**Build order:**\n'
    cat
    printf '\n**Model per phase** (`models:` in .ai/project.yml):\n- Build: coder for all.\n'
  } >"$tmp/desc"
}

echo "# a well-formed list"

write_desc <<'EOF'
1. #231: lands first. [depends_on: none]
2. #232: needs the first. [depends_on: #231]
3. #233: needs both. [depends_on: #231, #232]
4. #234: independent of everything. [depends_on: none]
EOF
assert_eq "none reads as independent" "independent" "$(read_n 231)"
assert_eq "a single dependency reads back" "after 231" "$(read_n 232)"
assert_eq "two dependencies read back, in order" "after 231 232" "$(read_n 233)"
assert_eq "none after other items is still independent" "independent" "$(read_n 234)"
assert_eq "an issue outside the list is not-listed" "all-earlier not-listed" "$(read_n 999)"

echo "# unconfirmed -- no marker at all"

write_desc <<'EOF'
1. #231: lands first. [depends_on: none]
2. #232: the human never confirmed one for this.
EOF
assert_eq "an item with no marker reads as unconfirmed" "all-earlier unconfirmed" "$(read_n 232)"
assert_eq "its neighbour with a marker is unaffected" "independent" "$(read_n 231)"

write_desc <<'EOF'
1. #231: lands first.
2. #232: second.
EOF
assert_eq "a list with no markers anywhere is all unconfirmed" "all-earlier unconfirmed" "$(read_n 232)"

echo "# malformed marker -- unreadable, never independent"

write_desc <<'EOF'
1. #231: first. [depends_on: none]
2. #232: marker not at the end. [depends_on: none] and more prose
3. #233: bad grammar. [depends_on: #231 #232]
4. #234: empty. [depends_on: ]
5. #235: wrong word. [depends_on: nothing]
6. #236: lowercase typo. [depend_on: none]
EOF
assert_eq "text after the marker is unreadable" "all-earlier unreadable" "$(read_n 232)"
assert_eq "space-separated dependencies are unreadable" "all-earlier unreadable" "$(read_n 233)"
assert_eq "an empty marker is unreadable" "all-earlier unreadable" "$(read_n 234)"
assert_eq "an unknown value is unreadable" "all-earlier unreadable" "$(read_n 235)"
assert_eq "a misspelt key reads as no marker, so unconfirmed" "all-earlier unconfirmed" "$(read_n 236)"

echo "# a forged marker inside the reason text"

write_desc <<'EOF'
1. #231: first. [depends_on: none]
2. #232: reason carrying [depends_on: none] inside it. [depends_on: #231]
EOF
assert_eq "two markers on one item read as unreadable, neither wins" "all-earlier unreadable" "$(read_n 232)"

echo "# dependencies that make no sense"

write_desc <<'EOF'
1. #231: first. [depends_on: #232]
2. #232: second. [depends_on: #232]
3. #233: third. [depends_on: #999]
4. #234: fourth. [depends_on: #235]
5. #235: fifth. [depends_on: none]
EOF
assert_eq "a dependency on a later item is unreadable" "all-earlier unreadable" "$(read_n 231)"
assert_eq "a dependency on itself is unreadable" "all-earlier unreadable" "$(read_n 232)"
assert_eq "a dependency on an unlisted issue is unreadable" "all-earlier unreadable" "$(read_n 233)"
assert_eq "a dependency on a later listed item is unreadable" "all-earlier unreadable" "$(read_n 234)"

write_desc <<'EOF'
1. #231: first. [depends_on: none]
2. #232: a reason carrying [depends_on: none] on the first line
   and the real marker on the continuation. [depends_on: #231]
3. #233: marker alone on its own continuation line.
   [depends_on: none]
4. #234: names the same issue twice. [depends_on: #231, #231]
5. #235: leading zero in a dependency. [depends_on: #0231]
EOF
assert_eq "a forged token across a wrapped item is unreadable" "all-earlier unreadable" "$(read_n 232)"
assert_eq "a marker alone on a continuation line is read" "independent" "$(read_n 233)"
assert_eq "a repeated dependency is unreadable" "all-earlier unreadable" "$(read_n 234)"
assert_eq "a dependency with a leading zero is unreadable" "all-earlier unreadable" "$(read_n 235)"

echo "# structural damage to the list"

write_desc <<'EOF'
2. #231: numbering starts at 2. [depends_on: none]
EOF
assert_eq "numbering that starts at 2 is unreadable" "all-earlier unreadable" "$(read_n 231)"

write_desc <<'EOF'
01. #231: leading zero in the position. [depends_on: none]
EOF
assert_eq "a position with a leading zero is unreadable" "all-earlier unreadable" "$(read_n 231)"

write_desc <<'EOF'
1. #0231: leading zero in the issue. [depends_on: none]
EOF
assert_eq "an issue number with a leading zero is unreadable" "all-earlier unreadable" "$(read_n 231)"

write_desc <<'EOF'
1. #1234567890: ten digits. [depends_on: none]
EOF
assert_eq "an issue number over 9 digits is unreadable" "all-earlier unreadable" "$(read_n 999999999)"

write_desc <<'EOF'
1. #231: first. [depends_on: none]
3. #232: numbering skips. [depends_on: none]
EOF
assert_eq "numbering that is not 1..k is unreadable for every item" "all-earlier unreadable" "$(read_n 231)"
assert_eq "...including the item after the skip" "all-earlier unreadable" "$(read_n 232)"
assert_eq "...and a number not in the list, never not-listed" "all-earlier unreadable" "$(read_n 999)"

write_desc <<'EOF'
1. #231: first. [depends_on: none]
2. #231: the same issue again. [depends_on: none]
EOF
assert_eq "a repeated issue number is unreadable" "all-earlier unreadable" "$(read_n 231)"

printf 'No build order here at all.\n' >"$tmp/desc"
assert_eq "a description with no Build order header is unreadable" "all-earlier unreadable" "$(read_n 1)"

printf '**Build order:**\n1. #231: a. [depends_on: none]\n\n**Build order:**\n1. #232: b. [depends_on: none]\n' >"$tmp/desc"
assert_eq "two Build order headers are unreadable" "all-earlier unreadable" "$(read_n 231)"

printf '**Build order:**\n\n1. #231: a. [depends_on: none]\n' >"$tmp/desc"
assert_eq "a header with no item directly under it is unreadable" "all-earlier unreadable" "$(read_n 231)"

rm -f "$tmp/desc"
assert_eq "a missing file is unreadable, exit 0" "all-earlier unreadable" "$(read_n 1)"
mkdir "$tmp/dir"
assert_eq "a directory is unreadable" "all-earlier unreadable" "$(sh "$script" read "$tmp/dir" 1)"

echo "# formats the description may arrive in"

printf '**Build order:**\r\n1. #231: a. [depends_on: none]\r\n2. #232: b. [depends_on: #231]\r\n\r\n**BLOCKING:** x\r\n' >"$tmp/desc"
assert_eq "CRLF line endings read the same" "after 231" "$(read_n 232)"

write_desc <<'EOF'
1. #231: first. [depends_on: none]
2. #232: a long reason that the human wrapped
   onto a second line. [depends_on: #231]
3. #233: last one. [depends_on: none]
EOF
assert_eq "a wrapped item finds its marker on the continuation line" "after 231" "$(read_n 232)"
assert_eq "the item after a wrapped one still parses" "independent" "$(read_n 233)"

write_desc <<'EOF'
1. #231: first. [depends_on: none]
EOF
printf '2. #232: past the list, after the blank line. [depends_on: none]\n' >>"$tmp/desc"
assert_eq "an item past the end of the list is not part of it" "all-earlier not-listed" "$(read_n 232)"

echo "# the marker is never trusted from outside the list"

printf 'Reason. [depends_on: none]\n\n**Build order:**\n1. #231: first.\n' >"$tmp/desc"
assert_eq "a marker outside the Build order list does not apply" "all-earlier unconfirmed" "$(read_n 231)"

echo "# usage errors"

status=0
sh "$script" read "$tmp/desc" 12x >"$tmp/out" 2>/dev/null || status=$?
assert_eq "a non-digit issue number exits 1" "1" "$status"
assert_eq "a non-digit issue number prints nothing on stdout" "" "$(cat "$tmp/out")"

status=0
sh "$script" read "$tmp/desc" 0231 >"$tmp/out" 2>/dev/null || status=$?
assert_eq "an issue number with a leading zero exits 1" "1" "$status"

status=0
sh "$script" read "$tmp/desc" 1234567890 >"$tmp/out" 2>/dev/null || status=$?
assert_eq "an issue number over 9 digits exits 1" "1" "$status"

# a file operand shaped like an awk variable assignment must still be read as a file
mkdir "$tmp/assign" && printf '**Build order:**\n1. #231: a. [depends_on: none]\n' >"$tmp/assign/want=999"
assert_eq "a file named like an awk assignment is read as a file" "independent" \
  "$(cd "$tmp/assign" && sh "$script" read "want=999" 231)"

status=0
sh "$script" read "$tmp/desc" >"$tmp/out" 2>/dev/null || status=$?
assert_eq "a missing argument exits 1" "1" "$status"

status=0
sh "$script" bogus "$tmp/desc" 1 >"$tmp/out" 2>/dev/null || status=$?
assert_eq "an unknown subcommand exits 1" "1" "$status"

echo "# order -- the list's issue numbers"

ord_() { sh "$script" order "$tmp/desc"; }
frm() { sh "$script" frame "$1"; }
itm() { sh "$script" items "$tmp/desc"; }

write_desc <<'EOF'
1. #12: first. [depends_on: none]
2. #14: second. [depends_on: #12]
3. #9: third, listed last but a lower number. [depends_on: none]
EOF
assert_eq "order prints the numbers in list order, not sorted" "order 12 14 9" "$(ord_)"

write_desc <<'EOF'
1. #12: first, a reason that the human wrapped
   onto a second line. [depends_on: none]
2. #14: no marker at all.
3. #9: ok. [depends_on: #12]
EOF
assert_eq "wrapped lines and a missing marker read the same" "order 12 14 9" "$(ord_)"

printf '**Build order:**\r\n1. #12: a. [depends_on: none]\r\n2. #14: b.\r\n' >"$tmp/desc"
assert_eq "a CRLF file reads the same" "order 12 14" "$(ord_)"

write_desc <<'EOF'
1. #12: ok. [depends_on: none]
2. #14: malformed. [depends_on: #12 #99]
EOF
assert_eq "one malformed marker does not make order unreadable" "order 12 14" "$(ord_)"

rm -f "$tmp/desc"
assert_eq "order: a missing file is unreadable" "unreadable" "$(sh "$script" order "$tmp/desc")"
assert_eq "order: a directory is unreadable" "unreadable" "$(sh "$script" order "$tmp/dir")"
printf 'No build order here.\n' >"$tmp/desc"
assert_eq "order: no header is unreadable" "unreadable" "$(ord_)"
printf '**Build order:**\n1. #1: a.\n\n**Build order:**\n1. #2: b.\n' >"$tmp/desc"
assert_eq "order: a repeated header is unreadable" "unreadable" "$(ord_)"
printf '**Build order:**\n1. #1: a.\n3. #2: b.\n' >"$tmp/desc"
assert_eq "order: numbering not 1..k is unreadable" "unreadable" "$(ord_)"
printf '**Build order:**\n1. #1: a.\n2. #1: b.\n' >"$tmp/desc"
assert_eq "order: a repeated issue is unreadable" "unreadable" "$(ord_)"
printf '**Build order:**\n1. #01: a.\n' >"$tmp/desc"
assert_eq "order: a leading zero is unreadable" "unreadable" "$(ord_)"
printf '**Build order:**\n1. #1234567890: a.\n' >"$tmp/desc"
assert_eq "order: a number over 9 digits is unreadable" "unreadable" "$(ord_)"
printf '**Build order:**\n\n1. #1: a.\n' >"$tmp/desc"
assert_eq "order: a header with no items is unreadable" "unreadable" "$(ord_)"
printf '**Build order:**\n' >"$tmp/desc"
assert_eq "order: a header at end of file is unreadable" "unreadable" "$(ord_)"

echo "# frame -- everything outside the list"

mkframe() { # mkframe <file> <list-body> [<trailer>]
  {
    printf 'Intro line.\n\n**Build order:**\n'
    printf '%s\n' "$2"
    printf '\n%s\n' "${3:-**Model per phase:** coder.}"
  } >"$1"
}
mkframe "$tmp/f1" '1. #12: a. [depends_on: none]'
mkframe "$tmp/f2" '1. #7: new. [depends_on: none]
2. #12: a, renumbered
   and wrapped. [depends_on: none]'
assert_eq "frames differing only inside the list are equal" "$(frm "$tmp/f1")" "$(frm "$tmp/f2")"
assert_eq "the frame keeps the header and the text around the list" \
  "Intro line.

**Build order:**

**Model per phase:** coder." "$(frm "$tmp/f1")"

printf 'Intro line.\n\n**Build order:**\n1. #12: a. [depends_on: none]\n\n**Model per phase:** coder.' >"$tmp/f3"
assert_eq "frames differing only in the final newline are equal" "$(frm "$tmp/f1")" "$(frm "$tmp/f3")"

mkframe "$tmp/f4" '1. #12: a. [depends_on: none]' '**BLOCKING:** wait for review.'
if [ "$(frm "$tmp/f1")" != "$(frm "$tmp/f4")" ]; then
  echo "ok - a changed line after the list changes the frame"
else
  echo "FAIL - a changed line after the list left the frame equal" >&2; fail=1
fi
sed 's/^Intro line\./Changed intro./' "$tmp/f1" >"$tmp/f5"
if [ "$(frm "$tmp/f1")" != "$(frm "$tmp/f5")" ]; then
  echo "ok - a changed line before the header changes the frame"
else
  echo "FAIL - a changed line before the header left the frame equal" >&2; fail=1
fi
sed 's/^\*\*Build order:\*\*$/**Build order:** /' "$tmp/f1" >"$tmp/f6"
assert_eq "a changed header makes the list unreadable, so the frame says so" "unreadable" "$(frm "$tmp/f6")"
printf '**Build order:**\n\n1. #1: a.\n' >"$tmp/f7"
assert_eq "frame: an unreadable list prints unreadable" "unreadable" "$(frm "$tmp/f7")"
assert_eq "frame: a missing file prints unreadable" "unreadable" "$(frm "$tmp/nosuch")"
printf 'Intro.\r\n\r\n**Build order:**\r\n1. #12: a.\r\n\r\nTail.\r\n' >"$tmp/f8"
assert_eq "frame strips CR as read does" "Intro.

**Build order:**

Tail." "$(frm "$tmp/f8")"

# the skill's real pair: gh --jq adds one newline to a stored description that already ends in
# one; the composed file drops it, and the check copy adds it back. Compared as files with cmp.
printf 'R.\n\n**Build order:**\n1. #5: a.\n\n**Model per phase**\n- x\n\n\n' >"$tmp/g-before"
printf 'R.\n\n**Build order:**\n1. #5: a.\n2. #6: b.\n\n**Model per phase**\n- x\n\n' >"$tmp/g-composed"
{ cat "$tmp/g-composed"; printf '\n'; } >"$tmp/g-check"
sh "$script" frame "$tmp/g-before" >"$tmp/g-fb"
sh "$script" frame "$tmp/g-check" >"$tmp/g-fc"
status=0; cmp -s "$tmp/g-fb" "$tmp/g-fc" || status=$?
assert_eq "frames of a stored-newline description and its check copy are cmp-equal" "0" "$status"

echo "# items -- each item's text"

write_desc <<'EOF'
1. #12: first. [depends_on: none]
2. #14: second, a reason that wraps
   onto a continuation. [depends_on: #12]
3. #9: third.
   **BLOCKING:** not yet.
EOF
assert_eq "items prints one N text line per item, continuations joined" \
  "12 first. [depends_on: none]
14 second, a reason that wraps onto a continuation. [depends_on: #12]
9 third. **BLOCKING:** not yet." "$(itm)"
printf '**Build order:**\r\n1. #12: first. [depends_on: none]\r\n2. #14: x\r\n   y.\r\n' >"$tmp/desc"
assert_eq "items: a CRLF file reads the same as an LF one" "12 first. [depends_on: none]
14 x y." "$(itm)"
printf '**Build order:**\n1. #1: a.\n1. #2: b.\n' >"$tmp/desc"
assert_eq "items: an unreadable list prints unreadable" "unreadable" "$(itm)"
assert_eq "items: a missing file prints unreadable" "unreadable" "$(sh "$script" items "$tmp/nosuch")"

echo "# usage errors for the new subcommands"

for sub in order frame items; do
  status=0
  sh "$script" "$sub" >"$tmp/out" 2>/dev/null || status=$?
  assert_eq "$sub with no file exits 1" "1" "$status"
  assert_eq "$sub with no file prints nothing" "" "$(cat "$tmp/out")"
  status=0
  sh "$script" "$sub" "$tmp/desc" extra >"$tmp/out" 2>/dev/null || status=$?
  assert_eq "$sub with an extra argument exits 1" "1" "$status"
  assert_eq "$sub with an extra argument prints nothing" "" "$(cat "$tmp/out")"
done

exit "$fail"
