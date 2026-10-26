#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/spec-comment.sh: the spec comment's
# checks (id, edit, issue, author trust, a declared author's fresh maintainer reaction, and any declared App's id off the maintainer list for a maintainer author too), shared by
# resume, the coder and architect-review (#614, #660).
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
cat >"$tmp/apps.yml" <<'EOF'
identities:
  maintainer:
    - { login: alice-dev, id: 1001 }
  dev_app: { login: "acme-dev[bot]", id: 2001 }
  reviewer_app: { login: "acme-review[bot]", id: 2002 }
  loop_app: { login: "acme-loop[bot]", id: 2003 }
EOF
printf 'identities: null\n' >"$tmp/null.yml"

# mk <name> <login> <uid> <assoc> [body-json-string]: write $tmp/<name>.json, a comment on ISSUE.
mk() {
  b="${5:-"## Spec\\n\\nline two\\n"}"
  printf '{"id":%s,"updated_at":"%s","issue_url":"https://api.github.com/repos/%s/issues/%s","user":{"login":"%s","id":%s},"author_association":"%s","body":"%s"}' \
    "$CID" "$UPD" "$REPO" "$ISSUE" "$2" "$3" "$4" "$b" >"$tmp/$1.json"
}

# run <mode> <file> <yml> [id] [updated] [issue] [repo] [reactions]: sets rc, out (stdout) and err (stderr).
run() {
  rc=0
  out="$(sh "$script" "$1" "$2" "${7:-$REPO}" "${6:-$ISSUE}" "${4:-$CID}" "${5:-$UPD}" "$3" ${8:+"$8"} 2>"$tmp/err")" || rc=$?
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

# Under a map every declared author needs a declared maintainer's reaction strictly after the
# last edit (WB-D30). rx <name> <rows...>: write $tmp/<name>.tsv, one TAB-separated row each.
rx() { n="$1"; shift; : >"$tmp/$n.tsv"; for r in "$@"; do printf '%s\n' "$r" >>"$tmp/$n.tsv"; done; }
T="$(printf '\t')"
rx fresh "1001${T}heart${T}2026-10-14T19:20:00Z"
rx own "2001${T}heart${T}2026-10-14T19:20:00Z"
rx stale "1001${T}heart${T}2026-10-14T19:17:38Z"
rx equal "1001${T}heart${T}$UPD"
rx wrongkind "1001${T}eyes${T}2026-10-14T19:20:00Z"
: >"$tmp/emptyrx.tsv"

# -- ok, and the body is printed exactly --------------------------------------------------
mk good alice-dev 1001 NONE
run check "$tmp/good.json" "$tmp/map.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/fresh.tsv"
expect_check "maintainer under a map" ok
run body "$tmp/good.json" "$tmp/map.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/fresh.tsv"
assert_eq "body: multi-line text, exactly" "$(printf '## Spec\n\nline two')" "$out"
assert_eq "body: rc 0" 0 "$rc"
assert_eq "body: nothing on stderr" "" "$err"

mk dash alice-dev 1001 NONE '- leading dash\n---\ntrue\n$(echo no)\n`x`'
run body "$tmp/dash.json" "$tmp/map.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/fresh.tsv"
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
# The dev App may author, but only with a declared maintainer's reaction strictly after the
# last edit (#660). rx <name> <rows...>: write $tmp/<name>.tsv, one TAB-separated row each.

mk dev 'acme-dev[bot]' 2001 NONE
run check "$tmp/dev.json" "$tmp/map.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/fresh.tsv"
expect_check "the dev App wrote it, fresh maintainer reaction" ok
run body "$tmp/dev.json" "$tmp/map.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/fresh.tsv"
assert_eq "dev App with a reaction: body printed" "$(printf '## Spec\n\nline two')" "$out"
assert_eq "dev App with a reaction: rc 0" 0 "$rc"
for r in none: empty:"$tmp/emptyrx.tsv" own:"$tmp/own.tsv" stale:"$tmp/stale.tsv" equal:"$tmp/equal.tsv" wrongkind:"$tmp/wrongkind.tsv" missing:"$tmp/nofile.tsv"; do
  name="${r%%:*}" f="${r#*:}"
  run check "$tmp/dev.json" "$tmp/map.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$f"
  expect_check "the dev App wrote it, reactions: $name" unreacted
  run body "$tmp/dev.json" "$tmp/map.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$f"
  expect_body_refused "the dev App wrote it, reactions: $name" unreacted
done
# unreacted comes after the earlier checks.
run check "$tmp/dev.json" "$tmp/map.yml" "$CID" 2026-10-14T19:17:40Z "$ISSUE" "$REPO" "$tmp/fresh.tsv"
expect_check "dev App edited after the anchor, fresh reaction" moved
# Maintainer ids unusable in the file: unreacted, never ok.
printf 'identities:\n  maintainer:\n    - { login: alice-dev, id: "1001" }\n  dev_app: { login: "acme-dev[bot]", id: 2001 }\n' >"$tmp/strid.yml"
run check "$tmp/dev.json" "$tmp/strid.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/fresh.tsv"
expect_check "maintainer id not an int" unreacted
printf 'identities:\n  maintainer:\n    - { login: alice-dev, id: 1001 }\n    - { login: bob, id: x }\n  dev_app: { login: "acme-dev[bot]", id: 2001 }\n' >"$tmp/mixid.yml"
run check "$tmp/dev.json" "$tmp/mixid.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/fresh.tsv"
expect_check "one maintainer id not an int" unreacted
# A malformed maintainer entry naming the dev App's id must not let the dev App approve itself.
printf 'identities:\n  maintainer:\n    - { login: alice-dev, id: 1001 }\n    - { id: 2001 }\n  dev_app: { login: "acme-dev[bot]", id: 2001 }\n' >"$tmp/selfapp.yml"
run check "$tmp/dev.json" "$tmp/selfapp.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/own.tsv"
expect_check "dev App id on a malformed maintainer entry, own reaction" unreacted
printf 'identities:\n  maintainer:\n    - { login: alice-dev, id: 1001 }\n    - { login: "acme-dev[bot]", id: 2001 }\n  dev_app: { login: "acme-dev[bot]", id: 2001 }\n' >"$tmp/dupapp.yml"
run check "$tmp/dev.json" "$tmp/dupapp.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/own.tsv"
expect_check "dev App id also declared a maintainer" untrusted

# The dev App's id on the maintainer list refuses a MAINTAINER author's comment too: the dev App
# has Issues write and could edit it, then approve the edited text (#689).
mk maint alice-dev 1001 NONE
printf 'identities:\n  maintainer:\n    - { login: alice-dev, id: 1001 }\n    - { login: devdup, id: 2001 }\n  dev_app: { login: "acme-dev[bot]", id: 2001 }\n' >"$tmp/dupother.yml"
for c in dupother:dupother dupapp:dupapp; do
  cname="${c%%:*}" cyml="$tmp/${c#*:}.yml"
  run check "$tmp/maint.json" "$cyml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/own.tsv"
  expect_check "maintainer author, dev App id on the list ($cname), dev App reaction" unreacted
  run body "$tmp/maint.json" "$cyml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/own.tsv"
  expect_body_refused "maintainer author, dev App id on the list ($cname), dev App reaction" unreacted
  run check "$tmp/maint.json" "$cyml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/fresh.tsv"
  expect_check "maintainer author, dev App id on the list ($cname), maintainer reaction" unreacted
done
# A non-canonical maintainer id beside a canonical author (#1131): gh-identity.sh refuses the file
# before declared-ids.sh runs, so untrusted, not unreacted.
printf 'identities:\n  maintainer:\n    - { login: alice-dev, id: 1001 }\n    - { login: bob, id: 0x3E9 }\n  dev_app: { login: "acme-dev[bot]", id: 2001 }\n' >"$tmp/noncanonmaint.yml"
run check "$tmp/maint.json" "$tmp/noncanonmaint.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/fresh.tsv"
expect_check "maintainer author, a second maintainer id spelled 0x3E9" untrusted
# A dev_app entry that is neither null nor well formed refuses a maintainer author's comment.
for v in 'string:dev_app: acme' 'strid:dev_app: { login: "acme-dev[bot]", id: "2001" }' 'nologin:dev_app: { id: 2001 }'; do
  vname="${v%%:*}"
  printf 'identities:\n  maintainer:\n    - { login: alice-dev, id: 1001 }\n  %s\n' "${v#*:}" >"$tmp/baddev.yml"
  run check "$tmp/maint.json" "$tmp/baddev.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/fresh.tsv"
  expect_check "maintainer author, malformed dev_app ($vname)" unreacted
done
# A non-decimal spelling of the dev App's id must not slip past the comparison with 2001:
# gh-identity.sh role refuses any id not in canonical decimal, under any role, as untrusted (#1130).
for s in +2001 0x7D1 02001; do
  printf 'identities:\n  maintainer:\n    - { login: alice-dev, id: 1001 }\n    - { login: devdup, id: 2001 }\n  dev_app: { login: "acme-dev[bot]", id: %s }\n' "$s" >"$tmp/spell.yml"
  run check "$tmp/maint.json" "$tmp/spell.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/own.tsv"
  expect_check "maintainer author, dev App id spelled $s, dev App reaction" untrusted
done
# The dev App as the author, with its own id spelled non-canonically: gh-identity.sh refuses the
# file (exit 2), so it reads untrusted before this check runs.
mk devself 'acme-dev[bot]' 2001 NONE
for s in +2001 0x7D1; do
  printf 'identities:\n  maintainer:\n    - { login: alice-dev, id: 1001 }\n    - { login: "acme-dev[bot]", id: 2001 }\n  dev_app: { login: "acme-dev[bot]", id: %s }\n' "$s" >"$tmp/spellself.yml"
  run check "$tmp/devself.json" "$tmp/spellself.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/own.tsv"
  expect_check "dev App author, own id spelled $s, own reaction" untrusted
done
# No dev App (null or absent), or one whose id is not on the list, leaves a maintainer approved.
printf 'identities:\n  maintainer:\n    - { login: alice-dev, id: 1001 }\n  dev_app: null\n' >"$tmp/nulldev.yml"
run check "$tmp/maint.json" "$tmp/nulldev.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/fresh.tsv"
expect_check "maintainer author, dev_app null" ok
printf 'identities:\n  maintainer:\n    - { login: alice-dev, id: 1001 }\n' >"$tmp/nokey.yml"
run check "$tmp/maint.json" "$tmp/nokey.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/fresh.tsv"
expect_check "maintainer author, dev_app key absent" ok
run check "$tmp/maint.json" "$tmp/map.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/fresh.tsv"
expect_check "maintainer author, dev App id not on the list" ok

# Every declared App is off the maintainer list, not only the dev App (#708): the reviewer App has
# Issues write too, and the loop App is treated as the same class. rx rev/loop own reactions.
rx ownrev "2002${T}heart${T}2026-10-14T19:20:00Z"
rx ownloop "2003${T}heart${T}2026-10-14T19:20:00Z"
for kk in reviewer_app:acme-review:2002:ownrev loop_app:acme-loop:2003:ownloop; do
  key="${kk%%:*}"; rest="${kk#*:}"; alog="${rest%%:*}[bot]"; rest="${rest#*:}"; aid="${rest%%:*}"; arx="${rest#*:}"
  for author in maint dev; do
      printf 'identities:\n  maintainer:\n    - { login: alice-dev, id: 1001 }\n    - { login: devdup, id: %s }\n  dev_app: { login: "acme-dev[bot]", id: 2001 }\n  %s: { login: "%s", id: %s }\n' "$aid" "$key" "$alog" "$aid" >"$tmp/appdup.yml"
      for r in "$arx" fresh; do
        run check "$tmp/$author.json" "$tmp/appdup.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/$r.tsv"
        expect_check "$author author, $key id on the list, reactions $r" unreacted
        run body "$tmp/$author.json" "$tmp/appdup.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/$r.tsv"
        expect_body_refused "$author author, $key id on the list, reactions $r" unreacted
      done
    for s in +"$aid" "$(printf '0x%X' "$aid")" 0"$aid"; do
      printf 'identities:\n  maintainer:\n    - { login: alice-dev, id: 1001 }\n    - { login: devdup, id: %s }\n  dev_app: { login: "acme-dev[bot]", id: 2001 }\n  %s: { login: "%s", id: %s }\n' "$aid" "$key" "$alog" "$s" >"$tmp/appspell.yml"
      run check "$tmp/$author.json" "$tmp/appspell.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/fresh.tsv"
      expect_check "$author author, $key id spelled $s, maintainer reaction" untrusted
    done
    for v in 'string:acme' 'strid:{ login: "x[bot]", id: "2002" }' 'nologin:{ id: 2002 }'; do
      vname="${v%%:*}"
      printf 'identities:\n  maintainer:\n    - { login: alice-dev, id: 1001 }\n  dev_app: { login: "acme-dev[bot]", id: 2001 }\n  %s: %s\n' "$key" "${v#*:}" >"$tmp/appbad.yml"
      run check "$tmp/$author.json" "$tmp/appbad.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/fresh.tsv"
      expect_check "$author author, malformed $key ($vname)" unreacted
    done
    printf 'identities:\n  maintainer:\n    - { login: alice-dev, id: 1001 }\n  dev_app: { login: "acme-dev[bot]", id: 2001 }\n  %s: null\n' "$key" >"$tmp/appnull.yml"
    run check "$tmp/$author.json" "$tmp/appnull.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/fresh.tsv"
    expect_check "$author author, $key null" ok
    run check "$tmp/$author.json" "$tmp/apps.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/fresh.tsv"
    expect_check "$author author, $key well formed and off the list" ok
  done
  run check "$tmp/maint.json" "$tmp/nokey.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/fresh.tsv"
  expect_check "maintainer author, $key key missing" ok
done
# The reviewer App as the author, its own id spelled non-canonically under reviewer_app and listed
# canonically as a maintainer under its own login: gh-identity.sh refuses the file, so untrusted.
mk revself 'acme-review[bot]' 2002 NONE
for s in +2002 0x7D2; do
  printf 'identities:\n  maintainer:\n    - { login: alice-dev, id: 1001 }\n    - { login: "acme-review[bot]", id: 2002 }\n  reviewer_app: { login: "acme-review[bot]", id: %s }\n' "$s" >"$tmp/spellrev.yml"
  run check "$tmp/revself.json" "$tmp/spellrev.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/ownrev.tsv"
  expect_check "reviewer App author, own id spelled $s, own reaction" untrusted
  run body "$tmp/revself.json" "$tmp/spellrev.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/ownrev.tsv"
  expect_body_refused "reviewer App author, own id spelled $s, own reaction" untrusted
done

# A maintainer's word depends on the reactions argument too (WB-D30): any declared maintainer's
# fresh approving reaction, their own included, and nothing else.
run check "$tmp/good.json" "$tmp/map.yml"
expect_check "maintainer, no reactions file" unreacted
run check "$tmp/good.json" "$tmp/map.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/emptyrx.tsv"
expect_check "maintainer, empty reactions file" unreacted
run check "$tmp/good.json" "$tmp/map.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/nofile.tsv"
expect_check "maintainer, missing reactions file" unreacted
run check "$tmp/good.json" "$tmp/map.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/stale.tsv"
expect_check "maintainer, stale reaction" unreacted
run check "$tmp/good.json" "$tmp/map.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/wrongkind.tsv"
expect_check "maintainer, a reaction that does not approve" unreacted
run check "$tmp/good.json" "$tmp/map.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/own.tsv"
expect_check "maintainer, only the dev App reacted" unreacted
run body "$tmp/good.json" "$tmp/map.yml"
expect_body_refused "maintainer, no reactions file" unreacted
# Their own fresh reaction approves a maintainer's comment; so does another maintainer's.
run check "$tmp/good.json" "$tmp/map.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/fresh.tsv"
expect_check "maintainer, their own fresh reaction" ok
printf 'identities:\n  maintainer:\n    - { login: alice-dev, id: 1001 }\n    - { login: bob-dev, id: 1002 }\n  dev_app: { login: "acme-dev[bot]", id: 2001 }\n' >"$tmp/two.yml"
rx bobs "1002${T}rocket${T}2026-10-14T19:20:00Z"
run check "$tmp/good.json" "$tmp/two.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/bobs.tsv"
expect_check "maintainer, another maintainer's fresh reaction" ok

# The dev App's login on another id, or its id under another login, is no dev App.
mk devlogin 'acme-dev[bot]' 2099 NONE
run check "$tmp/devlogin.json" "$tmp/map.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/fresh.tsv"
expect_check "the dev App's login on another id" untrusted
mk devid other-bot 2001 NONE
run check "$tmp/devid.json" "$tmp/map.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/fresh.tsv"
expect_check "the dev App's id under another login" untrusted

# The reviewer and loop Apps stay untrusted, reactions or not.
mk rev 'acme-review[bot]' 2002 NONE
run check "$tmp/rev.json" "$tmp/apps.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/fresh.tsv"
expect_check "the reviewer App wrote it" untrusted
mk loop 'acme-loop[bot]' 2003 NONE
run body "$tmp/loop.json" "$tmp/apps.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/fresh.tsv"
expect_body_refused "the loop App wrote it" untrusted

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
bad "too many arguments" check "$G" $REPO $ISSUE $CID $UPD "$Y" "$tmp/fresh.tsv" extra
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
printf '#!/bin/sh\necho dev_app\n' >"$tmp/plant/gh-identity.sh"
printf '#!/bin/sh\necho approved\n' >"$tmp/plant/spec-reaction.sh"
rc=0
out="$(cd "$tmp/plant" && sh spec-comment.sh check "$tmp/dev.json" $REPO $ISSUE $CID $UPD "$tmp/map.yml" 2>/dev/null)" || rc=$?
assert_eq "slash-less invocation refuses (stdout)" "" "$out"
assert_eq "slash-less invocation refuses (rc)" 2 "$rc"

# -- siblings ---------------------------------------------------------------------------------------
# A missing spec-reaction.sh is exit 2 with nothing on stdout for a dev-App author, never
# `unreacted`; under a map a maintainer's word depends on it too (WB-D30).
sib="$tmp/sib"
mkdir "$sib"
cp "$script" "$sib/spec-comment.sh"
cp "$(dirname "$script")/gh-identity.sh" "$sib/gh-identity.sh"
cp "$(dirname "$script")/declared-ids.sh" "$sib/declared-ids.sh"
for m in check body; do
  rc=0
  out="$(sh "$sib/spec-comment.sh" $m "$tmp/dev.json" $REPO $ISSUE $CID $UPD "$tmp/map.yml" "$tmp/fresh.tsv" 2>/dev/null)" || rc=$?
  assert_eq "no spec-reaction.sh, dev App, $m (stdout)" "" "$out"
  assert_eq "no spec-reaction.sh, dev App, $m (rc)" 2 "$rc"
done
rc=0
out="$(sh "$sib/spec-comment.sh" check "$tmp/good.json" $REPO $ISSUE $CID $UPD "$tmp/map.yml" "$tmp/fresh.tsv" 2>/dev/null)" || rc=$?
assert_eq "no spec-reaction.sh, maintainer (stdout)" "" "$out"
assert_eq "no spec-reaction.sh, maintainer (rc)" 2 "$rc"
# A legacy author needs neither the reactions nor the sibling.
mk owner stranger 9999 OWNER
rc=0
out="$(sh "$sib/spec-comment.sh" check "$tmp/owner.json" $REPO $ISSUE $CID $UPD "$tmp/null.yml" 2>/dev/null)" || rc=$?
assert_eq "no spec-reaction.sh, legacy OWNER (stdout)" ok "$out"
assert_eq "no spec-reaction.sh, legacy OWNER (rc)" 0 "$rc"

# A spec-reaction.sh that exits 2 (a bad argument) is `unreacted`; the sibling's word decides.
printf '#!/bin/sh\nexit 2\n' >"$sib/spec-reaction.sh"
rc=0
out="$(sh "$sib/spec-comment.sh" check "$tmp/dev.json" $REPO $ISSUE $CID $UPD "$tmp/map.yml" "$tmp/fresh.tsv" 2>/dev/null)" || rc=$?
assert_eq "spec-reaction.sh exiting 2 is unreacted (stdout)" unreacted "$out"
assert_eq "spec-reaction.sh exiting 2 is unreacted (rc)" 0 "$rc"
printf '#!/bin/sh\necho approved\n' >"$sib/spec-reaction.sh"
out="$(sh "$sib/spec-comment.sh" check "$tmp/dev.json" $REPO $ISSUE $CID $UPD "$tmp/map.yml" "$tmp/own.tsv" 2>/dev/null)"
assert_eq "the sibling's approved decides, not this script" ok "$out"

# A missing declared-ids.sh (#1079) is exit 2 with nothing on stdout for a declared author, the same as a
# missing spec-reaction.sh; a legacy author's word never depends on it.
nodi="$tmp/nodi"
mkdir "$nodi"
cp "$script" "$nodi/spec-comment.sh"
cp "$(dirname "$script")/gh-identity.sh" "$nodi/gh-identity.sh"
printf '#!/bin/sh\necho approved\n' >"$nodi/spec-reaction.sh"
for a in dev good; do
  rc=0
  out="$(sh "$nodi/spec-comment.sh" check "$tmp/$a.json" $REPO $ISSUE $CID $UPD "$tmp/map.yml" "$tmp/fresh.tsv" 2>/dev/null)" || rc=$?
  assert_eq "no declared-ids.sh, $a author (stdout)" "" "$out"
  assert_eq "no declared-ids.sh, $a author (rc)" 2 "$rc"
done
rc=0
out="$(sh "$nodi/spec-comment.sh" check "$tmp/owner.json" $REPO $ISSUE $CID $UPD "$tmp/null.yml" 2>/dev/null)" || rc=$?
assert_eq "no declared-ids.sh, legacy OWNER (stdout)" ok "$out"
assert_eq "no declared-ids.sh, legacy OWNER (rc)" 0 "$rc"

# A helper that fails or misprints is `unreacted`, never exit 2 and never ok. Each stub gets its own directory.
si=0
for stub in 'exit 2' 'exit 1' 'echo unreadable' 'echo "ok 101"' 'echo "ok 101 - "' 'echo "ok 101 -  "' 'echo "ok  - "' 'echo "ok 101 02001"' 'echo "ok 101 x"' 'echo "ok 101 - -"' 'printf "ok 101 -\\nok 101 -\\n"' ': # no output'; do
  si=$((si + 1))
  d="$tmp/stub$si"
  mkdir "$d"
  cp "$script" "$d/spec-comment.sh"
  cp "$(dirname "$script")/gh-identity.sh" "$d/gh-identity.sh"
  printf '#!/bin/sh\necho approved\n' >"$d/spec-reaction.sh"
  printf '#!/bin/sh\n%s\n' "$stub" >"$d/declared-ids.sh"
  for a in dev good; do
    rc=0
    out="$(sh "$d/spec-comment.sh" check "$tmp/$a.json" $REPO $ISSUE $CID $UPD "$tmp/map.yml" "$tmp/fresh.tsv" 2>/dev/null)" || rc=$?
    assert_eq "helper stub [$stub], $a author (stdout)" unreacted "$out"
    assert_eq "helper stub [$stub], $a author (rc)" 0 "$rc"
  done
done

# Eight arguments with a reactions file are accepted (the nine-argument refusal is above).
run check "$tmp/good.json" "$tmp/map.yml" "$CID" "$UPD" "$ISSUE" "$REPO" "$tmp/fresh.tsv"
assert_eq "eight arguments accepted (rc)" 0 "$rc"

[ "$fail" -eq 0 ]
