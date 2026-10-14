#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/spec-comment.sh: the anchored spec comment's
# checks (id, edit, issue, author trust), shared by resume, the coder and architect-review (#614).
#
# Runs the real gh-identity.sh beside the script over fixture project.yml files, so the trust
# word each case relies on is the one production produces. Needs yq (mikefarah v4); skips,
# loudly, when it is absent.
# Permitted toolset: POSIX sh.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/plugins/way-of-working/bin/spec-comment.sh"

if ! command -v yq >/dev/null 2>&1; then
  echo "SKIP - yq not on PATH; spec-comment.sh needs it" >&2
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok - $1"
  else
    echo "FAIL - $1: expected [$2], got [$3]" >&2
    fail=1
  fi
}

REPO=acme/backlog
ISSUE=614
CID=6176369440
UPD=2026-10-14T19:17:39Z

cat >"$tmp/map.yml" <<'EOF'
identities:
  maintainer:
    - { login: alice-dev, id: 1001 }
  dev_app: { login: "acme-dev[bot]", id: 2001 }
  reviewer_app: null
  loop_app: null
EOF
printf 'identities: null\n' >"$tmp/null.yml"

# mk <name> <login> <uid> <assoc> [body-json-string]: write $tmp/<name>.json, a comment on ISSUE.
mk() {
  b="${5:-"## Spec\\n\\nline two\\n"}"
  printf '{"id":%s,"updated_at":"%s","issue_url":"https://api.github.com/repos/%s/issues/%s","user":{"login":"%s","id":%s},"author_association":"%s","body":"%s"}' \
    "$CID" "$UPD" "$REPO" "$ISSUE" "$2" "$3" "$4" "$b" >"$tmp/$1.json"
}

# run <mode> <file> <yml> [id] [updated] [issue] [repo]: sets rc, out (stdout) and err (stderr).
run() {
  rc=0
  out="$(sh "$script" "$1" "$2" "${7:-$REPO}" "${6:-$ISSUE}" "${4:-$CID}" "${5:-$UPD}" "$3" 2>"$tmp/err")" || rc=$?
  err="$(cat "$tmp/err")"
}
expect_check() { # <desc> <word>
  assert_eq "$1 (check word)" "$2" "$out"
  assert_eq "$1 (check rc)" 0 "$rc"
}
expect_body_refused() { # <desc> <word>
  assert_eq "$1 (body stdout empty)" "" "$out"
  assert_eq "$1 (body stderr word)" "$2" "$err"
  assert_eq "$1 (body rc)" 1 "$rc"
}

# -- ok, and the body is printed exactly --------------------------------------------------
mk good alice-dev 1001 NONE
run check "$tmp/good.json" "$tmp/map.yml"
expect_check "maintainer under a map" ok
run body "$tmp/good.json" "$tmp/map.yml"
assert_eq "body: multi-line text, exactly" "$(printf '## Spec\n\nline two')" "$out"
assert_eq "body: rc 0" 0 "$rc"
assert_eq "body: nothing on stderr" "" "$err"

mk dash alice-dev 1001 NONE '- leading dash\n---\ntrue\n$(echo no)\n`x`'
run body "$tmp/dash.json" "$tmp/map.yml"
assert_eq "body: leading dash, rule line, shell metacharacters verbatim" \
  "$(printf '%s\n%s\n%s\n%s\n%s' '- leading dash' '---' 'true' '$(echo no)' '`x`')" "$out"

# -- the checks, in order --------------------------------------------------------------------
run check "$tmp/good.json" "$tmp/map.yml" 999
expect_check "different comment id" wrong-id
run body "$tmp/good.json" "$tmp/map.yml" 999
expect_body_refused "different comment id" wrong-id

run check "$tmp/good.json" "$tmp/map.yml" "$CID" 2026-10-14T19:17:40Z
expect_check "edited after the anchor" moved
run body "$tmp/good.json" "$tmp/map.yml" "$CID" 2026-10-14T19:17:40Z
expect_body_refused "edited after the anchor" moved

run check "$tmp/good.json" "$tmp/map.yml" "$CID" "$UPD" 615
expect_check "comment on another issue" wrong-issue
run body "$tmp/good.json" "$tmp/map.yml" "$CID" "$UPD" 615
expect_body_refused "comment on another issue" wrong-issue
run check "$tmp/good.json" "$tmp/map.yml" "$CID" "$UPD" "$ISSUE" acme/other
expect_check "comment in another repo" wrong-issue

# id is checked before moved, moved before issue: the first failing check names the word.
run check "$tmp/good.json" "$tmp/map.yml" 999 2026-10-14T19:17:40Z 615
expect_check "all three wrong names the id" wrong-id
run check "$tmp/good.json" "$tmp/map.yml" "$CID" 2026-10-14T19:17:40Z 615
expect_check "moved and wrong issue names moved" moved

# -- author trust ---------------------------------------------------------------------------------
mk dev 'acme-dev[bot]' 2001 NONE
run check "$tmp/dev.json" "$tmp/map.yml"
expect_check "the dev App wrote it, under a map" untrusted
run body "$tmp/dev.json" "$tmp/map.yml"
expect_body_refused "the dev App wrote it, under a map" untrusted

mk stranger stranger 9999 OWNER
run check "$tmp/stranger.json" "$tmp/map.yml"
expect_check "an undeclared account claiming OWNER, under a map" untrusted

mk rename alice-dev 1002 NONE
run check "$tmp/rename.json" "$tmp/map.yml"
expect_check "a declared login on another id, under a map" untrusted

mk contrib stranger 9999 CONTRIBUTOR
run check "$tmp/contrib.json" "$tmp/null.yml"
expect_check "CONTRIBUTOR under legacy" untrusted
run body "$tmp/contrib.json" "$tmp/null.yml"
expect_body_refused "CONTRIBUTOR under legacy" untrusted

for a in OWNER MEMBER COLLABORATOR; do
  mk "leg$a" someone 42 "$a"
  run check "$tmp/leg$a.json" "$tmp/null.yml"
  expect_check "$a under legacy" ok
done
mk none someone 42 NONE
run check "$tmp/none.json" "$tmp/null.yml"
expect_check "NONE under legacy" untrusted

# An unreadable identities in the default branch's copy is never a pass.
printf 'identities: [unclosed\n' >"$tmp/badyaml.yml"
run check "$tmp/good.json" "$tmp/badyaml.yml"
assert_eq "unparseable project.yml (stdout)" "" "$out"
assert_eq "unparseable project.yml (rc)" 2 "$rc"
printf 'repo: acme/x\n' >"$tmp/absent.yml"
run check "$tmp/good.json" "$tmp/absent.yml"
expect_check "no identities key (gh-identity.sh exits 2)" untrusted
printf 'identities: yes\n' >"$tmp/scalar.yml"
run body "$tmp/good.json" "$tmp/scalar.yml"
expect_body_refused "identities neither null nor a map" untrusted

# -- unreadable ----------------------------------------------------------------------------------
run check "$tmp/missing.json" "$tmp/map.yml"
expect_check "missing file" unreadable
run body "$tmp/missing.json" "$tmp/map.yml"
expect_body_refused "missing file" unreadable

printf 'not json at all' >"$tmp/text.json"
run check "$tmp/text.json" "$tmp/map.yml"
expect_check "not JSON" unreadable
: >"$tmp/empty.json"
run check "$tmp/empty.json" "$tmp/map.yml"
expect_check "empty file (a failed fetch redirected to a file)" unreadable
printf '[1,2]' >"$tmp/array.json"
run body "$tmp/array.json" "$tmp/map.yml"
expect_body_refused "a JSON array" unreadable

printf '{"id":%s,"updated_at":"%s","issue_url":"https://api.github.com/repos/%s/issues/%s","user":{"login":"alice-dev","id":1001},"author_association":"NONE"}' \
  "$CID" "$UPD" "$REPO" "$ISSUE" >"$tmp/nobody.json"
run check "$tmp/nobody.json" "$tmp/map.yml"
expect_check "no body field" unreadable
printf '{"id":%s,"updated_at":"%s","issue_url":"https://api.github.com/repos/%s/issues/%s","body":"x"}' \
  "$CID" "$UPD" "$REPO" "$ISSUE" >"$tmp/nouser.json"
run body "$tmp/nouser.json" "$tmp/map.yml"
expect_body_refused "no user field" unreadable
printf '{"id":"%s","updated_at":"%s","issue_url":"https://api.github.com/repos/%s/issues/%s","user":{"login":"alice-dev","id":1001},"body":"x"}' \
  "$CID" "$UPD" "$REPO" "$ISSUE" >"$tmp/strid.json"
run check "$tmp/strid.json" "$tmp/map.yml"
expect_check "a string id is not the comment id's type" unreadable
printf '{"id":%s,"updated_at":null,"issue_url":"https://api.github.com/repos/%s/issues/%s","user":{"login":"alice-dev","id":1001},"body":"x"}' \
  "$CID" "$REPO" "$ISSUE" >"$tmp/nullupd.json"
run check "$tmp/nullupd.json" "$tmp/map.yml"
expect_check "a null field" unreadable

# -- bad arguments -------------------------------------------------------------------------------
bad() { # <desc> <args...>
  d="$1"; shift
  rc=0
  out="$(sh "$script" "$@" 2>/dev/null)" || rc=$?
  assert_eq "$d (stdout)" "" "$out"
  assert_eq "$d (rc)" 2 "$rc"
}
G="$tmp/good.json"; Y="$tmp/map.yml"
bad "unknown mode" show "$G" $REPO $ISSUE $CID $UPD "$Y"
bad "too few arguments" check "$G" $REPO $ISSUE $CID $UPD
bad "too many arguments" check "$G" $REPO $ISSUE $CID $UPD "$Y" extra
bad "repo without a slash" check "$G" acme $ISSUE $CID $UPD "$Y"
bad "repo with two slashes" check "$G" acme/a/b $ISSUE $CID $UPD "$Y"
bad "repo with a space" check "$G" "acme/a b" $ISSUE $CID $UPD "$Y"
bad "issue not digits" check "$G" $REPO 61x $CID $UPD "$Y"
bad "empty issue" check "$G" $REPO "" $CID $UPD "$Y"
bad "comment id not digits" check "$G" $REPO $ISSUE '12;3' $UPD "$Y"
bad "malformed updated_at" check "$G" $REPO $ISSUE $CID 2026-10-14 "$Y"
bad "updated_at with a trailing newline" check "$G" $REPO $ISSUE $CID "$UPD
" "$Y"
bad "missing project.yml" check "$G" $REPO $ISSUE $CID $UPD "$tmp/none.yml"
bad "bad arguments in body mode too" body "$G" $REPO x $CID $UPD "$Y"

# -- never run from the cwd -------------------------------------------------------------------------
# A slash-less $0 could find a gh-identity.sh a branch under review planted in the cwd.
mkdir "$tmp/plant"
cp "$script" "$tmp/plant/spec-comment.sh"
printf '#!/bin/sh\necho trusted\n' >"$tmp/plant/gh-identity.sh"
rc=0
out="$(cd "$tmp/plant" && sh spec-comment.sh check "$tmp/dev.json" $REPO $ISSUE $CID $UPD "$tmp/map.yml" 2>/dev/null)" || rc=$?
assert_eq "slash-less invocation refuses (stdout)" "" "$out"
assert_eq "slash-less invocation refuses (rc)" 2 "$rc"

[ "$fail" -eq 0 ]
