#!/bin/sh
# Fixture tests for the shell blocks around blocked-state.sh in
# plugins/way-of-working/skills/pr-checks/SKILL.md (block (a2), the app-pinned contexts, #384;
# block (b), "ask the predicate").
#
# Issue #244: tests/blocked-state.test.sh covers the predicate; this covers the chain that
# feeds it. A failed gh must never reach the predicate and never print `lag`, and a branch
# name is untrusted text that must stop the chain before any gh api call. The blocks are
# extracted from the skill itself (not copied here), their placeholders filled in, and run
# against a stub gh on PATH. Mutants then prove the assertions can fail.
#
# Permitted toolset: POSIX sh and its standard utilities. No jq, no yq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
skill="$root_dir/plugins/way-of-working/skills/pr-checks/SKILL.md"
predicate="$root_dir/plugins/way-of-working/bin/blocked-state.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
trap 'exit 1' INT TERM
stub="$work/stub"
sandbox="$work/sandbox"
mkdir -p "$stub" "$sandbox"

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

# --- extract block (b) from the skill ----------------------------------------
# From the marker comment line to the closing fence, then fill the placeholders. The
# decision is filled with a shell default so each case picks it through DECISION.
awk '/^ *# \(b\) ask the predicate/ { p = 1 } p && /^ *```/ { exit } p' "$skill" |
  sed -e 's/^ *//' -e 's/<N>/7/g' -e 's/{repo}/o\/r/g' -e 's/<green>/1/g' \
      -e 's/<decision>/${DECISION:-NONE}/g' >"$work/block.sh"
if grep -Eq '(^|[^$])[<{][A-Za-z0-9_.-]+[>}]' "$work/block.sh"; then
  echo "FAIL - block (b) still has an unfilled placeholder; teach the fixture to fill it" >&2
  exit 1
fi
if [ ! -s "$work/block.sh" ] || ! grep -q 'blocked-state.sh' "$work/block.sh"; then
  echo "FAIL - could not extract block (b) from $skill" >&2
  exit 1
fi

# --- stubs --------------------------------------------------------------------
# gh: logs every call; STUB_PR_RC / STUB_API_RC make that call fail; STUB_BASE is the
# base branch name and STUB_SHA the head commit; STUB_RULES is the already-projected rule
# list the real --jq would print for block (b), STUB_PINS the projected "<app id> <context>"
# lines block (a2) asks for, STUB_RUNS the projected "<app id> <name>" passing check-runs.
# STUB_STATUSES is the projected "<type> <login> <state> <context>" commit statuses, newest
# first; STUB_STATUSES_RC makes that read fail. STUB_APPS is "<slug> <id>" lines for
# `gh api apps/<slug>`, which exits non-zero for an unknown slug or when STUB_APPS_RC is not 0.
cat >"$stub/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$STUB_LOG"
case "$1 $2" in
  "pr view")
    [ "${STUB_PR_RC:-0}" = 0 ] || exit 1
    case "$*" in
      *headRefOid*) printf '%s\n' "${STUB_SHA-0123456789abcdef0123456789abcdef01234567}" ;;
      *) printf '%s\n' "$STUB_BASE" ;;
    esac ;;
  "api --paginate")
    [ "${STUB_API_RC:-0}" = 0 ] || { echo "stub gh: api failed" >&2; exit 1; }
    case "$*" in
      */check-runs*) [ "${STUB_RUNS_RC:-0}" = 0 ] || { echo "stub gh: runs failed" >&2; exit 1; }
                    [ -z "${STUB_RUNS-}" ] || printf '%s\n' "$STUB_RUNS" ;;
      */statuses*) [ "${STUB_STATUSES_RC:-0}" = 0 ] || { echo "stub gh: statuses failed" >&2; exit 1; }
                   [ -z "${STUB_STATUSES-}" ] || printf '%s\n' "$STUB_STATUSES" ;;
      *'\(.integration_id) '*) [ -z "${STUB_PINS-}" ] || printf '%s\n' "$STUB_PINS" ;;
      *) [ -z "${STUB_RULES-}" ] || printf '%s\n' "$STUB_RULES" ;;
    esac ;;
  "api apps/"*)
    [ "${STUB_APPS_RC:-0}" = 0 ] || { echo "stub gh: app lookup failed" >&2; exit 1; }
    app_id="$(printf '%s\n' "${STUB_APPS-}" | while read -r a b; do
      if [ "$a" = "${2#apps/}" ]; then printf '%s\n' "$b"; break; fi
    done)"
    [ -n "$app_id" ] || { echo "stub gh: no such app" >&2; exit 1; }
    printf '%s\n' "$app_id" ;;
  *) exit 99 ;;
esac
EOF
# blocked-state.sh by bare name, as the skill calls it; logs that it ran, then defers to the
# real script (via sh, so no exec bit is needed).
cat >"$stub/blocked-state.sh" <<EOF
#!/bin/sh
printf 'PRED\n' >>"\$STUB_LOG"
exec sh "$predicate" "\$@"
EOF
chmod +x "$stub/gh" "$stub/blocked-state.sh"

# The skill ships the block as a bash block; run it under bash where there is one.
if command -v bash >/dev/null 2>&1; then block_shell=bash; else block_shell=sh; fi

# run_block <block-file> -> "<stdout>|<rc>"; STUB_* come from the caller's environment.
run_block() {
  : >"$work/log"
  out="$(cd "$sandbox" && STUB_LOG="$work/log" PATH="$stub:$PATH" "$block_shell" "$1" 2>/dev/null)" && rc=0 || rc=$?
  printf '%s|%s' "$out" "$rc"
}
calls() { grep -c "$1" "$work/log" || true; }

pr0='pull_request approvals=0 threads=false codeowner=false reviewers=0'
pr_co='pull_request approvals=1 threads=false codeowner=true reviewers=0'
rsc0='required_status_checks app_pinned=0'
export STUB_BASE=main STUB_PR_RC=0 STUB_API_RC=0
STUB_RULES="$(printf 'deletion\nnon_fast_forward\n%s\n%s' "$pr0" "$rsc0")"
export STUB_RULES

# --- answers ------------------------------------------------------------------
assert_eq "empty rule list -> lag" "lag|0" "$(STUB_RULES= run_block "$work/block.sh")"
assert_eq "no review rule -> lag" "lag|0" "$(run_block "$work/block.sh")"
with_approval="$(printf 'deletion\nnon_fast_forward\n%s\n%s' "$pr_co" "$rsc0")"
assert_eq "approval rule, REVIEW_REQUIRED -> awaiting-approval" "awaiting-approval|0" \
  "$(DECISION=REVIEW_REQUIRED STUB_RULES="$with_approval" run_block "$work/block.sh")"
assert_eq "approval rule, APPROVED -> lag" "lag|0" \
  "$(DECISION=APPROVED STUB_RULES="$with_approval" run_block "$work/block.sh")"
res="$(STUB_RULES="$(printf '%s
update' "$STUB_RULES")" run_block "$work/block.sh")"
case "$res" in *"cannot judge"*"|2") echo "ok - an update rule is no longer an admin-merge verdict: the refusal names it, exit 2" ;; *) echo "FAIL - update rule: got [$res]" >&2; fail=1 ;; esac
res="$(DECISION=MAYBE run_block "$work/block.sh")"
case "$res" in *"must be APPROVED"*"|2") echo "ok - a decision outside the vocabulary is refused, exit 2" ;; *) echo "FAIL - bad decision: got [$res]" >&2; fail=1 ;; esac

# --- a failed gh never reaches the predicate ----------------------------------
assert_eq "failing gh api -> no word, non-zero" "|1" "$(STUB_API_RC=1 run_block "$work/block.sh")"
assert_eq "failing gh api -> predicate never ran" "0" "$(calls PRED)"
assert_eq "failing gh pr view -> no word, non-zero" "|1" "$(STUB_PR_RC=1 run_block "$work/block.sh")"
assert_eq "failing gh pr view -> no gh api call" "0" "$(calls '^api')"

# --- an untrusted branch name stops the chain before any gh api call -----------
for b in 'x$(touch PWN)' 'a;b' 'a b' 'a|b' 'a&b' '' 'a`b`' 'caf'"$(printf '\303\251')"; do
  res="$(STUB_BASE="$b" run_block "$work/block.sh")"
  assert_eq "branch [$b] -> no word, non-zero" "|1" "$res"
  assert_eq "branch [$b] -> no gh api call" "0" "$(calls '^api')"
done
assert_eq "slashes, dots, dashes in a branch are allowed" "lag|0" \
  "$(STUB_BASE='feat/v1.2_x-y' run_block "$work/block.sh")"

# --- block (a2): a pinned context must be met by its pinned app (its newest status, else a run) (#384) --
awk '/^ *# \(a2\) every context/ { p = 1 } p && /^ *```/ { exit } p' "$skill" |
  sed -e 's/^ *//' -e 's/<N>/7/g' -e 's/{repo}/o\/r/g' >"$work/blocka2.sh"
if [ ! -s "$work/blocka2.sh" ] || grep -Eq '(^|[^$])[<{][A-Za-z0-9_.-]+[>}]' "$work/blocka2.sh"; then
  echo "FAIL - could not extract block (a2) from $skill, or it has an unfilled placeholder" >&2
  exit 1
fi
export STUB_PINS="$(printf '15368 lint\n15368 coupling')"
export STUB_RUNS="$(printf '15368 lint\n15368 coupling\n15368 invariants\n9999 other')"
assert_eq "every pinned context has a run from its app -> pins-ok" "pins-ok|0" \
  "$(run_block "$work/blocka2.sh")"
assert_eq "no pinned context at all -> pins-ok" "pins-ok|0" "$(STUB_PINS= run_block "$work/blocka2.sh")"
assert_eq "a pinned context whose only run came from another app -> unmet, named" "unmet 15368 coupling|0" \
  "$(STUB_RUNS="$(printf '15368 lint\n9999 coupling')" run_block "$work/blocka2.sh")"
assert_eq "a pinned context with no passing run at all -> unmet" "unmet 15368 lint
unmet 15368 coupling|0" "$(STUB_RUNS= run_block "$work/blocka2.sh")"
assert_eq "a context that merely contains the pinned name does not match" "unmet 15368 lint|0" \
  "$(STUB_PINS='15368 lint' STUB_RUNS="$(printf '15368 lint-extra\n1536 lint')" run_block "$work/blocka2.sh")"
assert_eq "a pinned context with a space in it is matched whole" "pins-ok|0" \
  "$(STUB_PINS='15368 Run tests' STUB_RUNS='15368 Run tests' run_block "$work/blocka2.sh")"
assert_eq "failing rules read -> no output, non-zero" "|1" "$(STUB_API_RC=1 run_block "$work/blocka2.sh")"
assert_eq "failing check-runs read -> no output, non-zero" "|1" "$(STUB_RUNS_RC=1 run_block "$work/blocka2.sh")"
assert_eq "failing pr view -> no output, non-zero" "|1" "$(STUB_PR_RC=1 run_block "$work/blocka2.sh")"
for b in 'x$(touch PWN)' 'a;b' ''; do
  assert_eq "branch [$b] -> no output, non-zero" "|1" "$(STUB_BASE="$b" run_block "$work/blocka2.sh")"
  assert_eq "branch [$b] -> no gh api call" "0" "$(calls '^api')"
done

# --- block (a2): a status for the context decides, else its run (#673) ----------
# a2f <block-file> <pins> <runs> <statuses> -> "<stdout>|<rc>". Runs are empty unless a fixture
# states one, or the default runs above would meet `15368 lint` and make each fixture vacuous.
a2f() { STUB_PINS="$2" STUB_RUNS="$3" STUB_STATUSES="$4" run_block "$1"; }
a2() { a2f "$work/blocka2.sh" "$@"; }
nl2() { printf '%s\n%s' "$1" "$2"; }
export STUB_APPS="$(printf 'github-actions 15368\nother-app 9999')"
gha='Bot github-actions[bot] success lint'
# Met.
assert_eq "REPRODUCTION: a pin met only by the pinned app's success status -> pins-ok" "pins-ok|0" \
  "$(a2 '15368 lint' '' "$gha")"
assert_eq "a pinned context with a space in it is met by a status" "pins-ok|0" \
  "$(a2 '15368 Run tests' '' 'Bot github-actions[bot] success Run tests')"
assert_eq "one pin met by a run, one by a status" "pins-ok|0" \
  "$(a2 "$(nl2 '15368 lint' '15368 coupling')" '15368 coupling' "$gha")"
assert_eq "pins of two apps, each met by its own status -> pins-ok" "pins-ok|0" \
  "$(a2 "$(nl2 '15368 lint' '9999 coupling')" '' "$(nl2 "$gha" 'Bot other-app[bot] success coupling')")"
assert_eq "  one apps/github-actions lookup" "1" "$(calls '^api apps/github-actions ')"
assert_eq "  one apps/other-app lookup" "1" "$(calls '^api apps/other-app ')"
assert_eq "two pins decided by the same app -> pins-ok" "pins-ok|0" \
  "$(a2 "$(nl2 '15368 lint' '15368 coupling')" '' "$(nl2 "$gha" 'Bot github-actions[bot] success coupling')")"
assert_eq "  one apps/github-actions lookup for both" "1" "$(calls '^api apps/github-actions ')"
assert_eq "a run and a newest success status both from the pinned app -> pins-ok" "pins-ok|0" \
  "$(a2 '15368 lint' '15368 lint' "$gha")"
# Unmet, with a lookup.
assert_eq "a success status from another app -> unmet" "unmet 15368 lint|0" \
  "$(a2 '15368 lint' '' 'Bot other-app[bot] success lint')"
assert_eq "a newest failure from the pinned app over an older success -> unmet" "unmet 15368 lint|0" \
  "$(a2 '15368 lint' '' "$(nl2 'Bot github-actions[bot] failure lint' "$gha")")"
assert_eq "a newest pending from the pinned app over an older success -> unmet" "unmet 15368 lint|0" \
  "$(a2 '15368 lint' '' "$(nl2 'Bot github-actions[bot] pending lint' "$gha")")"
assert_eq "a newest failure from another app over an older success -> unmet" "unmet 15368 lint|0" \
  "$(a2 '15368 lint' '' "$(nl2 'Bot other-app[bot] failure lint' "$gha")")"
assert_eq "a passing run does not override a newest failure status -> unmet" "unmet 15368 lint|0" \
  "$(a2 '15368 lint' '15368 lint' 'Bot github-actions[bot] failure lint')"
# Unmet, with no apps/ call: noapp <what> <pins> <statuses> <expected> (runs empty).
noapp() {
  assert_eq "$1" "$4" "$(a2 "$2" '' "$3")"
  assert_eq "  $1: no apps/ call" "0" "$(calls '^api apps/')"
}
noapp "a newest user failure over an older app success -> unmet" '15368 lint' \
  "$(nl2 'User someone failure lint' "$gha")" "unmet 15368 lint|0"
noapp "a user success -> unmet" '15368 lint' 'User someone success lint' "unmet 15368 lint|0"
noapp "a Bot login without [bot] -> unmet" '15368 lint' 'Bot github-actions success lint' "unmet 15368 lint|0"
noapp "a Bot slug with command substitution -> unmet" '15368 lint' 'Bot x$(touch PWN)[bot] success lint' "unmet 15368 lint|0"
noapp "a Bot slug with command substitution and no space -> unmet" '15368 lint' 'Bot x$(touch${IFS}PWN)[bot] success lint' "unmet 15368 lint|0"
assert_eq "  nothing ran" "no" "$([ -e "$sandbox/PWN" ] && echo yes || echo no)"
noapp "a Bot login ending in b, o or t without [bot] -> unmet" '15368 lint' 'Bot robot success lint' "unmet 15368 lint|0"
noapp "a Bot slug with a slash -> unmet" '15368 lint' 'Bot a/b[bot] success lint' "unmet 15368 lint|0"
noapp "a Bot slug with a leading dash -> unmet" '15368 lint' 'Bot -x[bot] success lint' "unmet 15368 lint|0"
noapp "a User creator with a [bot] login (type check alone) -> unmet" '15368 lint' \
  'User github-actions[bot] success lint' "unmet 15368 lint|0"
noapp "a null creator -> unmet" '15368 lint' 'null null success lint' "unmet 15368 lint|0"
noapp "a context with a trailing space is not the pin's" '15368 lint' 'Bot github-actions[bot] success lint ' "unmet 15368 lint|0"
noapp "a context with a leading space is not the pin's" '15368 lint' 'Bot github-actions[bot] success  lint' "unmet 15368 lint|0"
noapp "a context that extends the pin's is not the pin's" '15368 lint' 'Bot github-actions[bot] success lint-extra' "unmet 15368 lint|0"
noapp "a pin that is a word of the context is not that context" '15368 Run' 'Bot github-actions[bot] success Run tests' "unmet 15368 Run|0"
noapp "neither a run nor a status -> unmet" '15368 lint' '' "unmet 15368 lint|0"
assert_eq "a status for one pin does not meet the other" "unmet 15368 coupling|0" \
  "$(a2 "$(nl2 '15368 lint' '15368 coupling')" '' "$gha")"
assert_eq "  only the pin with a status made a lookup" "1" "$(calls '^api apps/')"
# Across pins, and the cache.
assert_eq "a pin's lookup is not inherited by the next pin" "unmet 15368 coupling|0" \
  "$(a2 "$(nl2 '15368 lint' '15368 coupling')" '' "$(nl2 "$gha" 'User someone success coupling')")"
assert_eq "  one apps/github-actions lookup" "1" "$(calls '^api apps/github-actions ')"
assert_eq "a slug that is the tail of a cached slug is looked up on its own" "unmet 15368 coupling|0" \
  "$(STUB_APPS="$(printf 'github-actions 15368\nactions 4242')" \
     a2 "$(nl2 '15368 lint' '15368 coupling')" '' "$(nl2 "$gha" 'Bot actions[bot] success coupling')")"
assert_eq "  one apps/actions lookup" "1" "$(calls '^api apps/actions ')"
assert_eq "a slug that is the head of a cached slug is looked up on its own" "unmet 9999 lint|0" \
  "$(STUB_APPS="$(printf 'other 7777\nother-app 9999')" \
     a2 "$(nl2 '9999 coupling' '9999 lint')" '' "$(nl2 'Bot other-app[bot] success coupling' 'Bot other[bot] success lint')")"
assert_eq "  one apps/other-app lookup" "1" "$(calls '^api apps/other-app ')"
assert_eq "  one apps/other lookup" "1" "$(calls '^api apps/other ')"
# Reads and the SHA.
assert_eq "failing statuses read -> no output, non-zero" "|1" \
  "$(STUB_STATUSES_RC=1 a2 '15368 lint' '' "$gha")"
assert_eq "failing app lookup -> no output, non-zero" "|1" \
  "$(STUB_APPS_RC=1 a2 '15368 lint' '' "$gha")"
for s in abc '' 0123456789ABCDEF0123456789ABCDEF01234567 0123456789abcdef0123456789abcdef0123456; do
  assert_eq "head SHA [$s] -> no output, non-zero" "|1" "$(STUB_SHA="$s" a2 '15368 lint' '' "$gha")"
  assert_eq "  no check-runs or statuses call" "0" "$(calls 'commits/')"
done
assert_eq "no pinned context -> pins-ok" "pins-ok|0" "$(a2 '' '' "$gha")"
assert_eq "  no statuses call" "0" "$(calls 'statuses')"
unset STUB_PINS STUB_RUNS

# --- mutants: the assertions above must be able to fail ------------------------
# (1) T=$(gh api ...) no longer chained to what follows (the && after it dropped).
sed -e '/^T=\$(/ s/ &&$//' "$work/block.sh" >"$work/mut1.sh"
# (2) the branch check no longer chained to the gh api call.
sed -e '/^case "\$B"/ s/ &&$//' "$work/block.sh" >"$work/mut2.sh"
# (3) gh piped straight into the predicate, no capture.
awk '/^T=\$\(/ { sub(/^T=\$\(/, ""); sub(/\) &&$/, " |"); print; getline; sub(/^.*\| /, ""); print; next } { print }' \
  "$work/block.sh" >"$work/mut3.sh"
for m in 1 2 3; do
  if cmp -s "$work/block.sh" "$work/mut$m.sh"; then
    echo "FAIL - mutant $m did not change the block (the mutation no longer applies)" >&2
    fail=1
  fi
done
# Each mutant must fail open exactly the way it models (lag, exit 0), not merely differ,
# so a mutant broken into a syntax error cannot count as caught.
assert_eq "mutant 1 (T= not chained) fails open on a failing gh api" "lag|0" \
  "$(STUB_API_RC=1 run_block "$work/mut1.sh")"
assert_eq "mutant 2 (branch check not chained) fails open on a;b" "lag|0" \
  "$(STUB_BASE='a;b' run_block "$work/mut2.sh")"
assert_eq "mutant 2 made the gh api call" "1" "$(calls '^api')"
assert_eq "mutant 3 (gh piped straight in) fails open on a failing gh api" "lag|0" \
  "$(STUB_API_RC=1 run_block "$work/mut3.sh")"

# (4) block (a2): the check-runs read no longer chained, so a failed read leaves R empty and
# every pin reads unmet -- the mutant must differ from the block (an unchained read that
# fails would otherwise still print the unmet lines, so it is told apart by the exit status
# the chain gives: the real block stops with 1, the mutant carries on and exits 0).
sed -e '/^R=\$(/ s/ &&$//' "$work/blocka2.sh" >"$work/mut4.sh"
if cmp -s "$work/blocka2.sh" "$work/mut4.sh"; then
  echo "FAIL - mutant 4 did not change block (a2) (the mutation no longer applies)" >&2
  fail=1
fi
export STUB_PINS='15368 lint'
assert_eq "mutant 4 (check-runs read not chained) carries on past a failed read" "unmet 15368 lint|0" \
  "$(STUB_RUNS_RC=1 run_block "$work/mut4.sh")"
# (5) block (a2): the whole-line match loosened to a substring match.
sed -e 's/grep -Fxq/grep -Fq/' "$work/blocka2.sh" >"$work/mut5.sh"
if cmp -s "$work/blocka2.sh" "$work/mut5.sh"; then
  echo "FAIL - mutant 5 did not change block (a2) (the mutation no longer applies)" >&2
  fail=1
fi
assert_eq "mutant 5 (substring match) wrongly accepts lint-extra for lint" "pins-ok|0" \
  "$(STUB_RUNS='15368 lint-extra' run_block "$work/mut5.sh")"
unset STUB_PINS

# (6)-(13) block (a2), the status rule (#673). Each mutant is a one-line sed, proven to change
# the block, and must fail open exactly the way it models.
mutant_a2() { # <n> <sed script>
  sed -e "$2" "$work/blocka2.sh" >"$work/mut$1.sh"
  if cmp -s "$work/blocka2.sh" "$work/mut$1.sh"; then
    echo "FAIL - mutant $1 did not change block (a2) (the mutation no longer applies)" >&2
    fail=1
  fi
}
mutant_a2 6 '/^ST=\$(/ s/ &&$//'
assert_eq "mutant 6 (statuses read not chained) carries on past a failed read" "unmet 15368 lint|0" \
  "$(STUB_STATUSES_RC=1 a2f "$work/mut6.sh" '15368 lint' '' "$gha")"
mutant_a2 7 's/\[ "\$id" = "\$pid" \]/true/'
assert_eq "mutant 7 (app id not compared) accepts another app's status" "pins-ok|0" \
  "$(a2f "$work/mut7.sh" '15368 lint' '' 'Bot other-app[bot] success lint')"
mutant_a2 8 's/if \[ "\$ctx" = "\$pctx" \]; then/if [ "$ctx" = "$pctx" ] \&\& [ "$t" = Bot ]; then/'
assert_eq "mutant 8 (newest Bot status, not newest overall) skips a newer user failure" "pins-ok|0" \
  "$(a2f "$work/mut8.sh" '15368 lint' '' "$(nl2 'User someone failure lint' "$gha")")"
mutant_a2 9 's/ || exit 1//'
assert_eq "mutant 9 (lookup failure swallowed) reads unmet, exit 0" "unmet 15368 lint|0" \
  "$(STUB_APPS_RC=1 a2f "$work/mut9.sh" '15368 lint' '' "$gha")"
mutant_a2 10 's/^if \[ -z "\$d" \]; then$/if printf "%s\\n" "$R" | grep -Fxq -- "$pin" || [ -z "$d" ]; then/'
assert_eq "mutant 10 (check-run short-circuit) lets a run override a newest failure" "pins-ok|0" \
  "$(a2f "$work/mut10.sh" '15368 lint' '15368 lint' 'Bot github-actions[bot] failure lint')"
mutant_a2 11 '/^d= slug= id= met=0$/d'
assert_eq "mutant 11 (per-pin reset dropped) leaks the first pin's met into the second" "pins-ok|0" \
  "$(a2f "$work/mut11.sh" "$(nl2 '15368 lint' '15368 coupling')" '' "$(nl2 "$gha" 'User someone success coupling')")"
mutant_a2 12 '/^\[ "\$t" = Bot \] || slug=$/d'
assert_eq "mutant 12 (type check dropped) accepts a User with a [bot] login" "pins-ok|0" \
  "$(a2f "$work/mut12.sh" '15368 lint' '' 'User github-actions[bot] success lint')"
mutant_a2 13 's/^id=\$(printf .*cache.*$/case "$cache" in *"$slug "*) id=${cache#*"$slug "}; id=${id%%[!0-9]*} ;; *) id= ;; esac/'
assert_eq "mutant 13 (unanchored cache hit) lets one slug pick up another's id" "pins-ok|0" \
  "$(STUB_APPS="$(printf 'github-actions 15368\nactions 4242')" \
     a2f "$work/mut13.sh" "$(nl2 '15368 lint' '15368 coupling')" '' "$(nl2 "$gha" 'Bot actions[bot] success coupling')")"

if [ "$fail" -ne 0 ]; then
  echo "blocked-state-block.test.sh: FAILED" >&2
  exit 1
fi
echo "blocked-state-block.test.sh: all passed"
