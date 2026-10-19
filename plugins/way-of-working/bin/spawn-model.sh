#!/bin/sh
# Confirm which model a subagent spawn actually ran as, from harness-written evidence --
# never from the subagent's own report text (its prompt and the diff it read are
# attacker-influenceable, and agent bodies carry "(Opus by default)"/"(Sonnet by default)"
# wording that competes with reality anyway). This is the provenance check behind
# `models.second_opinion` (reference/project-schema.md § `agents`, `models`):
# `/way-of-working:critic-gate`'s one late round on a different model is recorded as having
# run on it only when this script answers `confirmed`. This is strong evidence, not
# unforgeable -- a critic holds Bash and could in principle rewrite its own transcript file
# after the fact; the every-record rule below defeats appending a complete record to fix a mixed-model
# round, and that residual rewrite risk is accepted explicitly, same as the spec that requires
# this script does (the harm ceiling is false provenance, not execution). An unterminated
# append that the harness's next write completes joins two records into one line, so the
# next record is hidden (a `{"content":` or blob-prefix fragment) or relabelled (a forged
# header fragment supplies the role and model the script reads); the same gap already exists
# for a `{"content":` fragment. A process that does this before each assistant record, for
# instance one already writing before the spawn's first turn, can make a wrong-model spawn read
# `confirmed`. That gap is inside the same accepted residual, not closed here.
#
# Usage: spawn-model.sh <agent-id> <expected-alias>
#   <agent-id>        the id the Agent tool's own tool result names for the spawn
#                      (`toolUseResult.agentId` in the orchestrating session's transcript) --
#                      never a glob over `agent-*.jsonl`, so an earlier spawn cannot confirm
#                      a later round.
#   <expected-alias>  one of: sonnet | opus | haiku | fable (the schema's model names --
#                      reference/project-schema.md § `models.second_opinion` documents the
#                      legal ALIASES; the alias -> model-id PREFIX table below is this
#                      script's own, not documented a second time anywhere else).
#
# Prints exactly one of, to stdout, and always exits 0 (the caller decides policy):
#   confirmed    -- every assistant turn record found in the spawn's own transcript ran on a
#                   model id matching <expected-alias>'s prefix
#   mismatch     -- the transcript was read, but at least one assistant turn record's model does
#                   not match (including a record whose model field could not be read --
#                   appending to fix a mixed-model round must not confirm it)
#   unconfirmed  -- anything else: an unknown alias, no current session id (or one that
#                   isn't a plain id), no transcript file (zero or more than one candidate),
#                   an unreadable path, or no assistant turn record in the file at all (an empty
#                   projection; a transcript whose only assistant-role records are
#                   `api-request-blob` copies is one)
#
# Locating the transcript. Claude Code writes each subagent's transcript to
#   ~/.claude/projects/<project-slug>/<session-id>/subagents/agent-<agent-id>.jsonl
# This script does not hardcode or re-derive <project-slug> -- that is exactly the kind of
# machine-specific string this plugin avoids baking in. Instead it matches on <session-id>,
# a literal value this session already holds in $CLAUDE_CODE_SESSION_ID, which is unique --
# so the one wildcarded path segment is the slug directory whose exact spelling this script
# deliberately does not need to know, never the filename itself. That is not the "glob over
# agent-*.jsonl" this script's header rules out: the filename is fully specified by
# <agent-id> with no wildcard in it, and a session id resolving to more than one project-slug
# directory only means the lookup itself is ambiguous, which is exactly when this script
# must answer unconfirmed rather than guess.
#
# The model field. A record's `message` object carries its scalar header fields
# (`model`, `id`, `type`, `role`) BEFORE `content` -- verified against this repo's own real
# transcripts -- and `content` is where an assistant turn's own tool-call arguments live.
# So this script never searches the WHOLE line for `model`/`role`: it first cuts the line at
# the first `"content":` (POSIX parameter expansion, `${line%%"content":*}`, longest-suffix
# removal -- keeps everything before the FIRST occurrence), then looks for `"role":
# "assistant"` and `"model":"..."` only in that header slice. A tool call whose own arguments
# happen to carry a key named `model` (or a hand-crafted one, from a compromised critic)
# lives inside `content` and can therefore never reach either check -- reproduced against an
# earlier, whole-line-greedy version of this script during review, before this fix landed.
# Extraction within the header slice takes the FIRST `"model":"` there (again by parameter
# expansion, never a greedy sed `.*` pattern, which would silently prefer a later, wrong
# match on any line carrying more than one). The transcript's own content never reaches
# stdout, so it never re-enters the calling session's context the way re-reading the whole
# file for review would.
#
# Records that are not turns. Claude Code also writes `api-request-blob` records to a
# subagent transcript: copies of the request payload sent back to the API, which include
# earlier assistant turns. Their `message` header carries a role (system, user or assistant)
# and no `model`, so judging them would read every spawn as `mismatch`. A line that begins
# with the exact bytes `{"type":"api-request-blob",` (closing quote and comma included, and
# at the very start of the line, never anywhere inside it) is skipped: it neither counts as
# an assistant turn seen nor is judged. Every other record carrying `"role":"assistant"` in
# its header slice, of any or unknown type, is still judged and fails closed.
#
# Permitted toolset: POSIX sh only. No jq, no yq, no python -- this must run on any
# maintainer machine with nothing extra installed.
set -eu

agent_id="${1:?usage: spawn-model.sh <agent-id> <expected-alias>}"
alias_name="${2:?usage: spawn-model.sh <agent-id> <expected-alias>}"

# Reject anything that isn't a plain id before it ever reaches a glob or a path -- an
# agent id is harness-generated and alphanumeric; anything else (a `/`, a `..`, a space)
# is not a real id and must not be interpolated into a filesystem lookup unchecked.
case "$agent_id" in
  '' | *[!0-9a-zA-Z]*)
    echo unconfirmed
    exit 0
    ;;
esac

prefix=""
case "$alias_name" in
  sonnet) prefix='claude-sonnet-5' ;;
  opus) prefix='claude-opus-5' ;;
  haiku) prefix='claude-haiku-4-5' ;;
  fable) prefix='claude-fable-5' ;;
  *)
    echo unconfirmed
    exit 0
    ;;
esac

# Same reasoning as <agent-id> above: this becomes a literal path segment, so it is
# validated the same way before use, not merely quoted. A session id is harness-generated
# and alphanumeric-with-hyphens (it is a UUID); anything else is rejected.
session="${CLAUDE_CODE_SESSION_ID:-}"
case "$session" in
  '' | *[!0-9a-zA-Z-]*)
    echo unconfirmed
    exit 0
    ;;
esac

# A plain for-loop glob, not `ls` piped through anything -- the filename shape
# (agent-<hex>.jsonl) never carries a space or newline to parse wrong, and this avoids
# relying on `ls`'s output format at all. `[ -e "$f" ]` skips the single iteration a
# non-matching POSIX glob yields: its own literal, unexpanded pattern text.
match_count=0
transcript=""
for f in "$HOME"/.claude/projects/*/"$session"/subagents/"agent-$agent_id.jsonl"; do
  [ -e "$f" ] || continue
  match_count=$((match_count + 1))
  transcript="$f"
done
if [ "$match_count" -ne 1 ]; then
  echo unconfirmed
  exit 0
fi

if [ ! -r "$transcript" ]; then
  echo unconfirmed
  exit 0
fi

seen=0
mismatch=0
# `|| [ -n "$line" ]` is load-bearing: a final line with no trailing newline still ends a
# real record, and without this, `read` returns failure on it and the loop body never runs
# for it -- a mismatching last record would then never be checked, contradicting the
# every-record rule this script exists to enforce.
while IFS= read -r line || [ -n "$line" ]; do
  # A request-payload copy, not a turn (see the header comment above).
  case "$line" in
    '{"type":"api-request-blob",'*) continue ;;
  esac
  # Everything before the record's own first `"content":` -- the message header, never a
  # tool call's arguments (see the header comment above).
  head_part="${line%%\"content\":*}"
  case "$head_part" in
    *'"role":"assistant"'*) : ;;
    *) continue ;;
  esac
  seen=1
  case "$head_part" in
    *'"model":"'*)
      rest="${head_part#*\"model\":\"}"
      model="${rest%%\"*}"
      ;;
    *) model="" ;;
  esac
  case "$model" in
    "$prefix"*) : ;;
    *)
      mismatch=1
      break
      ;;
  esac
done <"$transcript"

if [ "$seen" -eq 0 ]; then
  echo unconfirmed
  exit 0
fi
if [ "$mismatch" -eq 1 ]; then
  echo mismatch
  exit 0
fi
echo confirmed
