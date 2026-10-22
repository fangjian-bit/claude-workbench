#!/bin/sh
# Fixture tests for scripts/invariants-check.sh's check 3: the reach check precedes the
# ruleset call in /resume.
#
# The check's ordering half was a silent no-op for its whole life: it looked for the
# ruleset call as `gh api repos/{repo}/rules/branches`, but every real call is written
# `gh api --paginate repos/{repo}/rules/branches/...`, so the pattern never matched, the
# `[ -n "$ruleset" ]` guard swallowed the empty result, and a wrong ordering could not
# fail. No fixture would have gone red against that bug, because the real file's order is
# already right -- a test that only feeds the real tree is a control that yields the same
# answer with or without the fix. So each case here mutates a COPY of the real /resume
# skill into a wrong order (or removes the call) and asserts the check fires. Run against
# the pre-#162 script, the `paginate`, `twoflags`, `missing` and `not_a_call` cases fail;
# `noflag` passes there too (the old pattern matched it) and stays as a guard against a
# later fix over-tightening the pattern. The real-tree case is a deliberate control.
# See issue #162.
#
# Only check 3's own messages are asserted, never the script's overall exit: every case but
# the control runs just that check (`--only 3`), and the control runs them all.
#
# Permitted toolset: POSIX sh. No jq, no yq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/scripts/invariants-check.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# One read of the checkout per run: every fixture copies from this, never from the root.
pristine="$tmp/.pristine"
mkdir -p "$pristine"
cp -R "$root_dir/plugins" "$pristine/plugins"

fail=0

ORDER_MSG="/resume checks the ruleset before establishing reach"
MISSING_MSG="/resume's ruleset call could not be found"
REACH_LINE='gh api repos/{repo} --jq .permissions'

# Fresh copy of the real plugins/ tree, cwd for one run of the script.
tree() {
  d="$tmp/$1"
  mkdir -p "$d"
  cp -R "$pristine/plugins" "$d/plugins"
  echo "$d"
}

resume_in() { ls "$1"/plugins/*/skills/resume/SKILL.md; }

sel="--only 3"

run() { # run <dir> -> stderr on stdout; a usage exit (2) leaves a marker
  ( cd "$1" || exit 1; rc=0; bash "$script" $sel 2>&1 >/dev/null || rc=$?; [ "$rc" -ne 2 ] || : >"$tmp/usage-exit" ) || true
}

assert_fires() { # assert_fires <desc> <dir> <message>
  if run "$2" | grep -qF -- "$3"; then
    echo "ok - $1"
  else
    echo "FAIL - $1: expected [$3] in the check's output" >&2
    fail=1
  fi
}

assert_silent() { # assert_silent <desc> <dir> <message>
  if run "$2" | grep -qF -- "$3"; then
    echo "FAIL - $1: unexpected [$3] in the check's output" >&2
    fail=1
  else
    echo "ok - $1"
  fi
}

# Move the reach call after everything else: rename the original occurrence, append a
# fresh one at end of file. Leaves the ruleset call untouched, so reach > ruleset.
reorder() { # reorder <resume-file>
  sed "s|$REACH_LINE|gh api repos/{repo} --jq .PERM|" "$1" >"$1.new"
  printf '\n%s\n' "$REACH_LINE" >>"$1.new"
  mv "$1.new" "$1"
}

# --- control: the real skill is in the right order ---------------------------
sel=
d="$(tree real)"
assert_silent "real tree: reach precedes the ruleset call" "$d" "$ORDER_MSG"
assert_silent "real tree: the ruleset call is found" "$d" "$MISSING_MSG"
sel="--only 3"

# --- the actual form: `gh api --paginate repos/...` (the #162 defect) ----------
d="$(tree paginate)"
grep -q 'gh api --paginate repos/{repo}/rules/branches' "$(resume_in "$d")" || {
  echo "FAIL - fixture premise: the real /resume no longer writes the --paginate form" >&2
  fail=1
}
reorder "$(resume_in "$d")"
assert_fires "wrong order fires against the real --paginate form" "$d" "$ORDER_MSG"

# Rewrite the ruleset call in a copy's resume skill, and fail the suite if the rewrite did
# not land -- a sed that silently changes nothing would let a case pass vacuously.
# $2 must not contain `|`, `&` or a backslash: it is spliced into a sed replacement.
subst() { # subst <dir> <replacement-for-"gh api --paginate repos/{repo}/rules/branches">
  r="$(resume_in "$1")"
  sed "s|gh api --paginate repos/{repo}/rules/branches|$2|" "$r" >"$1/r.new" && mv "$1/r.new" "$r"
  if grep -qF -- "gh api --paginate repos/{repo}/rules/branches" "$r" || ! grep -qF -- "$2" "$r"; then
    echo "FAIL - fixture premise: the substitution [$2] did not apply" >&2
    fail=1
  fi
}

# --- flag placement: no flag, and more than one flag -------------------------
d="$(tree noflag)"
subst "$d" 'gh api repos/{repo}/rules/branches'
reorder "$(resume_in "$d")"
assert_fires "wrong order fires with no flag between gh api and the path" "$d" "$ORDER_MSG"

d="$(tree twoflags)"
subst "$d" 'gh api --paginate --jq . repos/{repo}/rules/branches'
reorder "$(resume_in "$d")"
assert_fires "wrong order fires with two flags before the path" "$d" "$ORDER_MSG"

# --- the pattern drifting again must be loud, not silent ---------------------
d="$(tree missing)"
subst "$d" 'gh api --paginate repos/{repo}/rulesets/x'
assert_fires "a reworded ruleset call is reported, not silently passed" "$d" "$MISSING_MSG"

# --- a line that merely names the path is not the ruleset call ---------------
# The `gh api` prefix is what stops this echo line being taken for the call; without it
# the pattern would match here and the missing-call report would not fire.
d="$(tree not_a_call)"
subst "$d" 'echo repos/{repo}/rules/branches'
assert_fires "a non-call line naming the path is not mistaken for the call" "$d" "$MISSING_MSG"

[ ! -e "$tmp/usage-exit" ] || { echo "FAIL - the checker exited 2 (usage) in at least one case" >&2; fail=1; }

exit "$fail"
