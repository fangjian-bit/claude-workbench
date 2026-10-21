#!/bin/sh
# Fixture tests for scripts/invariants-check.sh's check 16: one spec-reaction rule, one
# implementation -- plan-anchor.sh, spec-comment.sh, architect-review and the loop's dispatch
# preflight (scripts/loop/preflight.sh, #666) call spec-reaction.sh and no other bin/ script matches an
# approving reaction content itself (#613).
#
# Each case mutates a COPY of the real tree and asserts the check fires (or stays silent), so
# a check that only passes on the real tree cannot hide. Only check 16's own message is
# asserted, never the script's overall exit.
#
# Every case but the first control runs just check 16 (`--only 16`); that control runs the full checker.
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
  mkdir -p "$d/scripts/loop"
  cp "$root_dir/scripts/loop/preflight.sh" "$d/scripts/loop/preflight.sh"
  echo "$d"
}

sel="--only 16"

run() { ( cd "$1" && bash "$script" $sel 2>&1 >/dev/null ) || true; }

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
sel=
d="$(tree control)"
assert_silent "real tree passes" "$d"
sel="--only 16"

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

# spec-comment.sh no longer calling the predicate (the call line mutated) fires (#660).
d="$(tree nocallcomment)"
f="$(ls "$d"/plugins/*/bin/spec-comment.sh)"
sed 's#sh "\$sr" "\$updated" "\$ids" <"\$rx"#true "\$updated" "\$ids" <"\$rx"#' "$f" >"$f.new" && mv "$f.new" "$f"
assert_fires "spec-comment.sh without a spec-reaction.sh call fires" "$d"

# plan-anchor.sh passing another id list than the maintainers' fires (#660).
d="$(tree anchorarg)"
f="$(ls "$d"/plugins/*/bin/plan-anchor.sh)"
sed 's#sh "\$sr" "\$c_updated" "\$maint_ids"#sh "\$sr" "\$c_updated" "\$dev_id"#' "$f" >"$f.new" && mv "$f.new" "$f"
assert_fires "plan-anchor.sh passing another id list fires" "$d"

# A tree with no spec-comment.sh fails, never passes.
d="$(tree nocommentscript)"
rm -f "$d"/plugins/*/bin/spec-comment.sh
assert_fires "a missing spec-comment.sh fires" "$d"

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

# The loop's dispatch preflight (#666) is held to the same rule from outside plugins/*/bin/.
pf=scripts/loop/preflight.sh
d="$(tree pfnocall)"
grep -v 'sh "\$sr" "\$c_updated" "\$maint_ids"' "$d/$pf" >"$d/$pf.new" && mv "$d/$pf.new" "$d/$pf"
assert_fires "preflight.sh without its spec-reaction.sh call line fires" "$d"

d="$(tree pfinlineplus)"
printf '%s\n' 'x=$(jq -r ".[] | select(.content | IN(\"+1\",\"heart\",\"hooray\",\"rocket\"))" f)' >>"$d/$pf"
assert_fires "preflight.sh with a non-comment IN(...) reaction match fires" "$d"

d="$(tree pfinlineeq)"
printf '%s\n' 'x=$(jq -r "select(.content == \"hooray\")" f)' >>"$d/$pf"
assert_fires "preflight.sh with a non-comment == hooray comparison fires" "$d"

d="$(tree pfcommentcall)"
sed 's#sh "\$sr" "\$c_updated" "\$maint_ids" <"\$reactions"#true#' "$d/$pf" >"$d/$pf.new" && mv "$d/$pf.new" "$d/$pf"
printf '%s\n' '# sh "$sr" "$c_updated" "$maint_ids" <"$reactions"' >>"$d/$pf"
assert_fires "preflight.sh with the call line only in a comment fires" "$d"

d="$(tree pfgone)"
rm -f "$d/$pf"
assert_fires "a missing preflight.sh fires" "$d"

d="$(tree pfcommentok)"
printf '%s\n' '# hooray and rocket are named in this header and in the jq comments' >>"$d/$pf"
assert_silent "preflight.sh naming the contents in a comment is silent" "$d"


# bin/spec-find.sh (#662) is held to the preflight's rule: its call line on a non-comment line.
sf=plugins/way-of-working/bin/spec-find.sh
d="$(tree sfnocall)"
f="$d/$sf"
sed 's#sh "\$sr" "\$c_updated" "\$maint_ids" <"\$rx"#true "\$c_updated" "\$maint_ids" <"\$rx"#' "$f" >"$f.new" && mv "$f.new" "$f"
assert_fires "spec-find.sh without its spec-reaction.sh call line fires" "$d"

d="$(tree sfcommentcall)"
f="$d/$sf"
sed 's#sh "\$sr" "\$c_updated" "\$maint_ids" <"\$rx"#true#' "$f" >"$f.new" && mv "$f.new" "$f"
printf '%s\n' '# sh "$sr" "$c_updated" "$maint_ids" <"$rx"' >>"$f"
assert_fires "spec-find.sh with the call line only in a comment fires" "$d"

d="$(tree sfgone)"
rm -f "$d/$sf"
assert_fires "a missing spec-find.sh fires" "$d"


# bin/spec-issue.sh and bin/spec-post.sh (#664, WB-D32) must each carry their call line on a
# non-comment line, and a tree that lacks either fails.
for name in spec-issue spec-post; do
  sp=plugins/way-of-working/bin/$name.sh
  d="$(tree ${name}nocall)"
  f="$d/$sp"
  sed 's#sh "\$sr" "\$i_updated" "\$maint_ids" <"\$tmp/reactions.tsv"#true "\$i_updated" "\$maint_ids" <"\$tmp/reactions.tsv"#' "$f" >"$f.new" && mv "$f.new" "$f"
  assert_fires "$name.sh without its spec-reaction.sh call line fires" "$d"

  d="$(tree ${name}commentcall)"
  f="$d/$sp"
  sed 's#sh "\$sr" "\$i_updated" "\$maint_ids" <"\$tmp/reactions.tsv"#true#' "$f" >"$f.new" && mv "$f.new" "$f"
  printf '%s\n' '# sh "$sr" "$i_updated" "$maint_ids" <"$tmp/reactions.tsv"' >>"$f"
  assert_fires "$name.sh with the call line only in a comment fires" "$d"

  d="$(tree ${name}gone)"
  rm -f "$d/$sp"
  assert_fires "a missing $name.sh fires" "$d"
done

[ "$fail" -eq 0 ]
