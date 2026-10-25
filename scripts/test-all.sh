#!/usr/bin/env bash
# Runs every tests/*.test.sh, N at a time, and reports one verdict per file.
#
# Usage: bash scripts/test-all.sh [-j N] [-x NAME]... [-s FILE]
#   -j N     run at most N files at once. N is one to three decimal digits with no leading
#            zero. Default: the CPU count (`nproc`, else `getconf _NPROCESSORS_ONLN`, else 4).
#   -x NAME  leave tests/NAME out of the run; repeatable. NAME is the file name, byte for byte,
#            of a tests/*.test.sh file the glob finds (a pool file or a held-out one).
#   -s FILE  after the run, before the final count line, append a Markdown section to FILE (CI
#            passes $GITHUB_STEP_SUMMARY): each `skip` suite with its `SKIP - ` and `skip - ` lines
#            in a fenced code block, or one line saying no suite skipped. It changes neither the
#            exit code nor stdout. FILE is an absolute path to an existing, writable file (the
#            script changes to the repo root before running suites); anything else exits 2 before
#            any suite starts.
#   -h       print this usage on stdout and exit 0.
# A bad -j value, a bad -x value (none, or one naming no such file), a bad -s value, a missing
# value or any other argument prints the usage on stderr and exits 2.
#
# The files are found by a glob (sorted), so a new tests/X.test.sh is picked up with no list to
# edit; every matching file runs, tracked or not. Each runs as `sh tests/NAME` from the repo
# root with stdout and stderr together in one log under a mktemp -d directory.
# tests/identity-review.test.sh is the longest suite (its own header's Runtime note: about 26 s
# alone in the dev container), so it is the first suite started, with the pool, and takes one of
# the -j slots. Two suites are held out of the pool and started one at a time after the pool,
# identity-review included, has drained, in this order, each with nothing else running:
# tests/ai-cursor-banner.test.sh and tests/loop-critic.test.sh assert wall-clock upper bounds
# that a loaded pool can trip. A held-out file the glob does not find is skipped. No glob match
# prints `no tests found` and exits 1.
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
# Tool notes for some suites (a suite missing a tool it needs reports `skip`, loudly; but
# tests/identity-review.test.sh, tests/identity-launchers.test.sh and tests/review-verdict.test.sh
# fail instead when WOW_TESTS_REQUIRE_TOOLS is exactly 1, which ci.yml sets):
#   - tests/invariants-only.test.sh needs `yq`, `jq` and `git` for its run-each-id-alone case and
#     skips that case loudly without them.
#   - `yq` also: tests/review-base-anchor.test.sh, tests/schema-complete.test.sh,
#     tests/milestone-desc.test.sh, tests/spec-issue.test.sh, tests/spec-post.test.sh,
#     tests/spec-fresh.test.sh and tests/critic-select.test.sh (which also need `git`),
#     tests/draft-identity.test.sh and
#     tests/invariants-required-checks.test.sh (the checker's check 26 needs it).
#   - `yq` also, for part of a suite: tests/token-check.test.sh (its actor cases),
#     tests/gh-identity.test.sh (its classify cases) and tests/app-push.test.sh (its commit_route
#     reader cases) skip those cases without it; tests/spec-comment.test.sh and
#     tests/review-sandbox.test.sh skip the whole suite.
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
#   - tests/invariants-manifest-agents.test.sh needs `jq` (the checker's check 25 does).
#   - tests/identity-review.test.sh takes 26 s alone and its bound is 52 s; see the Runtime
#     bullet of the Lanes section of docs/identity/DEV-CONTAINER.md.
# The script is verified under bash 5 (the dev container and CI); it has not been run under bash
# 3.2.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash scripts/test-all.sh [-j N] [-x NAME]... [-s FILE]
  -j N     run at most N test files at once (one to three digits, no leading zero);
           default: the CPU count
  -x NAME  leave tests/NAME out of the run (a tests/*.test.sh file name); repeatable
  -s FILE  append the skipped suites to FILE (absolute path of an existing, writable file)
  -h       print this usage
EOF
}

jobs=""
xs=()   # -x names, checked against the glob after the cd below
summary=""   # -s FILE
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
    -x)
      if [ "$#" -lt 2 ]; then
        usage >&2
        exit 2
      fi
      xs+=("$2")
      shift 2
      ;;
    -s)
      if [ "$#" -lt 2 ]; then
        usage >&2
        exit 2
      fi
      summary="$2"
      shift 2
      case "$summary" in
        /*) ;;
        *)
          usage >&2
          exit 2
          ;;
      esac
      if [ ! -f "$summary" ] || [ ! -w "$summary" ]; then
        usage >&2
        exit 2
      fi
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

is_excluded() { # <name>
  local x
  for x in ${xs[@]+"${xs[@]}"}; do
    [ "$x" = "$1" ] && return 0
  done
  return 1
}
# Each -x name must be a file the glob finds, so a renamed suite cannot drop out of every job.
for x in ${xs[@]+"${xs[@]}"}; do
  found=0
  for f in tests/*.test.sh; do
    [ -f "$f" ] && [ "${f#tests/}" = "$x" ] && found=1
  done
  if [ "$found" -eq 0 ]; then
    usage >&2
    exit 2
  fi
done

held=(ai-cursor-banner.test.sh loop-critic.test.sh)
first=identity-review.test.sh   # the longest suite: started first so it overlaps the rest of the pool
names=()
if [ -f "tests/$first" ] && ! is_excluded "$first"; then
  names+=("$first")
fi
for f in tests/*.test.sh; do
  [ -f "$f" ] || continue
  ! is_excluded "${f#tests/}" || continue
  is_held=0
  for h in "$first" "${held[@]}"; do
    [ "${f#tests/}" = "$h" ] && is_held=1
  done
  [ "$is_held" -eq 1 ] || names+=("${f#tests/}")
done
pool_end="${#names[@]}"
for h in "${held[@]}"; do
  [ -f "tests/$h" ] && ! is_excluded "$h" && names+=("$h")
done
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
  jobs -rp 2>/dev/null >"$logdir/jobs" || true
  local live=" $(tr '\n' ' ' 2>/dev/null <"$logdir/jobs") "
  for i in $running; do
    case "$live" in
      *" ${pids[$i]} "*) kill -TERM "${pids[$i]}" 2>/dev/null || true ;;
    esac
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
  local keep="" i rc live
  # bash's own job table: a reused PID cannot pass for a suite. `jobs -rp` is its own statement,
  # not the first stage of a pipeline, so it reads this shell's table on every bash (a pipeline's
  # subshell is not guaranteed to keep it); "jobs" cannot collide with the numbered logs.
  jobs -rp >"$logdir/jobs"
  live=" $(tr '\n' ' ' <"$logdir/jobs") "
  for i in $running; do
    case "$live" in
      *" ${pids[$i]} "*)
        keep="$keep $i"
        ;;
      *)
        rc=0
        wait "${pids[$i]}" || rc=$?
        rcs[$i]=$rc
        ;;
    esac
  done
  running="$keep"
}

count() { # number of running suites
  local n=0 i
  for i in $running; do n=$((n + 1)); done
  echo "$n"
}

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

while [ "$next" -lt "$total" ]; do
  start "$next"
  next=$((next + 1))
  while [ -n "$running" ]; do
    reap
    [ -z "$running" ] || sleep 0.1
  done
done

pass=0
fail=0
skip=0
skipped=""   # the -s section's body: one block per skipped suite
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
    skipped="$skipped
\`tests/${names[$i]}\`

\`\`\`
$(grep -E '^(SKIP|skip) - ' "$log")
\`\`\`
"
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

if [ -n "$summary" ]; then
  if [ "$skip" -eq 0 ]; then
    printf '\n### test-all skips\n\nNo suite skipped.\n' >>"$summary"
  else
    printf '\n### test-all skips\n%s' "$skipped" >>"$summary"
  fi
fi

echo "test-all: $pass pass, $fail fail, $skip skip"
[ "$fail" -eq 0 ]
