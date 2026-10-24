#!/bin/sh
# Classify .ai/state.json's `last_commit` against the current HEAD.
#
# This is a deterministic predicate with a correctness argument, not a judgment
# call, so it is a tested script that /way-of-working:resume's *Check reality vs. the
# cursor* step invokes
# rather than a computation described in skill prose -- prose shipped the wrong
# answer here twice: first by comparing `last_commit` to HEAD with plain SHA
# equality, then by replacing that with a commit-*range* form that only means
# what it looks like when `last_commit` is an ancestor of HEAD. Squash-merge
# routinely makes it not one, since it replays a branch as a brand-new commit
# object the original tip never becomes an ancestor of.
#
# Usage: cursor-drift.sh <last_commit>
# Prints exactly one of, to stdout, and always exits 0 (the caller decides policy):
#   clean        -- last_commit IS the current HEAD
#   cursor-sync  -- HEAD differs from last_commit only in .ai/next-steps.md and/or
#                   files under .ai/parked/ (a parked sprint's snapshot)
#   drift        -- HEAD differs from last_commit in some other way too
#   unreadable   -- last_commit is not a commit git has (treat as drift; wait)
#
# The allowlist is exactly those two shapes and nothing "docs-shaped" in general: a
# roadmap or sprint-plan edit can invalidate the live cursor's next_action, so it
# must read as drift. A parked file describes a DIFFERENT sprint and cannot, which
# is why .ai/parked/ is the one directory admitted (issue #87).
#
# Deliberately NOT part of this script's job: whether the working tree is clean.
# That is a separate, single-command check (`git status --short`) with no
# multi-step correctness argument -- it stays a one-liner in the skill.
#
# Permitted toolset: git, POSIX sh. No jq, no yq, no python -- this must run on
# any maintainer machine without an extra interpreter installed.
set -eu

last_commit="${1:?usage: cursor-drift.sh <last_commit>}"

if ! git cat-file -e "${last_commit}^{commit}" 2>/dev/null; then
  echo unreadable
  exit 0
fi

head_sha="$(git rev-parse HEAD)"
last_sha="$(git rev-parse "$last_commit")"

if [ "$head_sha" = "$last_sha" ]; then
  echo clean
  exit 0
fi

# TWO arguments -- never <last_commit>..HEAD (see the top-of-file note). This
# compares trees, not history, and does not care whether last_commit is an
# ancestor of HEAD. diff.relative is pinned off: a caller with that set in
# their git config would otherwise get paths relative to cwd, not repo root,
# silently breaking the .ai/next-steps.md comparison below. core.quotePath is
# pinned OFF for the same reason: on it wraps any path with a non-ASCII byte in
# quotes (".ai/parked/caf\303\251.md"), which the allowlist would then reject.
# Off, only double-quote, backslash and control characters are still quoted --
# always, regardless of the setting -- so a path carrying a newline cannot split
# into two lines that match separately; it arrives quoted and reads as drift.
# --no-renames lists a rename as its old path and its new one: with rename
# detection a file moved from outside the allowlist into .ai/parked/ would list
# only its new path and read as cursor-sync, hiding the file that left.
paths="$(git -c diff.relative=false -c core.quotePath=false diff --no-renames --name-only "$last_commit" HEAD)"

# Two distinct commits with identical trees (an empty commit, a revert pair) give
# an empty path list. That is not a cursor-sync; fail closed.
if [ -z "$paths" ]; then
  echo drift
  exit 0
fi

# cursor-sync iff EVERY path is the ledger or lies under .ai/parked/. The
# pattern's trailing slash is load-bearing: a FILE at .ai/parked is `.ai/parked`
# with no slash and falls through to drift, as does any sibling like
# .ai/parked.md. Pure sh `case` on purpose -- no regex to escape, no grep to
# depend on. The verdict is a variable echoed from inside the group, never an
# `exit` from inside the loop: POSIX lets a shell run the last pipeline stage
# in the current environment (ksh93 does; bash under `lastpipe`), where an
# `exit` there would kill the script with no output and a nonzero status --
# breaking the "exactly one line, always exit 0" contract above precisely on
# the drift answer.
printf '%s\n' "$paths" | {
  verdict=cursor-sync
  while IFS= read -r p; do
    case "$p" in
      .ai/next-steps.md | .ai/parked/*) ;;
      *) verdict=drift; break ;;
    esac
  done
  echo "$verdict"
}
