#!/bin/sh
# Static checks for issues #899, #900, #904, #914, #916, #927, #939, #940, #941, #942, #946, #957, #961, #981 and #982: /way-of-working:retro's transcript reader is a plugin agent
# confined by its frontmatter tool list, not by a prose instruction.
# Permitted toolset: POSIX sh, grep, sed, and the leak screen's own tools (mktemp, cut, rm).
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
  [ "$(grep -c 'never write an absolute path' "$agent")" = 1 ] || bad "$agent: not exactly one 'never write an absolute path' line"
  rule_line="$(grep -n 'never write an absolute path' "$agent" | sed -n '1s/:.*//p')"
  how_line="$(grep -n '^## How to work$' "$agent" | sed -n '1s/:.*//p')"
  report_line="$(grep -n '^## Report back$' "$agent" | sed -n '1s/:.*//p')"
  if [ -z "$rule_line" ] || [ -z "$how_line" ] || [ -z "$report_line" ] || [ "$rule_line" -le "$how_line" ] || [ "$rule_line" -ge "$report_line" ]; then
    bad "$agent: the path rule is not between '## How to work' and '## Report back'"
  fi
  grep -qF 'repo-relative' "$agent" || bad "$agent: no 'repo-relative' wording"
  grep -qF 'credential-shaped text' "$agent" || bad "$agent: no 'credential-shaped text' wording"
  screen_out="$(sh "$root_dir/plugins/way-of-working/bin/leak-screen.sh" "$agent" 2>&1 || true)"
  [ "$screen_out" = ok ] || bad "$agent: the leak screen says '$screen_out', not ok"
fi
grep -q 'way-of-working:transcript-reader' "$skill" || bad "$skill: does not name way-of-working:transcript-reader"
if grep -q 'runs only `jq`' "$skill"; then bad "$skill: still says the reader runs only jq"; fi
grep -qF 'path match only, not confirmed to be this repo' "$skill" || bad "$skill: no caveat text"
grep -q 'confirms in this session' "$skill" || bad "$skill: no confirmation wording ('confirms in this session')"
if grep -qF 'is filed or surfaced, never written to memory' "$skill"; then bad "$skill: old filing rule is back"; fi
grep -qF 'with no normalization, so the match is POSIX-only' "$skill" || bad "$skill: no POSIX-only statement for the cross-session path match"
grep -qF 'is not filed, noted as "confirmed again" on an existing item, written to memory or landed as a fix' "$skill" || bad "$skill: no not-filed clause for held material"
grep -qF 'ask the human once, in one message that lists every held item' "$skill" || bad "$skill: no single question about the held items"
grep -qF 'Each held item needs its own confirmation' "$skill" || bad "$skill: no per-item confirmation wording"
grep -qF 'first** for `{repo}`, `{backlog}`,' "$skill" || bad "$skill: the config read line does not name {repo}"

grep -qF 'the reader broke that rule' "$skill" || bad "$skill: no reader-broke-the-rule sentence"
grep -qF "any of the screen's path shapes" "$skill" || bad "$skill: no 'any of the screen's path shapes' wording"
grep -qF "leak-screen.sh" "$skill" || bad "$skill: does not name leak-screen.sh"
grep -qF "transcript-reader report dropped" "$skill" || bad "$skill: no drop line text"
grep -qF "\`empty\`" "$skill" || bad "$skill: no backticked empty status word"
if grep -qF "only \`ok\` or \`failed\`" "$skill"; then bad "$skill: old status wording is back"; fi

[ "$fail" = 0 ] && echo "retro-reader: ok"
exit "$fail"
