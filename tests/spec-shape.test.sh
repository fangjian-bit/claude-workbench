#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/spec-shape.sh (#611).
#
# /way-of-working:spec-task posts or holds its draft only when this predicate says `ok`: the required
# sections, in order, each with a non-empty body.
#
# Permitted toolset: POSIX sh.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/plugins/way-of-working/bin/spec-shape.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0

assert_eq() {
  desc="$1"
  expected="$2"
  actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "ok - $desc"
  else
    echo "FAIL - $desc: expected [$expected], got [$actual]" >&2
    fail=1
  fi
}

# write_draft <name> <section>... : a draft with the named sections, each with one body line.
# The title line is free-form, but never begins with a marker prefix. A section named `Restated from the issue body` gets the body
# in $RESTATED (default: one bullet).
RESTATED='- The skill is draft-only.'
write_draft() {
  f="$tmp/$1"
  shift
  printf '%s\n\n' '## Spec — #611: a title' >"$f"
  for s in "$@"; do
    printf '### %s\n\n' "$s" >>"$f"
    if [ "$s" = 'Restated from the issue body' ]; then
      [ -z "$RESTATED" ] || printf '%s\n\n' "$RESTATED" >>"$f"
    else
      printf 'body of %s\n\n' "$s" >>"$f"
    fi
  done
  echo "$f"
}

check() {
  desc="$1"
  expected="$2"
  file="$3"
  assert_eq "$desc" "$expected" "$("$script" check "$file")"
}

ALL="Goal|Files touched|Done when|Tests|Out of scope|Restated from the issue body"

d() { # <name> <sections joined by |>
  name="$1"
  oldifs=$IFS; IFS='|'
  # shellcheck disable=SC2086
  set -- $2
  IFS=$oldifs
  write_draft "$name" "$@"
}

check "all six sections" ok "$(d full "$ALL")"

# Each section missing in turn.
check "no Goal" "missing Goal" "$(d m1 "Files touched|Done when|Tests|Out of scope|Restated from the issue body")"
check "no Files touched" "missing Files touched" "$(d m2 "Goal|Done when|Tests|Out of scope|Restated from the issue body")"
check "no Done when" "missing Done when" "$(d m3 "Goal|Files touched|Tests|Out of scope|Restated from the issue body")"
check "no Tests" "missing Tests" "$(d m4 "Goal|Files touched|Done when|Out of scope|Restated from the issue body")"
check "no Out of scope" "missing Out of scope" "$(d m5 "Goal|Files touched|Done when|Tests|Restated from the issue body")"
check "no Restated" "missing Restated from the issue body" "$(d m6 "Goal|Files touched|Done when|Tests|Out of scope")"

# Out of order: the later heading is not found after the one it should follow.
check "Tests before Done when" "missing Tests" "$(d o1 "Goal|Files touched|Tests|Done when|Out of scope|Restated from the issue body")"
check "Goal last" "missing Files touched,Done when,Tests,Out of scope,Restated from the issue body" \
  "$(d o2 "Files touched|Done when|Tests|Out of scope|Restated from the issue body|Goal")"

# A heading must be the whole line.
check "heading with extra words" "missing Goal" \
  "$(d h1 "Goal and more|Files touched|Done when|Tests|Out of scope|Restated from the issue body")"
f="$tmp/h2"
{ printf '## Spec\n\n'; printf '## Goal\n\ntext\n\n### Files touched\n\nx\n\n'; } >"$f"
check "wrong heading level" "missing Goal,Done when,Tests,Out of scope,Restated from the issue body" "$f"
f="$tmp/h3"
printf '### Goal  \nx\n### Files touched\nx\n### Done when\nx\n### Tests\nx\n### Out of scope\nx\n### Restated from the issue body\nx\n' >"$f"
check "trailing blanks on a heading" ok "$f"
f="$tmp/h4"
printf '### Goal\r\nx\r\n### Files touched\r\nx\r\n### Done when\r\nx\r\n### Tests\r\nx\r\n### Out of scope\r\nx\r\n### Restated from the issue body\r\nx\r\n' >"$f"
check "CRLF line endings" ok "$f"

# The last section: empty, blank-only, or the literal `nothing`.
RESTATED=''
check "empty Restated section" "missing Restated from the issue body" "$(d r1 "$ALL")"
RESTATED='   '
check "blank-only Restated section" "missing Restated from the issue body" "$(d r2 "$ALL")"
RESTATED='nothing'
check "Restated reads nothing" ok "$(d r3 "$ALL")"
RESTATED='- one
- two'
check "Restated with several lines" ok "$(d r4 "$ALL")"

# A later heading ends the last section, so text under it is not the last section's body.
f="$tmp/r5"
printf '### Goal\nx\n### Files touched\nx\n### Done when\nx\n### Tests\nx\n### Out of scope\nx\n### Restated from the issue body\n\n### Extra\ntext\n' >"$f"
check "text under a later heading is not Restated's body" "missing Restated from the issue body" "$f"

f="$tmp/r6"
printf '### Goal\nx\n### Files touched\nx\n### Done when\nx\n### Tests\nx\n### Out of scope\nx\n### Restated from the issue body\n## Notes\ntext\n' >"$f"
check "a level-2 heading ends the last section" "missing Restated from the issue body" "$f"

# Every section needs a body, not only the last.
f="$tmp/e1"
printf '### Goal\n\n### Files touched\nx\n### Done when\n  \n### Tests\nx\n### Out of scope\nx\n### Restated from the issue body\nnothing\n' >"$f"
check "empty Goal and Done when sections" "missing Goal,Done when" "$f"

# A path shaped like an awk assignment is still read as a file.
mkdir "$tmp/cwd"
printf '### Goal\nx\n### Files touched\nx\n### Done when\nx\n### Tests\nx\n### Out of scope\nx\n### Restated from the issue body\nnothing\n' >"$tmp/cwd/k=v"
assert_eq "a name=value path is a file, not an awk assignment" ok "$(cd "$tmp/cwd" && "$script" check 'k=v' </dev/null)"

# Title line is free-form (apart from the marker prefixes below); no title at all is fine.
f="$tmp/t1"
printf '### Goal\nx\n### Files touched\nx\n### Done when\nx\n### Tests\nx\n### Out of scope\nx\n### Restated from the issue body\nnothing\n' >"$f"
check "no title line" ok "$f"

# A line beginning with a marker prefix is refused, as spec-post.sh refuses it, and wins over missing.
ALLS='### Goal\nx\n### Files touched\nx\n### Done when\nx\n### Tests\nx\n### Out of scope\nx\n### Restated from the issue body\nnothing\n'
f="$tmp/k1"
{ printf 'spec-task: issue=1 base=main sha=abc\n'; printf "$ALLS"; } >"$f"
check "marker title line" has-marker "$f"
f="$tmp/k2"
{ printf 'spec-task-escalated: issue=1\n'; printf "$ALLS"; } >"$f"
check "escalated marker title line" has-marker "$f"
f="$tmp/k3"
printf '### Goal\nx\nspec-task-escalated: y\n### Files touched\nx\n### Done when\nx\n### Tests\nx\n### Out of scope\nx\n### Restated from the issue body\nnothing\n' >"$f"
check "marker line in a section body" has-marker "$f"
f="$tmp/k4"
printf 'spec-task: x\r\n### Goal\r\nx\r\n### Files touched\r\nx\r\n### Done when\r\nx\r\n### Tests\r\nx\r\n### Out of scope\r\nx\r\n### Restated from the issue body\r\nx\r\n' >"$f"
check "marker title line with CRLF" has-marker "$f"
f="$tmp/k5"
printf 'see spec-task: x\n### Goal\nx\n### Files touched\nx\n### Done when\nx\n### Tests\nx\n### Out of scope\nx\n### Restated from the issue body\nnothing\n' >"$f"
check "prefix after leading text" ok "$f"
f="$tmp/k6"
printf '### Goal\nx\n  spec-task: x\n### Files touched\nx\n### Done when\nx\n### Tests\nx\n### Out of scope\nx\n### Restated from the issue body\nnothing\n' >"$f"
check "prefix after two leading blanks" ok "$f"
f="$tmp/k7"
printf 'spec-task: x\n### Files touched\nx\n### Done when\nx\n### Tests\nx\n### Out of scope\nx\n### Restated from the issue body\nnothing\n' >"$f"
check "marker line and no Goal is has-marker, not missing" has-marker "$f"

# Unreadable: absent, a directory, empty.
check "absent file" unreadable "$tmp/nope"
check "a directory" unreadable "$tmp"
: >"$tmp/empty"
check "empty file" unreadable "$tmp/empty"

# The file is data: a body that looks like a shell command is only read.
f="$tmp/inj"
printf '### Goal\n$(touch %s/pwned)\n### Files touched\nx\n### Done when\nx\n### Tests\nx\n### Out of scope\nx\n### Restated from the issue body\n`touch %s/pwned2`\n' "$tmp" "$tmp" >"$f"
check "command-looking text is only read" ok "$f"
if [ -e "$tmp/pwned" ] || [ -e "$tmp/pwned2" ]; then
  assert_eq "nothing in the file was run" none ran
else
  assert_eq "nothing in the file was run" none none
fi

# Usage errors exit non-zero.
for args in "" "check" "check a b" "other $tmp/full" "$tmp/full"; do
  # shellcheck disable=SC2086
  if "$script" $args >/dev/null 2>&1; then
    assert_eq "usage error [$args] exits non-zero" nonzero zero
  else
    assert_eq "usage error [$args] exits non-zero" nonzero nonzero
  fi
done

[ "$fail" -eq 0 ] || exit 1
echo "All spec-shape fixtures passed."
