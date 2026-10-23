#!/bin/sh
# Fixture tests for scripts/test-all.sh: the parallel runner for every tests/*.test.sh (#809).
#
# Each case copies the real scripts/test-all.sh into a scratch tree whose tests/ holds only stub
# suites and runs it there, so the real suites never run from this fixture. Stubs: pass.test.sh
# passes; fail.test.sh prints a sentinel and exits 1; skipa.test.sh prints `SKIP - stub` on
# stderr and exits 0; skipb.test.sh prints `skip - stub` on stdout and exits 0; and
# identity-review.test.sh is an ordinary stub (marker, sleep, done file). The held-out case adds
# ai-cursor-banner.test.sh and loop-critic.test.sh stubs that fail if any other stub's marker
# exists when they start or just before they end (ai-cursor-banner also fails unless
# identity-review has finished, and loop-critic unless ai-cursor-banner has). The TERM case's slow
# stub traps TERM, writes a marker and exits. The parallel case's two stubs each wait up to about
# 5 s for the other's marker, so a serialised -j 2 pool fails; the overlap case does the same with
# an identity-review stub and a pool stub, so a run that starts identity-review after the pool
# fails.
# The -x cases add extra.test.sh, a stub that passes: -x extra.test.sh and
# -x identity-review.test.sh each leave that file's verdict line out and the rest of the run
# unchanged, two -x options leave both out, and -x with no value, an empty value, a value with a
# slash and a value naming no file exit 2 with the usage on stderr and run nothing.
# Needs bash (the runner is a bash script). Permitted toolset: POSIX sh, plus bash, grep, sed
# and sleep.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
runner="$root_dir/scripts/test-all.sh"

if ! command -v bash >/dev/null 2>&1; then
  echo "SKIP - bash not on PATH; test-all.test.sh needs it" >&2
  exit 0
fi

tmp="$(cd -P "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

fail=0
ok() { echo "ok   - $1"; }
bad() { echo "FAIL - $1"; fail=1; }
assert_eq() { # <desc> <want> <got>
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$2', got '$3')"; fi
}
assert_has() { # <desc> <file> <fixed string>
  if grep -qF -- "$3" "$2"; then ok "$1"; else bad "$1 (missing '$3')"; fi
}
assert_lacks() { # <desc> <file> <fixed string>
  if grep -qF -- "$3" "$2"; then bad "$1 (found '$3')"; else ok "$1"; fi
}

# make_tree <dir> <with-fail 0|1>: a scratch repo layout with the runner and the stubs
make_tree() {
  d="$1"
  mkdir -p "$d/scripts" "$d/tests" "$d/state"
  cp "$runner" "$d/scripts/test-all.sh"
  for n in pass skipa skipb fail; do
    [ "$n" = fail ] && [ "$2" = 0 ] && continue
    body="touch \"$d/state/$n.marker\"; sleep 1; rm -f \"$d/state/$n.marker\"; touch \"$d/state/$n.done\""
    case "$n" in
      pass) printf '%s\n' "$body" >"$d/tests/pass.test.sh" ;;
      skipa) printf '%s\necho "SKIP - stub" >&2\n' "$body" >"$d/tests/skipa.test.sh" ;;
      skipb) printf '%s\necho "skip - stub"\n' "$body" >"$d/tests/skipb.test.sh" ;;
      fail) printf '%s\necho "SENTINEL-FAILURE-LINE"\nexit 1\n' "$body" >"$d/tests/fail.test.sh" ;;
    esac
  done
  printf '%s\n' "touch \"$d/state/identity-review.marker\"; sleep 1; rm -f \"$d/state/identity-review.marker\"; touch \"$d/state/identity-review.done\"" \
    >"$d/tests/identity-review.test.sh"
}

# run <dir> [args...]: run the copied runner, stdout to out, stderr to err, status to rc
run() {
  d="$1"; shift
  rc=0
  rm -f "$d"/state/*.done
  (cd "$d" && bash scripts/test-all.sh "$@") >"$d/out" 2>"$d/err" || rc=$?
}

# --- a failing stub, default -j ---
t1="$tmp/t1"
make_tree "$t1" 1
run "$t1"
assert_eq "failing tree exits 1" 1 "$rc"
assert_has "fail verdict" "$t1/out" "fail tests/fail.test.sh"
assert_has "pass verdict" "$t1/out" "pass tests/pass.test.sh"
assert_has "skip verdict, SKIP form" "$t1/out" "skip tests/skipa.test.sh"
assert_has "skip verdict, skip form" "$t1/out" "skip tests/skipb.test.sh"
assert_has "SKIP line indented" "$t1/out" "  SKIP - stub"
assert_has "skip line indented" "$t1/out" "  skip - stub"
assert_has "failure header" "$t1/out" "--- tests/fail.test.sh (exit 1)"
assert_has "failure log sentinel" "$t1/out" "SENTINEL-FAILURE-LINE"
assert_has "identity-review passes" "$t1/out" "pass tests/identity-review.test.sh"
assert_eq "identity-review verdict is first" "pass tests/identity-review.test.sh" \
  "$(grep -E '^(pass|fail|skip) ' "$t1/out" | head -n 1)"
assert_has "summary counts" "$t1/out" "test-all: 2 pass, 1 fail, 2 skip"

# --- without the failing stub ---
t2="$tmp/t2"
make_tree "$t2" 0
run "$t2"
assert_eq "clean tree exits 0" 0 "$rc"
assert_has "clean: SKIP form skip" "$t2/out" "skip tests/skipa.test.sh"
assert_has "clean: skip form skip" "$t2/out" "skip tests/skipb.test.sh"
assert_has "clean: summary" "$t2/out" "test-all: 2 pass, 0 fail, 2 skip"
assert_lacks "clean: no failure header" "$t2/out" "--- "

# --- -j 1 and -j 3 give the same verdicts ---
run "$t1" -j 1
v1="$(grep -E '^(pass|fail|skip) ' "$t1/out")"
run "$t1" -j 3
v3="$(grep -E '^(pass|fail|skip) ' "$t1/out")"
assert_eq "-j 1 and -j 3 agree" "$v1" "$v3"
run "$t1"
assert_eq "default -j agrees with -j 1" "$v1" "$(grep -E '^(pass|fail|skip) ' "$t1/out")"

# --- bad arguments ---
for args in "-j 0" "-j 08" "-j 1000" "-j x" "-j" "--bogus" "-j 2 extra"; do
  # shellcheck disable=SC2086
  run "$t1" $args
  assert_eq "'$args' exits 2" 2 "$rc"
  assert_has "'$args' prints usage on stderr" "$t1/err" "Usage: bash scripts/test-all.sh"
done
run "$t1" -h
assert_eq "-h exits 0" 0 "$rc"
assert_has "-h prints usage on stdout" "$t1/out" "Usage: bash scripts/test-all.sh"

# --- an empty tests/ ---
t3="$tmp/t3"
mkdir -p "$t3/scripts" "$t3/tests"
cp "$runner" "$t3/scripts/test-all.sh"
rc=0
(cd "$t3" && bash scripts/test-all.sh) >"$t3/out" 2>"$t3/err" || rc=$?
assert_eq "empty tests/ exits 1" 1 "$rc"
assert_has "empty tests/ message" "$t3/err" "no tests found"

# --- the runner's temp directory is gone ---
t4="$tmp/t4"
make_tree "$t4" 1
mkdir "$t4/tmpd"
rc=0
(cd "$t4" && TMPDIR="$t4/tmpd" bash scripts/test-all.sh) >"$t4/out" 2>"$t4/err" || rc=$?
assert_eq "temp dir run exits 1" 1 "$rc"
assert_eq "runner temp directory removed" "" "$(ls -A "$t4/tmpd")"

# --- TERM: the runner exits 143 and removes its directory ---
t5="$tmp/t5"
mkdir -p "$t5/scripts" "$t5/tests" "$t5/tmpd"
cp "$runner" "$t5/scripts/test-all.sh"
{
  echo "trap 'touch \"$t5/termed\"; kill \$c 2>/dev/null; exit 0' TERM"
  echo "sleep 5 &"
  echo "c=\$!"
  echo "touch \"$t5/ready\""
  echo "wait \$c"
} >"$t5/tests/slow.test.sh"
(cd "$t5" && TMPDIR="$t5/tmpd" exec bash scripts/test-all.sh) >"$t5/out" 2>"$t5/err" &
pid=$!
n=0
while [ ! -f "$t5/ready" ] && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
kill -TERM "$pid"
rc=0
wait "$pid" || rc=$?
assert_eq "TERM exits 143" 143 "$rc"
assert_eq "TERM leaves no runner temp directory" "" "$(ls -A "$t5/tmpd")"
assert_eq "TERM prints nothing" "" "$(cat "$t5/out")"
assert_eq "TERM reached the running suite" 1 "$([ -f "$t5/termed" ] && echo 1 || echo 0)"

# --- -j 2 really runs two suites at once (a serialised pool fails) ---
t8="$tmp/t8"
mkdir -p "$t8/scripts" "$t8/tests" "$t8/state"
cp "$runner" "$t8/scripts/test-all.sh"
for n in a b; do
  o=b
  [ "$n" = b ] && o=a
  {
    echo "touch \"$t8/state/$n.marker\""
    echo "i=0"
    echo "while [ ! -f \"$t8/state/$o.marker\" ] && [ \"\$i\" -lt 50 ]; do sleep 0.1; i=\$((i + 1)); done"
    echo "[ -f \"$t8/state/$o.marker\" ] || { echo \"$o never started\"; exit 1; }"
  } >"$t8/tests/$n.test.sh"
done
rc=0
(cd "$t8" && bash scripts/test-all.sh -j 2) >"$t8/out" 2>"$t8/err" || rc=$?
assert_eq "parallel pool exits 0" 0 "$rc"
assert_has "parallel pool: a passes" "$t8/out" "pass tests/a.test.sh"
assert_has "parallel pool: b passes" "$t8/out" "pass tests/b.test.sh"

# --- identity-review starts with the pool (starting it after the pool fails) ---
t9="$tmp/t9"
mkdir -p "$t9/scripts" "$t9/tests" "$t9/state"
cp "$runner" "$t9/scripts/test-all.sh"
for n in identity-review a; do
  o=a
  [ "$n" = a ] && o=identity-review
  {
    echo "touch \"$t9/state/$n.marker\""
    echo "i=0"
    echo "while [ ! -f \"$t9/state/$o.marker\" ] && [ \"\$i\" -lt 50 ]; do sleep 0.1; i=\$((i + 1)); done"
    echo "[ -f \"$t9/state/$o.marker\" ] || { echo \"$o never started\"; exit 1; }"
  } >"$t9/tests/$n.test.sh"
done
rc=0
(cd "$t9" && bash scripts/test-all.sh -j 2) >"$t9/out" 2>"$t9/err" || rc=$?
assert_eq "overlap tree exits 0" 0 "$rc"
assert_has "overlap: identity-review passes" "$t9/out" "pass tests/identity-review.test.sh"
assert_has "overlap: pool stub passes" "$t9/out" "pass tests/a.test.sh"

# --- held-out suites run alone, after the pool, in list order ---
t6="$tmp/t6"
mkdir -p "$t6/scripts" "$t6/tests" "$t6/state"
cp "$runner" "$t6/scripts/test-all.sh"
for n in pass skipa identity-review; do
  echo "touch \"$t6/state/$n.marker\"; sleep 1; rm -f \"$t6/state/$n.marker\"; touch \"$t6/state/$n.done\"" \
    >"$t6/tests/$n.test.sh"
done
for n in ai-cursor-banner loop-critic; do
  {
    [ "$n" = ai-cursor-banner ] &&
      echo "[ -f \"$t6/state/identity-review.done\" ] || { echo \"identity-review not done\"; exit 1; }"
    [ "$n" = loop-critic ] &&
      echo "[ -f \"$t6/state/ai-cursor-banner.done\" ] || { echo \"ai-cursor-banner not done\"; exit 1; }"
    echo "ls \"$t6/state\" | grep -q marker && { echo marker at start; exit 1; }"
    echo "touch \"$t6/state/$n.marker\"; sleep 1"
    echo "ls \"$t6/state\" | grep -v '^$n.marker\$' | grep -q marker && { echo marker at end; exit 1; }"
    echo "rm -f \"$t6/state/$n.marker\"; touch \"$t6/state/$n.done\""
  } >"$t6/tests/$n.test.sh"
done
run "$t6"
assert_eq "held-out tree exits 0" 0 "$rc"
assert_eq "held-out: identity-review verdict is first" "tests/identity-review.test.sh" \
  "$(grep -E '^(pass|fail|skip) ' "$t6/out" | head -n 1 | sed 's/^[a-z]* //')"
assert_eq "held-out verdicts end in list order" \
  "tests/ai-cursor-banner.test.sh tests/loop-critic.test.sh" \
  "$(grep -E '^(pass|fail|skip) ' "$t6/out" | tail -n 2 | sed 's/^[a-z]* //' | tr '\n' ' ' | sed 's/ $//')"
assert_has "held-out: summary" "$t6/out" "test-all: 5 pass, 0 fail, 0 skip"
run "$t6" -x loop-critic.test.sh
assert_eq "-x held-out file exits 0" 0 "$rc"
assert_lacks "-x held-out file: verdict line gone" "$t6/out" "tests/loop-critic.test.sh"
assert_has "-x held-out file: ai-cursor-banner runs" "$t6/out" "pass tests/ai-cursor-banner.test.sh"
assert_has "-x held-out file: summary" "$t6/out" "test-all: 4 pass, 0 fail, 0 skip"

# --- -x leaves a file out ---
t7="$tmp/t7"
make_tree "$t7" 0
echo "exit 0" >"$t7/tests/extra.test.sh"
run "$t7"
assert_eq "-x baseline exits 0" 0 "$rc"
assert_has "-x baseline: extra runs" "$t7/out" "pass tests/extra.test.sh"
assert_has "-x baseline: summary" "$t7/out" "test-all: 3 pass, 0 fail, 2 skip"
run "$t7" -x extra.test.sh
assert_eq "-x pool file exits 0" 0 "$rc"
assert_lacks "-x pool file: verdict line gone" "$t7/out" "tests/extra.test.sh"
assert_has "-x pool file: rest unchanged" "$t7/out" "pass tests/pass.test.sh"
assert_has "-x pool file: identity-review still runs" "$t7/out" "pass tests/identity-review.test.sh"
assert_has "-x pool file: summary" "$t7/out" "test-all: 2 pass, 0 fail, 2 skip"
run "$t7" -x identity-review.test.sh
assert_eq "-x pool file (identity-review) exits 0" 0 "$rc"
assert_lacks "-x pool file (identity-review): verdict line gone" "$t7/out" "tests/identity-review.test.sh"
assert_has "-x pool file (identity-review): extra runs" "$t7/out" "pass tests/extra.test.sh"
assert_has "-x pool file (identity-review): summary" "$t7/out" "test-all: 2 pass, 0 fail, 2 skip"
run "$t7" -x extra.test.sh -x identity-review.test.sh
assert_eq "two -x exits 0" 0 "$rc"
assert_lacks "two -x: extra gone" "$t7/out" "tests/extra.test.sh"
assert_lacks "two -x: identity-review gone" "$t7/out" "tests/identity-review.test.sh"
assert_has "two -x: summary" "$t7/out" "test-all: 1 pass, 0 fail, 2 skip"
for x in "a/b" "../tests/extra.test.sh" "tests/extra.test.sh" "nosuch.test.sh" "extra" "*"; do
  run "$t7" -x "$x"
  assert_eq "-x '$x' exits 2" 2 "$rc"
  assert_has "-x '$x' prints usage on stderr" "$t7/err" "Usage: bash scripts/test-all.sh"
  assert_eq "-x '$x' runs nothing" "" "$(cat "$t7/out")"
done
run "$t7" -x ""
assert_eq "-x with an empty value exits 2" 2 "$rc"
assert_has "-x with an empty value prints usage on stderr" "$t7/err" "Usage: bash scripts/test-all.sh"
run "$t7" -x
assert_eq "-x with no value exits 2" 2 "$rc"
assert_has "-x with no value prints usage on stderr" "$t7/err" "Usage: bash scripts/test-all.sh"
run "$t7" -x extra.test.sh -x
assert_eq "a trailing -x with no value exits 2" 2 "$rc"
# the name is checked against the repo root's tests/, whatever the caller's directory
rc=0
(cd "$t7/tests" && bash ../scripts/test-all.sh -x extra.test.sh) >"$t7/out" 2>"$t7/err" || rc=$?
assert_eq "-x from another directory exits 0" 0 "$rc"
assert_lacks "-x from another directory: verdict line gone" "$t7/out" "tests/extra.test.sh"
run "$t7" -h
assert_has "-h shows -x" "$t7/out" "-x NAME"

exit "$fail"
