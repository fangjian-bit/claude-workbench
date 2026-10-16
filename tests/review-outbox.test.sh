#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/review-outbox.sh (#636): the one writer of the
# review container's outbox.
#
# The script runs as a sed-substituted copy whose marker and outbox are temp paths. Its two fixed
# lines are unquoted (REVIEW_CONTAINER_MARKER=... and REVIEW_OUTBOX=...), so this file substitutes
# them with its own sed, not review-image.test.sh's quoted-value helper, and asserts with grep that
# both substitutions took before any case runs. `body` reads the default branch's schema from a
# throwaway git repository whose refs/remotes/origin/main holds the gate strings; the working
# tree's copy is changed on purpose in one case, to show it is never read.
#
# Agreement with the launcher: the mention, secret and forged-footer pattern literals, the five
# session stop reasons and the marker line are pinned equal to scripts/identity/wow-review and
# review-sandbox.sh, and scripts/identity/review/outbox-read accepts what `outcome`, `body` and
# `findings` wrote.
#
# Permitted toolset: POSIX sh and its standard utilities, git, jq and yq (skipped, loudly, if jq or
# yq is absent).
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/plugins/way-of-working/bin/review-outbox.sh"
launcher="$root_dir/scripts/identity/wow-review"
sandbox_script="$root_dir/plugins/way-of-working/bin/review-sandbox.sh"
reader="$root_dir/scripts/identity/review/outbox-read"

for t in jq yq git; do
  if ! command -v "$t" >/dev/null 2>&1; then
    echo "SKIP - $t not on PATH; review-outbox fixtures not run" >&2
    exit 0
  fi
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
ok() { printf 'ok - %s\n' "$1"; }
bad() { printf 'FAIL - %s\n' "$1" >&2; fail=1; }
check() { # check <label> <command...>
  l=$1; shift
  if "$@"; then ok "$l"; else bad "$l"; fi
}
assert_eq() { # assert_eq <label> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: expected [$2], got [$3]"; fi
}

marker="$tmp/marker"
ob="$tmp/outbox"
S="$tmp/review-outbox.sh"
sed -e "s|^REVIEW_CONTAINER_MARKER=.*\$|REVIEW_CONTAINER_MARKER=$marker|" -e "s|^REVIEW_OUTBOX=.*\$|REVIEW_OUTBOX=$ob|" "$script" >"$S"
check "the marker substitution took" grep -qxF "REVIEW_CONTAINER_MARKER=$marker" "$S"
check "the outbox substitution took" grep -qxF "REVIEW_OUTBOX=$ob" "$S"
check "the real script carries the two fixed lines" sh -c 'grep -qxF "REVIEW_CONTAINER_MARKER=/etc/way-of-working/review-container" "$0" && grep -qxF "REVIEW_OUTBOX=/review-out" "$0"' "$script"
if [ "$fail" != 0 ]; then echo "cannot continue without the substituted copy" >&2; exit 1; fi

SHA=$(printf 'a%.0s' $(seq 1 40))
OTHER=$(printf 'b%.0s' $(seq 1 40))
HDR='## Architect Review (fresh session)'
ATT='I attest this review was written in a fresh session.'

# The repository whose origin/main holds the gate strings.
repo="$tmp/repo"
mkdir -p "$repo/.ai"
git -C "$repo" init -q
git -C "$repo" config user.email t@example.invalid
git -C "$repo" config user.name t
git -C "$repo" config core.autocrlf false
git -C "$repo" config commit.gpgsign false
printf 'review:\n  ci_gate:\n    header: "%s"\n    attestation: "%s"\n' "$HDR" "$ATT" >"$repo/.ai/project.yml"
git -C "$repo" add .ai/project.yml
git -C "$repo" commit -q -m fixture
git -C "$repo" update-ref refs/remotes/origin/main HEAD

ENVA="WOW_REVIEW_PR=12 WOW_REVIEW_SHA=$SHA"
run() { # run <args...> -> $rc $out $err
  rc=0
  # shellcheck disable=SC2086
  ( cd "$repo" && env -u WOW_REVIEW_PR -u WOW_REVIEW_SHA $ENVA sh "$S" "$@" ) >"$tmp/r.out" 2>"$tmp/r.err" </dev/null || rc=$?
  out=$(cat "$tmp/r.out"); err=$(cat "$tmp/r.err")
}
container() { rm -rf "$ob" "$marker"; mkdir "$ob"; : >"$marker"; }
host() { rm -rf "$ob" "$marker"; mkdir "$ob"; }
outbox_empty() { [ -z "$(ls -A "$ob")" ]; }

have_links=1
if ln -s "$tmp/nowhere" "$tmp/linkprobe" 2>/dev/null && [ -L "$tmp/linkprobe" ]; then :; else
  have_links=0
  echo "SKIP - a symlink cannot be made here; the link fixtures did not run" >&2
fi
rm -f "$tmp/linkprobe"

# --- where ----------------------------------------------------------------------------------
host
run where
assert_eq "where: host" host "$out"; assert_eq "where: host exits 0" 0 "$rc"; assert_eq "where: host prints nothing else" "" "$err"
container
run where
assert_eq "where: container" container "$out"; assert_eq "where: container exits 0" 0 "$rc"
if [ "$have_links" = 1 ]; then
  rm -f "$marker"; ln -s "$tmp/nowhere" "$marker"
  run where
  assert_eq "where: a dangling link reads container" container "$out"
  rm -f "$marker"; ln -s "$tmp" "$marker"
  run where
  assert_eq "where: a link to a directory reads container" container "$out"
fi
run where extra
assert_eq "where: an argument is usage" 2 "$rc"

# --- every write refuses on the host and on usage errors --------------------------------------
printf 'x\n' >"$tmp/any"
host
for cmdline in "outcome review 12 $SHA" "body $tmp/any $SHA main" "findings $tmp/any"; do
  # shellcheck disable=SC2086
  run $cmdline
  assert_eq "host refuses [$cmdline]: exit 2" 2 "$rc"
  check "host refuses [$cmdline]: nothing written" outbox_empty
done
container
run
assert_eq "no subcommand: exit 2" 2 "$rc"
run bogus
assert_eq "an unknown subcommand: exit 2" 2 "$rc"
for cmdline in "outcome" "outcome review" "outcome review 12" "outcome bogus 12 $SHA" "outcome review 12 $SHA extra" \
  "outcome stopped 12 $SHA" "outcome stopped 12 $SHA bogus" "outcome stopped 12 $SHA entry-env" "outcome review 012 $SHA" \
  "outcome review 0 $SHA" "outcome review 12 abc" "outcome review 12 ${SHA}0" "outcome review 12 AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" \
  "body" "body $tmp/any" "body $tmp/any $SHA" "body $tmp/any abc main" "body $tmp/any $SHA -x" "body $tmp/any $SHA a/../b" "body $tmp/any $SHA main extra" \
  "findings" "findings a b"; do
  # shellcheck disable=SC2086
  run $cmdline
  assert_eq "usage [$cmdline]: exit 2" 2 "$rc"
  check "usage [$cmdline]: nothing written" outbox_empty
done
# The environment variables unset or empty are usage, in a container.
for v in "" "WOW_REVIEW_PR=12" "WOW_REVIEW_SHA=$SHA" "WOW_REVIEW_PR= WOW_REVIEW_SHA=$SHA" "WOW_REVIEW_PR=12 WOW_REVIEW_SHA="; do
  ENVA=$v
  run outcome review 12 "$SHA"
  assert_eq "outcome with the environment [$v]: exit 2" 2 "$rc"
  run body "$tmp/any" "$SHA" main
  assert_eq "body with the environment [$v]: exit 2" 2 "$rc"
done
ENVA="WOW_REVIEW_PR=12 WOW_REVIEW_SHA=$SHA"
check "...and nothing was written" outbox_empty
rm -rf "$ob"
run outcome review 12 "$SHA"
assert_eq "an absent outbox directory: exit 2" 2 "$rc"
container

# --- outcome --------------------------------------------------------------------------------
for k in review exempt already-reviewed; do
  container
  run outcome "$k" 12 "$SHA"
  assert_eq "outcome $k: exit 0" 0 "$rc"
  assert_eq "outcome $k: the exact line" "$k 12 $SHA" "$(cat "$ob/outcome")"
  assert_eq "outcome $k: one newline-terminated line" 1 "$(wc -l <"$ob/outcome" | tr -d ' ')"
  assert_eq "outcome $k: nothing else in the outbox" outcome "$(ls -A "$ob")"
done
for r in head-moved checks-pending checks-red base-override needs-human; do
  container
  run outcome stopped 12 "$SHA" "$r"
  assert_eq "outcome stopped $r: exit 0" 0 "$rc"
  assert_eq "outcome stopped $r: the exact line" "stopped 12 $SHA $r" "$(cat "$ob/outcome")"
done
container
run outcome review 13 "$SHA"
assert_eq "outcome with another <N>: exit 1" 1 "$rc"; assert_eq "...reason" mismatch "$out"; check "...nothing written" outbox_empty
run outcome review 12 "$OTHER"
assert_eq "outcome with another <sha>: exit 1" 1 "$rc"; assert_eq "...reason" mismatch "$out"; check "...nothing written" outbox_empty
run outcome review 12 "$SHA"
run outcome stopped 12 "$SHA" needs-human
assert_eq "a second outcome: exit 1" 1 "$rc"; assert_eq "...reason" outcome-exists "$out"
assert_eq "...the first one stands" "review 12 $SHA" "$(cat "$ob/outcome")"
if [ "$have_links" = 1 ]; then
  container; ln -s "$tmp/elsewhere" "$ob/outcome"
  run outcome review 12 "$SHA"
  assert_eq "an outcome that is a dangling link: exit 1" 1 "$rc"
  check "...nothing was written through it" test ! -e "$tmp/elsewhere"
fi

# --- body -----------------------------------------------------------------------------------
good_body() { # good_body <file> [extra line]
  printf '%s\n\n%s\nReviewed against head %s\n\nA clean review.\n' "$HDR" "$ATT" "$SHA" >"$1"
  [ -z "${2:-}" ] || printf '%s\n' "$2" >>"$1"
}
body_ok() { # body_ok <label> <file>
  container
  run body "$2" "$SHA" main
  assert_eq "body: $1: exit 0" 0 "$rc"
  check "body: $1: review.md is the file" cmp -s "$2" "$ob/review.md"
  assert_eq "body: $1: nothing else left in the outbox" review.md "$(ls -A "$ob")"
}
body_refused() { # body_refused <label> <word> <file>
  container
  run body "$3" "$SHA" main
  assert_eq "body: $1: exit 1" 1 "$rc"
  assert_eq "body: $1: the reason word" "$2" "$out"
  check "body: $1: nothing written" outbox_empty
}

good_body "$tmp/b"
body_ok "a clean body" "$tmp/b"
good_body "$tmp/b" 'Use at-types/node and an email-free text, h'$(printf '\303\251')'llo.'
body_ok "a UTF-8 body with at-types/node" "$tmp/b"
good_body "$tmp/b"
head -c $((64000 - $(wc -c <"$tmp/b"))) /dev/zero | tr '\000' 'a' >>"$tmp/b"
assert_eq "...the cap fixture is exactly 64000 bytes" 64000 "$(wc -c <"$tmp/b" | tr -d ' ')"
body_ok "a body of exactly 64000 bytes" "$tmp/b"
printf 'a' >>"$tmp/b"
body_refused "64001 bytes" too-big "$tmp/b"
{ head -c 70000 /dev/zero | tr '\000' 'a'; } >"$tmp/b"
body_refused "far over the cap" too-big "$tmp/b"

mkdir "$tmp/adir"
body_refused "a directory" not-regular "$tmp/adir"
body_refused "a missing file" not-regular "$tmp/missing"
if [ "$have_links" = 1 ]; then
  good_body "$tmp/real"; rm -f "$tmp/lnk"; ln -s "$tmp/real" "$tmp/lnk"
  body_refused "a link source" not-regular "$tmp/lnk"
  container; ln -s "$tmp/elsewhere" "$ob/review.md"
  run body "$tmp/real" "$SHA" main
  assert_eq "body: a link destination: exit 1" 1 "$rc"; assert_eq "...reason" dest "$out"
  check "...nothing was written through it" test ! -e "$tmp/elsewhere"
fi

good_body "$tmp/b2"; printf 'bad \377 byte\n' >>"$tmp/b2"; body_refused "invalid UTF-8" bad-utf8 "$tmp/b2"
good_body "$tmp/b2"; printf 'bad \300\257 overlong\n' >>"$tmp/b2"; body_refused "an overlong UTF-8 sequence" bad-utf8 "$tmp/b2"
good_body "$tmp/b2"; printf 'a CR here\r\n' >>"$tmp/b2"; body_refused "a carriage return" control "$tmp/b2"
good_body "$tmp/b2"; printf 'esc \033[31m red\n' >>"$tmp/b2"; body_refused "an escape sequence" control "$tmp/b2"
good_body "$tmp/b2"; printf 'nul \000 byte\n' >>"$tmp/b2"; body_refused "a NUL byte" control "$tmp/b2"
good_body "$tmp/b2"; printf 'del \177 byte\n' >>"$tmp/b2"; body_refused "a DEL byte" control "$tmp/b2"
good_body "$tmp/b2"; printf 'c1 \302\205 char\n' >>"$tmp/b2"; body_refused "a UTF-8 C1 control" control "$tmp/b2"
good_body "$tmp/b2"; printf 'tab\there\n' >>"$tmp/b2"; body_ok "a tab" "$tmp/b2"

printf 'Wrong header\n\n%s\nReviewed against head %s\n' "$ATT" "$SHA" >"$tmp/b2"; body_refused "a wrong header line" header "$tmp/b2"
printf '%s\nnot blank\n%s\nReviewed against head %s\n' "$HDR" "$ATT" "$SHA" >"$tmp/b2"; body_refused "a non-empty second line" header "$tmp/b2"
printf '%s\n\nWrong attestation\nReviewed against head %s\n' "$HDR" "$SHA" >"$tmp/b2"; body_refused "a wrong attestation" header "$tmp/b2"
printf '%s\n\n' "$HDR" >"$tmp/b2"; body_refused "a body of two lines" header "$tmp/b2"
: >"$tmp/b2"; body_refused "an empty file" header "$tmp/b2"
# The working tree's copy is never read: change the header there, and a body that matches it is refused.
printf 'review:\n  ci_gate:\n    header: "Edited header"\n    attestation: "%s"\n' "$ATT" >"$repo/.ai/project.yml"
printf 'Edited header\n\n%s\nReviewed against head %s\n' "$ATT" "$SHA" >"$tmp/b2"; body_refused "a header matching only the working tree's copy" header "$tmp/b2"
good_body "$tmp/b"; body_ok "a body matching the remote-tracking ref while the working tree differs" "$tmp/b"
git -C "$repo" checkout -q -- .ai/project.yml

printf '%s\n\n%s\n' "$HDR" "$ATT" >"$tmp/b2"; body_refused "no head line" no-head-line "$tmp/b2"
printf '%s\n\n%s\nReviewed against head `%s`\n' "$HDR" "$ATT" "$SHA" >"$tmp/b2"; body_refused "a head line in backticks" no-head-line "$tmp/b2"
printf '%s\n\n%s\nReviewed against head %s\n' "$HDR" "$ATT" "$(printf '%s' "$SHA" | cut -c1-12)" >"$tmp/b2"; body_refused "a short head SHA" no-head-line "$tmp/b2"
printf '%s\n\n%s\nReviewed against head %s\n' "$HDR" "$ATT" "$OTHER" >"$tmp/b2"; body_refused "another head SHA" no-head-line "$tmp/b2"
printf '%s\n\n%s\n- Reviewed against head %s\n' "$HDR" "$ATT" "$SHA" >"$tmp/b2"; body_refused "a head line with a prefix" no-head-line "$tmp/b2"

good_body "$tmp/b2" 'the package @types/node is old'; body_refused "@types/node in text" mention "$tmp/b2"
good_body "$tmp/b2" '```
npm i @types/node
```'; body_refused "@types/node in a code block" mention "$tmp/b2"
good_body "$tmp/b2" 'ask @someone'; body_refused "a mention" mention "$tmp/b2"
good_body "$tmp/b2" 'ask &commat;someone'; body_refused "&commat;" mention "$tmp/b2"
good_body "$tmp/b2" 'ask &#64;someone'; body_refused "&#64;" mention "$tmp/b2"
good_body "$tmp/b2" 'ask &#x40;someone'; body_refused "&#x40;" mention "$tmp/b2"
good_body "$tmp/b2" 'mail me a@b'; body_ok "an @ after a letter is not a mention" "$tmp/b2"

TOKEN36=$(printf 'A%.0s' $(seq 1 36))
good_body "$tmp/b2" "token ghp_$TOKEN36"; body_refused "a ghp_ token" secret "$tmp/b2"
good_body "$tmp/b2" "token ghs_$TOKEN36"; body_refused "a ghs_ token" secret "$tmp/b2"
good_body "$tmp/b2" "token github_pat_$(printf 'B%.0s' $(seq 1 22))"; body_refused "a github_pat_ token" secret "$tmp/b2"
good_body "$tmp/b2" "token sk-ant-$(printf 'C%.0s' $(seq 1 20))"; body_refused "an sk-ant- key" secret "$tmp/b2"
good_body "$tmp/b2" "token ghp_short"; body_ok "a short ghp_ string passes" "$tmp/b2"

good_body "$tmp/b2" 'Host: no findings to file'; body_refused "a Host: line" host-line "$tmp/b2"
good_body "$tmp/b2" 'Host: anything'; body_refused "any line beginning Host: " host-line "$tmp/b2"
good_body "$tmp/b2" '  **Host: 3 findings will be filed in x/y'; body_refused "a forged footer behind spaces and markup" host-line "$tmp/b2"
good_body "$tmp/b2" '> Host: findings not filed (x)'; body_refused "a forged footer behind a quote marker" host-line "$tmp/b2"
good_body "$tmp/b2" "$(printf '\342\200\213')Host: no findings to file"; body_refused "a forged footer behind a zero-width space" host-line "$tmp/b2"
good_body "$tmp/b2" 'The word Host: inside a line passes'; body_ok "Host: mid-line passes" "$tmp/b2"

# The environment guard, and an existing outcome.
container; good_body "$tmp/b"
run body "$tmp/b" "$OTHER" main
assert_eq "body with another <sha>: exit 1" 1 "$rc"; assert_eq "...reason" mismatch "$out"; check "...nothing written" outbox_empty
run outcome review 12 "$SHA"
run body "$tmp/b" "$SHA" main
assert_eq "body after an outcome: exit 1" 1 "$rc"; assert_eq "...reason" outcome-exists "$out"; check "...no review.md" test ! -e "$ob/review.md"
container
run body "$tmp/b" "$SHA" nosuchbranch
assert_eq "body with a branch the repository does not hold: exit 1" 1 "$rc"; assert_eq "...reason" schema "$out"
# A retry replaces the earlier body.
container; good_body "$tmp/b" 'first'
run body "$tmp/b" "$SHA" main
good_body "$tmp/b" 'second'
run body "$tmp/b" "$SHA" main
assert_eq "a second body write: exit 0" 0 "$rc"; check "...replaces the first" cmp -s "$tmp/b" "$ob/review.md"

# --- findings -------------------------------------------------------------------------------
findings_ok() { # findings_ok <label> <json>
  container; printf '%s\n' "$2" >"$tmp/f.json"
  run findings "$tmp/f.json"
  assert_eq "findings: $1: exit 0" 0 "$rc"
  check "findings: $1: findings.json is the file" cmp -s "$tmp/f.json" "$ob/findings.json"
  assert_eq "findings: $1: nothing else in the outbox" findings.json "$(ls -A "$ob")"
}
findings_refused() { # findings_refused <label> <word> <json>
  container; printf '%s\n' "$3" >"$tmp/f.json"
  run findings "$tmp/f.json"
  assert_eq "findings: $1: exit 1" 1 "$rc"
  assert_eq "findings: $1: the reason word" "$2" "$out"
  check "findings: $1: nothing written" outbox_empty
}
F1='{"title":"T","body":"B","type":"bug"}'
findings_ok "an empty array" '[]'
findings_ok "one finding" "[$F1]"
findings_ok "a finding with an area" '[{"title":"T","body":"B","type":"docs","area":"area/skills-2"}]'
findings_ok "five findings" "[$F1,$F1,$F1,$F1,$F1]"
for ty in bug feature chore docs; do findings_ok "type $ty" "[{\"title\":\"T\",\"body\":\"B\",\"type\":\"$ty\"}]"; done
findings_refused "six findings" count "[$F1,$F1,$F1,$F1,$F1,$F1]"
findings_refused "not JSON" unreadable 'not json'
findings_refused "an object, not an array" shape "$F1"
findings_refused "a number in the array" shape '[1]'
findings_refused "an extra key" shape '[{"title":"T","body":"B","type":"bug","extra":1}]'
findings_refused "a missing key" shape '[{"title":"T","type":"bug"}]'
findings_refused "a non-string title" shape '[{"title":1,"body":"B","type":"bug"}]'
findings_refused "a non-string area" shape '[{"title":"T","body":"B","type":"bug","area":1}]'
findings_refused "an empty title" title '[{"title":"","body":"B","type":"bug"}]'
findings_refused "a title of 121 characters" title "[{\"title\":\"$(printf 'a%.0s' $(seq 1 121))\",\"body\":\"B\",\"type\":\"bug\"}]"
findings_ok "a title of 120 characters" "[{\"title\":\"$(printf 'a%.0s' $(seq 1 120))\",\"body\":\"B\",\"type\":\"bug\"}]"
findings_ok "a body of 4000 bytes" "[{\"title\":\"T\",\"body\":\"$(printf 'a%.0s' $(seq 1 4000))\",\"type\":\"bug\"}]"
findings_refused "a body of 4001 bytes" body "[{\"title\":\"T\",\"body\":\"$(printf 'a%.0s' $(seq 1 4001))\",\"type\":\"bug\"}]"
findings_refused "a body of 2001 two-byte characters" body "[{\"title\":\"T\",\"body\":\"$(printf '\303\251%.0s' $(seq 1 2001))\",\"type\":\"bug\"}]"
findings_refused "an unknown type" type '[{"title":"T","body":"B","type":"epic"}]'
findings_refused "an area with capitals" area '[{"title":"T","body":"B","type":"bug","area":"area/Skills"}]'
findings_refused "an area without the prefix" area '[{"title":"T","body":"B","type":"bug","area":"skills"}]'
findings_refused "an empty area name" area '[{"title":"T","body":"B","type":"bug","area":"area/"}]'
findings_refused "a tab in a title" control '[{"title":"a\tb","body":"B","type":"bug"}]'
findings_refused "a newline in a title" control '[{"title":"a\nb","body":"B","type":"bug"}]'
findings_refused "an escape in a body" control '[{"title":"T","body":"a\u001bb","type":"bug"}]'
findings_refused "a DEL in a body" control '[{"title":"T","body":"a\u007fb","type":"bug"}]'
findings_refused "a C1 control in a body" control '[{"title":"T","body":"a\u0085b","type":"bug"}]'
findings_ok "a tab and a newline in a body" '[{"title":"T","body":"a\tb\nc","type":"bug"}]'
findings_refused "a mention in a title" mention '[{"title":"ask @someone","body":"B","type":"bug"}]'
findings_refused "a mention in a body" mention '[{"title":"T","body":"npm i @types/node","type":"bug"}]'
findings_refused "an entity mention" mention '[{"title":"T","body":"&commat;x","type":"bug"}]'
findings_refused "a token in a body" secret "[{\"title\":\"T\",\"body\":\"ghp_$TOKEN36\",\"type\":\"bug\"}]"
container; { printf '['; head -c 33000 /dev/zero | tr '\000' ' '; printf ']\n'; } >"$tmp/f.json"
run findings "$tmp/f.json"
assert_eq "findings: over 32768 bytes: exit 1" 1 "$rc"; assert_eq "...reason" too-big "$out"
container; run findings "$tmp/adir"
assert_eq "findings: a directory: exit 1" 1 "$rc"; assert_eq "...reason" not-regular "$out"
container; printf '[]' >"$tmp/f.json"; run outcome review 12 "$SHA"; run findings "$tmp/f.json"
assert_eq "findings after an outcome: exit 1" 1 "$rc"; assert_eq "...reason" outcome-exists "$out"
if [ "$have_links" = 1 ]; then
  container; ln -s "$tmp/elsewhere" "$ob/findings.json"
  run findings "$tmp/f.json"
  assert_eq "findings: a link destination: exit 1" 1 "$rc"; assert_eq "...reason" dest "$out"
  check "...nothing was written through it" test ! -e "$tmp/elsewhere"
fi

# --- agreement with the launcher and the outbox reader ------------------------------------------
cat >"$tmp/literals" <<'LITERALS'
LC_ALL=C grep -Eq '(^|[^A-Za-z0-9_])@[A-Za-z0-9]' "$1" && return 0
LC_ALL=C grep -Eiq '&#0*64([^0-9]|$)|&#x0*40([^0-9a-f]|$)|&commat;' "$1" && return 0
LC_ALL=C grep -Eq 'gh[spour]_[A-Za-z0-9._-]{36,}|github_pat_[A-Za-z0-9_]{22,}|sk-ant-[A-Za-z0-9_-]{20,}' "$1"
zw1=$(printf '\342\200'); zwlo=$(printf '\213'); zwhi=$(printf '\217'); bom=$(printf '\357\273\277')
if LC_ALL=C grep -q '^Host: ' "$B" || LC_ALL=C grep -Eq "^([[:space:]*_>#\`~|-]|${zw1}[${zwlo}-${zwhi}]|${bom})*Host: (no findings to file|findings not filed|[0-9]+ findings will be filed)" "$B"
jq -e 'all(.[]; type == "object"
and ((keys - ["area"]) | sort) == ["body", "title", "type"]
LITERALS
n=0
while IFS= read -r lit || [ -n "$lit" ]; do
  n=$((n + 1))
  # Leading blanks differ with indentation in the two files; compare the trimmed literal.
  check "literal $n appears in review-outbox.sh" grep -qF -- "$lit" "$script"
  check "literal $n appears in wow-review" grep -qF -- "$lit" "$launcher"
done <"$tmp/literals"
for rule in \
  "jq -e -s 'length == 1 and (.[0] | type) == \"array\"'" \
  "jq -e 'length <= 5'" \
  "jq -e 'all(.[]; (.title | length) >= 1 and (.title | length) <= 120)'" \
  "jq -e 'all(.[]; (.body | utf8bytelength) <= 4000)'" \
  "jq -e 'all(.[]; .type == \"bug\" or .type == \"feature\" or .type == \"chore\" or .type == \"docs\")'" \
  "jq -e 'all(.[]; (has(\"area\") | not) or (.area | test(\"\\\\Aarea/[a-z0-9-]+\\\\z\")))'" \
  "jq -e 'all(.[]; ((.title | explode | any(. < 32 or (. >= 127 and . <= 159))) or (.body | explode | any((. < 32 and . != 9 and . != 10) or (. >= 127 and . <= 159)))) | not)'"; do
  check "findings rule appears in both: $rule" sh -c 'grep -qF -- "$1" "$2" && grep -qF -- "$1" "$3"' x "$rule" "$script" "$launcher"
done

mine=$(sed -n 's/^ *head-moved|\(checks-pending|checks-red|base-override|needs-human\)) ;;.*$/head-moved|\1/p' "$script")
theirs=$(sed -n 's/^ *entry-env|entry-token|entry-clone|entry-identity|entry-plugin|\(head-moved|checks-pending|checks-red|base-override|needs-human\)) ;;.*$/\1/p' "$launcher")
assert_eq "the five session reasons equal decide_stopped's" "$theirs" "$mine"
assert_eq "...and there are five" 5 "$(printf '%s' "$mine" | tr '|' '\n' | grep -c . )"

assert_eq "the marker line equals review-sandbox.sh's" \
  "$(grep -x 'REVIEW_CONTAINER_MARKER=.*' "$sandbox_script")" "$(grep -x 'REVIEW_CONTAINER_MARKER=.*' "$script")"

# outbox-read accepts what the writer wrote.
R="$tmp/outbox-read"
sed "s|^outbox='.*'\$|outbox='$ob'|" "$reader" >"$R"
check "the outbox-read substitution took" grep -qF "outbox='$ob'" "$R"
container
good_body "$tmp/b" 'h'$(printf '\303\251')'llo'
run body "$tmp/b" "$SHA" main
printf '[%s]\n' "$F1" >"$tmp/f.json"; run findings "$tmp/f.json"
run outcome review 12 "$SHA"
for pair in outcome:outcome body:review.md findings:findings.json; do
  sub=${pair%%:*}; f=${pair#*:}
  rrc=0
  TMPDIR="$tmp" sh "$R" "$sub" >"$tmp/rd.out" 2>"$tmp/rd.err" </dev/null || rrc=$?
  assert_eq "outbox-read $sub accepts what was written: exit 0" 0 "$rrc"
  check "outbox-read $sub prints the file" cmp -s "$tmp/rd.out" "$ob/$f"
done
container
run outcome stopped 12 "$SHA" head-moved
rrc=0; TMPDIR="$tmp" sh "$R" outcome >"$tmp/rd.out" 2>/dev/null </dev/null || rrc=$?
assert_eq "outbox-read outcome accepts a stopped line" 0 "$rrc"

# No temp file is left behind in the outbox by any write.
container; good_body "$tmp/b"; run body "$tmp/b" "$SHA" main; run findings "$tmp/f.json"
assert_eq "no temp file is left in the outbox" "findings.json
review.md" "$(ls -A "$ob")"

if [ "$fail" = 0 ]; then echo "review-outbox: all fixtures passed"; else echo "review-outbox: FAILURES" >&2; fi
exit "$fail"
