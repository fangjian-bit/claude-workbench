#!/bin/sh
# Fixture tests for scripts/invariants-check.sh's check 15: architect-review never loads the
# task issue's body under an identities map, and the schema doc does not call it uncovered (#566).
#
# Each case mutates a COPY of the real tree and asserts the check fires (or stays silent), so
# a check that only passes on the real tree cannot hide. Only check 15's own message is
# asserted, never the script's overall exit.
#
# Every case but the first control runs just check 15 (`--only 15`); that control runs the full checker.
#
# Permitted toolset: POSIX sh. No jq, no yq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/scripts/invariants-check.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
MSG="architect-review may load the task issue's body under an identities map"

tree() {
  d="$tmp/$1"
  mkdir -p "$d"
  cp -R "$root_dir/plugins" "$d/plugins"
  echo "$d"
}

sel="--only 15"

run() { ( cd "$1" && bash "$script" $sel 2>&1 >/dev/null ) || true; }

assert_fires() { # <desc> <dir>
  if run "$2" | grep -qF -- "$MSG"; then
    echo "ok - $1"
  else
    echo "FAIL - $1: expected check 15 to fire" >&2
    fail=1
  fi
}

assert_silent() { # <desc> <dir>
  if run "$2" | grep -qF -- "$MSG"; then
    echo "FAIL - $1: check 15 fired" >&2
    fail=1
  else
    echo "ok - $1"
  fi
}

# Control: the real tree is clean.
sel=
d="$(tree control)"
assert_silent "real tree passes" "$d"
sel="--only 15"

# The map-mode rule removed fires.
d="$(tree norule)"
f="$(ls "$d"/plugins/*/skills/architect-review/SKILL.md)"
sed 's/the body is never loaded/the body is loaded/' "$f" >"$f.new" && mv "$f.new" "$f"
assert_fires "architect-review without the map-mode rule fires" "$d"

# The unconditional body-and-comment phrasing coming back fires.
d="$(tree oldphrase)"
f="$(ls "$d"/plugins/*/skills/architect-review/SKILL.md)"
printf '%s\n' '(`{repo}` when `null`; its body and, when one exists, its anchored spec comment)' >>"$f"
assert_fires "the unconditional body phrasing fires" "$d"

# The schema doc calling architect-review uncovered again fires.
d="$(tree notcovered)"
f="$(ls "$d"/plugins/*/reference/project-schema.md)"
printf '%s\n' '`/way-of-working:architect-review` is not yet covered.' >>"$f"
assert_fires "the schema doc saying not yet covered fires" "$d"

# A tree with no architect-review skill fails, never passes.
d="$(tree noskill)"
rm -rf "$d"/plugins/*/skills/architect-review
assert_fires "a missing architect-review skill fires" "$d"

# A tree with no schema doc fails, never passes.
d="$(tree noschema)"
rm -f "$d"/plugins/*/reference/project-schema.md
assert_fires "a missing schema doc fires" "$d"

[ "$fail" -eq 0 ]
