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
      *'\(.integration_id) '*) [ -z "${STUB_PINS-}" ] || printf '%s\n' "$STUB_PINS" ;;
      *) [ -z "${STUB_RULES-}" ] || printf '%s\n' "$STUB_RULES" ;;
    esac ;;
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

# --- block (a2): a pinned context needs a run from its pinned app (#384) --------
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

if [ "$fail" -ne 0 ]; then
  echo "blocked-state-block.test.sh: FAILED" >&2
  exit 1
fi
echo "blocked-state-block.test.sh: all passed"
