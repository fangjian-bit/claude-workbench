#!/bin/sh
# Fixture tests for scripts/invariants-check.sh's check 25: every plugins/*/agents/*.md name is
# a whole token in both manifest descriptions of its plugin (#932).
#
# Each case mutates a COPY of the real tree and asserts the check fires (or stays silent), so
# a check that only passes on the real tree cannot hide. Only check 25's own message is
# asserted, never the script's overall exit; a usage exit (2) fails the suite.
#
# Every case but the first control runs just check 25 (`--only 25`); that control runs the full checker.
#
# Permitted toolset: POSIX sh, sed, grep and jq (one fixture edits a manifest with it; the checker
# needs jq too, so this test skips, loudly, without it). No yq, no python.
set -eu

command -v jq >/dev/null 2>&1 || { echo "SKIP - jq is not on PATH; check 25 cannot run" >&2; exit 0; }

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/scripts/invariants-check.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# One read of the checkout per run: every fixture copies from this, never from the root.
pristine="$tmp/.pristine"
mkdir -p "$pristine"
cp -R "$root_dir/plugins" "$pristine/plugins"
cp -R "$root_dir/.claude-plugin" "$pristine/.claude-plugin"

fail=0
MSG='an agent is missing from a manifest description (#932)'

tree() {
  d="$tmp/$1"
  mkdir -p "$d"
  cp -R "$pristine/plugins" "$d/plugins"
  cp -R "$pristine/.claude-plugin" "$d/.claude-plugin"
  echo "$d"
}

sel="--only 25"

run() { ( cd "$1" || exit 1; rc=0; bash "$script" $sel 2>&1 >/dev/null || rc=$?; [ "$rc" -ne 2 ] || : >"$tmp/usage-exit" ) || true; }

assert_fires() { # <desc> <dir>
  if run "$2" | grep -qF -- "$MSG"; then
    echo "ok - $1"
  else
    echo "FAIL - $1: expected check 25 to fire" >&2
    fail=1
  fi
}

assert_silent() { # <desc> <dir>
  if run "$2" | grep -qF -- "$MSG"; then
    echo "FAIL - $1: check 25 fired" >&2
    fail=1
  else
    echo "ok - $1"
  fi
}

plugin_json() { ls "$1"/plugins/way-of-working/.claude-plugin/plugin.json; }
market() { echo "$1/.claude-plugin/marketplace.json"; }
newagent() { # <dir>: a new agent file named zzqagent
  printf -- '---\nname: zzqagent\ndescription: x\n---\nbody\n' >"$1/plugins/way-of-working/agents/zzqagent.md"
}
# Add a name after "architect/coder" in a manifest's description (the one place both hold it).
addname() { # <file> <name>
  sed "s|architect/coder|architect/$2/coder|" "$1" >"$1.new" && mv "$1.new" "$1"
}

# Control: the real tree is clean, under the full checker.
sel=
d="$(tree control)"
assert_silent "real tree passes" "$d"
sel="--only 25"

d="$(tree neither)"
newagent "$d"
assert_fires "a new agent named in neither description fires" "$d"

d="$(tree pluginonly)"
newagent "$d"
addname "$(plugin_json "$d")" zzqagent
assert_fires "a new agent named only in plugin.json fires" "$d"

d="$(tree marketonly)"
newagent "$d"
addname "$(market "$d")" zzqagent
assert_fires "a new agent named only in marketplace.json fires" "$d"

d="$(tree both)"
newagent "$d"
addname "$(plugin_json "$d")" zzqagent
addname "$(market "$d")" zzqagent
assert_silent "a new agent named in both descriptions is silent" "$d"

d="$(tree token)"
sed 's/transcript-reader/transcript-readers/g' "$(market "$d")" >"$d/m.new" && mv "$d/m.new" "$(market "$d")"
assert_fires "transcript-reader rewritten to transcript-readers in one manifest fires" "$d"

d="$(tree hyphen)"
for m in "$(plugin_json "$d")" "$(market "$d")"; do
  sed 's|the architect/coder/|the coder/|' "$m" >"$m.new" && mv "$m.new" "$m"
done
assert_fires "architect left only inside architect-review fires (hyphen is not a boundary)" "$d"

d="$(tree leading)"
sed 's/transcript-reader/xtranscript-reader/g' "$(market "$d")" >"$d/m.new" && mv "$d/m.new" "$(market "$d")"
assert_fires "a letter before the name fires (leading boundary)" "$d"

d="$(tree dupname)"
f="$d/plugins/way-of-working/agents/coder.md"
sed '/^name: coder$/p' "$f" >"$f.new" && mv "$f.new" "$f"
assert_fires "an agent file with two name: lines fires" "$d"

d="$(tree dupentry)"
m="$(market "$d")"
jq '.plugins += [.plugins[] | select(.name == "way-of-working")]' "$m" >"$m.new" && mv "$m.new" "$m"
assert_fires "two marketplace entries for the plugin fire" "$d"

d="$(tree noname)"
f="$(ls "$d"/plugins/way-of-working/agents/coder.md)"
grep -v '^name:' "$f" >"$f.new" && mv "$f.new" "$f"
assert_fires "an agent file with no name: line fires" "$d"

d="$(tree noentry)"
sed 's/"name": "way-of-working"/"name": "other-plugin"/' "$(market "$d")" >"$d/m.new" && mv "$d/m.new" "$(market "$d")"
assert_fires "no marketplace entry for the plugin fires" "$d"

d="$(tree nomarket)"
rm -f "$(market "$d")"
assert_fires "a missing marketplace.json fires" "$d"

d="$(tree noagents)"
rm -rf "$d"/plugins/*/agents
assert_fires "a tree with no agent files fires" "$d"

[ ! -e "$tmp/usage-exit" ] || { echo "FAIL - the checker exited 2 (usage) in at least one case" >&2; fail=1; }

[ "$fail" -eq 0 ]
