#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/gh-identity.sh.
#
# #379 (WB-D24): one predicate says whether the acting identity is a user or the declared
# dev App, matched on the numeric id, and says nothing when unsure.
#
# Needs yq (mikefarah v4) for `classify`; skips those cases, loudly, when it is absent.
# Permitted toolset: POSIX sh.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/plugins/way-of-working/bin/gh-identity.sh"

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

# run <args...>: sets rc and out (stdout only); stderr is kept in $tmp/err.
run() {
  rc=0
  out=$(sh "$script" "$@" 2>"$tmp/err") || rc=$?
}
# runin <records> <args...>
runin() {
  recs="$1"; shift
  rc=0
  out=$(printf '%s' "$recs" | sh "$script" "$@" 2>"$tmp/err") || rc=$?
}
expect() { # expect <desc> <out> <rc>
  assert_eq "$1 (stdout)" "$2" "$out"
  assert_eq "$1 (rc)" "$3" "$rc"
}

# -- reach ----------------------------------------------------------------------------
runin 'acme/one
acme/two
' reach acme/two
expect "reach: listed repo" reached 0
runin 'Acme/Two
' reach acme/two
expect "reach: case-insensitive" reached 0
runin "$(printf 'acme/one\r\nacme/two\r\n')" reach acme/two
expect "reach: CRLF records" reached 0
runin 'acme/one
' reach acme/two
expect "reach: records without the repo" unreached 0
runin 'acme/two' reach acme/two
expect "reach: last record without a newline" reached 0
runin 'acme/two
' reach acme/two-extra
expect "reach: a prefix is not the repo" unreached 0
runin '' reach acme/two
expect "reach: empty input is not a result" "" 2
runin '

' reach acme/two
expect "reach: only blank lines is not a result" "" 2
runin 'acme/one
not a repo
' reach acme/two
expect "reach: malformed record" "" 2
runin 'acme/one/extra
' reach acme/two
expect "reach: three-part record" "" 2
runin 'acme/two
' reach 'acme/two;x'
expect "reach: bad repo argument" "" 2
runin 'acme/two
' reach
expect "reach: no repo argument" "" 2

# -- classify -------------------------------------------------------------------------
if ! command -v yq >/dev/null 2>&1; then
  echo "skip - yq not on PATH; classify cases not run" >&2
else
  mk() { printf '%s\n' "$2" >"$tmp/$1.yml"; }

  mk null 'identities: null'
  mk full 'identities:
  maintainer:
    - { login: Alice-Dev, id: 1001 }
    - { login: bob, id: 1002 }
  dev_app: { login: "acme-dev[bot]", id: 2001 }
  reviewer_app: { login: "acme-review[bot]", id: 2002 }
  loop_app: { login: "acme-loop[bot]", id: 2003 }'
  mk noapps 'identities:
  maintainer:
    - { login: alice-dev, id: 1001 }
  dev_app: null
  reviewer_app: null
  loop_app: null'
  mk absent 'repo: acme/x'
  mk scalar 'identities: yes'
  mk list 'identities: [a, b]'
  mk bad 'identities:
  maintainer:
    - alice-dev
    - { login: alice-dev, id: "1001" }
    - { login: alice-dev, id: 0 }
    - { login: alice-dev, id: -5 }
    - { login: 7, id: 1001 }
    - { id: 1001 }
  dev_app: "acme-dev[bot]"
  reviewer_app: { login: "acme-review[bot]", id: "2002" }
  loop_app: null'
  mk badyaml 'identities: [unclosed'

  # role: which declared account is acting
  run role alice-dev 1001 "$tmp/full.yml"
  expect "role: maintainer" maintainer 0
  run role 'acme-dev[bot]' 2001 "$tmp/full.yml"
  expect "role: dev App" dev_app 0
  run role 'acme-review[bot]' 2002 "$tmp/full.yml"
  expect "role: reviewer App" reviewer_app 0
  run role 'acme-loop[bot]' 2003 "$tmp/full.yml"
  expect "role: loop App" loop_app 0
  run role stranger 9999 "$tmp/full.yml"
  expect "role: undeclared account" undeclared 0
  run role anyone 5 "$tmp/null.yml"
  expect "role: identities null" legacy 0
  run role 'acme-dev[bot]' 2002 "$tmp/full.yml"
  expect "role: an id declared under another login" "" 2
  run role alice-dev 1001 "$tmp/absent.yml"
  expect "role: identities absent" "" 2
  run role alice-dev abc "$tmp/full.yml"
  expect "role: bad id" "" 2

  # pr-actor: is this the declared dev App (viewer before the push, PR user after)? (#464) Only `match` clears.
  run pr-actor 'acme-dev[bot]' 2001 "$tmp/full.yml"
  expect "pr-actor: the dev App" match 0
  run pr-actor 'ACME-DEV[bot]' 2001 "$tmp/full.yml"
  expect "pr-actor: the dev App, login case folded" match 0
  run pr-actor 'acme-review[bot]' 2002 "$tmp/full.yml"
  expect "pr-actor: wrong App (reviewer)" mismatch 0
  run pr-actor 'acme-loop[bot]' 2003 "$tmp/full.yml"
  expect "pr-actor: wrong App (loop)" mismatch 0
  run pr-actor alice-dev 1001 "$tmp/full.yml"
  expect "pr-actor: a maintainer's user login" mismatch 0
  run pr-actor stranger 9999 "$tmp/full.yml"
  expect "pr-actor: an undeclared account" mismatch 0
  run pr-actor 'acme-dev[bot]' 2999 "$tmp/full.yml"
  expect "pr-actor: the dev App's login with an undeclared id" mismatch 0
  run pr-actor 'acme-dev[bot]' 2002 "$tmp/full.yml"
  expect "pr-actor: dev App login on another App's id will not be guessed" "" 2
  run pr-actor 'acme-dev[bot]' 2001 "$tmp/noapps.yml"
  expect "pr-actor: dev_app null" mismatch 0
  run pr-actor 'acme-dev[bot]' 2001 "$tmp/null.yml"
  expect "pr-actor: identities null (no dev App declared)" mismatch 0
  run pr-actor 'acme-dev[bot]' 2001 "$tmp/bad.yml"
  expect "pr-actor: malformed dev_app entry" mismatch 0
  run pr-actor '' '' "$tmp/full.yml"
  expect "pr-actor: unreadable response (no login, no id)" "" 2
  run pr-actor 'acme-dev[bot]' '' "$tmp/full.yml"
  expect "pr-actor: unreadable response (no id)" "" 2
  run pr-actor 'null' 'null' "$tmp/full.yml"
  expect "pr-actor: a jq null for login and id" "" 2
  run pr-actor 'acme-dev[bot]' 2001 "$tmp/absent.yml"
  expect "pr-actor: identities absent" "" 2
  run pr-actor 'acme-dev[bot]' 2001 "$tmp/missing.yml"
  expect "pr-actor: project file missing" "" 2
  run pr-actor 'acme-dev[bot]' 2001
  expect "pr-actor: too few arguments" "" 2

  # user mode
  run classify alice-dev 1001 "$tmp/full.yml"
  expect "maintainer, exact login" user 0
  run classify ALICE-DEV 1001 "$tmp/full.yml"
  expect "maintainer, login case folded" user 0
  run classify bob 1002 "$tmp/full.yml"
  expect "second maintainer" user 0
  run classify anyone 5 "$tmp/null.yml"
  expect "identities null: a plain account is user mode" user 0

  # app mode
  run classify 'acme-dev[bot]' 2001 "$tmp/full.yml"
  expect "dev App" app 0
  run classify 'ACME-DEV[bot]' 2001 "$tmp/full.yml"
  expect "dev App, login case folded" app 0

  # unknown: never guessed
  run classify 'acme-dev[bot]' 2001 "$tmp/null.yml"
  expect "identities null: an undeclared [bot] is not user mode" "" 2
  run classify stranger 9999 "$tmp/full.yml"
  expect "undeclared account" "" 2
  run classify alice-dev 9999 "$tmp/full.yml"
  expect "a declared login on another id is not that account" "" 2
  run classify alice-renamed 1001 "$tmp/full.yml"
  expect "a declared id under another login: will not guess" "" 2
  run classify 'acme-review[bot]' 2002 "$tmp/full.yml"
  expect "reviewer App is neither mode" "" 2
  run classify 'acme-loop[bot]' 2003 "$tmp/full.yml"
  expect "loop App is neither mode" "" 2
  run classify 'acme-dev[bot]' 2001 "$tmp/noapps.yml"
  expect "dev_app null: a [bot] is undeclared" "" 2
  run classify alice-dev 1001 "$tmp/absent.yml"
  expect "no identities key" "" 2
  run classify alice-dev 1001 "$tmp/scalar.yml"
  expect "identities a scalar" "" 2
  run classify alice-dev 1001 "$tmp/list.yml"
  expect "identities a list" "" 2
  run classify alice-dev 1001 "$tmp/missing.yml"
  expect "project file missing" "" 2
  run classify alice-dev 1001 "$tmp/badyaml.yml"
  expect "project file unparseable" "" 2

  # malformed entries match nothing, not even by login alone
  run classify alice-dev 1001 "$tmp/bad.yml"
  expect "malformed maintainer entries never match" "" 2
  run classify 'acme-dev[bot]' 2001 "$tmp/bad.yml"
  expect "dev_app as a bare string never matches" "" 2
  run classify 'acme-review[bot]' 2002 "$tmp/bad.yml"
  expect "string id never matches" "" 2

  # single-entry files, where a wrongly accepted entry would print user/app
  mk onlystrid 'identities:
  maintainer:
    - { login: alice-dev, id: "1001" }
  dev_app: null
  reviewer_app: null
  loop_app: null'
  run classify alice-dev 1001 "$tmp/onlystrid.yml"
  expect "a string-id maintainer alone never matches" "" 2
  mk appstrid 'identities:
  maintainer:
    - { login: bob, id: 1002 }
  dev_app: { login: "acme-dev[bot]", id: "2001" }
  reviewer_app: null
  loop_app: null'
  run classify 'acme-dev[bot]' 2001 "$tmp/appstrid.yml"
  expect "a string-id dev_app never matches" "" 2
  mk appnologin 'identities:
  maintainer:
    - { login: bob, id: 1002 }
  dev_app: { id: 2001 }
  reviewer_app: null
  loop_app: null'
  run classify 'acme-dev[bot]' 2001 "$tmp/appnologin.yml"
  expect "a loginless dev_app never matches" "" 2
  mk mapmaint 'identities:
  maintainer:
    x: { login: alice-dev, id: 1001 }
  dev_app: null
  reviewer_app: null
  loop_app: null'
  run classify alice-dev 1001 "$tmp/mapmaint.yml"
  expect "maintainer written as a map never matches" "" 2
  mk dupid 'identities:
  maintainer:
    - { login: acme-dev, id: 2001 }
  dev_app: { login: "acme-dev", id: 2001 }
  reviewer_app: null
  loop_app: null'
  run classify acme-dev 2001 "$tmp/dupid.yml"
  expect "one id under two roles will not be guessed" "" 2
  assert_eq "cross-role reason" 1 "$(grep -c 'declared more than once' "$tmp/err" || true)"

  mk numlogin 'identities:
  maintainer:
    - { login: 1001, id: 1001 }
  dev_app: null
  reviewer_app: null
  loop_app: null'
  run classify 1001 1001 "$tmp/numlogin.yml"
  expect "a non-string login never matches" "" 2
  assert_eq "numeric-login reason" 1 "$(grep -c 'not declared' "$tmp/err" || true)"
  run classify 'acme-dev[bot]' 2001 "$tmp/appnologin.yml"
  assert_eq "loginless dev_app reason" 1 "$(grep -c 'not declared' "$tmp/err" || true)"
  mk mixed 'identities:
  maintainer:
    - bare
    - { login: alice-dev, id: "1001" }
    - { login: 7, id: 1003 }
    - { id: 1004 }
    - { login: bob, id: 1002 }
  dev_app: null
  reviewer_app: null
  loop_app: null'
  run classify bob 1002 "$tmp/mixed.yml"
  expect "malformed siblings do not block a valid maintainer" user 0
  mk alias2 'identities:
  maintainer: [ &m { login: x-dev, id: 5 } ]
  dev_app: *m
  reviewer_app: null
  loop_app: null'
  run classify x-dev 5 "$tmp/alias2.yml"
  expect "an id repeated through an alias is still repeated" "" 2
  mk alias3 'identities:
  dev_app: &m { login: x-dev, id: 5 }
  maintainer: [ *m ]
  reviewer_app: null
  loop_app: null'
  run classify x-dev 5 "$tmp/alias3.yml"
  expect "an alias inside maintainer counts as a declaration" "" 2
  mk aliasid 'x: &i { login: x-dev, id: 5 }
identities: *i'
  run classify x-dev 5 "$tmp/aliasid.yml"
  expect "identities itself written as an alias is refused" "" 2
  dupsame='identities:
  maintainer:
    - { login: bob, id: 1002 }
    - { login: bob, id: 1002 }
  dev_app: null
  reviewer_app: null
  loop_app: null'
  mk dupsame "$dupsame"
  run classify bob 1002 "$tmp/dupsame.yml"
  expect "the same id twice in one role will not be guessed" "" 2

  # the reason, where the exit code alone cannot tell the paths apart
  run classify alice-renamed 1001 "$tmp/full.yml"
  assert_eq "rename reason" 1 "$(grep -c 'different login' "$tmp/err" || true)"
  run classify 'acme-review[bot]' 2002 "$tmp/full.yml"
  assert_eq "reviewer reason" 1 "$(grep -c 'declared reviewer_app' "$tmp/err" || true)"
  run classify 'acme-loop[bot]' 2003 "$tmp/full.yml"
  assert_eq "loop reason" 1 "$(grep -c 'declared loop_app' "$tmp/err" || true)"
  run classify stranger 9999 "$tmp/full.yml"
  assert_eq "undeclared reason" 1 "$(grep -c 'not declared' "$tmp/err" || true)"

  # malformed inputs
  for bad in '' '-' 'a b' 'a;b' 'a$(x)' '-lead' 'trail-' 'a--b' '[bot]' 'x[bot]y'; do
    run classify "$bad" 1001 "$tmp/full.yml"
    expect "bad login [$bad]" "" 2
  done
  for bad in '' 0 007 -1 1.5 abc '1 2'; do
    run classify alice-dev "$bad" "$tmp/full.yml"
    expect "bad id [$bad]" "" 2
  done
  run classify alice-dev 1001
  expect "classify: too few arguments" "" 2

  # -- author (#382): trust by declared identity, the answer to a viewer-relative
  # author_association. Only a maintainer's authorship is trusted.
  mk dup 'identities:
  maintainer:
    - { login: alice-dev, id: 1001 }
  dev_app: { login: "alice-dev", id: 1001 }
  reviewer_app: null
  loop_app: null'
  run author alice-dev 1001 "$tmp/full.yml"
  expect "author: a maintainer is trusted" trusted 0
  run author ALICE-DEV 1001 "$tmp/full.yml"
  expect "author: login case folded" trusted 0
  run author bob 1002 "$tmp/full.yml"
  expect "author: a second maintainer is trusted" trusted 0
  run author 'acme-dev[bot]' 2001 "$tmp/full.yml"
  expect "author: the dev App's own text is not trusted" untrusted 0
  run author 'acme-review[bot]' 2002 "$tmp/full.yml"
  expect "author: the reviewer App is not trusted" untrusted 0
  run author 'acme-loop[bot]' 2003 "$tmp/full.yml"
  expect "author: the loop App is not trusted" untrusted 0
  run author stranger 9999 "$tmp/full.yml"
  expect "author: an undeclared account is untrusted, not an error" untrusted 0
  run author stranger 9999 "$tmp/noapps.yml"
  expect "author: undeclared account, null Apps" untrusted 0
  run author 'acme-dev[bot]' 2001 "$tmp/noapps.yml"
  expect "author: an App that is not declared is untrusted" untrusted 0
  run author stranger 9999 "$tmp/null.yml"
  expect "author: identities null defers to the caller" legacy 0
  run author 'acme-dev[bot]' 2001 "$tmp/null.yml"
  expect "author: identities null, a [bot] still defers" legacy 0
  run author alice-dev 9999 "$tmp/full.yml"
  expect "author: a maintainer's login on another id is untrusted" untrusted 0
  run author alice-renamed 1001 "$tmp/full.yml"
  expect "author: a maintainer's id under another login is not guessed" "" 2
  run author alice-dev 1001 "$tmp/dup.yml"
  expect "author: one id declared twice is not guessed" "" 2
  run author alice-dev 1001 "$tmp/bad.yml"
  expect "author: only malformed entries match nothing" untrusted 0
  run author alice-dev 1001 "$tmp/absent.yml"
  expect "author: no identities key" "" 2
  run author alice-dev 1001 "$tmp/scalar.yml"
  expect "author: identities neither null nor a map" "" 2
  run author alice-dev 1001 "$tmp/badyaml.yml"
  expect "author: unparseable file" "" 2
  run author alice-dev 1001 "$tmp/missing.yml"
  expect "author: unreadable file" "" 2
  for bad in '' 'a b' 'a;b' '-lead'; do
    run author "$bad" 1001 "$tmp/full.yml"
    expect "author: bad login [$bad]" "" 2
  done
  for bad in '' 0 -1 abc; do
    run author alice-dev "$bad" "$tmp/full.yml"
    expect "author: bad id [$bad]" "" 2
  done
  run author alice-dev 1001
  expect "author: too few arguments" "" 2

  # -- task-author (#664, WB-D32): the task issue's author. A maintainer is trusted, the declared
  # dev or reviewer App is an agent (the caller still needs a maintainer's reaction), the loop
  # App and an undeclared account are untrusted. `author` is unchanged above.
  run task-author alice-dev 1001 "$tmp/full.yml"
  expect "task-author: a maintainer is trusted" trusted 0
  run task-author ALICE-DEV 1001 "$tmp/full.yml"
  expect "task-author: login case folded" trusted 0
  run task-author 'acme-dev[bot]' 2001 "$tmp/full.yml"
  expect "task-author: the dev App is an agent" agent 0
  run task-author 'acme-review[bot]' 2002 "$tmp/full.yml"
  expect "task-author: the reviewer App is an agent" agent 0
  run task-author 'acme-loop[bot]' 2003 "$tmp/full.yml"
  expect "task-author: the loop App is untrusted" untrusted 0
  run task-author stranger 9999 "$tmp/full.yml"
  expect "task-author: an undeclared account is untrusted, not an error" untrusted 0
  run task-author 'acme-dev[bot]' 2001 "$tmp/noapps.yml"
  expect "task-author: an App that is not declared is untrusted" untrusted 0
  run task-author stranger 9999 "$tmp/null.yml"
  expect "task-author: identities null defers to the caller" legacy 0
  run task-author 'acme-dev[bot]' 2001 "$tmp/null.yml"
  expect "task-author: identities null, a [bot] still defers" legacy 0
  run task-author alice-dev 9999 "$tmp/full.yml"
  expect "task-author: a maintainer's login on another id is untrusted" untrusted 0
  run task-author 'acme-dev[bot]' 9999 "$tmp/full.yml"
  expect "task-author: the dev App's login on another id is untrusted" untrusted 0
  run task-author alice-renamed 1001 "$tmp/full.yml"
  expect "task-author: a maintainer's id under another login is not guessed" "" 2
  run task-author 'acme-dev[bot]' 2002 "$tmp/full.yml"
  expect "task-author: the reviewer App's id under the dev App's login is not guessed" "" 2
  run task-author alice-dev 1001 "$tmp/dup.yml"
  expect "task-author: one id declared twice is not guessed" "" 2
  run task-author alice-dev 1001 "$tmp/bad.yml"
  expect "task-author: only malformed entries match nothing" untrusted 0
  run task-author alice-dev 1001 "$tmp/absent.yml"
  expect "task-author: no identities key" "" 2
  run task-author alice-dev 1001 "$tmp/scalar.yml"
  expect "task-author: identities neither null nor a map" "" 2
  run task-author alice-dev 1001 "$tmp/badyaml.yml"
  expect "task-author: unparseable file" "" 2
  run task-author alice-dev 1001 "$tmp/missing.yml"
  expect "task-author: unreadable file" "" 2
  for bad in '' 'a b' 'a;b' '-lead'; do
    run task-author "$bad" 1001 "$tmp/full.yml"
    expect "task-author: bad login [$bad]" "" 2
  done
  for bad in '' 0 -1 abc; do
    run task-author alice-dev "$bad" "$tmp/full.yml"
    expect "task-author: bad id [$bad]" "" 2
  done
  run task-author alice-dev 1001
  expect "task-author: too few arguments" "" 2
fi

run
expect "no subcommand" "" 2
run bogus
expect "unknown subcommand" "" 2

if [ "$fail" -ne 0 ]; then exit 1; fi
echo "gh-identity: all assertions passed"
