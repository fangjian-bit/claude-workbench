#!/bin/sh
# PreCompact / PostCompact hook: when the driver session's context is compacted AUTOMATICALLY,
# point it at /way-of-working:handoff (#729). Registered in hooks.json with matcher `auto`, so a
# manual /compact never reaches it.
#
# Usage: compact-handoff.sh pre | post
#   pre   prints fixed compaction instructions on stdout; on the pinned claude, exit 0 appends
#         stdout to the compaction as custom instructions.
#   post  prints one fixed line on stdout; on the pinned claude, exit 0 shows stdout to the user.
#
# It prints nothing, exit 0, unless the session directory has a .ai/project.yml and is the MAIN
# worktree (the absolute --git-dir equals the absolute --git-common-dir, scripts/lanes/lane.sh's
# `not-main` test, run here with GIT_DIR, GIT_WORK_TREE and GIT_COMMON_DIR unset). Lane and spec
# worktrees are linked worktrees and stay silent: lanes never run handoff. A bad argument, or any
# internal error, is also silence with exit 0. It NEVER exits 2: a blocked automatic compaction
# leaves the session to run out of context. It never reads its stdin, and no value is
# interpolated into its text.
#
# Permitted toolset: POSIX sh, git 2.31 or later, awk.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR
LC_ALL=C
export LC_ALL

[ "$#" -eq 1 ] || exit 0
case "$1" in
  pre | post) mode=$1 ;;
  *) exit 0 ;;
esac

[ -f .ai/project.yml ] || exit 0
dirs=$(git rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null) || exit 0
gd=$(printf '%s\n' "$dirs" | awk 'NR==1')
gc=$(printf '%s\n' "$dirs" | awk 'NR==2')
[ -n "$gd" ] && [ "$gd" = "$gc" ] || exit 0

case "$mode" in
  pre)
    printf '%s\n' \
      "This session is being compacted automatically. Keep in the summary: the current next action, any open HITL gate, and every in-flight lane (issue, branch, PR). Open the summary with one line saying the session was compacted automatically and that /way-of-working:handoff should run before any new work."
    ;;
  post)
    printf '%s\n' \
      "This session was compacted automatically: run /way-of-working:handoff before any new work."
    ;;
esac
exit 0
