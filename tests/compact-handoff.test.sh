#!/bin/sh
# Fixture tests for plugins/way-of-working/hooks/compact-handoff.sh and its hooks.json
# registration (#729).
#
# Runs the REAL hook in scratch git repos: a main worktree with .ai/project.yml says its fixed
# text; a linked worktree, a directory without .ai/project.yml, a directory outside any work
# tree and a bad argument all stay silent. No case may exit 2.
#
# Permitted toolset: POSIX sh, git, jq (for hooks.json; the registration cases skip without it).
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
hook="$root_dir/plugins/way-of-working/hooks/compact-handoff.sh"
hooks_json="$root_dir/plugins/way-of-working/hooks/hooks.json"

if ! command -v git >/dev/null 2>&1; then
  echo "skip - compact-handoff.sh fixtures: no git on PATH" >&2
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
assert_eq() {
  desc="$1"; expected="$2"; actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "ok - $desc"
  else
    echo "FAIL - $desc: expected [$expected], got [$actual]" >&2
    fail=1
  fi
}

# run_hook <dir> <arg...> -- prints "<exit>|<stdout>"
run_hook() {
  d="$1"; shift
  out=$(cd "$d" && "$hook" "$@" 2>/dev/null </dev/null) && rc=0 || rc=$?
  printf '%s|%s' "$rc" "$out"
}

pre_text="This session is being compacted automatically. Keep in the summary: the current next action, any open HITL gate, and every in-flight lane (issue, branch, PR). Open the summary with one line saying the session was compacted automatically and that /way-of-working:handoff should run before any new work."
post_text="This session was compacted automatically: run /way-of-working:handoff before any new work."

git_q() { git -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false "$@"; }

main="$tmp/main"
mkdir -p "$main/.ai"
git_q -C "$main" init -q
echo "repo: acme/widgets" >"$main/.ai/project.yml"
git_q -C "$main" add -A
git_q -C "$main" commit -q -m init
git_q -C "$main" worktree add -q "$tmp/linked" -b feat/linked

assert_eq "pre in a main worktree with a project file prints the instructions" \
  "0|$pre_text" "$(run_hook "$main" pre)"
assert_eq "post in a main worktree with a project file prints the line" \
  "0|$post_text" "$(run_hook "$main" post)"
assert_eq "pre in a linked worktree is silent" "0|" "$(run_hook "$tmp/linked" pre)"
assert_eq "post in a linked worktree is silent" "0|" "$(run_hook "$tmp/linked" post)"

nofile="$tmp/nofile"
mkdir -p "$nofile"
git_q -C "$nofile" init -q
assert_eq "pre without .ai/project.yml is silent" "0|" "$(run_hook "$nofile" pre)"
assert_eq "post without .ai/project.yml is silent" "0|" "$(run_hook "$nofile" post)"

nogit="$tmp/nogit"
mkdir -p "$nogit/.ai"
echo "repo: acme/widgets" >"$nogit/.ai/project.yml"
assert_eq "pre outside any git work tree is silent" "0|" "$(run_hook "$nogit" pre)"
assert_eq "post outside any git work tree is silent" "0|" "$(run_hook "$nogit" post)"

assert_eq "a bad argument is silent" "0|" "$(run_hook "$main" nope)"
assert_eq "no argument is silent" "0|" "$(run_hook "$main")"
assert_eq "a bad argument alongside a good one is silent" "0|" "$(run_hook "$main" pre extra)"

# The repo-settable git variables must not turn a linked worktree into a main one.
out=$(cd "$tmp/linked" && GIT_DIR="$main/.git" GIT_WORK_TREE="$main" "$hook" pre 2>/dev/null </dev/null) && rc=0 || rc=$?
assert_eq "GIT_DIR and GIT_WORK_TREE in the environment do not change the verdict" "0|" "$rc|$out"

# stdin is never read into the output.
out=$(cd "$main" && printf 'injected text\n' | "$hook" post 2>/dev/null) && rc=0 || rc=$?
assert_eq "stdin is not echoed" "0|$post_text" "$rc|$out"

if command -v jq >/dev/null 2>&1; then
  for ev in PreCompact:pre PostCompact:post; do
    e="${ev%%:*}"; a="${ev#*:}"
    assert_eq "hooks.json registers $e with matcher auto" "auto" \
      "$(jq -r --arg e "$e" '.hooks[$e][0].matcher' "$hooks_json")"
    assert_eq "hooks.json $e runs compact-handoff.sh $a with a 10-second timeout" \
      "\"\${CLAUDE_PLUGIN_ROOT}\"/hooks/compact-handoff.sh $a|10" \
      "$(jq -r --arg e "$e" '.hooks[$e][0].hooks[0] | "\(.command)|\(.timeout)"' "$hooks_json")"
  done
  assert_eq "hooks.json keeps SessionStart" \
    "\"\${CLAUDE_PLUGIN_ROOT}\"/hooks/ai-cursor-banner.sh|10" \
    "$(jq -r '.hooks.SessionStart[0].hooks[0] | "\(.command)|\(.timeout)"' "$hooks_json")"
else
  echo "skip - hooks.json registration cases: no jq on PATH" >&2
fi

exit "$fail"
