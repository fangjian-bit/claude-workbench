#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/spawn-model.sh -- the harness-evidence
# provenance check behind `models.second_opinion` (reference/project-schema.md § `agents`,
# `models`; issue #72). Each fixture builds a fake transcript tree under a tempdir (never
# the real ~/.claude/projects/) and points the script at it via $HOME and
# $CLAUDE_CODE_SESSION_ID, so the assertions run against the script's real file-lookup and
# line-parsing logic, not a mock of it.
#
# Permitted toolset: POSIX sh. No jq, no yq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/plugins/way-of-working/bin/spawn-model.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0

assert_eq() {
  desc="$1"
  expected="$2"
  actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "ok - $desc"
  else
    echo "FAIL - $desc: expected [$expected], got [$actual]" >&2
    fail=1
  fi
}

# Each fixture gets its own $HOME and session id so fixtures never see each other's files.
fixture_home() {
  h="$tmp/home-$1"
  mkdir -p "$h"
  printf '%s' "$h"
}

# write_transcript <home> <session> <agent-id> <model-id>...
# One assistant record per given model id, in the FIELD ORDER the harness actually writes
# (model, id, type, role, content -- verified against a real transcript on this machine
# during review; a fixture that reordered these would not have caught the review's own
# greedy-match finding, since a `model` key placed after `role` used to pass anyway).
write_transcript() {
  home="$1"; session="$2"; agent_id="$3"; shift 3
  dir="$home/.claude/projects/some-project-slug/$session/subagents"
  mkdir -p "$dir"
  f="$dir/agent-$agent_id.jsonl"
  : >"$f"
  for model in "$@"; do
    printf '{"parentUuid":"x","isSidechain":true,"agentId":"%s","message":{"model":"%s","id":"m1","type":"message","role":"assistant","content":[]},"type":"assistant"}\n' \
      "$agent_id" "$model" >>"$f"
  done
  printf '%s' "$f"
}

# write_lines <home> <session> <agent-id> <raw-line>... -- appends raw records to the transcript
# (starting it afresh), for the blob fixtures below.
write_lines() {
  home="$1"; session="$2"; agent_id="$3"; shift 3
  dir="$home/.claude/projects/some-project-slug/$session/subagents"
  mkdir -p "$dir"
  : >"$dir/agent-$agent_id.jsonl"
  for l in "$@"; do printf '%s\n' "$l" >>"$dir/agent-$agent_id.jsonl"; done
}

# blob <agent-id> <role> -- an api-request-blob record in the real field order.
blob() {
  printf '{"type":"api-request-blob","sessionId":"s","agentId":"%s","hash":"h","message":{"role":"%s","content":[]}}' "$1" "$2"
}

# turn <model-id> -- a real assistant turn record.
turn() {
  printf '{"parentUuid":"x","isSidechain":true,"message":{"model":"%s","id":"m1","type":"message","role":"assistant","content":[]},"type":"assistant"}' "$1"
}

run() { # run <home> <session> <agent-id> <alias>
  HOME="$1" CLAUDE_CODE_SESSION_ID="$2" "$script" "$3" "$4"
}

# --- confirmed: every assistant record matches the expected alias's prefix -------------
home="$(fixture_home confirmed)"
write_transcript "$home" sess1 aaa111 claude-opus-5-5 claude-opus-5-5 >/dev/null
assert_eq "confirmed: every record is claude-opus-5-5, alias opus" \
  "confirmed" "$(run "$home" sess1 aaa111 opus)"

# --- confirmed: point-release prefix match (fable 5.1 against alias fable) -------------
home="$(fixture_home confirmed-point-release)"
write_transcript "$home" sess1 bbb222 claude-fable-5-1 >/dev/null
assert_eq "confirmed: claude-fable-5-1 matches alias fable's documented prefix" \
  "confirmed" "$(run "$home" sess1 bbb222 fable)"

# --- confirmed: sonnet (every alias gets a positive fixture, not just opus/fable) -------
home="$(fixture_home confirmed-sonnet)"
write_transcript "$home" sess1 sss111 claude-sonnet-5 >/dev/null
assert_eq "confirmed: claude-sonnet-5 matches alias sonnet" \
  "confirmed" "$(run "$home" sess1 sss111 sonnet)"

# --- confirmed: haiku (its point-release id carries a trailing date suffix) -------------
home="$(fixture_home confirmed-haiku)"
write_transcript "$home" sess1 hhh111 claude-haiku-4-5-20251001 >/dev/null
assert_eq "confirmed: claude-haiku-4-5-20251001 matches alias haiku" \
  "confirmed" "$(run "$home" sess1 hhh111 haiku)"

# --- mismatch: one record ran on a different model -------------------------------------
home="$(fixture_home mismatch)"
write_transcript "$home" sess1 ccc333 claude-fable-5 claude-opus-5-5 >/dev/null
assert_eq "mismatch: appending a later record on a different model does not confirm" \
  "mismatch" "$(run "$home" sess1 ccc333 fable)"

# --- mismatch: expected alias entirely wrong ---------------------------------------------
home="$(fixture_home mismatch-wrong-alias)"
write_transcript "$home" sess1 ddd444 claude-sonnet-5 >/dev/null
assert_eq "mismatch: transcript is sonnet, expected opus" \
  "mismatch" "$(run "$home" sess1 ddd444 opus)"

# --- mismatch: an assistant record with no readable model field ------------------------
home="$(fixture_home mismatch-no-model-field)"
dir="$home/.claude/projects/slug/sess1/subagents"
mkdir -p "$dir"
f="$dir/agent-eee555.jsonl"
printf '{"parentUuid":"x","message":{"id":"m1","type":"message","role":"assistant","content":[]},"type":"assistant"}\n' >"$f"
assert_eq "mismatch: an assistant record with no model field is not silently skipped" \
  "mismatch" "$(run "$home" sess1 eee555 opus)"

# --- mismatch: a tool call's own arguments cannot smuggle a "model" key ----------------
# The finding this fixture pins: a greedy whole-line match on `"model":"` takes the LAST
# such key on the line, so a tool_use whose input happens to carry one wins over the real
# message.model field. This transcript's real model is opus; the tool call's forged "model"
# argument names fable. Checked against opus, it must confirm (the forged key must never be
# read at all); checked against fable, it must mismatch (the forged key must never pass).
home="$(fixture_home mismatch-tool-input-smuggling)"
dir="$home/.claude/projects/slug/sess1/subagents"
mkdir -p "$dir"
f="$dir/agent-tis000.jsonl"
printf '{"parentUuid":"x","message":{"model":"claude-opus-5-5","id":"m1","type":"message","role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"model":"claude-fable-5","command":"echo hi"}}]},"type":"assistant"}\n' >"$f"
assert_eq "confirmed: a forged 'model' key inside tool_use input is never read (checked against the real model)" \
  "confirmed" "$(run "$home" sess1 tis000 opus)"
assert_eq "mismatch: a forged 'model' key inside tool_use input must not itself confirm" \
  "mismatch" "$(run "$home" sess1 tis000 fable)"

# --- mismatch: the transcript's LAST line has no trailing newline ----------------------
# The finding this fixture pins: `read` without `|| [ -n "$line" ]` returns failure on an
# unterminated final line and the loop body never runs for it, so a mismatching last record
# is silently never checked -- exactly the "every record" guarantee this script exists to
# enforce.
home="$(fixture_home mismatch-no-trailing-newline)"
write_transcript "$home" sess1 ntn000 claude-opus-5-5 >/dev/null
f="$home/.claude/projects/some-project-slug/sess1/subagents/agent-ntn000.jsonl"
printf '{"parentUuid":"x","message":{"model":"claude-fable-5","id":"m2","type":"message","role":"assistant","content":[]},"type":"assistant"}' >>"$f"
assert_eq "mismatch: a final record with no trailing newline is still checked" \
  "mismatch" "$(run "$home" sess1 ntn000 opus)"

# --- unconfirmed: empty projection -- no assistant-type record at all ------------------
home="$(fixture_home unconfirmed-empty-projection)"
dir="$home/.claude/projects/slug/sess1/subagents"
mkdir -p "$dir"
f="$dir/agent-fff666.jsonl"
printf '{"parentUuid":null,"message":{"role":"user","content":"hi"},"type":"user"}\n' >"$f"
assert_eq "unconfirmed: transcript has no assistant record to project" \
  "unconfirmed" "$(run "$home" sess1 fff666 opus)"

# --- unconfirmed: no transcript file for that agent id at all --------------------------
home="$(fixture_home unconfirmed-missing-file)"
write_transcript "$home" sess1 real000 claude-opus-5-5 >/dev/null
assert_eq "unconfirmed: agent id does not match any transcript file" \
  "unconfirmed" "$(run "$home" sess1 doesnotexist opus)"

# --- unconfirmed: never a glob -- an earlier spawn's file must not confirm a later one --
home="$(fixture_home unconfirmed-never-a-glob)"
write_transcript "$home" sess1 earlier111 claude-opus-5-5 >/dev/null
assert_eq "unconfirmed: a different, earlier agent id's file is not picked up as a fallback" \
  "unconfirmed" "$(run "$home" sess1 later222 opus)"

# --- unconfirmed: unknown alias ----------------------------------------------------------
home="$(fixture_home unconfirmed-unknown-alias)"
write_transcript "$home" sess1 ggg777 claude-opus-5-5 >/dev/null
assert_eq "unconfirmed: alias is not one of the schema's model names" \
  "unconfirmed" "$(run "$home" sess1 ggg777 gpt5)"

# --- unconfirmed: no current session id --------------------------------------------------
home="$(fixture_home unconfirmed-no-session)"
write_transcript "$home" sess1 hhh888 claude-opus-5-5 >/dev/null
out="$(HOME="$home" CLAUDE_CODE_SESSION_ID= "$script" hhh888 opus)"
assert_eq "unconfirmed: CLAUDE_CODE_SESSION_ID unset/empty" "unconfirmed" "$out"

# --- unconfirmed: session id carries a path-breaking character -------------------------
home="$(fixture_home unconfirmed-bad-session-id)"
write_transcript "$home" sess1 sid000 claude-opus-5-5 >/dev/null
out="$(HOME="$home" CLAUDE_CODE_SESSION_ID="../sess1" "$script" sid000 opus)"
assert_eq "unconfirmed: session id is not a plain alphanumeric-with-hyphens id" "unconfirmed" "$out"

# --- unconfirmed: agent id carries a path-breaking character ----------------------------
home="$(fixture_home unconfirmed-bad-agent-id)"
write_transcript "$home" sess1 iii999 claude-opus-5-5 >/dev/null
assert_eq "unconfirmed: agent id is not a plain alphanumeric id" \
  "unconfirmed" "$(run "$home" sess1 "../iii999" opus)"

# --- unconfirmed: session id resolves under more than one project slug -----------------
home="$(fixture_home unconfirmed-ambiguous-session)"
write_transcript "$home" dupsess jjj000 claude-opus-5-5 >/dev/null
dir2="$home/.claude/projects/another-slug/dupsess/subagents"
mkdir -p "$dir2"
cp "$home/.claude/projects/some-project-slug/dupsess/subagents/agent-jjj000.jsonl" \
  "$dir2/agent-jjj000.jsonl"
assert_eq "unconfirmed: the session id is not unique to one project-slug directory" \
  "unconfirmed" "$(run "$home" dupsess jjj000 opus)"

# --- api-request-blob records are request copies, not turns ----------------------------
home="$(fixture_home blob-interleaved)"
write_lines "$home" sess1 bl1 "$(turn claude-opus-5-5)" "$(blob bl1 assistant)" "$(blob bl1 user)" \
  "$(blob bl1 system)" "$(turn claude-opus-5-5)" "$(blob bl1 assistant)"
assert_eq "confirmed: blob records of every role between opus turns are skipped" \
  "confirmed" "$(run "$home" sess1 bl1 opus)"

home="$(fixture_home blob-mixed)"
write_lines "$home" sess1 bl2 "$(turn claude-opus-5-5)" "$(blob bl2 assistant)" "$(turn claude-fable-5)" \
  "$(blob bl2 user)" "$(turn claude-opus-5-5)"
assert_eq "mismatch: a real fable turn among blobs still mismatches" \
  "mismatch" "$(run "$home" sess1 bl2 opus)"

home="$(fixture_home blob-only)"
write_lines "$home" sess1 bl3 "$(blob bl3 assistant)" "$(blob bl3 user)" "$(blob bl3 assistant)"
assert_eq "unconfirmed: only blob records, no assistant turn seen" \
  "unconfirmed" "$(run "$home" sess1 bl3 opus)"

home="$(fixture_home blob-unknown-type)"
write_lines "$home" sess1 bl4 "$(turn claude-opus-5-5)" \
  '{"type":"api-request-copy","sessionId":"s","message":{"role":"assistant","content":[]}}'
assert_eq "mismatch: an unknown record type with an assistant role still fails closed" \
  "mismatch" "$(run "$home" sess1 bl4 opus)"

home="$(fixture_home blob-near-miss)"
write_lines "$home" sess1 bl5 "$(turn claude-opus-5-5)" \
  '{"type":"api-request-blobs","sessionId":"s","message":{"role":"assistant","content":[]}}'
assert_eq "mismatch: a near-miss prefix (no closing quote and comma) is judged" \
  "mismatch" "$(run "$home" sess1 bl5 opus)"

home="$(fixture_home blob-in-content)"
write_lines "$home" sess1 bl6 \
  '{"parentUuid":"x","message":{"model":"claude-fable-5","id":"m1","type":"message","role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"type":"api-request-blob","x":1}}]},"type":"assistant"}'
assert_eq "mismatch: the blob prefix inside content does not skip the record" \
  "mismatch" "$(run "$home" sess1 bl6 opus)"

home="$(fixture_home blob-leading-space)"
write_lines "$home" sess1 bl7 ' {"type":"api-request-blob","sessionId":"s","message":{"role":"assistant","content":[]}}'
assert_eq "mismatch: a blob line with leading whitespace is judged" \
  "mismatch" "$(run "$home" sess1 bl7 opus)"

home="$(fixture_home blob-type-not-first)"
write_lines "$home" sess1 bl8 \
  '{"sessionId":"s","type":"api-request-blob","message":{"role":"assistant","content":[]}}'
assert_eq "mismatch: a blob type that is not the first field is judged" \
  "mismatch" "$(run "$home" sess1 bl8 opus)"

exit "$fail"
