#!/bin/sh
# Fixture tests for scripts/invariants-check.sh's check 11: `gh` output is never piped
# straight into a bin/ predicate script (#243).
#
# A test that only feeds the real tree is a control that answers the same with or without
# the check (the real skills already capture first), so each case here mutates a COPY of
# the real pr-checks skill to reintroduce a pipe and asserts the check fires. The `safe_*`
# cases are the other half: the captured form the skill actually uses, and `||`, must NOT
# fire, or the check would reject the very shape it exists to protect.
#
# Only check 11's own message is asserted, never the script's overall exit: every case but the
# control runs just that check (`--only 11`), and the control runs them all.
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
MSG="gh output is piped directly into a bin/ predicate script"

tree() {
  d="$tmp/$1"
  mkdir -p "$d"
  cp -R "$pristine/plugins" "$d/plugins"
  echo "$d"
}

skill_in() { ls "$1"/plugins/*/skills/pr-checks/SKILL.md; }
agent_in() { ls "$1"/plugins/*/agents/architect.md; }

sel="--only 11"

run() { ( cd "$1" || exit 1; rc=0; bash "$script" $sel 2>&1 >/dev/null || rc=$?; [ "$rc" -ne 2 ] || : >"$tmp/usage-exit" ) || true; }

assert_fires() { # <desc> <dir>
  if run "$2" | grep -qF -- "$MSG"; then echo "ok - $1"
  else echo "FAIL - $1: expected [$MSG]" >&2; fail=1; fi
}

assert_silent() { # <desc> <dir>
  if run "$2" | grep -qF -- "$MSG"; then echo "FAIL - $1: unexpected [$MSG]" >&2; fail=1
  else echo "ok - $1"; fi
}

append() { printf '\n%s\n' "$2" >>"$1"; } # <file> <line(s)>

# --- control: the real tree ----------------------------------------------------
sel=
d="$(tree real)"
assert_silent "real tree passes" "$d"
sel="--only 11"

# --- the defect, in each shape it can take -------------------------------------
d="$(tree plain)"
append "$(skill_in "$d")" 'gh api repos/x/rules/branches/main | blocked-state.sh BLOCKED 1'
assert_fires "gh api | blocked-state.sh" "$d"

d="$(tree review)"
append "$(skill_in "$d")" 'gh api repos/x/pulls/1/reviews | review-gate-state.sh check'
assert_fires "gh api | review-gate-state.sh" "$d"

d="$(tree jqstage)"
append "$(skill_in "$d")" 'gh api repos/x --jq . | jq -r .y | blocked-state.sh BLOCKED 1'
assert_fires "a jq stage between gh and the predicate" "$d"

d="$(tree path)"
append "$(skill_in "$d")" 'gh api repos/x | "$PLUGIN_BIN"/blocked-state.sh BLOCKED 1'
assert_fires "predicate invoked by path" "$d"

d="$(tree cont)"
append "$(skill_in "$d")" 'gh api repos/x \
  | blocked-state.sh BLOCKED 1'
assert_fires "pipe on a backslash-continued line" "$d"

d="$(tree appendix)"
append "$(ls "$d"/plugins/*/skills/resume/appendices/schema-interview.md)" 'gh api repos/x | blocked-state.sh BLOCKED 1'
assert_fires "a skill appendix, not only SKILL.md" "$d"

d="$(tree agent)"
append "$(agent_in "$d")" 'gh pr view 1 | blocked-state.sh BLOCKED 1'
assert_fires "an agent file, not only a skill" "$d"

d="$(tree anybin)"
append "$(skill_in "$d")" 'gh api repos/x | cursor-drift.sh abc'
assert_fires "any bin/ script is a target, not a fixed list" "$d"

d="$(tree insub)"
append "$(skill_in "$d")" 'G=$(gh api repos/x | blocked-state.sh BLOCKED 1)'
assert_fires "pipe inside a command substitution" "$d"

# --- shapes the first version missed (both critics, round 1) -------------------
# The real regression: pr-checks' block (b), with its capture taken out so the gh call is
# piped straight into the predicate. Its --jq filter is full of parentheses, which the
# first matcher refused -- every toy fixture above is paren-free, so only this one sees it.
d="$(tree realblock)"
sk="$(skill_in "$d")"
sed -e 's/T=\$(gh api/gh api/' -e '/gh api --paginate/s/) &&$/ |/' \
    -e 's/^ *{ \[ -z.*} | blocked-state/blocked-state/' "$sk" >"$sk.new"
mv "$sk.new" "$sk"
grep -q '^gh api --paginate\|^ *gh api --paginate' "$sk" || { echo "FAIL - realblock: mutation did not apply" >&2; fail=1; }
assert_fires "pr-checks block (b) with its capture removed" "$d"

d="$(tree jqparens)"
append "$(skill_in "$d")" "gh api repos/x --jq '.[] | select(.type==\"y\") | .type' | blocked-state.sh BLOCKED 1"
assert_fires "parentheses in a --jq filter" "$d"

d="$(tree trailing)"
append "$(skill_in "$d")" 'gh api repos/x |
  blocked-state.sh BLOCKED 1'
assert_fires "pipe at end of line, no backslash" "$d"

d="$(tree stderr)"
append "$(skill_in "$d")" 'gh api repos/x 2>&1 | blocked-state.sh BLOCKED 1'
assert_fires "2>&1 on the gh side" "$d"

d="$(tree pipeamp)"
append "$(skill_in "$d")" 'gh api repos/x |& blocked-state.sh BLOCKED 1'
assert_fires "|& is a pipe" "$d"

d="$(tree interp)"
append "$(skill_in "$d")" 'gh api repos/x | bash "$P/bin/blocked-state.sh" BLOCKED 1'
assert_fires "predicate run under bash" "$d"

d="$(tree subarg)"
append "$(skill_in "$d")" 'gh api "repos/$(git remote)/x" | blocked-state.sh BLOCKED 1'
assert_fires "command substitution inside a gh argument" "$d"

d="$(tree crlf)"
sk="$(skill_in "$d")"
printf 'gh api repos/x \\\r\n  | blocked-state.sh BLOCKED 1\r\n' >>"$sk"
assert_fires "CRLF line endings" "$d"

# --- shapes the second round found (both critics, round 2) ---------------------
# The repo's own capture style is double-quoted: "$(gh ... | pred)".
d="$(tree dqcapture)"
append "$(skill_in "$d")" 'G="$(gh api repos/x --jq '"'"'.a'"'"' | blocked-state.sh BLOCKED 1)"'
assert_fires 'quoted capture "$(gh ... | pred)"' "$d"

d="$(tree query)"
append "$(skill_in "$d")" 'gh api "repos/x/pulls?state=all&per_page=100" | review-gate-state.sh check'
assert_fires "& inside a double-quoted gh argument" "$d"

d="$(tree unqsub)"
append "$(skill_in "$d")" 'gh api repos/$(git remote)/x | blocked-state.sh BLOCKED 1'
assert_fires "unquoted command substitution in a gh argument" "$d"

d="$(tree pipeamp_eol)"
append "$(skill_in "$d")" 'gh api repos/x |&
  blocked-state.sh BLOCKED 1'
assert_fires "|& at end of line" "$d"

d="$(tree wrapper)"
append "$(skill_in "$d")" 'gh api repos/x | timeout 30 blocked-state.sh BLOCKED 1'
assert_fires "predicate behind timeout" "$d"

d="$(tree shflags)"
append "$(skill_in "$d")" 'gh api repos/x | sh -eu blocked-state.sh BLOCKED 1'
assert_fires "predicate under sh with flags" "$d"

# Round 3: quotes on BOTH sides of the pipe. Pairing quotes anywhere but left to right
# re-pairs a closing quote with the next opening one, and the gap holds the pipe.
d="$(tree bothquoted)"
append "$(skill_in "$d")" 'gh api "repos/x/rules/branches/main" | blocked-state.sh "BLOCKED" 1'
assert_fires "plain double-quoted args on both sides of the pipe" "$d"

d="$(tree quotedbin)"
append "$(skill_in "$d")" 'gh api "repos/$REPO/rules" | "$BIN"/blocked-state.sh "$STATE" "$N"'
assert_fires 'quoted "$BIN"/predicate path' "$d"

d="$(tree quotedpath)"
append "$(skill_in "$d")" 'gh api repos/x | bash "$P/bin/blocked-state.sh" BLOCKED 1'
assert_fires "predicate path wholly inside quotes" "$d"

d="$(tree dqjq)"
append "$(skill_in "$d")" 'gh api x --jq "map(.type)" | blocked-state.sh BLOCKED 1'
assert_fires "double-quoted --jq filter ending in a paren" "$d"

# Round 4 (architect, round 3): a leftover closing quote from unwrapping "$(...)" must not
# re-pair with the next span, and an `@` in a jq format string must not collide with the
# pairing markers.
d="$(tree strayquote)"
append "$(skill_in "$d")" 'gh api "$(echo x)" --jq "map(.a)" | blocked-state.sh BLOCKED 1'
assert_fires 'a "$(...)" argument before a quoted --jq filter' "$d"

d="$(tree atsign)"
append "$(skill_in "$d")" 'gh api x --jq ".[] | select(.x) | @tsv" | blocked-state.sh BLOCKED 1'
assert_fires "@tsv in a double-quoted --jq filter" "$d"

# A table row directly above code: the join guard is what keeps the row from swallowing it.
d="$(tree tableabove)"
append "$(skill_in "$d")" '| a | b |
gh api x | blocked-state.sh BLOCKED 1'
assert_fires "code on the line right after a table row" "$d"

# Round 5: shapes only the raw second pass sees. Each hides a real pipe from the quote
# collapse (a leftover closing quote, an apostrophe inside a double-quoted string, a capture
# that does not open its string); the raw pass deletes `"` instead of pairing them.
d="$(tree raw1)"
append "$(skill_in "$d")" 'V="$(gh api a --jq '"'"'.[] | .x'"'"')" && gh api b | blocked-state.sh "$V"'
assert_fires 'a "$(...)" capture earlier on the line' "$d"

d="$(tree raw2)"
append "$(skill_in "$d")" 'V="$(gh api a --jq "select(.a)")" && gh api b | blocked-state.sh "$V"'
assert_fires 'a nested-quote "$(...)" capture earlier on the line' "$d"

d="$(tree raw3)"
append "$(skill_in "$d")" 'echo "can'"'"'t read rule"; gh api x | blocked-state.sh --x '"'"'y'"'"
assert_fires "an apostrophe inside a double-quoted string" "$d"

d="$(tree raw4)"
append "$(skill_in "$d")" 'echo "state: $(gh api x | blocked-state.sh B 1)"'
assert_fires "a capture that does not open its double-quoted string" "$d"

d="$(tree raw5)"
append "$(skill_in "$d")" 'X="$(f "$(g)")"; gh api x | blocked-state.sh "y"'
assert_fires 'nested "$(...)" captures before the pipe' "$d"

# A hit near the TOP of a file larger than a pipe buffer (padded below, so it stays past 64 KiB however small resume gets) must be reported
# as the hit it is, not as "the matcher itself failed": an early-exiting grep SIGPIPEs the
# writer on a big file, and under pipefail that surfaces as status 141.
d="$(tree bigfile)"
rs="$(ls "$d"/plugins/*/skills/resume/SKILL.md)"
{ printf '%s\n' 'gh api x | blocked-state.sh B 1'; cat "$rs"; i=0; while [ "$i" -lt 1500 ]; do echo "padding line $i to keep this fixture past a 64 KiB pipe buffer, xxxxxxxx"; i=$((i+1)); done; } >"$rs.new" && mv "$rs.new" "$rs"
assert_fires "an early hit in a large file is reported as a hit" "$d"
assert_silent_msg() { # <desc> <dir> <message>
  if run "$2" | grep -qF -- "$3"; then echo "FAIL - $1: unexpected [$3]" >&2; fail=1
  else echo "ok - $1"; fi
}
assert_silent_msg "an early hit in a large file is not a matcher failure" "$d" "the matcher itself failed"

# A markdown table row ends in `|`; it must neither be joined to the next row nor trip the
# check, even with a gh cell above a predicate cell.
d="$(tree table)"
append "$(skill_in "$d")" '| tool | feeds |
| `gh api` | `blocked-state.sh` |
| gh pr view | review-gate-state.sh |'
assert_silent "a markdown table naming gh and a predicate" "$d"

# A bin name with a space is rejected by the name guard alone: unlike `a(b.sh` it would
# embed into a VALID pattern, so this fixture cannot be satisfied by the grep-error branch.
d="$(tree badname)"
printf '#!/bin/sh\n' >"$(ls -d "$d"/plugins/*/bin)/a b.sh"
assert_fires_msg() { # <desc> <dir> <message>
  if run "$2" | grep -qF -- "$3"; then echo "ok - $1"
  else echo "FAIL - $1: expected [$3]" >&2; fail=1; fi
}
assert_fires_msg "a bin name outside the safe set fails the check" "$d" "name outside"

# An invalid pattern must also fail the gate, not pass it.
d="$(tree badre)"
printf '#!/bin/sh\n' >"$(ls -d "$d"/plugins/*/bin)/a(b.sh"
assert_fires_msg "an unembeddable bin name fails the check" "$d" "check 11 could not run"

# No bin scripts at all: nothing to build the list from is an error, not a pass.
d="$(tree nobin)"
rm -rf "$d"/plugins/*/bin
assert_fires_msg "no bin scripts found fails the check" "$d" "no plugins/*/bin/*.sh found"

# An upstream stage of the normaliser failing must read as a failure, not as "no match".
# A stub sed that exits non-zero stands in for a missing or non-GNU sed; the file under
# test carries a real hit, so a pass here would be the fail-open itself.
d="$(tree stubsed)"
append "$(skill_in "$d")" 'gh api repos/x | blocked-state.sh BLOCKED 1'
mkdir -p "$tmp/stub"
# It fails only on check 11's own first normalising call (the `|&` rewrite); every other
# call is passed to the real sed. Under `--only 11` no earlier check runs.
real_sed="$(command -v sed)"
printf '#!/bin/sh\ncase "$*" in *"s/|&/|/g"*) exit 4;; esac\nexec "%s" "$@"\n' "$real_sed" >"$tmp/stub/sed"
chmod +x "$tmp/stub/sed"
if ( cd "$d" && PATH="$tmp/stub:$PATH" bash "$script" --only 11 2>&1 >/dev/null ) | grep -qF -- "normalising failed"; then
  echo "ok - a failing sed fails the check"
else
  echo "FAIL - a failing sed: expected [normalising failed]" >&2; fail=1
fi

# --- the safe shapes must stay silent ------------------------------------------
d="$(tree captured)"
append "$(skill_in "$d")" 'T=$(gh api repos/x) && printf '"'"'%s\n'"'"' "$T" | blocked-state.sh BLOCKED 1'
assert_silent "capture first, then feed" "$d"

d="$(tree oror)"
append "$(skill_in "$d")" 'gh api repos/x || blocked-state.sh BLOCKED 1'
assert_silent "|| is not a pipe" "$d"

d="$(tree unrelated)"
append "$(skill_in "$d")" 'gh api repos/x | jq -r .y'
assert_silent "gh piped into a non-bin command" "$d"

[ ! -e "$tmp/usage-exit" ] || { echo "FAIL - the checker exited 2 (usage) in at least one case" >&2; fail=1; }

exit "$fail"
