#!/bin/sh
# Fixture tests for scripts/invariants-check.sh's check 16: one spec-reaction rule, one
# implementation -- plan-anchor.sh and architect-review call spec-reaction.sh and no other bin/ script matches an
# approving reaction content itself (#613).
#
# Each case mutates a COPY of the real tree and asserts the check fires (or stays silent), so
# a check that only passes on the real tree cannot hide. Only check 16's own message is
# asserted, never the script's overall exit.
#
# Permitted toolset: POSIX sh. No jq, no yq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/scripts/invariants-check.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
MSG="a second spec-reaction implementation, or a caller no longer calls it"

tree() {
  d="$tmp/$1"
  mkdir -p "$d"
  cp -R "$root_dir/plugins" "$d/plugins"
  echo "$d"
}

run() { ( cd "$1" && bash "$script" 2>&1 >/dev/null ) || true; }

assert_fires() { # <desc> <dir>
  if run "$2" | grep -qF -- "$MSG"; then
    echo "ok - $1"
  else
    echo "FAIL - $1: expected check 16 to fire" >&2
    fail=1
  fi
}

assert_silent() { # <desc> <dir>
  if run "$2" | grep -qF -- "$MSG"; then
    echo "FAIL - $1: check 16 fired" >&2
    fail=1
  else
    echo "ok - $1"
  fi
}

# Control: the real tree is clean.
d="$(tree control)"
assert_silent "real tree passes" "$d"

# architect-review no longer calling the predicate fires.
d="$(tree nocall)"
f="$(ls "$d"/plugins/*/skills/architect-review/SKILL.md)"
sed 's/spec-reaction\.sh/some-other-check.sh/g' "$f" >"$f.new" && mv "$f.new" "$f"
assert_fires "architect-review without a spec-reaction.sh call fires" "$d"

# plan-anchor.sh regaining the inline case pattern fires.
d="$(tree inlinecase)"
f="$(ls "$d"/plugins/*/bin/plan-anchor.sh)"
printf '%s\n' "case \"\$r_content\" in '+1' | heart | hooray | rocket) : ;; esac" >>"$f"
assert_fires "plan-anchor.sh with an inline reaction match fires" "$d"

# plan-anchor.sh no longer calling the predicate fires.
d="$(tree nocallanchor)"
f="$(ls "$d"/plugins/*/bin/plan-anchor.sh)"
sed 's#sh "\$sr" "\$c_updated"#true "\$c_updated"#' "$f" >"$f.new" && mv "$f.new" "$f"
assert_fires "plan-anchor.sh without a spec-reaction.sh call fires" "$d"

# Another bin/ script matching the content in awk form fires too.
d="$(tree inlineawk)"
f="$(ls "$d"/plugins/*/bin/review-gate-state.sh)"
printf '%s\n' '# $2 == "hooray"' >>"$f"
assert_fires "another bin script comparing == \"hooray\" fires" "$d"

# The predicate itself may match the contents: it is the one implementation.
d="$(tree selfok)"
assert_silent "spec-reaction.sh matching the contents is the implementation" "$d"

# A tree with no predicate fails, never passes.
d="$(tree nopredicate)"
rm -f "$d"/plugins/*/bin/spec-reaction.sh
assert_fires "a missing spec-reaction.sh fires" "$d"

# A tree with no architect-review skill fails, never passes.
d="$(tree noskill)"
rm -rf "$d"/plugins/*/skills/architect-review
assert_fires "a missing architect-review skill fires" "$d"

# A tree with no plan-anchor.sh fails, never passes.
d="$(tree noanchor)"
rm -f "$d"/plugins/*/bin/plan-anchor.sh
assert_fires "a missing plan-anchor.sh fires" "$d"

[ "$fail" -eq 0 ]
