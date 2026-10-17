#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/plan-anchor.sh.
#
# `gh` is stubbed rather than mocked at the jq-filter level: the fake below is
# keyed only by the API PATH (which endpoint), and returns canned output
# selected by environment variable, set per fixture. It does not interpret the
# --jq expression plan-anchor.sh passes -- it trusts that expression to be
# whichever one the real script actually sends for that endpoint, which is
# pinned by construction (this file and the script under test are maintained
# together). That is a boundary mock, not a reimplementation of `gh` or `jq`.
#
# Every fixture's env-var assignments are prefixed directly onto the `run`
# call INSIDE the command substitution (`out="$(VAR=x run ...)"`), never onto
# the `out=` assignment itself -- `out=$(cmd)` expands the command
# substitution during word expansion, before any assignment on that same
# line takes effect, so `VAR=x out="$(run ...)"` would run `run` with $VAR
# still unset in the parent shell. Only a prefix on the command actually
# inside the substitution reaches the fake gh subprocess.
#
# Permitted toolset: POSIX sh. No jq, no yq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/plugins/way-of-working/bin/plan-anchor.sh"

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

# --- the fake gh --------------------------------------------------------
fakebin="$tmp/fakebin"
mkdir -p "$fakebin"
cat >"$fakebin/gh" <<'FAKE_GH'
#!/bin/sh
set -eu
[ "$1" = api ] || { echo "fake gh: unsupported command $1" >&2; exit 1; }
path="$2"
[ -z "${FAKE_GH_LOG:-}" ] || printf '%s %s\n' "$path" "$*" >>"$FAKE_GH_LOG"
case "$path" in
  repos/*/milestones/*)
    [ "${FAKE_MS_FAIL:-0}" = 1 ] && exit 1
    case "$*" in
      *'.number'*) printf '%s\n' "${FAKE_MS_NUMBER-${path##*/}}" ;;
      *'.creator'*)
        [ "${FAKE_AUTHOR_FAIL:-0}" = 1 ] && exit 1
        printf '%s\n' "${FAKE_MS_CREATOR-maintainer}" ;;
      *'.state'*) printf '%s\n' "${FAKE_MS_STATE:-open}" ;;
      *'.description'*) printf '%s' "${FAKE_MS_DESC-}" ;;
      *) echo "fake gh: unrecognised milestone jq: $*" >&2; exit 1 ;;
    esac
    ;;
  repos/*/issues/comments/*/reactions)
    [ "${FAKE_REACTIONS_FAIL:-0}" = 1 ] && exit 1
    printf '%b' "${FAKE_REACTIONS-}" ;;
  repos/*/issues/comments/*)
    [ "${FAKE_COMMENT_FAIL:-0}" = 1 ] && exit 1
    case "$*" in
      *'.user.login'*)
        [ "${FAKE_COMMENT_AUTHOR_FAIL:-0}" = 1 ] && exit 1
        printf '%s\n' "${FAKE_COMMENT_AUTHOR-maintainer}" ;;
      *'@tsv'*) printf '%s\t%s\t%s\n' "${FAKE_COMMENT_UPDATED:-2026-01-01T00:00:00Z}" "${FAKE_COMMENT_ISSUE_URL:-}" "${FAKE_COMMENT_AUTHOR_ID-1001}" ;;
      *) [ "${FAKE_COMMENT_RECHECK_FAIL:-0}" = 1 ] && exit 1
         printf '%s\n' "${FAKE_COMMENT_RECHECK_UPDATED:-${FAKE_COMMENT_UPDATED:-2026-01-01T00:00:00Z}}" ;;
    esac
    ;;
  repos/*/issues/*)
    [ "${FAKE_ISSUE_FAIL:-0}" = 1 ] && exit 1
    case "$*" in
      *'.user.login'*)
        [ "${FAKE_ISSUE_AUTHOR_FAIL:-0}" = 1 ] && exit 1
        printf '%s\n' "${FAKE_ISSUE_AUTHOR-maintainer}" ;;
      *'@tsv'*)
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
          "${FAKE_ISSUE_STATE:-open}" "${FAKE_ISSUE_UPDATED:-2026-01-01T00:00:00Z}" \
          "${FAKE_ISSUE_REPO_URL:-https://api.github.com/repos/o/r}" \
          "${FAKE_ISSUE_NUMBER:-86}" "${FAKE_ISSUE_MILESTONE:-12}" "${FAKE_ISSUE_PR:-0}"
        ;;
      *) printf '%s\n' "${FAKE_ISSUE_UPDATED:-2026-01-01T00:00:00Z}" ;;
    esac
    ;;
  *) echo "fake gh: unrecognised path $path" >&2; exit 1 ;;
esac
FAKE_GH
chmod +x "$fakebin/gh"

run() { # run <args...> -- invokes the script under test with the fake gh on PATH
  PATH="$fakebin:$PATH" "$script" "$@"
}

REPO="o/r"
POINTER="https://github.com/$REPO/milestone/12"

echo "# write"

# WB-D27 (#628, #637): write no longer reads the milestone description or emits
# description_sha256; it reads the milestone's number instead.
out="$(FAKE_MS_DESC="the plan" FAKE_ISSUE_UPDATED="2026-09-20T12:00:00Z" \
       FAKE_COMMENT_UPDATED="2026-09-21T09:00:00Z" \
       run write "$REPO" 12 86 335)"
assert_eq "write: full anchor is well-formed JSON with the right fields" \
  "{\"milestone\":12,\"task_issue\":86,\"task_issue_updated_at\":\"2026-09-20T12:00:00Z\",\"spec_comment\":{\"id\":335,\"updated_at\":\"2026-09-21T09:00:00Z\"}}" \
  "$out"

out="$(FAKE_MS_DESC="the plan" run write "$REPO" 12 - -)"
assert_eq "write: no task, no comment -- both fields null" \
  "{\"milestone\":12,\"task_issue\":null,\"task_issue_updated_at\":null,\"spec_comment\":null}" \
  "$out"

out="$(FAKE_ISSUE_UPDATED="2026-09-20T12:00:00Z" run write "$REPO" 12 86)"
assert_eq "write: comment argument may be omitted, defaults to none" \
  "{\"milestone\":12,\"task_issue\":86,\"task_issue_updated_at\":\"2026-09-20T12:00:00Z\",\"spec_comment\":null}" \
  "$out"

out="$(run write "$REPO" 12 - -)"
assert_eq "write: a milestone with no description writes the same shape" \
  "{\"milestone\":12,\"task_issue\":null,\"task_issue_updated_at\":null,\"spec_comment\":null}" \
  "$out"

case "$out" in
  *description_sha256*) assert_eq "write: output has no description_sha256 key" absent present ;;
  *) assert_eq "write: output has no description_sha256 key" absent absent ;;
esac

: >"$tmp/log"
out="$(FAKE_GH_LOG="$tmp/log" FAKE_ISSUE_UPDATED="2026-09-20T12:00:00Z" \
       FAKE_COMMENT_UPDATED="2026-09-21T09:00:00Z" run write "$REPO" 12 86 335)"
if grep -q 'description' "$tmp/log"; then seen=read; else seen=none; fi
assert_eq "write: the call log has no description read" none "$seen"
assert_eq "write: the milestone read asks for .number" \
  "repos/$REPO/milestones/12 api repos/$REPO/milestones/12 --jq .number" \
  "$(sed -n 1p "$tmp/log")"

out="$(run write "$REPO" abc 86)"
assert_eq "write: a non-digit milestone is unreadable" "unreadable" "$out"

out="$(FAKE_MS_FAIL=1 run write "$REPO" 12 86)"
assert_eq "write: a failed milestone read is unreadable" "unreadable" "$out"

out="$(FAKE_MS_NUMBER=13 run write "$REPO" 12 86)"
assert_eq "write: a milestone read returning another number is unreadable" "unreadable" "$out"

out="$(FAKE_MS_NUMBER= run write "$REPO" 12 86)"
assert_eq "write: a milestone read returning no number is unreadable" "unreadable" "$out"

: >"$tmp/log"
out="$(FAKE_GH_LOG="$tmp/log" run write "$REPO" 012 86)"
assert_eq "write: a leading-zero milestone is unreadable" "unreadable" "$out"
assert_eq "write: a leading-zero milestone makes no call" "0" "$(wc -l <"$tmp/log" | tr -d ' ')"

out="$(FAKE_ISSUE_FAIL=1 run write "$REPO" 12 86)"
assert_eq "write: a failed issue read is unreadable" "unreadable" "$out"

out="$(FAKE_ISSUE_UPDATED="2026-01-01T00:00:00Z" FAKE_COMMENT_FAIL=1 \
       run write "$REPO" 12 86 335)"
assert_eq "write: a failed comment read is unreadable" "unreadable" "$out"

out="$(run write "$REPO" 12)"
assert_eq "write: too few arguments is unreadable" "unreadable" "$out"

echo "# verify -- pointer shape"

anchor='{"milestone":12,"description_sha256":"x","task_issue":86,"task_issue_updated_at":"2026-01-01T00:00:00Z","spec_comment":null}'
out="$(run verify "$REPO" "https://github.com/other/repo/milestone/12" "$anchor")"
assert_eq "verify: a pointer naming a different repo is unreadable" "unreadable" "$out"

out="$(run verify "$REPO" "https://github.com/$REPO/milestone/abc" "$anchor")"
assert_eq "verify: a non-digit milestone number in the pointer is unreadable" "unreadable" "$out"

out="$(run verify "$REPO" "https://github.com/$REPO/milestone/12/extra" "$anchor")"
assert_eq "verify: trailing text after the number is unreadable" "unreadable" "$out"

echo "# verify (full) -- match and each drift dimension"

# NOTE: named plan_desc, not desc -- assert_eq's own parameter is a GLOBAL
# `desc` in POSIX sh (no `local`), and every assert_eq call below overwrites
# it. A test-data variable named `desc` would silently read back whatever the
# PREVIOUS assertion's description string was.
plan_desc="the live plan"
# An older anchor's description_sha256: verify ignores it, whatever the value (WB-D27).
# This one matches no description in this file.
hash="0000000000000000000000000000000000000000000000000000000000000000"
good_anchor="{\"milestone\":12,\"description_sha256\":\"$hash\",\"task_issue\":86,\"task_issue_updated_at\":\"2026-09-20T12:00:00Z\",\"spec_comment\":null}"

out="$(FAKE_MS_STATE=open FAKE_MS_DESC="$plan_desc" \
       FAKE_ISSUE_STATE=open FAKE_ISSUE_UPDATED="2026-09-20T12:00:00Z" \
       FAKE_ISSUE_REPO_URL="https://api.github.com/repos/$REPO" FAKE_ISSUE_NUMBER=86 \
       FAKE_ISSUE_MILESTONE=12 FAKE_ISSUE_PR=0 \
       run verify "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify: everything live matches the anchor" "match" "$out"

out="$(FAKE_MS_STATE=closed FAKE_MS_DESC="$plan_desc" \
       run verify "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify: a closed milestone is drift" "drift" "$out"

# WB-D27: this used to assert drift on a changed description. The description is no
# longer bound, so an old anchor's stale hash is ignored.
out="$(FAKE_MS_STATE=open FAKE_MS_DESC="a different plan now" \
       FAKE_ISSUE_STATE=open FAKE_ISSUE_UPDATED="2026-09-20T12:00:00Z" \
       FAKE_ISSUE_REPO_URL="https://api.github.com/repos/$REPO" FAKE_ISSUE_NUMBER=86 FAKE_ISSUE_MILESTONE=12 \
       run verify "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify: an old anchor's hash that matches no description is ignored (WB-D27)" "match" "$out"

out="$(FAKE_MS_STATE=open FAKE_MS_DESC="$plan_desc" \
       FAKE_ISSUE_STATE=closed FAKE_ISSUE_UPDATED="2026-09-20T12:00:00Z" \
       FAKE_ISSUE_REPO_URL="https://api.github.com/repos/$REPO" FAKE_ISSUE_NUMBER=86 FAKE_ISSUE_MILESTONE=12 \
       run verify "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify: a closed task issue is drift" "drift" "$out"

out="$(FAKE_MS_STATE=open FAKE_MS_DESC="$plan_desc" \
       FAKE_ISSUE_STATE=open FAKE_ISSUE_UPDATED="2026-09-20T12:00:00Z" \
       FAKE_ISSUE_REPO_URL="https://api.github.com/repos/$REPO" FAKE_ISSUE_NUMBER=86 FAKE_ISSUE_MILESTONE=12 \
       FAKE_ISSUE_PR=1 \
       run verify "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify: #N being a pull request, not a true issue, is drift" "drift" "$out"

out="$(FAKE_MS_STATE=open FAKE_MS_DESC="$plan_desc" \
       FAKE_ISSUE_STATE=open FAKE_ISSUE_UPDATED="2026-09-20T12:00:00Z" \
       FAKE_ISSUE_REPO_URL="https://api.github.com/repos/other/repo" FAKE_ISSUE_NUMBER=86 FAKE_ISSUE_MILESTONE=12 \
       run verify "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify: #N living in a different repo is drift" "drift" "$out"

out="$(FAKE_MS_STATE=open FAKE_MS_DESC="$plan_desc" \
       FAKE_ISSUE_STATE=open FAKE_ISSUE_UPDATED="2026-09-20T12:00:00Z" \
       FAKE_ISSUE_REPO_URL="https://api.github.com/repos/$REPO" FAKE_ISSUE_NUMBER=86 FAKE_ISSUE_MILESTONE=99 \
       run verify "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify: #N moved to a different milestone is drift" "drift" "$out"

out="$(FAKE_MS_STATE=open FAKE_MS_DESC="$plan_desc" \
       FAKE_ISSUE_STATE=open FAKE_ISSUE_UPDATED="2026-09-22T00:00:00Z" \
       FAKE_ISSUE_REPO_URL="https://api.github.com/repos/$REPO" FAKE_ISSUE_NUMBER=86 FAKE_ISSUE_MILESTONE=12 \
       run verify "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify: #N edited since the anchor (updated_at moved) is drift" "drift" "$out"

null_task_anchor="{\"milestone\":12,\"description_sha256\":\"$hash\",\"task_issue\":null,\"task_issue_updated_at\":null,\"spec_comment\":null}"
out="$(FAKE_MS_STATE=open FAKE_MS_DESC="$plan_desc" \
       run verify "$REPO" "$POINTER" "$null_task_anchor")"
assert_eq "verify (full): a planning cursor's null task_issue never matches" "drift" "$out"

echo "# verify (full) -- spec comment"

comment_anchor="{\"milestone\":12,\"description_sha256\":\"$hash\",\"task_issue\":86,\"task_issue_updated_at\":\"2026-09-20T12:00:00Z\",\"spec_comment\":{\"id\":335,\"updated_at\":\"2026-09-21T09:00:00Z\"}}"

out="$(FAKE_MS_STATE=open FAKE_MS_DESC="$plan_desc" \
       FAKE_ISSUE_STATE=open FAKE_ISSUE_UPDATED="2026-09-20T12:00:00Z" \
       FAKE_ISSUE_REPO_URL="https://api.github.com/repos/$REPO" FAKE_ISSUE_NUMBER=86 FAKE_ISSUE_MILESTONE=12 \
       FAKE_COMMENT_UPDATED="2026-09-21T09:00:00Z" FAKE_COMMENT_ISSUE_URL="https://api.github.com/repos/$REPO/issues/86" \
       run verify "$REPO" "$POINTER" "$comment_anchor")"
assert_eq "verify: an anchored, unedited spec comment matches" "match" "$out"

out="$(FAKE_MS_STATE=open FAKE_MS_DESC="$plan_desc" \
       FAKE_ISSUE_STATE=open FAKE_ISSUE_UPDATED="2026-09-20T12:00:00Z" \
       FAKE_ISSUE_REPO_URL="https://api.github.com/repos/$REPO" FAKE_ISSUE_NUMBER=86 FAKE_ISSUE_MILESTONE=12 \
       FAKE_COMMENT_UPDATED="2026-09-22T00:00:00Z" FAKE_COMMENT_ISSUE_URL="https://api.github.com/repos/$REPO/issues/86" \
       run verify "$REPO" "$POINTER" "$comment_anchor")"
assert_eq "verify: a spec comment edited since the anchor is drift" "drift" "$out"

out="$(FAKE_MS_STATE=open FAKE_MS_DESC="$plan_desc" \
       FAKE_ISSUE_STATE=open FAKE_ISSUE_UPDATED="2026-09-20T12:00:00Z" \
       FAKE_ISSUE_REPO_URL="https://api.github.com/repos/$REPO" FAKE_ISSUE_NUMBER=86 FAKE_ISSUE_MILESTONE=12 \
       FAKE_COMMENT_UPDATED="2026-09-21T09:00:00Z" FAKE_COMMENT_ISSUE_URL="https://api.github.com/repos/$REPO/issues/99" \
       run verify "$REPO" "$POINTER" "$comment_anchor")"
assert_eq "verify: a spec comment that moved to a different issue is drift" "drift" "$out"

echo "# verify (full) -- a malformed spec_comment must never read as null (regression)"

# A critic round caught this: anchor_obj used to return "" for a value that
# didn't parse, and the caller treated "" the same as a legitimate `null` --
# skipping the comment check entirely and answering `match` on an anchor it
# could not actually read. Each row here is a shape that must now answer
# unreadable, not match.

# Both trailing braces are dropped -- the object's own closer AND the
# anchor's -- so `{[^{}]*}` genuinely has no closing brace left to find,
# rather than accidentally closing on an intact inner object (the mistake an
# earlier draft of this fixture made: dropping only the outer brace still
# leaves `{"id":335,...}` well-formed, and the test then exercised the
# unrelated "comment content mismatched" path instead of "couldn't parse").
truncated_comment_anchor="{\"milestone\":12,\"description_sha256\":\"$hash\",\"task_issue\":86,\"task_issue_updated_at\":\"2026-09-20T12:00:00Z\",\"spec_comment\":{\"id\":335,\"updated_at\":\"2026-09-21T09:00:00Z\""
out="$(FAKE_MS_STATE=open FAKE_MS_DESC="$plan_desc" \
       FAKE_ISSUE_STATE=open FAKE_ISSUE_UPDATED="2026-09-20T12:00:00Z" \
       FAKE_ISSUE_REPO_URL="https://api.github.com/repos/$REPO" FAKE_ISSUE_NUMBER=86 FAKE_ISSUE_MILESTONE=12 \
       run verify "$REPO" "$POINTER" "$truncated_comment_anchor")"
assert_eq "verify: a truncated spec_comment object (missing closing brace) is unreadable, never match" \
  "unreadable" "$out"

no_comment_key_anchor="{\"milestone\":12,\"description_sha256\":\"$hash\",\"task_issue\":86,\"task_issue_updated_at\":\"2026-09-20T12:00:00Z\"}"
out="$(FAKE_MS_STATE=open FAKE_MS_DESC="$plan_desc" \
       FAKE_ISSUE_STATE=open FAKE_ISSUE_UPDATED="2026-09-20T12:00:00Z" \
       FAKE_ISSUE_REPO_URL="https://api.github.com/repos/$REPO" FAKE_ISSUE_NUMBER=86 FAKE_ISSUE_MILESTONE=12 \
       run verify "$REPO" "$POINTER" "$no_comment_key_anchor")"
assert_eq "verify: an anchor with no spec_comment key at all is unreadable, never match" \
  "unreadable" "$out"

echo "# verify (full) -- a malformed task_issue must never read as null (regression)"

no_task_key_anchor="{\"milestone\":12,\"description_sha256\":\"$hash\",\"spec_comment\":null}"
out="$(FAKE_MS_STATE=open FAKE_MS_DESC="$plan_desc" \
       run verify "$REPO" "$POINTER" "$no_task_key_anchor")"
assert_eq "verify: an anchor with no task_issue key at all is unreadable, never drift" \
  "unreadable" "$out"

echo "# verify -- the anchor's own milestone number vs. the pointer's"

wrong_milestone_anchor="{\"milestone\":5,\"description_sha256\":\"$hash\",\"task_issue\":86,\"task_issue_updated_at\":\"2026-09-20T12:00:00Z\",\"spec_comment\":null}"
out="$(run verify "$REPO" "$POINTER" "$wrong_milestone_anchor")"
assert_eq "verify: the anchor names a different milestone than the pointer is drift" "drift" "$out"

echo "# verify --plan"

out="$(FAKE_MS_STATE=open FAKE_MS_DESC="$plan_desc" \
       run verify --plan "$REPO" "$POINTER" "$null_task_anchor")"
assert_eq "verify --plan: a null task_issue is fine -- plan mode never looks at it" "match" "$out"

out="$(FAKE_MS_STATE=open FAKE_MS_DESC="$plan_desc" \
       run verify --plan "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify --plan: ignores the task issue even when the anchor carries one" "match" "$out"

out="$(FAKE_MS_STATE=closed FAKE_MS_DESC="$plan_desc" \
       run verify --plan "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify --plan: still checks the milestone is open" "drift" "$out"

echo "# verify -- unreadable on a failed live read"

out="$(FAKE_MS_FAIL=1 run verify "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify: a failed milestone-state read is unreadable" "unreadable" "$out"

out="$(FAKE_MS_STATE=open FAKE_MS_DESC="$plan_desc" FAKE_ISSUE_FAIL=1 \
       run verify "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify: a failed issue read is unreadable" "unreadable" "$out"

out="$(FAKE_MS_STATE=open FAKE_MS_DESC="$plan_desc" \
       FAKE_ISSUE_STATE=open FAKE_ISSUE_UPDATED="2026-09-20T12:00:00Z" \
       FAKE_ISSUE_REPO_URL="https://api.github.com/repos/$REPO" FAKE_ISSUE_NUMBER=86 FAKE_ISSUE_MILESTONE=12 \
       FAKE_COMMENT_FAIL=1 \
       run verify "$REPO" "$POINTER" "$comment_anchor")"
assert_eq "verify: a failed spec-comment read is unreadable" "unreadable" "$out"

echo "# verify -- a malformed anchor is unreadable, never a false match"

out="$(run verify "$REPO" "$POINTER" '{"description_sha256":"x"}')"
assert_eq "verify: an anchor missing 'milestone' is unreadable" "unreadable" "$out"

out="$(run verify "$REPO" "$POINTER" 'not json at all')"
assert_eq "verify: an anchor that is not JSON is unreadable" "unreadable" "$out"

echo "# a pretty-printed anchor (one space after each colon) parses the same as compact"

pretty_anchor='{"milestone": 12, "description_sha256": "'"$hash"'", "task_issue": 86, "task_issue_updated_at": "2026-09-20T12:00:00Z", "spec_comment": {"id": 335, "updated_at": "2026-09-21T09:00:00Z"}}'
out="$(FAKE_MS_STATE=open FAKE_MS_DESC="$plan_desc" \
       FAKE_ISSUE_STATE=open FAKE_ISSUE_UPDATED="2026-09-20T12:00:00Z" \
       FAKE_ISSUE_REPO_URL="https://api.github.com/repos/$REPO" FAKE_ISSUE_NUMBER=86 FAKE_ISSUE_MILESTONE=12 \
       FAKE_COMMENT_UPDATED="2026-09-21T09:00:00Z" FAKE_COMMENT_ISSUE_URL="https://api.github.com/repos/$REPO/issues/86" \
       run verify "$REPO" "$POINTER" "$pretty_anchor")"
assert_eq "verify: a pretty-printed anchor (space after each colon) still matches" "match" "$out"

echo "# the name rule: --loop-identity (#235) -- untrusted BY NAME, before any drift comparison"

spec_anchor="{\"milestone\":12,\"description_sha256\":\"$hash\",\"task_issue\":86,\"task_issue_updated_at\":\"2026-09-20T12:00:00Z\",\"spec_comment\":{\"id\":335,\"updated_at\":\"2026-09-21T09:00:00Z\"}}"

# lrun -- `run` with every artifact live and matching; a fixture prefixes the one
# variable it varies (FAKE_ISSUE_AUTHOR=x lrun verify ...), which reaches the fake gh
# the same way it does for `run` itself.
lrun() {
  FAKE_MS_STATE="${FAKE_MS_STATE:-open}" FAKE_MS_DESC="${FAKE_MS_DESC-$plan_desc}" FAKE_ISSUE_STATE="${FAKE_ISSUE_STATE:-open}"   FAKE_ISSUE_UPDATED="${FAKE_ISSUE_UPDATED:-2026-09-20T12:00:00Z}" FAKE_ISSUE_REPO_URL="https://api.github.com/repos/$REPO"   FAKE_ISSUE_NUMBER=86 FAKE_ISSUE_MILESTONE="${FAKE_ISSUE_MILESTONE:-12}"   FAKE_COMMENT_UPDATED="${FAKE_COMMENT_UPDATED:-2026-09-21T09:00:00Z}" FAKE_COMMENT_ISSUE_URL="${FAKE_COMMENT_ISSUE_URL:-https://api.github.com/repos/$REPO/issues/86}"   run "$@"
}
out="$(lrun verify --loop-identity loop-app[bot] "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify --loop-identity: a different author on every artifact still matches" "match" "$out"

out="$(FAKE_ISSUE_AUTHOR='loop-app[bot]' lrun verify --loop-identity 'loop-app[bot]' "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify --loop-identity: a task issue authored by the loop identity is untrusted" "untrusted" "$out"

out="$(FAKE_ISSUE_AUTHOR='LOOP-App[BOT]' lrun verify --loop-identity 'loop-app[bot]' "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify --loop-identity: the comparison is case-insensitive" "untrusted" "$out"

out="$(FAKE_MS_CREATOR='loop-app[bot]' lrun verify --loop-identity 'loop-app[bot]' "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify --loop-identity: a milestone created by the loop identity is untrusted" "untrusted" "$out"

out="$(FAKE_COMMENT_AUTHOR='loop-app[bot]' lrun verify --loop-identity 'loop-app[bot]' "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --loop-identity: a spec comment authored by the loop identity is untrusted" "untrusted" "$out"

out="$(lrun verify --loop-identity 'loop-app[bot]' "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --loop-identity: a different spec-comment author still matches" "match" "$out"

# The name rule comes BEFORE every drift comparison: a loop-authored task whose
# artifacts have ALSO drifted reads untrusted, never drift or unreadable.
out="$(FAKE_MS_STATE=closed FAKE_MS_DESC='edited since' FAKE_ISSUE_AUTHOR='loop-app[bot]' \
       run verify --loop-identity 'loop-app[bot]' "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify --loop-identity: untrusted wins over a closed milestone" "untrusted" "$out"

# The failing-open case: a STALE loop_identity (the loop is now a machine user whose
# association would pass any association check). The name rule fires on the login alone.
out="$(FAKE_ISSUE_AUTHOR='old-machine-user' lrun verify --loop-identity 'old-machine-user' "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify --loop-identity: a plain machine-user login is untrusted by name too" "untrusted" "$out"

out="$(FAKE_ISSUE_AUTHOR='old-machine-user2' lrun verify --loop-identity 'old-machine-user' "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify --loop-identity: a login that merely starts with the identity is not it" "match" "$out"

out="$(FAKE_ISSUE_AUTHOR='loop-app[bot]' lrun verify --plan --loop-identity 'loop-app[bot]' "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify --plan --loop-identity: --plan ignores the task issue's author" "match" "$out"

out="$(FAKE_MS_CREATOR='loop-app[bot]' lrun verify --plan --loop-identity 'loop-app[bot]' "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify --plan --loop-identity: --plan still refuses a loop-created milestone" "untrusted" "$out"

out="$(FAKE_ISSUE_AUTHOR='loop-app[bot]' lrun verify "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify: without the flag no author is read, and the verdict is unchanged" "match" "$out"

out="$(FAKE_AUTHOR_FAIL=1 lrun verify --loop-identity 'loop-app[bot]' "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify --loop-identity: a failed author read is unreadable, never a pass" "unreadable" "$out"

out="$(FAKE_MS_CREATOR= lrun verify --loop-identity 'loop-app[bot]' "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify --loop-identity: an empty author is unreadable, never a pass" "unreadable" "$out"

out="$(FAKE_ISSUE_AUTHOR_FAIL=1 lrun verify --loop-identity 'loop-app[bot]' "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify --loop-identity: a failed task-issue author read is unreadable" "unreadable" "$out"

out="$(FAKE_ISSUE_AUTHOR= lrun verify --loop-identity 'loop-app[bot]' "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify --loop-identity: an empty task-issue author is unreadable" "unreadable" "$out"

out="$(FAKE_COMMENT_AUTHOR_FAIL=1 lrun verify --loop-identity 'loop-app[bot]' "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --loop-identity: a failed spec-comment author read is unreadable" "unreadable" "$out"

out="$(FAKE_COMMENT_AUTHOR= lrun verify --loop-identity 'loop-app[bot]' "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --loop-identity: an empty spec-comment author is unreadable" "unreadable" "$out"

out="$(FAKE_ISSUE_AUTHOR='loop-app' lrun verify --loop-identity 'loop-app[bot]' "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify --loop-identity: the bare slug author is the App's name too" "untrusted" "$out"

out="$(FAKE_ISSUE_AUTHOR='loop-app[bot]' lrun verify --loop-identity 'loop-app' "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify --loop-identity: a bare-slug loop_identity still matches the App's login" "untrusted" "$out"

long40="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
long39="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
out="$(lrun verify --loop-identity "$long40" "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify --loop-identity: a 40-character stem is unreadable (cap is 39)" "unreadable" "$out"
out="$(lrun verify --loop-identity "$long39" "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify --loop-identity: a 39-character stem is accepted" "match" "$out"

for bad in '' '-x' 'x-' 'a b' 'a/b' 'a;b' '[bot]'; do
  out="$(lrun verify --loop-identity "$bad" "$REPO" "$POINTER" "$good_anchor")"
  assert_eq "verify --loop-identity: a malformed login [$bad] is unreadable" "unreadable" "$out"
done

out="$(lrun verify --loop-identity)"
assert_eq "verify --loop-identity: the flag with no value is unreadable" "unreadable" "$out"

echo "# the new anchor shape (no description_sha256) -- WB-D27"

# The removed fixtures hashed a multi-line and an empty description on both sides, and
# asserted that an empty description matches an empty-hash anchor. write and verify no
# longer read a description at all (WB-D27).
new_anchor='{"milestone":12,"task_issue":86,"task_issue_updated_at":"2026-09-20T12:00:00Z","spec_comment":null}'
new_null_anchor='{"milestone":12,"task_issue":null,"task_issue_updated_at":null,"spec_comment":null}'
new_spec_anchor='{"milestone":12,"task_issue":86,"task_issue_updated_at":"2026-09-20T12:00:00Z","spec_comment":{"id":335,"updated_at":"2026-09-21T09:00:00Z"}}'
bad_hash_anchor='{"milestone":12,"description_sha256":"not-a-hash","task_issue":86,"task_issue_updated_at":"2026-09-20T12:00:00Z","spec_comment":null}'

out="$(lrun verify "$REPO" "$POINTER" "$new_anchor")"
assert_eq "verify: a new-shape anchor matches when everything is live" "match" "$out"

out="$(lrun verify "$REPO" "$POINTER" "$bad_hash_anchor")"
assert_eq "verify: a malformed description_sha256 value is ignored" "match" "$out"

out="$(FAKE_MS_DESC="entirely different" lrun verify "$REPO" "$POINTER" "$new_anchor")"
assert_eq "verify: a changed description alone never turns a full-mode match into drift" "match" "$out"

out="$(FAKE_MS_DESC="entirely different" lrun verify --plan "$REPO" "$POINTER" "$new_anchor")"
assert_eq "verify --plan: a changed description is not drift" "match" "$out"

out="$(FAKE_MS_STATE=open run verify --plan "$REPO" "$POINTER" "$new_null_anchor")"
assert_eq "verify --plan: a new-shape anchor with no task matches on an open milestone" "match" "$out"

out="$(FAKE_MS_STATE=closed run verify --plan "$REPO" "$POINTER" "$new_null_anchor")"
assert_eq "verify --plan: a new-shape anchor on a closed milestone is drift" "drift" "$out"

out="$(FAKE_MS_STATE=closed lrun verify "$REPO" "$POINTER" "$new_anchor")"
assert_eq "verify: a new-shape anchor on a closed milestone is drift" "drift" "$out"

out="$(lrun verify --plan "$REPO" "$POINTER" '{"milestone":5,"task_issue":null,"task_issue_updated_at":null,"spec_comment":null}')"
assert_eq "verify --plan: an anchor whose milestone differs from the pointer's is drift" "drift" "$out"

out="$(FAKE_MS_CREATOR='loop-app[bot]' lrun verify --plan --loop-identity 'loop-app[bot]' "$REPO" "$POINTER" "$new_null_anchor")"
assert_eq "verify --plan --loop-identity: a new-shape anchor on a loop-created milestone is untrusted" "untrusted" "$out"

out="$(FAKE_MS_FAIL=1 run verify --plan "$REPO" "$POINTER" "$new_null_anchor")"
assert_eq "verify --plan: a failed state read on a new-shape anchor is unreadable" "unreadable" "$out"

out="$(FAKE_ISSUE_UPDATED="2026-09-22T00:00:00Z" lrun verify "$REPO" "$POINTER" "$new_anchor")"
assert_eq "verify: a new-shape anchor still drifts when the task issue moved" "drift" "$out"

out="$(lrun verify "$REPO" "$POINTER" "$new_spec_anchor")"
assert_eq "verify: a new-shape anchor with a spec comment matches" "match" "$out"

out="$(FAKE_COMMENT_UPDATED="2026-09-22T00:00:00Z" lrun verify "$REPO" "$POINTER" "$new_spec_anchor")"
assert_eq "verify: a new-shape anchor's edited spec comment is drift" "drift" "$out"

out="$(FAKE_REACTIONS="$(printf '1001\t+1\t2026-09-21T09:00:01Z')\n" lrun verify --maintainer-ids "1001,1002" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$new_spec_anchor")"
assert_eq "verify --maintainer-ids: a new-shape anchor with a fresh maintainer reaction matches" "match" "$out"

out="$(FAKE_COMMENT_AUTHOR_ID=7777 FAKE_REACTIONS= lrun verify --maintainer-ids "1001,1002" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$new_spec_anchor")"
assert_eq "verify --maintainer-ids: a new-shape anchor's outsider comment is untrusted" "untrusted" "$out"

out="$(FAKE_ISSUE_AUTHOR='loop-app[bot]' lrun verify --loop-identity 'loop-app[bot]' "$REPO" "$POINTER" "$new_anchor")"
assert_eq "verify --loop-identity: a new-shape anchor's loop-authored task issue is untrusted" "untrusted" "$out"

echo "# no verify ever reads the description"

: >"$tmp/log"
for a in "$good_anchor" "$new_anchor" "$new_spec_anchor" "$bad_hash_anchor"; do
  FAKE_GH_LOG="$tmp/log" lrun verify "$REPO" "$POINTER" "$a" >/dev/null
  FAKE_GH_LOG="$tmp/log" lrun verify --plan "$REPO" "$POINTER" "$a" >/dev/null
  FAKE_GH_LOG="$tmp/log" lrun verify --loop-identity 'loop-app[bot]' "$REPO" "$POINTER" "$a" >/dev/null
done
if grep -q 'description' "$tmp/log"; then seen=read; else seen=none; fi
assert_eq "verify: across every shape and mode, no call names the description" none "$seen"
assert_eq "verify: the call log is not empty (the check is live)" yes \
  "$([ -s "$tmp/log" ] && echo yes || echo no)"

echo "# the reaction rule: --maintainer-ids (#383) -- a comment alone never approves a spec"

# tab-separated user id, content, created_at -- one record per line, as the real --jq prints
rx() { printf '%s\t%s\t%s\n' "$1" "$2" "$3"; }
M="1001,1002"

out="$(FAKE_REACTIONS= lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --maintainer-ids: no reaction waits" "unreacted" "$out"

out="$(FAKE_REACTIONS="$(rx 1001 +1 2026-09-21T08:59:59Z)\n" lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --maintainer-ids: a reaction before the spec's last edit is stale and waits" "unreacted" "$out"

out="$(FAKE_REACTIONS="$(rx 1001 +1 2026-09-21T09:00:00Z)\n" lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --maintainer-ids: a reaction in the same second as the edit waits" "unreacted" "$out"

out="$(FAKE_REACTIONS="$(rx 1001 +1 2026-09-21T09:00:01Z)\n" lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --maintainer-ids: a fresh maintainer reaction starts" "match" "$out"

out="$(FAKE_REACTIONS="$(rx 1002 heart 2026-10-01T00:00:00Z)\n" lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --maintainer-ids: any listed maintainer's fresh heart starts" "match" "$out"

out="$(FAKE_REACTIONS="$(rx 1001 +1 2026-09-20T00:00:00Z)\n$(rx 1001 +1 2026-09-22T00:00:00Z)\n" lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --maintainer-ids: a stale reaction beside a fresh one still starts" "match" "$out"

out="$(FAKE_REACTIONS="$(rx 7777 +1 2026-10-01T00:00:00Z)\n" lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --maintainer-ids: a fresh reaction by a non-maintainer waits" "unreacted" "$out"

out="$(FAKE_REACTIONS="$(rx 10010 +1 2026-10-01T00:00:00Z)\n" lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --maintainer-ids: an id that merely contains a maintainer id waits" "unreacted" "$out"

for c in -1 confused eyes laugh; do
  out="$(FAKE_REACTIONS="$(rx 1001 "$c" 2026-10-01T00:00:00Z)\n" lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$spec_anchor")"
  assert_eq "verify --maintainer-ids: a fresh maintainer [$c] is not approval" "unreacted" "$out"
done

out="$(FAKE_REACTIONS="$(rx 1001 +1 tomorrow)\n" lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --maintainer-ids: a malformed reaction timestamp never counts" "unreacted" "$out"

out="$(FAKE_REACTIONS_FAIL=1 lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --maintainer-ids: a failed reactions read is unreadable, never a pass" "unreadable" "$out"

out="$(FAKE_REACTIONS="$(rx 1001 +1 2026-09-21T09:00:01Z)\n" FAKE_COMMENT_RECHECK_UPDATED=2026-09-21T09:00:00Z lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --maintainer-ids: a fresh reaction and an unchanged re-check match" "match" "$out"

out="$(FAKE_REACTIONS="$(rx 1001 +1 2026-09-21T09:00:01Z)\n" FAKE_COMMENT_RECHECK_UPDATED=2026-09-21T09:00:02Z lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --maintainer-ids: a comment edited after the reactions read is drift, never a pass" "drift" "$out"

out="$(FAKE_REACTIONS="$(rx 1001 +1 2026-09-21T09:00:01Z)\n" FAKE_COMMENT_RECHECK_FAIL=1 lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --maintainer-ids: a failed re-check read is unreadable, never a pass" "unreadable" "$out"

out="$(FAKE_REACTIONS= lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$good_anchor")"
assert_eq "verify --maintainer-ids: a null-spec anchor with the flag waits when no reaction is fresh" "unreacted" "$out"

out="$(FAKE_COMMENT_AUTHOR_ID=7777 FAKE_REACTIONS="$(rx 1001 +1 2026-10-01T00:00:00Z)\n" lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --maintainer-ids: an outsider's comment a maintainer reacted to is untrusted" "untrusted" "$out"

out="$(FAKE_COMMENT_AUTHOR_ID=10010 FAKE_REACTIONS="$(rx 1001 +1 2026-10-01T00:00:00Z)\n" lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --maintainer-ids: an author id that merely contains a maintainer id is untrusted" "untrusted" "$out"

out="$(FAKE_COMMENT_AUTHOR_ID=1002 FAKE_REACTIONS="$(rx 1001 +1 2026-10-01T00:00:00Z)\n" lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --maintainer-ids: any listed maintainer may author the comment" "match" "$out"

out="$(FAKE_COMMENT_AUTHOR_ID= FAKE_REACTIONS="$(rx 1001 +1 2026-10-01T00:00:00Z)\n" lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --maintainer-ids: a comment with no author id is untrusted" "untrusted" "$out"

out="$(FAKE_COMMENT_AUTHOR_ID=7777 FAKE_REACTIONS= lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --maintainer-ids: an outsider's comment is untrusted even with no reaction (author rule runs first)" "untrusted" "$out"

out="$(FAKE_COMMENT_AUTHOR_ID=7777 FAKE_REACTIONS= FAKE_MS_STATE=open FAKE_MS_DESC="$plan_desc" FAKE_ISSUE_STATE=open FAKE_ISSUE_UPDATED="2026-09-20T12:00:00Z" \
       FAKE_ISSUE_REPO_URL="https://api.github.com/repos/$REPO" FAKE_ISSUE_NUMBER=86 FAKE_ISSUE_MILESTONE=12 \
       FAKE_COMMENT_UPDATED="2026-09-22T00:00:00Z" FAKE_COMMENT_ISSUE_URL="https://api.github.com/repos/$REPO/issues/86" \
       run verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --maintainer-ids: an outsider's drifted comment is drift (the drift checks run before the author rule)" "drift" "$out"

out="$(FAKE_COMMENT_AUTHOR_ID=7777 FAKE_REACTIONS= lrun verify "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify without --maintainer-ids reads no comment author (an outsider's comment still matches)" "match" "$out"

out="$(FAKE_COMMENT_AUTHOR_ID=7777 FAKE_REACTIONS= lrun verify --plan --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --plan ignores the comment author under --maintainer-ids" "match" "$out"

out="$(FAKE_REACTIONS= lrun verify --plan --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --plan ignores --maintainer-ids" "match" "$out"

out="$(FAKE_REACTIONS= FAKE_MS_STATE=open FAKE_MS_DESC="$plan_desc" FAKE_ISSUE_STATE=open FAKE_ISSUE_UPDATED="2026-09-20T12:00:00Z" \
       FAKE_ISSUE_REPO_URL="https://api.github.com/repos/$REPO" FAKE_ISSUE_NUMBER=86 FAKE_ISSUE_MILESTONE=12 \
       FAKE_COMMENT_UPDATED="2026-09-22T00:00:00Z" FAKE_COMMENT_ISSUE_URL="https://api.github.com/repos/$REPO/issues/86" \
       run verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --maintainer-ids: a drifted spec comment is drift, ahead of the reaction rule" "drift" "$out"

out="$(FAKE_REACTIONS="$(rx 1001 +1 2026-10-01T00:00:00Z)\n" lrun verify "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify without --maintainer-ids keeps today's behavior (no reaction read)" "match" "$out"

for bad in '' 'abc' '*' '[0-9]*' '1001,' ',1001' '1001,,1002' '0' '01001' '1001 1002' '-1'; do
  out="$(lrun verify --maintainer-ids "$bad" "$REPO" "$POINTER" "$spec_anchor")"
  assert_eq "verify --maintainer-ids: a malformed list [$bad] is unreadable" "unreadable" "$out"
done

out="$(lrun verify --maintainer-ids)"
assert_eq "verify --maintainer-ids: the flag with no value is unreadable" "unreadable" "$out"

out="$(FAKE_REACTIONS="$(rx 1001 +1 2026-10-01T00:00:00Z)\n" FAKE_COMMENT_AUTHOR='loop-app[bot]' lrun verify --loop-identity 'loop-app[bot]' --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify: --loop-identity still wins over a fresh reaction" "untrusted" "$out"

echo "# the dev App as spec author: --dev-app-id (#660) -- it may write the spec, never approve it"

D=2001
FRESH="$(rx 1001 +1 2026-10-01T00:00:00Z)\n"

out="$(FAKE_COMMENT_AUTHOR_ID=$D FAKE_REACTIONS="$FRESH" lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z --dev-app-id "$D" "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --dev-app-id: a dev-App comment with a fresh maintainer reaction matches" "match" "$out"

out="$(FAKE_COMMENT_AUTHOR_ID=$D FAKE_REACTIONS= lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z --dev-app-id "$D" "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --dev-app-id: a dev-App comment with no reaction is unreacted" "unreacted" "$out"

out="$(FAKE_COMMENT_AUTHOR_ID=$D FAKE_REACTIONS="$(rx $D +1 2026-10-01T00:00:00Z)\n" lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z --dev-app-id "$D" "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --dev-app-id: only the dev App's own reaction is unreacted" "unreacted" "$out"

out="$(FAKE_COMMENT_AUTHOR_ID=$D FAKE_REACTIONS="$(rx 1001 +1 2026-09-21T08:59:59Z)\n" lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z --dev-app-id "$D" "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --dev-app-id: a reaction older than the comment's last edit is unreacted" "unreacted" "$out"

out="$(FAKE_COMMENT_AUTHOR_ID=$D FAKE_REACTIONS="$FRESH" lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify: a dev-App comment without --dev-app-id is untrusted, as before" "untrusted" "$out"

out="$(FAKE_COMMENT_AUTHOR_ID=$D FAKE_REACTIONS="$FRESH" lrun verify --dev-app-id "$D" --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --dev-app-id: given before --maintainer-ids it behaves the same" "match" "$out"

out="$(FAKE_COMMENT_AUTHOR_ID=1001 FAKE_REACTIONS="$FRESH" lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z --dev-app-id "$D" "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --dev-app-id: a maintainer's comment still matches" "match" "$out"

out="$(FAKE_COMMENT_AUTHOR_ID=7777 FAKE_REACTIONS="$FRESH" lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z --dev-app-id "$D" "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --dev-app-id: an outsider's comment is untrusted" "untrusted" "$out"

out="$(FAKE_COMMENT_AUTHOR_ID=20010 FAKE_REACTIONS="$FRESH" lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z --dev-app-id "$D" "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --dev-app-id: an author id that merely contains the dev-App id is untrusted" "untrusted" "$out"

out="$(FAKE_COMMENT_AUTHOR_ID=1 FAKE_REACTIONS="$FRESH" lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z --dev-app-id 20010 "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --dev-app-id: an author id contained in the dev-App id is untrusted" "untrusted" "$out"

out="$(lrun verify --dev-app-id "$D" "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --dev-app-id without --maintainer-ids is unreadable" "unreadable" "$out"

out="$(lrun verify --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z --dev-app-id)"
assert_eq "verify --dev-app-id with no value is unreadable" "unreadable" "$out"

for bad in '' '0' '-1' '012' '12a' '1001' '1002' '2001,2002' ' 2001'; do
  out="$(lrun verify --maintainer-ids "$M" --dev-app-id "$bad" "$REPO" "$POINTER" "$spec_anchor")"
  assert_eq "verify --dev-app-id: [$bad] is unreadable" "unreadable" "$out"
done

out="$(lrun verify --plan --maintainer-ids "$M" --dev-app-id "$D" "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --plan with --dev-app-id is match" "match" "$out"

out="$(lrun verify --plan --maintainer-ids "$M" --dev-app-id 012 "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --plan validates --dev-app-id too" "unreadable" "$out"

out="$(FAKE_COMMENT_AUTHOR_ID=$D FAKE_COMMENT_AUTHOR='loop-app[bot]' FAKE_REACTIONS="$FRESH" lrun verify --loop-identity 'loop-app[bot]' --maintainer-ids "$M" --spec-comment 335 2026-09-21T09:00:00Z --dev-app-id "$D" "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --dev-app-id: the loop-identity rule still prints untrusted for the loop's login" "untrusted" "$out"

echo "# the flagged spec comment: --spec-comment (WB-D30) -- the finder's pair, not the anchor's"

# The flagged comment (777, edited 2026-10-02) differs from the anchored one (335, 2026-09-21), and
# #N's live updated_at (2026-10-05) differs from the anchor's: posting the spec moves it.
SC="--spec-comment 777 2026-10-02T00:00:00Z"
SU=2026-10-02T00:00:00Z
SFRESH="$(rx 1001 +1 2026-10-03T00:00:00Z)\n"
sc() { # sc <args...> -- lrun with the flagged comment live and #N moved
  FAKE_COMMENT_UPDATED="${FAKE_COMMENT_UPDATED:-$SU}" FAKE_ISSUE_UPDATED="${FAKE_ISSUE_UPDATED:-2026-10-05T00:00:00Z}" lrun "$@"
}
sc_ids() { # sc_ids <rows> <args...> -- reactions as the first argument
  r="$1"; shift
  FAKE_REACTIONS="$r" sc verify --maintainer-ids "$M" "$@" "$REPO" "$POINTER" "$spec_anchor"
}

: >"$tmp/log"
out="$(FAKE_GH_LOG="$tmp/log" FAKE_REACTIONS="$SFRESH" lrun verify --maintainer-ids "$M" "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --maintainer-ids, no flag: an anchored approved comment alone is unreacted" "unreacted" "$out"
if grep -q 'comments/335' "$tmp/log"; then seen=requested; else seen=never; fi
assert_eq "verify --maintainer-ids, no flag: the anchored comment is never requested" never "$seen"

: >"$tmp/log"
out="$(FAKE_GH_LOG="$tmp/log" sc_ids "$SFRESH" $SC)"
assert_eq "verify --spec-comment: an approved maintainer comment matches though #N's updated_at moved" "match" "$out"
if grep -q 'comments/777' "$tmp/log"; then seen=requested; else seen=never; fi
assert_eq "verify --spec-comment: the flagged comment is requested" requested "$seen"
if grep -q 'comments/335' "$tmp/log"; then seen=requested; else seen=never; fi
assert_eq "verify --spec-comment: the anchored comment is never requested" never "$seen"

out="$(FAKE_COMMENT_AUTHOR_ID=$D sc_ids "$SFRESH" $SC --dev-app-id "$D")"
assert_eq "verify --spec-comment: an approved dev-App comment matches under --dev-app-id" "match" "$out"

out="$(FAKE_COMMENT_AUTHOR_ID=$D sc_ids "$SFRESH" $SC)"
assert_eq "verify --spec-comment: a dev-App comment without --dev-app-id is untrusted" "untrusted" "$out"

out="$(sc verify $SC "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --spec-comment without --maintainer-ids is unreadable" "unreadable" "$out"

for bad in 0 012 abc '' 7x; do
  out="$(sc_ids "$SFRESH" --spec-comment "$bad" $SU)"
  assert_eq "verify --spec-comment: id [$bad] is unreadable" "unreadable" "$out"
done
for bad in tomorrow 2026-10-02 2026-10-02T00:00:00 '2026-10-02T00:00:00Z ' ''; do
  out="$(sc_ids "$SFRESH" --spec-comment 777 "$bad")"
  assert_eq "verify --spec-comment: updated_at [$bad] is unreadable" "unreadable" "$out"
done
out="$(sc_ids "$SFRESH" --spec-comment 777)"
assert_eq "verify --spec-comment with one value is unreadable" "unreadable" "$out"

bad_task_ts='{"milestone":12,"task_issue":86,"task_issue_updated_at":"not-a-time","spec_comment":null}'
out="$(FAKE_REACTIONS="$SFRESH" sc verify --maintainer-ids "$M" $SC "$REPO" "$POINTER" "$bad_task_ts")"
assert_eq "verify --spec-comment: an unparseable task_issue_updated_at is unreadable" "unreadable" "$out"
null_task_ts='{"milestone":12,"task_issue":86,"task_issue_updated_at":null,"spec_comment":null}'
out="$(FAKE_REACTIONS="$SFRESH" sc verify --maintainer-ids "$M" $SC "$REPO" "$POINTER" "$null_task_ts")"
assert_eq "verify --spec-comment: a null task_issue_updated_at is unreadable" "unreadable" "$out"
malformed_spec='{"milestone":12,"task_issue":86,"task_issue_updated_at":"2026-09-20T12:00:00Z","spec_comment":{"id":335}}'
out="$(FAKE_REACTIONS="$SFRESH" sc verify --maintainer-ids "$M" $SC "$REPO" "$POINTER" "$malformed_spec")"
assert_eq "verify --spec-comment: a malformed anchored spec_comment is still unreadable" "unreadable" "$out"

out="$(FAKE_COMMENT_UPDATED=2026-10-02T00:00:01Z sc_ids "$SFRESH" $SC)"
assert_eq "verify --spec-comment: the live updated_at differs from the flag's -- drift" "drift" "$out"
out="$(FAKE_COMMENT_ISSUE_URL="https://api.github.com/repos/$REPO/issues/99" sc_ids "$SFRESH" $SC)"
assert_eq "verify --spec-comment: a comment on another issue is drift" "drift" "$out"
out="$(FAKE_COMMENT_AUTHOR_ID=7777 sc_ids "$SFRESH" $SC)"
assert_eq "verify --spec-comment: an undeclared author is untrusted" "untrusted" "$out"
out="$(sc_ids "" $SC)"
assert_eq "verify --spec-comment: no reaction is unreacted" "unreacted" "$out"
out="$(sc_ids "$(rx 1001 +1 2026-10-01T00:00:00Z)\n" $SC)"
assert_eq "verify --spec-comment: a reaction before the last edit is unreacted" "unreacted" "$out"
out="$(FAKE_COMMENT_RECHECK_UPDATED=2026-10-02T00:00:09Z sc_ids "$SFRESH" $SC)"
assert_eq "verify --spec-comment: an edit after the reactions read is drift" "drift" "$out"
out="$(FAKE_COMMENT_RECHECK_FAIL=1 sc_ids "$SFRESH" $SC)"
assert_eq "verify --spec-comment: a failed re-check read is unreadable" "unreadable" "$out"

: >"$tmp/log"
out="$(FAKE_GH_LOG="$tmp/log" FAKE_COMMENT_AUTHOR='loop-app[bot]' sc_ids "$SFRESH" $SC --loop-identity 'loop-app[bot]')"
assert_eq "verify --spec-comment: the loop's login as the flagged comment's author is untrusted" "untrusted" "$out"
if grep -q 'comments/777' "$tmp/log"; then seen=requested; else seen=never; fi
assert_eq "verify --spec-comment: the name rule read the flagged comment" requested "$seen"
if grep -q 'comments/335' "$tmp/log"; then seen=requested; else seen=never; fi
assert_eq "verify --spec-comment: the name rule never read the anchored comment" never "$seen"

# Everything else about #N still holds with the flag.
out="$(FAKE_ISSUE_STATE=closed sc_ids "$SFRESH" $SC)"
assert_eq "verify --spec-comment: a closed #N is still drift" "drift" "$out"
out="$(FAKE_ISSUE_MILESTONE=13 sc_ids "$SFRESH" $SC)"
assert_eq "verify --spec-comment: #N on another milestone is still drift" "drift" "$out"


# The anchor a map repo actually has after WB-D30: handoff writes spec_comment null.
null_spec_anchor='{"milestone":12,"task_issue":86,"task_issue_updated_at":"2026-09-20T12:00:00Z","spec_comment":null}'
out="$(FAKE_REACTIONS="$SFRESH" sc verify --maintainer-ids "$M" $SC "$REPO" "$POINTER" "$null_spec_anchor")"
assert_eq "verify --spec-comment: a null-spec anchor matches on the flagged approved comment" "match" "$out"
out="$(FAKE_REACTIONS="$SFRESH" lrun verify --maintainer-ids "$M" "$REPO" "$POINTER" "$null_spec_anchor")"
assert_eq "verify --maintainer-ids, no flag: a null-spec anchor is unreacted" "unreacted" "$out"
out="$(FAKE_REACTIONS="$SFRESH" sc verify --maintainer-ids "$M" "$REPO" "$POINTER" "$null_spec_anchor")"
assert_eq "verify --maintainer-ids, no flag, #N moved: a null-spec anchor is drift" "drift" "$out"
# Without the flag a moved #N is drift, as before.
out="$(FAKE_ISSUE_UPDATED=2026-10-05T00:00:00Z FAKE_REACTIONS="$SFRESH" lrun verify --maintainer-ids "$M" "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --maintainer-ids, no flag: #N's updated_at moved is still drift" "drift" "$out"

# --plan validates the flag and otherwise ignores it.
out="$(lrun verify --plan --maintainer-ids "$M" $SC "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --plan with --spec-comment is match" "match" "$out"
out="$(lrun verify --plan --maintainer-ids "$M" --spec-comment 012 $SU "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --plan validates --spec-comment too" "unreadable" "$out"
out="$(lrun verify --plan $SC "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify --plan --spec-comment without --maintainer-ids is unreadable" "unreadable" "$out"

# Legacy: without --maintainer-ids the anchored comment is checked as before.
: >"$tmp/log"
out="$(FAKE_GH_LOG="$tmp/log" lrun verify "$REPO" "$POINTER" "$spec_anchor")"
assert_eq "verify without --maintainer-ids: the anchored comment still matches" "match" "$out"
if grep -q 'comments/335' "$tmp/log"; then seen=requested; else seen=never; fi
assert_eq "verify without --maintainer-ids: the anchored comment is requested" requested "$seen"

exit "$fail"
