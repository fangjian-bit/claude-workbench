#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/app-push.sh (#478), and the static check that
# no pushing skill spells an App-mode push itself.
#
# Permitted toolset: POSIX sh. No jq, no yq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/plugins/way-of-working/bin/app-push.sh"
skills_dir="$root_dir/plugins/way-of-working/skills"

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

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM
mkdir "$work/bin"
# A stub git. `push` records one argument per line to $STUB_GIT_LOG and exits with
# $STUB_GIT_EXIT (default 0); `remote get-url` prints $STUB_URL (default an https github URL,
# or nothing and a failure when STUB_URL_FAIL is set); `config --get-urlmatch` prints
# $STUB_URLMATCH (default nothing).
cat >"$work/bin/git" <<'EOF'
#!/bin/sh
for a in "$@"; do
  case "$a" in
    push)
      for b in "$@"; do printf '%s\n' "$b"; done >"$STUB_GIT_LOG"
      exit "${STUB_GIT_EXIT:-0}"
      ;;
    get-url)
      [ -z "${STUB_URL_FAIL:-}" ] || exit 1
      printf '%s\n' "${STUB_URL:-https://github.com/o/r.git}"
      exit 0
      ;;
    remote.*.vcs)
      printf '%s
' "${STUB_VCS:-}"
      exit 0
      ;;
    --get-urlmatch)
      printf '%s\n' "${STUB_URLMATCH:-}"
      exit 0
      ;;
  esac
done
exit 0
EOF
chmod +x "$work/bin/git"

run() {
  : >"$work/log"
  rc=0
  PATH="$work/bin:$PATH" STUB_GIT_LOG="$work/log" sh "$script" "$@" 2>/dev/null || rc=$?
  echo "$rc"
}

pin='-c
credential.helper=
-c
credential.helper=!gh auth git-credential
-c
http.extraHeader=
push'

# --- the pin, then the caller's arguments --------------------------------------------
assert_eq "exit 0 passes through" "0" "$(run -u origin feat/x)"
assert_eq "pin precedes push, arguments follow in order" "$pin
-u
origin
feat/x" "$(cat "$work/log")"

assert_eq "dry-run is passed through" "0" "$(run --dry-run origin feat/x)"
assert_eq "dry-run argument list" "$pin
--dry-run
origin
feat/x" "$(cat "$work/log")"

assert_eq "no options is allowed" "0" "$(run origin feat/x HEAD:refs/heads/y)"
assert_eq "several refspecs, no options" "$pin
origin
feat/x
HEAD:refs/heads/y" "$(cat "$work/log")"

: >"$work/log"
rc=0
PATH="$work/bin:$PATH" STUB_GIT_LOG="$work/log" STUB_GIT_EXIT=7 sh "$script" origin b 2>/dev/null || rc=$?
assert_eq "git's exit status is the script's" "7" "$rc"

# --- the allow-list: every other spelling is refused, and nothing runs ----------------
for bad in "-f" "--force" "--force-with-lease" "--force-with-lease=x" "--force-if-includes" \
           "--mirror" "--mirr" "--delete" "--del" "-d" "--prune" "--pru" "-uf" "-ud" "-vf" \
           "--receive-pack=x" "--exec=x" "--repo=x" "--all" "--tags" "--no-verify"; do
  assert_eq "refuses option $bad" "2" "$(run "$bad" origin b)"
  assert_eq "refusing option $bad ran no git" "" "$(cat "$work/log")"
  assert_eq "refuses option $bad after the remote" "2" "$(run origin "$bad")"
done
for bad in "+feat/x" ":victim" "HEAD^" "a b" "" "*" "refs/heads/*:refs/heads/*" "refs/*:refs/*"; do
  assert_eq "refuses refspec [$bad]" "2" "$(run origin "$bad")"
  assert_eq "refusing refspec [$bad] ran no git" "" "$(cat "$work/log")"
done
for bad in "https://github.com/o/r.git" "git@github.com:o/r.git" "/tmp/r" "./r" "../r"; do
  assert_eq "refuses a URL or path as the remote [$bad]" "2" "$(run "$bad" b)"
done
assert_eq "refuses no arguments" "2" "$(run)"
assert_eq "refuses a remote with no refspec" "2" "$(run -u origin)"
assert_eq "refuses options only" "2" "$(run -u)"
assert_eq "none of those ran git" "" "$(cat "$work/log")"

# --- the pin has to be able to work: https://github.com/, no URL-scoped header ----------
for url in "git@github.com:o/r.git" "ssh://git@github.com/o/r.git" "http://github.com/o/r.git" \
           "https://example.com/o/r.git" "/srv/git/r.git"; do
  rc=0
  : >"$work/log"
  PATH="$work/bin:$PATH" STUB_GIT_LOG="$work/log" STUB_URL="$url" sh "$script" origin b 2>/dev/null || rc=$?
  assert_eq "refuses a remote URL of $url" "2" "$rc"
  assert_eq "refusing $url ran no push" "" "$(cat "$work/log")"
done
rc=0
PATH="$work/bin:$PATH" STUB_GIT_LOG="$work/log" STUB_URL_FAIL=1 sh "$script" origin b 2>/dev/null || rc=$?
assert_eq "refuses a remote whose URL cannot be read" "2" "$rc"
rc=0
PATH="$work/bin:$PATH" STUB_GIT_LOG="$work/log" STUB_URLMATCH='AUTHORIZATION: basic x' sh "$script" origin b 2>/dev/null || rc=$?
assert_eq "refuses a URL-scoped http.extraheader" "2" "$rc"
rc=0
PATH="$work/bin:$PATH" STUB_GIT_LOG="$work/log" STUB_VCS=evilhelper sh "$script" origin b 2>/dev/null || rc=$?
assert_eq "refuses a remote that sets a remote helper (vcs)" "2" "$rc"
assert_eq "refusing a URL-scoped header ran no push" "" "$(cat "$work/log")"

# --- static: every pushing skill goes through the script, at every push site ----------
# The pin has one spelling (bin/app-push.sh, narrated in reference/conventions.md). A skill
# or appendix that spells it again has copied prose that can drift, and a skill whose push
# sites are not all routed through the script can push as the human. Each file is flattened
# to one line first, so a command wrapped across lines is still seen.
n=0
spelled=
unpaired=
for f in "$skills_dir"/*/SKILL.md "$skills_dir"/*/appendices/*.md; do
  [ -f "$f" ] || continue
  n=$((n + 1))
  flat=$(tr '\n' ' ' <"$f" | tr -s ' ')
  if printf '%s' "$flat" | grep -qE "credential\.helper=.?.?!gh auth git-credential"; then
    spelled="$spelled ${f#"$root_dir"/}"
  fi
  # A literal push command (plain or with -c/-C options, any remote spelling) is a user-mode
  # spelling; each one must be paired with an App-mode `app-push.sh` mention. A bare prohibition
  # on a force push is exempt.
  lit=$(printf '%s' "$flat" | grep -oE 'git( +-[cC] +[^ ]+)* +push( +-[-a-z]+)* +[^ ]+' | grep -vE -- '--force|push +-f( |$)' | wc -l | tr -d ' ')
  app=$(printf '%s' "$flat" | grep -o 'app-push\.sh' | wc -l | tr -d ' ')
  if [ "$lit" -gt 0 ] && [ "$app" -lt "$lit" ]; then
    unpaired="$unpaired ${f#"$root_dir"/}($lit pushes,$app app-push.sh)"
  fi
done
assert_eq "the scan saw the skill files" "yes" "$([ "$n" -ge 10 ] && echo yes || echo no)"
assert_eq "no skill spells the credential-helper pin itself" "" "$spelled"
assert_eq "every literal git push is paired with an app-push.sh mention" "" "$unpaired"

# The skills that push a branch, with the exact number of literal user-mode push commands and
# of app-push.sh and api-commit.sh mentions each carries (#601: the two App-mode routes, picked
# by identities.dev_app.commit_route). Exact on all three, so removing a mention fails, and so does
# adding a plain push that hides behind a prose mention's spare count. Adding a push site means
# updating the numbers here, in the same diff. A new pushing skill is added here.
expect() {
  file="$1"
  lits="$2"
  apps="$3"
  apis="$4"
  got=$(grep -o 'app-push\.sh' "$skills_dir/$file" | wc -l | tr -d ' ')
  assert_eq "$file names app-push.sh exactly $apps times" "$apps" "$got"
  gota=$(grep -o 'api-commit\.sh' "$skills_dir/$file" | wc -l | tr -d ' ')
  assert_eq "$file names api-commit.sh exactly $apis times" "$apis" "$gota"
  gotl=$(tr '\n' ' ' <"$skills_dir/$file" | tr -s ' ' | grep -oE 'git( +-[cC] +[^ ]+)* +push( +-[-a-z]+)* +[^ ]+' | grep -vE -- '--force|push +-f( |$)' | wc -l | tr -d ' ')
  assert_eq "$file has exactly $lits literal git push commands" "$lits" "$gotl"
}
expect ship/SKILL.md 1 3 1
expect handoff/SKILL.md 1 2 2
expect archive-sprint/SKILL.md 2 5 5
expect resume/appendices/schema-interview.md 1 1 1

# Every skill or appendix that names app-push.sh also names api-commit.sh: a push site that
# learns one route and not the other would push as the human on a repo that selects the other.
# The pairing rule above is unchanged: a literal git push still pairs with app-push.sh alone,
# so a bare push cannot pair with api-commit.sh.
one_route=
for f in "$skills_dir"/*/SKILL.md "$skills_dir"/*/appendices/*.md; do
  [ -f "$f" ] || continue
  if grep -q 'app-push\.sh' "$f" && ! grep -q 'api-commit\.sh' "$f"; then
    one_route="$one_route ${f#"$root_dir"/}"
  fi
done
assert_eq "every file that names app-push.sh also names api-commit.sh" "" "$one_route"

# --- ship proves the acting App before its first push (#476) ----------------------------
# The viewer read must feed gh-identity.sh pr-actor, and both come before the dry-run probe,
# the first App-mode write-shaped call; the PR-user check stays as the backstop.
ship="$skills_dir/ship/SKILL.md"
viewer_at=$(grep -n 'gh api .*graphql .*viewer { login databaseId }' "$ship" | head -n 1 | cut -d: -f1)
actor_at=$(grep -n 'gh-identity\.sh pr-actor "\$LOGIN" "\$ID"' "$ship" | head -n 1 | cut -d: -f1)
dry_at=$(grep -n 'app-push\.sh --dry-run' "$ship" | head -n 1 | cut -d: -f1)
ordered=no
if [ -n "$viewer_at" ] && [ -n "$actor_at" ] && [ -n "$dry_at" ] && [ "$viewer_at" -lt "$actor_at" ] && [ "$actor_at" -lt "$dry_at" ]; then ordered=yes; fi
assert_eq "ship reads viewer, then tests it with pr-actor, before the dry-run push probe" "yes" "$ordered"
assert_eq "ship still checks the PR's user afterwards" "yes" "$(grep -c 'gh-identity\.sh pr-actor "\$LOGIN" "\$ID"' "$ship" | tr -d ' ' | grep -qx 2 && echo yes || echo no)"

# --- the commit_route reader (#601): the yq expression conventions.md spells, run on fixtures ---
# The expression is cut out of conventions.md and must be the one ship carries. Needs yq; skips
# loudly without it.
conv="$root_dir/plugins/way-of-working/reference/conventions.md"
if command -v yq >/dev/null 2>&1; then
  expr=$(grep -m1 "^RT=\$(yq -r '" "$conv" | sed "s/^RT=\$(yq -r '//; s/' \"\$DEF_YML_FILE\")\$//")
  assert_eq "ship carries the reader conventions.md spells" "1" "$(grep -cF -- "$expr" "$skills_dir/ship/SKILL.md" | tr -d ' ')"
  rt_case() { # <dev_app flow map body> <expected>
    printf 'identities:\n  dev_app: { login: d, id: 1%s }\n' "$1" >"$work/rt.yml"
    assert_eq "commit_route reader on [$1]" "$2" "$(yq -r "$expr" "$work/rt.yml")"
  }
  rt_case '' 'false'
  rt_case ', commit_route: git' 'true !!str git|'
  rt_case ', commit_route: api' 'true !!str api|'
  rt_case ', commit_route: null' 'true !!null |'
  rt_case ', commit_route: "api\n"' 'true !!str api
|'
  rt_case ', commit_route: yes' 'true !!str yes|'
  for lab in '"false"|"true !!str git|")' '"true !!str api|")'; do
    assert_eq "ship's case carries the label $lab" "1" "$(grep -cF -- "$lab" "$skills_dir/ship/SKILL.md" | tr -d ' ')"
  done
else
  echo "skip - yq not on PATH, the commit_route reader cases did not run"
fi

exit "$fail"
