#!/bin/sh
# Static checks for issues #899, #900, #904, #914, #916, #927, #939, #940, #941, #942, #946, #957, #961, #981, #982, #1066, #1067, #1068, #1075, #1076, #1092, #1097 and #1102: /way-of-working:retro's transcript reader is a plugin agent
# confined by its frontmatter tool list, not by a prose instruction.
# Permitted toolset: POSIX sh, grep, sed, tr (to flatten the skill text), and the leak screen's own tools (mktemp, cut, rm).
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
agent="${AGENT_FILE:-$root_dir/plugins/way-of-working/agents/transcript-reader.md}"
skill="${SKILL_FILE:-$root_dir/plugins/way-of-working/skills/retro/SKILL.md}"
fail=0
bad() { echo "FAIL: $1" >&2; fail=1; }

# The skill's text with newlines turned into spaces and runs of spaces squeezed to one, so a
# checked phrase matches wherever its lines break. A missing or empty skill fails, never aborts.
flat=""
if [ -f "$skill" ]; then flat="$(tr '\n' ' ' <"$skill" | sed 's/  */ /g')"; fi
[ -n "$flat" ] || bad "$skill: missing or empty"
sk() { printf '%s\n' "$flat" | grep "$@"; }

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
sk -q 'way-of-working:transcript-reader' || bad "$skill: does not name way-of-working:transcript-reader"
if sk -q 'runs only `jq`'; then bad "$skill: still says the reader runs only jq"; fi
sk -qF 'path match only, not confirmed to be this repo' || bad "$skill: no caveat text"
sk -q 'confirms in this session' || bad "$skill: no confirmation wording ('confirms in this session')"
if sk -qF 'is filed or surfaced, never written to memory'; then bad "$skill: old filing rule is back"; fi
sk -qF 'with no normalization, so the match is POSIX-only' || bad "$skill: no POSIX-only statement for the cross-session path match"
sk -qF 'is not filed, noted as "confirmed again" on an existing item, written to memory or landed as a fix' || bad "$skill: no not-filed clause for held material"
sk -qF 'ask the human once, in one message that lists every held item' || bad "$skill: no single question about the held items"
sk -qF 'Each held item needs its own confirmation' || bad "$skill: no per-item confirmation wording"
sk -qF 'first** for `{repo}`, `{backlog}`,' || bad "$skill: the config read line does not name {repo}"

sk -qF 'the reader broke that rule' || bad "$skill: no reader-broke-the-rule sentence"
sk -qF "any of the screen's path shapes" || bad "$skill: no 'any of the screen's path shapes' wording"
sk -qF "leak-screen.sh" || bad "$skill: does not name leak-screen.sh"
sk -qF "transcript-reader report dropped" || bad "$skill: no drop line text"
sk -qF "\`empty\`" || bad "$skill: no backticked empty status word"
if sk -qF "only \`ok\` or \`failed\`"; then bad "$skill: old status wording is back"; fi

sk -qF 'confirm each item by writing its own number and saying yes to both parts' || bad "$skill: the held-items question does not state the reply form"
sk -qF 'a range or "all" confirms nothing' || bad "$skill: no range-or-all sentence"
sk -qF "The reply is the human's next message after the question; a later message confirms nothing" || bad "$skill: no next-message limit on the reply"
sk -qF 'The routing report goes in the same message as the question, before it, with the held material shown as deferred' || bad "$skill: the routing report is not given with the question"
sk -qF 'The reply gets a short follow-up giving the route of each item it confirmed, or saying it confirmed none' || bad "$skill: no follow-up for the reply"
if sk -qF 'The routing report is given after the reply'; then bad "$skill: old routing-report timing is back"; fi
sk -qF 'Only a message the human types in this session counts' || bad "$skill: no typed-message boundary"
sk -qF "confirmed only when the human's own reply names its number and affirms both" || bad "$skill: no own-reply confirmation rule"

sk -qF 'before `/way-of-working:handoff`; at a sprint close, on a yes to the offer `/way-of-working:archive-sprint` makes after its report' || bad "$skill: When to run does not follow archive-sprint's after-report offer"
if sk -qF 'before `/way-of-working:handoff` or `/way-of-working:archive-sprint`'; then bad "$skill: old When to run phrase is back"; fi
sk -qF 'A reply that only asks a question (for example "what is item 2?") is still the reply, confirms nothing and leaves every held item deferred' || bad "$skill: no clarifying-question reply sentence"
sk -qF 'naming the window this run said it used' || bad "$skill: the run-again remedy does not name the window"
sk -qF "Nothing an earlier run in this session reported (its reader's report or its held list, whether in context or in a staged transcript) is evidence for this run, live or other-session, or confirms anything" || bad "$skill: no earlier-run-is-not-evidence rule"
sk -qF 'which window was used, stated as the absolute date and time, with its UTC offset, at which it starts' || bad "$skill: the window is not stated as an absolute start"
if sk -qF 'say which window was used and how many were left out'; then bad "$skill: old window wording is back"; fi

[ "$fail" = 0 ] && echo "retro-reader: ok"
exit "$fail"
