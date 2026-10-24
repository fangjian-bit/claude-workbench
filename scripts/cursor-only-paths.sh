#!/bin/sh
# Are all of a PR's changed paths cursor-sync files? Reads newline-separated repo paths on stdin
# and prints `true` or `false`, then exits 0. ci.yml's `changed-paths` job runs the base's copy
# of this script to decide whether the test jobs may be skipped (#989).
#
# `true` only when the input has at least one line and every line is exactly `.ai/next-steps.md`
# or starts with `.ai/parked/` and is longer than that. Anything else is `false`: empty input,
# any other path (a final line with no newline counts as a line), a quoted path from git (one
# that starts with a double quote), or `.ai/parked` with no slash. Lines are read byte for byte.
#
# The list is the one in plugins/way-of-working/bin/cursor-drift.sh. No suite reads these paths
# from the repository: a search of tests/ shows the only suites that mention `.ai/next-steps.md`
# or `.ai/parked/` (tests/cursor-sync-pr.test.sh, tests/spec-fresh.test.sh,
# tests/loop-baseline.test.sh, tests/ai-cursor-banner.test.sh, tests/cursor-drift.test.sh) write
# them as fixtures in their own temp directory or fake input;
# tests/invariants-gate-args.test.sh and tests/invariants-usage-exit.test.sh copy only
# .ai/project.yml from the checkout, and scripts/test-all.sh reads only tests/.
#
# Permitted toolset: POSIX sh.
n=0
while IFS= read -r line || [ -n "$line" ]; do
  n=$((n + 1))
  case "$line" in
    .ai/next-steps.md) ;;
    .ai/parked/?*) ;;
    *)
      echo false
      exit 0
      ;;
  esac
done
if [ "$n" -gt 0 ]; then echo true; else echo false; fi
