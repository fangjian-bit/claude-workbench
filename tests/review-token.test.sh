#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/review-token.sh.
#
# #389 (WB-D24): architect-review mints a reviewer token only after the review sandbox is
# destroyed, posts with it, then deletes it. The broker is a stub `wow-review-mint` on PATH.
#
# Permitted toolset: POSIX sh.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/plugins/way-of-working/bin/review-token.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok - $1"
  else
    echo "FAIL - $1: expected [$2], got [$3]" >&2
    fail=1
  fi
}

home="$tmp/home"
bin="$tmp/bin"
mkdir -p "$bin" "$home"
calls="$tmp/calls"
tokfile="$home/review-tokens/scratch/reviewer-token"
tok=ghs_0123456789abcdefghijklmnopqrstuvwxyzABCD

# The stub honours STUB_MODE: good | expired | user | empty | noop | fail. It records its argv.
cat >"$bin/wow-review-mint" <<'STUB'
#!/bin/sh
echo "$*" >>"$STUB_CALLS"
[ "${STUB_MODE:-good}" != fail ] || exit 1
d="$WOW_HOME/review-tokens/$1"
mkdir -p "$d"
case "${STUB_MODE:-good}" in
  good)    printf '%s\n%s\n' ghs_0123456789abcdefghijklmnopqrstuvwxyzABCD 2999-01-01T00:00:00Z >"$d/reviewer-token" ;;
  expired) printf '%s\n%s\n' ghs_0123456789abcdefghijklmnopqrstuvwxyzABCD 2000-01-01T00:00:00Z >"$d/reviewer-token" ;;
  user)    printf '%s\n%s\n' ghp_0123456789abcdefghijklmnopqrstuvwxyzABCD 2999-01-01T00:00:00Z >"$d/reviewer-token" ;;
  empty)   : >"$d/reviewer-token" ;;
  noop)    : ;;
esac
STUB
chmod +x "$bin/wow-review-mint"

root="$tmp/root"
mkdir -p "$root"
run() { # run <mode> <args...>
  mode=$1; shift
  rc=0
  out=$(PATH="$bin:$PATH" WOW_HOME="$home" REVIEW_SANDBOX_ROOT="$root" STUB_MODE="$mode" STUB_CALLS="$calls" sh "$script" "$@" 2>"$tmp/err") || rc=$?
}
expect() { # expect <desc> <out> <rc>
  assert_eq "$1 (stdout)" "$2" "$out"
  assert_eq "$1 (rc)" "$3" "$rc"
  [ "$rc" = "$3" ] || sed "s/^/  stderr: /" "$tmp/err" >&2
}
nocalls() { assert_eq "$1: broker never called" "" "$(cat "$calls")"; }
gone() { assert_eq "$1" "no" "$([ -e "$tokfile" ] && echo yes || echo no)"; }

: >"$calls"
mkdir -p "$root/7"
run good request owner/scratch
expect "sandbox dir present: refused" "" 2
nocalls "sandbox dir present"
gone "sandbox dir present: no token file"
rmdir "$root/7"

: >"$root/7.marker"
run good request owner/scratch
expect "marker present: refused" "" 2
nocalls "marker present"
rm "$root/7.marker"

# Any sandbox blocks, whichever PR it belongs to: another PR's code must not run beside this token.
mkdir -p "$root/8"
run good request owner/scratch
expect "other PR's sandbox present: refused" "" 2
nocalls "other PR's sandbox"
rmdir "$root/8"

# A sandbox root that does not exist at all (nothing was ever built) passes.
rmdir "$root"
run good request owner/scratch
expect "no sandbox root: token path printed" "$tokfile" 0
mkdir -p "$root"
assert_eq "broker got only the bare repo name" "scratch" "$(cat "$calls")"
assert_eq "token file exists" "yes" "$([ -f "$tokfile" ] && echo yes || echo no)"

run good discard owner/scratch
expect "discard removes the file" "discarded" 0
gone "discard: file gone"
run good discard owner/scratch
expect "discard of a missing file is fine" "discarded" 0

# A stale live token is never read as this request's: a broker that exits 0 and writes nothing.
mkdir -p "$(dirname "$tokfile")"
printf '%s\n%s\n' "$tok" 2999-01-01T00:00:00Z >"$tokfile"
run noop request owner/scratch
expect "broker writes nothing: stale token not returned" "" 2
gone "broker writes nothing: stale token removed"

printf '%s\n%s\n' "$tok" 2999-01-01T00:00:00Z >"$tokfile"
run fail request owner/scratch
expect "broker failure: refused" "" 2
gone "broker failure: stale token removed"

for m in expired user empty; do
  run "$m" request owner/scratch
  expect "$m token: refused" "" 2
  gone "$m token: file removed"
done

# No broker on PATH.
rc=0
out=$(PATH="/usr/bin:/bin" WOW_HOME="$home" REVIEW_SANDBOX_ROOT="$root" sh "$script" request owner/scratch 2>/dev/null) || rc=$?
expect "no broker on PATH: refused" "" 2

# WOW_HOME is required and absolute.
: >"$calls"
for h in "" relative/dir; do
  rc=0
  out=$(PATH="$bin:$PATH" WOW_HOME="$h" REVIEW_SANDBOX_ROOT="$root" STUB_CALLS="$calls" sh "$script" request owner/scratch 2>/dev/null) || rc=$?
  expect "WOW_HOME [$h]: refused" "" 2
done
rc=0
out=$(env -u WOW_HOME PATH="$bin:$PATH" REVIEW_SANDBOX_ROOT="$root" STUB_CALLS="$calls" sh "$script" discard owner/scratch 2>/dev/null) || rc=$?
expect "WOW_HOME unset: refused" "" 2
nocalls "WOW_HOME refused"

# A sandbox root that is a symlink, or a plain file, is refused, never read as empty.
rm -rf "$root"
: >"$root"
run good request owner/scratch
expect "sandbox root is a file: refused" "" 2
rm -f "$root"
if ln -s "$tmp" "$root" 2>/dev/null && [ -L "$root" ]; then
  run good request owner/scratch
  expect "symlinked sandbox root: refused" "" 2
  rm -f "$root"
else
  echo "skip - symlinked sandbox root (no symlink support here)"
fi
rm -rf "$root"; mkdir -p "$root"
nocalls "symlink and file roots"

# Bad names and usage never reach the broker.
for r in scratch owner/ /scratch 'a/b/c' 'owner/-x' 'owner/a b' 'owner/..' ''; do
  run good request "$r"
  expect "bad repo [$r]: refused" "" 2
done
nocalls "bad names"
run good request
expect "missing argument" "" 2
run good frob
expect "unknown command" "" 2
run good discard
expect "discard without a repo" "" 2

# -- never run from the cwd ---------------------------------------------------------------------
# A slash-less $0 could find a token-check.sh a branch under review planted in the cwd.
mkdir "$tmp/plant"
cp "$script" "$tmp/plant/review-token.sh"
printf '#!/bin/sh\ntouch "%s/marker"\nexit 0\n' "$tmp/plant" >"$tmp/plant/token-check.sh"
: >"$calls"
rm -rf "$root"; mkdir -p "$root"
rc=0
out="$(cd "$tmp/plant" && PATH="$bin:$PATH" WOW_HOME="$home" REVIEW_SANDBOX_ROOT="$root" STUB_MODE=good STUB_CALLS="$calls" sh review-token.sh request owner/scratch 2>/dev/null)" || rc=$?
assert_eq "slash-less request refuses (stdout)" "" "$out"
assert_eq "slash-less request refuses (rc)" 2 "$rc"
assert_eq "slash-less request never reached the planted token-check.sh" no "$([ -e "$tmp/plant/marker" ] && echo yes || echo no)"
nocalls "slash-less request"
rc=0
out="$(cd "$tmp/plant" && PATH="$bin:$PATH" WOW_HOME="$home" REVIEW_SANDBOX_ROOT="$root" STUB_MODE=good STUB_CALLS="$calls" sh review-token.sh discard owner/scratch 2>/dev/null)" || rc=$?
assert_eq "slash-less discard refuses (stdout)" "" "$out"
assert_eq "slash-less discard refuses (rc)" 2 "$rc"

exit "$fail"
