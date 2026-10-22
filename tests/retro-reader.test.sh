#!/bin/sh
# Static checks for issues #899, #900 and #904: /way-of-working:retro's transcript reader is a plugin agent
# confined by its frontmatter tool list, not by a prose instruction.
# Permitted toolset: POSIX sh, grep, sed.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
agent="${AGENT_FILE:-$root_dir/plugins/way-of-working/agents/transcript-reader.md}"
skill="${SKILL_FILE:-$root_dir/plugins/way-of-working/skills/retro/SKILL.md}"
fail=0
bad() { echo "FAIL: $1" >&2; fail=1; }

if [ ! -f "$agent" ]; then
  bad "$agent: missing"
else
  [ "$(sed -n '2,/^---$/p' "$agent" | grep -c '^tools:')" = 1 ] || bad "$agent: not exactly one tools line in the frontmatter"
  sed -n '2,/^---$/p' "$agent" | grep -qx 'tools: Read, Grep, Glob' || bad "$agent: tools line is not exactly 'Read, Grep, Glob'"
  grep -q '^model: ' "$agent" || bad "$agent: no model line"
fi
grep -q 'way-of-working:transcript-reader' "$skill" || bad "$skill: does not name way-of-working:transcript-reader"
if grep -q 'runs only `jq`' "$skill"; then bad "$skill: still says the reader runs only jq"; fi
grep -qF 'path match only, not confirmed to be this repo' "$skill" || bad "$skill: no caveat text"
grep -q 'confirms in this session' "$skill" || bad "$skill: no confirmation wording ('confirms in this session')"
if grep -qF 'is filed or surfaced, never written to memory' "$skill"; then bad "$skill: old filing rule is back"; fi
grep -qF 'POSIX-only' "$skill" || bad "$skill: no POSIX-only statement for the cross-session path match"

[ "$fail" = 0 ] && echo "retro-reader: ok"
exit "$fail"
