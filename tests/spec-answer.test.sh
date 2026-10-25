#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/spec-answer.sh: the checked read of an escalated spec comment
# and the maintainer's answer to it (#790, WB-D39).
#
# Each case copies spec-answer.sh into its own fixture bin/ directory and runs it by path, beside the real
# gh-identity.sh and spec-fresh.sh. A stub `gh`, first on PATH and keyed on the path of the call, serves
# canned comment JSON and logs its argv. The stub plants a sentinel on its failure paths; no case's stdout or
# stderr may contain it.
# Needs yq (mikefarah v4) and jq; skips, loudly, without either.
# Permitted toolset: POSIX sh, plus jq, yq, awk, sed and grep as the cases need.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
bindir="$root_dir/plugins/way-of-working/bin"
script="$bindir/spec-answer.sh"

for tool in yq jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "SKIP - $tool not on PATH; spec-answer.test.sh needs it" >&2
    exit 0
  fi
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
assert_eq() { # <desc> <want> <got>
  if [ "$2" = "$3" ]; then
    echo "ok - $1"
  else
    echo "FAIL - $1: expected [$2], got [$3]" >&2
    fail=1
  fi
}

SENTINEL="SENTINEL-7c20d5aa"
SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
TE="2026-09-21T09:00:00Z"
TA="2026-09-21T09:10:00Z"
ISSUE=7
URL="https://api.github.com/repos/acme/app/issues/7"
EM="spec-task-escalated: issue=7 base=main sha=$SHA"
ESC_REST="
Spec for #7: an escalated draft.

### Goal

Do the thing.

### Files touched

- \`scripts/a.sh\`
  The change.

### Done when

- It works.

### Open findings

- finding one. Recommendation: do X."
CRc="$(printf '\r')"

fakebin="$tmp/fakebin"
mkdir -p "$fakebin"
cat >"$fakebin/gh" <<'FAKE_GH'
#!/bin/sh
printf '%s\n' "$*" >>"$FX_DIR/gh.log"
case "$*" in
  "api repos/acme/app/issues/comments/"*)
    id="${2##*/issues/comments/}"
    if [ -f "$FX_DIR/c/$id.json" ] && [ -z "${FX_FAIL:-}" ]; then
      cat "$FX_DIR/c/$id.json"
      exit 0
    fi
    echo "$FX_MARK gh failure text"
    echo "$FX_MARK gh failure text" >&2
    exit 1
    ;;
  *)
    echo "$FX_MARK gh failure text"
    echo "$FX_MARK gh failure text" >&2
    exit 1
    ;;
esac
FAKE_GH
chmod +x "$fakebin/gh"

cn=0
nc() {
  cn=$((cn + 1))
  cd_="$tmp/c$cn"
  mkdir -p "$cd_/bin" "$cd_/c"
  cp "$script" "$cd_/bin/spec-answer.sh"
  cp "$bindir/gh-identity.sh" "$bindir/spec-fresh.sh" "$bindir/declared-ids.sh" "$cd_/bin/"
  : >"$cd_/gh.log"
  cat >"$cd_/project.yml" <<'YML'
repo: acme/app
pr_base: main
backlog:
  repo: null
identities:
  maintainer:
    - {login: maint1, id: 101}
    - {login: maint2, id: 102}
  dev_app: {login: "dev-app[bot]", id: 201}
  reviewer_app: {login: "rev-app[bot]", id: 202}
  loop_app: {login: "loop-app[bot]", id: 203}
YML
  # defaults: a dev-App escalated comment 1001 and a maintainer's apply answer 1002
  mk 1001 "$TE" "$TE" "$URL" "dev-app[bot]" 201 "$EM$ESC_REST"
  mk 1002 "$TA" "$TA" "$URL" maint1 101 "spec-task-answer: escalated=1001 choice=apply"
}
# mk <id> <updated> <created> <url> <login> <uid> <body>
mk() {
  jq -n --argjson id "$1" --arg up "$2" --arg cr "$3" --arg url "$4" --arg login "$5" --argjson uid "$6" --arg body "$7" \
    '{id: $id, updated_at: $up, created_at: $cr, issue_url: $url, user: {login: $login, id: $uid}, body: $body}' >"$cd_/c/$1.json"
}

# run <mode> [esc-up] [ans-up]
run() {
  rc=0
  out="$(PATH="$fakebin:$PATH" FX_DIR="$cd_" FX_MARK="$SENTINEL" sh "$cd_/bin/spec-answer.sh" "$1" "$ISSUE" "$cd_/project.yml" 1001 "${2:-$TE}" 1002 "${3:-$TA}" 2>"$cd_/err" </dev/null)" || rc=$?
  err="$(cat "$cd_/err")"
}
expect() { # <desc> <want-stdout> [want-rc]
  assert_eq "$1" "$2|${3:-0}" "$out|$rc"
  case "$out$err" in
    *"$SENTINEL"*) echo "FAIL - $1: the sentinel reached an output stream" >&2; fail=1 ;;
  esac
}
refused() { # <desc>
  run check
  expect "$1" refused
}

# --- ok ---
nc; run check
expect "check: an apply answer to a dev-App escalated comment" "ok apply"

nc; mk 1002 "$TA" "$TA" "$URL" maint2 102 "spec-task-answer: escalated=1001 choice=amend
change this"; run check
expect "check: an amend answer" "ok amend"

nc; mk 1001 "$TE" "$TE" "$URL" maint1 101 "$EM$ESC_REST"; run check
expect "check: a maintainer-authored escalated comment" "ok apply"

nc
body="$(printf '%s\r\n' "$EM" "" "Spec for #7." "" "### Goal" "" "Do." "" "### Files touched" "" '- `scripts/a.sh`' "" "### Done when" "" "- It works.")"
mk 1001 "$TE" "$TE" "$URL" "dev-app[bot]" 201 "$body"
mk 1002 "$TA" "$TA" "$URL" maint1 101 "$(printf 'spec-task-answer: escalated=1001 choice=amend\r\nchange one\r\n')"
run check
expect "check: CRLF bodies pass" "ok amend"

# --- moved ---
nc; run check "2026-09-21T09:00:01Z"
expect "moved: the escalated comment's updated_at differs" moved
nc; run check "$TE" "2026-09-21T09:10:01Z"
expect "moved: the answer's updated_at differs" moved
nc; mk 1002 "$TA" "$TA" "$URL" maint1 101 "spec-task-answer: escalated=1001 choice=apply"
sed 's/"id": 1002/"id": 1003/' "$cd_/c/1002.json" >"$cd_/c/x.json" && mv "$cd_/c/x.json" "$cd_/c/1002.json"; run check
expect "moved: the answer's id differs" moved

# --- refused, one condition each ---
nc; mk 1001 "$TE" "$TE" "https://api.github.com/repos/acme/app/issues/8" "dev-app[bot]" 201 "$EM$ESC_REST"; refused "refused: the escalated comment is on another issue"
nc; mk 1001 "$TE" "$TE" "$URL" "dev-app[bot]" 201 "spec-task: issue=7 base=main sha=$SHA$ESC_REST"; refused "refused: the escalated comment carries the spec-task marker"
nc; mk 1001 "$TE" "$TE" "$URL" "dev-app[bot]" 201 "spec-task-escalated: issue=8 base=main sha=$SHA$ESC_REST"; refused "refused: the escalated marker names another issue"
nc; mk 1001 "$TE" "$TE" "$URL" "dev-app[bot]" 201 "spec-task-escalated: issue=7 base=other sha=$SHA$ESC_REST"; refused "refused: the escalated marker names another base"
nc; mk 1001 "$TE" "$TE" "$URL" "dev-app[bot]" 201 "spec-task-escalated: issue=7 base=main sha=${SHA}0$ESC_REST"; refused "refused: a 41-character sha"
nc; mk 1001 "$TE" "$TE" "$URL" outsider 555 "$EM$ESC_REST"; refused "refused: the escalated author is undeclared"
nc; mk 1001 "$TE" "$TE" "$URL" "rev-app[bot]" 202 "$EM$ESC_REST"; refused "refused: the escalated author is the reviewer App"
nc; mk 1001 "$TE" "$TE" "$URL" "dev-app[bot]" 201 "$EM

### Goal

Do.

### Files touched

- \`scripts/a.sh\`

### Done when

- It works. A hidden$(printf '\342\200\213')character."; refused "refused: hidden text in the escalated body"
nc; mk 1001 "$TE" "$TE" "$URL" "dev-app[bot]" 201 "$EM
no sections here"; refused "refused: an escalated body the shape check cannot read"
nc; mk 1002 "$TA" "$TA" "https://api.github.com/repos/acme/app/issues/8" maint1 101 "spec-task-answer: escalated=1001 choice=apply"; refused "refused: the answer is on another issue"
nc; mk 1002 "$TA" "$TA" "$URL" maint1 101 "spec-task-answer: escalated=1001 choice=other"; refused "refused: an unknown choice"
nc; mk 1002 "$TA" "$TA" "$URL" maint1 101 "spec-task-answer: escalated=1001 choice=apply "; refused "refused: a trailing space on the answer line"
nc; mk 1002 "$TA" "$TA" "$URL" maint1 101 "spec-task-answer: escalated=1005 choice=apply"; refused "refused: the answer names another escalated id"
nc; mk 1002 "$TA" "$TA" "$URL" maint1 101 "intro
spec-task-answer: escalated=1001 choice=apply"; refused "refused: the answer line is not first"
nc; mk 1002 "$TA" "$TA" "$URL" "dev-app[bot]" 201 "spec-task-answer: escalated=1001 choice=apply"; refused "refused: the answer is by the dev App"
nc; mk 1002 "$TA" "$TA" "$URL" outsider 555 "spec-task-answer: escalated=1001 choice=apply"; refused "refused: the answer is by an undeclared id"
nc; mk 1002 "$TA" "$TA" "$URL" other-login 101 "spec-task-answer: escalated=1001 choice=apply"; refused "refused: the answer's login does not match role"
nc; mk 1002 "$TA" "2026-09-21T09:09:00Z" "$URL" maint1 101 "spec-task-answer: escalated=1001 choice=apply"; refused "refused: the answer was edited (created_at not updated_at)"
nc; mk 1002 "$TE" "$TE" "$URL" maint1 101 "spec-task-answer: escalated=1001 choice=apply"; run check "$TE" "$TE"
expect "refused: the answer was created in the same second as the escalated comment's last edit" refused

# --- unreadable ---
nc; FX_FAIL=1; export FX_FAIL; run check; unset FX_FAIL
expect "unreadable: a failed fetch" unreadable
nc; printf 'not json' >"$cd_/c/1001.json"; run check
expect "unreadable: bad JSON" unreadable
nc; rm "$cd_/c/1002.json"; run check
expect "unreadable: the answer cannot be fetched" unreadable
nc; jq -n '{id: 1001, updated_at: "'"$TE"'", created_at: "'"$TE"'", issue_url: "'"$URL"'", user: {login: "x", id: 201}, body: null}' >"$cd_/c/1001.json"; run check
expect "unreadable: a null body" unreadable
nc; printf 'repo: acme/app\npr_base: main\nidentities: null\n' >"$cd_/project.yml"; run check
expect "unreadable: a bad config (identities null)" unreadable
nc; sed 's/id: 203/id: 101/' "$cd_/project.yml" >"$cd_/p2" && mv "$cd_/p2" "$cd_/project.yml"; run check
expect "unreadable: a declared App's id on the maintainer list" unreadable

# --- escalated and changes ---
nc; run escalated
expect "escalated: prints the body after a pass" "$EM$ESC_REST"
nc; mk 1002 "$TA" "$TA" "$URL" outsider 555 "spec-task-answer: escalated=1001 choice=apply"; run escalated
assert_eq "escalated: prints nothing on stdout when a check fails" "|1" "$out|$rc"
assert_eq "escalated: names the word on stderr" "refused" "$err"
nc; run changes
expect "changes: prints nothing under apply" ""
nc; mk 1002 "$TA" "$TA" "$URL" maint1 101 "$(printf 'spec-task-answer: escalated=1001 choice=amend\r\nline one\r\n\r\nline three')"; run changes
expect "changes: prints the lines after the first under amend, CR removed" "line one

line three"
nc; mk 1002 "$TA" "$TA" "$URL" maint1 101 "spec-task-answer: escalated=1001 choice=amend
$SENTINEL"; run check
expect "check: a sentinel in the answer's change lines does not reach check" "ok amend"
nc; mk 1002 "$TA" "$TA" "$URL" outsider 555 "spec-task-answer: escalated=1001 choice=amend
change"; run changes
assert_eq "changes: prints nothing and exits 1 when a check fails" "|1" "$out|$rc"

# --- the gh log ---
nc; run check
assert_eq "gh: exactly two reads, escalated first, no listing" "api repos/acme/app/issues/comments/1001
api repos/acme/app/issues/comments/1002" "$(cat "$cd_/gh.log")"

# --- exit 2, no gh call ---
nc
rc=0; out="$(PATH="$fakebin:$PATH" FX_DIR="$cd_" sh "$cd_/bin/spec-answer.sh" check 7 2>/dev/null)" || rc=$?
expect "exit 2: a wrong argument count" "" 2
rc=0; out="$(PATH="$fakebin:$PATH" FX_DIR="$cd_" sh "$cd_/bin/spec-answer.sh" show 7 "$cd_/project.yml" 1001 "$TE" 1002 "$TA" 2>/dev/null)" || rc=$?
expect "exit 2: an unknown mode" "" 2
rc=0; out="$(PATH="$fakebin:$PATH" FX_DIR="$cd_" sh "$cd_/bin/spec-answer.sh" check 07 "$cd_/project.yml" 1001 "$TE" 1002 "$TA" 2>/dev/null)" || rc=$?
expect "exit 2: an issue with a leading zero" "" 2
rc=0; out="$(PATH="$fakebin:$PATH" FX_DIR="$cd_" sh "$cd_/bin/spec-answer.sh" check 7 "$cd_/project.yml" 1001 "bad" 1002 "$TA" 2>/dev/null)" || rc=$?
expect "exit 2: a malformed updated_at" "" 2
rc=0; out="$(PATH="$fakebin:$PATH" FX_DIR="$cd_" sh "$cd_/bin/spec-answer.sh" check 7 "$cd_/none.yml" 1001 "$TE" 1002 "$TA" 2>/dev/null)" || rc=$?
expect "exit 2: a missing project file" "" 2
rc=0; out="$(cd "$cd_/bin" && PATH="$fakebin:$PATH" FX_DIR="$cd_" sh spec-answer.sh check 7 ../project.yml 1001 "$TE" 1002 "$TA" 2>/dev/null)" || rc=$?
expect "exit 2: a slash-less \$0" "" 2
rm "$cd_/bin/gh-identity.sh"; run check
expect "exit 2: a missing gh-identity.sh" "" 2
cp "$bindir/gh-identity.sh" "$cd_/bin/"; rm "$cd_/bin/spec-fresh.sh"; run check
expect "exit 2: a missing spec-fresh.sh" "" 2
assert_eq "exit 2: no gh call was made in this fixture" "" "$(cat "$cd_/gh.log")"
cp "$bindir/spec-fresh.sh" "$cd_/bin/"; rm "$cd_/bin/declared-ids.sh"; run check
expect "exit 2: a missing declared-ids.sh" "" 2
assert_eq "exit 2: no gh call was made without declared-ids.sh" "" "$(cat "$cd_/gh.log")"

# A helper that fails or misprints gives the script's own word (#1079). Each stub gets its own fixture.
for stub in 'exit 2' 'exit 1' 'echo unreadable' 'echo "ok 101"' 'echo "ok 101 - "' 'echo "ok 101 -  "' 'echo "ok  - "' 'echo "ok 101 02001"' 'echo "ok 101 x"' 'echo "ok 101 - -"' 'printf "ok 101 -\\nok 101 -\\n"' ': # no output'; do
  nc
  printf '#!/bin/sh\n%s\n' "$stub" >"$cd_/bin/declared-ids.sh"
  run check
  expect "unreadable: a helper stub that does [$stub]" unreadable
done

[ "$fail" -eq 0 ]
