#!/usr/bin/env bash
# Runs every tests/*.test.sh, N at a time, and reports one verdict per file.
#
# Usage: bash scripts/test-all.sh [-j N]
#   -j N   run at most N files at once. N is one to three decimal digits with no leading
#          zero. Default: the CPU count (`nproc`, else `getconf _NPROCESSORS_ONLN`, else 4).
#   -h     print this usage on stdout and exit 0.
# A bad -j value, a missing value or any other argument prints the usage on stderr and exits 2.
#
# The files are found by a glob (sorted), so a new tests/X.test.sh is picked up with no list to
# edit; every matching file runs, tracked or not. Each runs as `sh tests/NAME` from the repo
# root with stdout and stderr together in one log under a mktemp -d directory.
# tests/identity-review.test.sh is held out of the pool and started last, with nothing else
# running (its own header's Runtime note: about 88 s alone in the dev container), so a whole run
# needs more than a two-minute tool timeout. No glob match prints `no tests found` and exits 1.
#
# Verdicts: a non-zero exit is `fail`; exit 0 with a log line beginning `SKIP - ` or `skip - `
# is `skip`; any other exit 0 is `pass`. A skip never fails the run. Output, once every file has
# finished: one `<verdict> <path>` line per file in run order (a skip line's `SKIP - ` and
# `skip - ` lines indented two spaces under it), then `--- <path> (exit CODE)` and the whole log
# of each failed file, then `test-all: P pass, F fail, S skip`. Exit 1 when F is not zero.
# On INT or TERM the runner sends TERM to the suites it started that are still running,
# removes its own directory, prints nothing more and exits 130 or 143. A suite so stopped, like
# every suite when the runner is KILLed, may leave its own children and temp directory behind.
# The runner waits for each stopped suite, so a suite that traps TERM delays the exit.
#
# Tool notes for some suites (a suite missing a tool it needs reports `skip`, loudly):
#   - tests/invariants-only.test.sh needs `yq`, `jq` and `git` for its run-each-id-alone case and
#     skips that case loudly without them.
#   - `yq` also: tests/review-base-anchor.test.sh, tests/schema-complete.test.sh,
#     tests/milestone-desc.test.sh, tests/spec-issue.test.sh, tests/spec-post.test.sh,
#     tests/spec-fresh.test.sh (which also needs `git`) and tests/draft-identity.test.sh.
#   - tests/lane.test.sh and tests/lane-state.test.sh need `git`, `yq` and `jq`;
#     tests/statusline-context.test.sh needs `jq`; tests/compact-handoff.test.sh needs `git`
#     (and `jq` for its registration cases).
#   - tests/review-image.test.sh needs `jq` and `yq`.
#   - tests/review-verdict.test.sh needs `jq`.
#   - tests/plan-gather.test.sh needs `yq` for its `authors` section and skips that section loudly
#     without it.
#   - tests/identity-launchers.test.sh needs `pwsh`, `git`, `yq` and `jq`;
#     tests/identity-broker.test.sh needs `pwsh`.
#   - tests/invariants-files-filter.test.sh needs `jq` (the checker's check 20 does).
#   - tests/identity-review.test.sh takes 88 s alone and its bound is 176 s; see the Runtime
#     bullet of the Lanes section of docs/identity/DEV-CONTAINER.md.
# The script runs under bash 3.2.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash scripts/test-all.sh [-j N]
  -j N   run at most N test files at once (one to three digits, no leading zero);
         default: the CPU count
  -h     print this usage
EOF
}

jobs=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h)
      usage
      exit 0
      ;;
    -j)
      if [ "$#" -lt 2 ]; then
        usage >&2
        exit 2
      fi
      jobs="$2"
      shift 2
      case "$jobs" in
        [1-9] | [1-9][0-9] | [1-9][0-9][0-9]) ;;
        *)
          usage >&2
          exit 2
          ;;
      esac
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$jobs" ]; then
  jobs="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
  case "$jobs" in
    [1-9] | [1-9][0-9] | [1-9][0-9][0-9]) ;;
    *) jobs=4 ;;
  esac
fi

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

last="identity-review.test.sh"
names=()
have_last=0
for f in tests/*.test.sh; do
  [ -f "$f" ] || continue
  if [ "${f#tests/}" = "$last" ]; then
    have_last=1
  else
    names+=("${f#tests/}")
  fi
done
[ "$have_last" -eq 1 ] && names+=("$last")
if [ "${#names[@]}" -eq 0 ]; then
  echo "no tests found" >&2
  exit 1
fi
total="${#names[@]}"

logdir="$(mktemp -d)"
running=""   # space-separated indexes of started, unreaped suites
pids=()
rcs=()

cleanup() {
  trap '' INT TERM
  for i in $running; do
    kill -TERM "${pids[$i]}" 2>/dev/null || true
  done
  for i in $running; do
    wait "${pids[$i]}" 2>/dev/null || true
  done
  rm -rf "$logdir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

start() { # <index>
  sh "tests/${names[$1]}" >"$logdir/$1.log" 2>&1 &
  pids[$1]=$!
  running="$running $1"
}

reap() { # reap every finished suite
  local keep="" i rc
  for i in $running; do
    if kill -0 "${pids[$i]}" 2>/dev/null; then
      keep="$keep $i"
    else
      rc=0
      wait "${pids[$i]}" || rc=$?
      rcs[$i]=$rc
    fi
  done
  running="$keep"
}

count() { # number of running suites
  local n=0 i
  for i in $running; do n=$((n + 1)); done
  echo "$n"
}

pool_end="$total"
[ "$have_last" -eq 1 ] && pool_end=$((total - 1))

next=0
while [ "$next" -lt "$pool_end" ]; do
  reap
  if [ "$(count)" -lt "$jobs" ]; then
    start "$next"
    next=$((next + 1))
  else
    sleep 0.1
  fi
done
while [ -n "$running" ]; do
  reap
  [ -z "$running" ] || sleep 0.1
done

if [ "$have_last" -eq 1 ]; then
  start "$pool_end"
  while [ -n "$running" ]; do
    reap
    [ -z "$running" ] || sleep 0.1
  done
fi

pass=0
fail=0
skip=0
i=0
while [ "$i" -lt "$total" ]; do
  log="$logdir/$i.log"
  if [ "${rcs[$i]}" -ne 0 ]; then
    verdict=fail
    fail=$((fail + 1))
  elif grep -Eq '^(SKIP|skip) - ' "$log"; then
    verdict=skip
    skip=$((skip + 1))
  else
    verdict=pass
    pass=$((pass + 1))
  fi
  echo "$verdict tests/${names[$i]}"
  if [ "$verdict" = skip ]; then
    grep -E '^(SKIP|skip) - ' "$log" | sed 's/^/  /'
  fi
  i=$((i + 1))
done

i=0
while [ "$i" -lt "$total" ]; do
  if [ "${rcs[$i]}" -ne 0 ]; then
    echo "--- tests/${names[$i]} (exit ${rcs[$i]})"
    cat "$logdir/$i.log"
  fi
  i=$((i + 1))
done

echo "test-all: $pass pass, $fail fail, $skip skip"
[ "$fail" -eq 0 ]
