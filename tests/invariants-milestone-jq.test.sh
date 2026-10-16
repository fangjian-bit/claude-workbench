#!/bin/sh
# Fixture tests for scripts/invariants-check.sh's check 19: a milestone is never read
# without a projecting --jq, and a description read goes to a file and through
# blocking-criteria.sh (#640).
#
# Each case mutates a COPY of the real tree and asserts the check fires (or stays silent),
# so a check that only passes on the real tree cannot hide. Only check 19's own message is
# asserted, never the script's overall exit.
#
# Permitted toolset: POSIX sh. No jq, no yq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/scripts/invariants-check.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
MSG="blocking-criteria.sh (#640)"

tree() {
  d="$tmp/$1"
  mkdir -p "$d"
  cp -R "$root_dir/plugins" "$d/plugins"
  echo "$d"
}

run() { ( cd "$1" && bash "$script" 2>&1 >/dev/null ) || true; }

assert_fires() { # <desc> <dir> [<substring>]
  out="$(run "$2")"
  if printf '%s\n' "$out" | grep -qF -- "$MSG" && { [ -z "${3:-}" ] || printf '%s\n' "$out" | grep -qF -- "$3"; }; then
    echo "ok - $1"
  else
    echo "FAIL - $1: expected check 19 to fire" >&2
    fail=1
  fi
}

assert_silent() { # <desc> <dir>
  if run "$2" | grep -qF -- "$MSG"; then
    echo "FAIL - $1: check 19 fired" >&2
    fail=1
  else
    echo "ok - $1"
  fi
}

skill() { ls "$1"/plugins/*/skills/"$2"/SKILL.md; }

# Control: the real tree is clean.
d="$(tree control)"
assert_silent "real tree passes" "$d"

# The real PATCH close, with its --jq removed (the read-back on the next line stays projected).
d="$(tree patch)"
f="$(skill "$d" archive-sprint)"
grep -qF -- '-f state=closed --jq .state' "$f" || { echo "FAIL - the PATCH line is not in archive-sprint" >&2; fail=1; }
sed 's/ -f state=closed --jq \.state/ -f state=closed/' "$f" >"$f.new" && mv "$f.new" "$f"
assert_fires "the PATCH close without --jq fires" "$d" "archive-sprint"

# Prose that names gh api and milestones/ with no --jq.
d="$(tree prose)"
f="$(skill "$d" ship)"
printf '\nAlso run `gh api repos/{backlog.repo}/milestones/7` and look.\n' >>"$f"
assert_fires "a prose line naming gh api and milestones/ without --jq fires" "$d" "ship"

# A description read with no redirect, with only 2>/dev/null, and followed by cat.
d="$(tree noredirect)"
f="$(skill "$d" ship)"
printf "\n    gh api \"repos/\$BR/milestones/\$N\" --jq '.description // \"\"' && blocking-criteria.sh \"\$T/d\"\n" >>"$f"
assert_fires "a description read with no redirect fires" "$d" "ship"

d="$(tree devnull)"
f="$(skill "$d" ship)"
printf "\n    gh api \"repos/\$BR/milestones/\$N\" --jq '.description // \"\"' 2>/dev/null && blocking-criteria.sh \"\$T/d\"\n" >>"$f"
assert_fires "a description read with only 2>/dev/null fires" "$d" "ship"

d="$(tree cat)"
f="$(skill "$d" ship)"
printf "\n    gh api \"repos/\$BR/milestones/\$N\" --jq '.description // \"\"' >\"\$T/d\" && blocking-criteria.sh \"\$T/d\" && cat \"\$T/d\"\n" >>"$f"
assert_fires "a description read followed by cat fires" "$d" "ship"

d="$(tree toscreen)"
f="$(skill "$d" ship)"
printf "\n    gh api \"repos/\$BR/milestones/\$N\" --jq '.description // \"\"' >/dev/stdout && blocking-criteria.sh \"\$T/d\"\n" >>"$f"
assert_fires "a description read aimed at /dev/stdout fires" "$d" "ship"

d="$(tree tostderr)"
f="$(skill "$d" ship)"
printf "\n    gh api \"repos/\$BR/milestones/\$N\" --jq '.description' >&2 && blocking-criteria.sh \"\$T/d\"\n" >>"$f"
assert_fires "a description read sent to stderr with >&2 fires" "$d" "ship"

d="$(tree noscript)"
f="$(skill "$d" ship)"
printf "\n    gh api \"repos/\$BR/milestones/\$N\" --jq '.description // \"\"' >\"\$T/d\"\n" >>"$f"
assert_fires "a description read that never reaches the script fires" "$d" "ship"

# A milestone read whose filter passes whole objects through.
d="$(tree dot)"
f="$(skill "$d" ship)"
printf '\n    gh api repos/{backlog.repo}/milestones/7 --jq .\n' >>"$f"
assert_fires "a milestone read with --jq . fires" "$d" "ship"

d="$(tree object)"
f="$(skill "$d" ship)"
printf "\n    gh api repos/{backlog.repo}/milestones/7 --jq '.. | .description?'\n" >>"$f"
assert_fires "a milestone read with a recursive filter fires" "$d" "ship"

d="$(tree list)"
f="$(skill "$d" ship)"
printf '\n    gh api "repos/{backlog.repo}/milestones?state=open" --jq ".[]"\n' >>"$f"
assert_fires "a milestone list read with .[] fires" "$d" "ship"

# ship no longer names the script.
d="$(tree shipnoscript)"
f="$(skill "$d" ship)"
sed 's/blocking-criteria\.sh/the-projection/g' "$f" >"$f.new" && mv "$f.new" "$f"
assert_fires "a ship/SKILL.md that no longer names blocking-criteria.sh fires" "$d" "ship"

# A missing skill file, and a missing script.
d="$(tree missing)"
rm -f "$(skill "$d" archive-sprint)"
assert_fires "a missing archive-sprint skill file fires" "$d" "archive-sprint"

d="$(tree noscriptfile)"
rm -f "$d"/plugins/*/bin/blocking-criteria.sh
assert_fires "a missing blocking-criteria.sh fires" "$d" "no plugins/*/bin/blocking-criteria.sh"

# Shapes that pass.
d="$(tree continued)"
f="$(skill "$d" ship)"
printf "\n    gh api \"repos/\$BR/milestones/\$N\" \\\\\n      --jq '.state' | head -n 1\n" >>"$f"
assert_silent "a backslash-continued call with --jq on its second line passes" "$d"

d="$(tree goodread)"
f="$(skill "$d" ship)"
printf "\n    gh api \"repos/\$BR/milestones/\$N\" --jq '.description // \"\"' >\"\$T/d\" 2>\"\$T/err\" && blocking-criteria.sh \"\$T/d\"\n" >>"$f"
assert_silent "a description read to a file and through the script passes" "$d"

d="$(tree plansprint)"
f="$(skill "$d" plan-sprint)"
printf '\n    gh api repos/{backlog.repo}/milestones/7\n' >>"$f"
assert_silent "plan-sprint reads descriptions in full by design and is exempt" "$d"

[ "$fail" -eq 0 ]
