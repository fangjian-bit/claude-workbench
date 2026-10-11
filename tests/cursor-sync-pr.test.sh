#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/cursor-sync-pr.sh.
#
# Issue #215: /way-of-working:resume looks for a forgotten handoff cursor-sync PR and
# whether HEAD is on a sync branch nobody merged. Issue #385 (WB-D24): the script only
# reports now -- no merge verdict, no check, review or ruleset read.
#
# `gh` is stubbed in two modes. By default, as tests/plan-gather.test.sh stubs it, it
# does NOT interpret --jq: it returns pre-formed TSV standing in for what the real --jq
# would emit, so those cases test the script's own shell code -- the shape checks, the
# candidate count, each refusal, the local-branch binding -- not GitHub's field
# semantics. With FAKE_JSON set it instead runs the script's REAL --jq program under jq
# over a JSON fixture trimmed to the fields --json asked for (as real gh would return),
# so the projection itself, and the fields it depends on, are under test. The stub also
# asserts the call's own arguments (the repo, the base, the state, the --jq projection's
# column anchors, whose order the parser depends on), and fails on ANY other gh call: a
# script that reads rulesets, checks or reviews again fails a fixture.
#
# The local-branch binding needs a real checkout, so each case runs inside a
# throwaway repo (the same setup tests/cursor-drift.test.sh uses).
#
# Permitted toolset: POSIX sh and its standard utilities, git; jq for the FAKE_JSON
# cases only (skipped loudly when absent). No yq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/plugins/way-of-working/bin/cursor-sync-pr.sh"

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

# --- the fake gh -------------------------------------------------------
fakebin="$tmp/fakebin"
mkdir -p "$fakebin"
cat >"$fakebin/gh" <<'FAKE_GH'
#!/bin/sh
set -eu
[ "$1" = pr ] && [ "$2" = list ] || { echo "fake gh: unsupported command $*" >&2; exit 1; }
args=" $* "
case "$args" in *" --base $FAKE_BASE "*) ;; *) echo "fake gh: base not $FAKE_BASE: $*" >&2; exit 1 ;; esac
case "$args" in *" --repo $FAKE_REPO "*) ;; *) echo "fake gh: repo not $FAKE_REPO: $*" >&2; exit 1 ;; esac
case "$args" in
  *" --state open "*)
    case "$args" in
      *'select(.headRefName | startswith("docs/sync-cursor-"))'*) ;;
      *) echo "fake gh: prefix filter missing" >&2; exit 1 ;;
    esac
    case "$args" in
      *'[.number, .headRefName, .headRefOid, .isCrossRepository,'*'(.files | length), (.files[0].path // "")]'*) ;;
      *) echo "fake gh: projection changed -- update the parser and this stub together" >&2; exit 1 ;;
    esac
    case "$args" in *"length, (.[] | select"*) ;; *) echo "fake gh: total count missing" >&2; exit 1 ;; esac
    [ -z "${FAKE_FAIL:-}" ] || { echo "fake gh: HTTP 502" >&2; exit 1; }
    # The value of --json (the comma list of fields gh will return) and of --jq.
    prog=""; fields=""; take=""
    for a in "$@"; do
      case "$take" in jq) prog="$a" ;; json) fields="$a" ;; esac
      take=""
      case "$a" in --jq) take=jq ;; --json) take=json ;; esac
    done
    # Exactly the fields the projection reads may be requested: a script that asks for the
    # merge state, checks or reviews again is acting on them.
    [ "$fields" = number,headRefName,headRefOid,isCrossRepository,files ] ||
      { echo "fake gh: --json is not exactly the projection's fields: $fields" >&2; exit 1; }
    if [ -n "${FAKE_JSON:-}" ]; then
      # Run the script's REAL --jq program (jq stands in for gh's embedded gojq) over a
      # JSON fixture trimmed to the requested fields, so a dropped field changes the
      # result as it would with real gh. tr drops the CR a Windows jq.exe emits.
      jq -c --arg f "$fields" '($f | split(",")) as $k
        | map(with_entries(select(.key as $x | $k | index($x))))' "$FAKE_JSON" >"$FAKE_JSON.trim"
      jq -r "$prog" "$FAKE_JSON.trim" | tr -d '\015'
    else
      cat "$FAKE_ROWS"
    fi
    ;;
  *" --state merged "*)
    case "$args" in *" --head $FAKE_HEAD "*) ;; *) echo "fake gh: head not $FAKE_HEAD: $*" >&2; exit 1 ;; esac
    [ -z "${FAKE_MERGED_FAIL:-}" ] || { echo "fake gh: HTTP 502" >&2; exit 1; }
    cat "$FAKE_MERGED"
    ;;
  *) echo "fake gh: unexpected state: $*" >&2; exit 1 ;;
esac
FAKE_GH
chmod +x "$fakebin/gh"

export FAKE_REPO=acme/widgets FAKE_BASE=main FAKE_HEAD=unset

# --- a throwaway checkout with a local sync branch ---------------------
repo="$tmp/repo"
git init -q "$repo"
cd "$repo"
git config user.email test@example.com
git config user.name test
git config core.autocrlf false
echo a >a.txt && git add a.txt && git commit -qm initial
git checkout -q -b docs/sync-cursor-x
mkdir -p .ai && echo cursor >.ai/next-steps.md && git add .ai && git commit -qm "cursor sync"
oid_a="$(git rev-parse HEAD)"
git checkout -q -
other=89abcdef0123456789abcdef0123456789abcdef   # a head no local branch carries

# rows <total>: the count line alone, no candidate rows
rows() { printf '%s\n' "$1"; }

run() { FAKE_ROWS="$1" PATH="$fakebin:$PATH" sh "$script" acme/widgets main 2>/dev/null; }

rows 0 >"$tmp/empty"
assert_eq "no open PRs -> none" "none" "$(run "$tmp/empty")"

rows 4 >"$tmp/nocand"
assert_eq "open PRs, none of them sync branches -> none" "none" "$(run "$tmp/nocand")"

printf '1\n210\tdocs/sync-cursor-x\t%s\tfalse\t1\t.ai/next-steps.md\n' "$oid_a" >"$tmp/open"
assert_eq "one same-repo, one-file, local PR -> open, with its head and branch" \
  "open 210 $oid_a docs/sync-cursor-x" "$(run "$tmp/open")"

printf '1\n210\tdocs/sync-cursor-x\t%s\tfalse\t1\t.ai/next-steps.md' "$oid_a" >"$tmp/nonl"
assert_eq "a last row with no trailing newline is still read" \
  "open 210 $oid_a docs/sync-cursor-x" "$(run "$tmp/nonl")"

printf '1\n210\tdocs/sync-cursor-x\t%s\ttrue\t1\t.ai/next-steps.md\n' "$oid_a" >"$tmp/fork"
assert_eq "a fork PR is refused, whatever else it passes" \
  "refuse 210 cross-repository" "$(run "$tmp/fork")"

printf '1\n210\tdocs/sync-cursor-x\t%s\tfalse\t2\t.ai/next-steps.md\n' "$oid_a" >"$tmp/twofiles"
assert_eq "a PR touching more than the cursor (e.g. park/unpark) is refused" \
  "refuse 210 files" "$(run "$tmp/twofiles")"

printf '1\n210\tdocs/sync-cursor-x\t%s\tfalse\t1\tdocs/decisions.md\n' "$oid_a" >"$tmp/otherfile"
assert_eq "a one-file PR on some other file is refused" \
  "refuse 210 files" "$(run "$tmp/otherfile")"

printf '1\n210\tdocs/sync-cursor-x\t%s\tfalse\t0\t\n' "$oid_a" >"$tmp/nofiles"
assert_eq "a sync PR with zero files is refused as files, not unreadable (empty path field)" \
  "refuse 210 files" "$(run "$tmp/nofiles")"

printf '1\n210\tdocs/sync-cursor-x\t%s\tfalse\t1\t.ai/next-steps.md\n' "$other" >"$tmp/moved"
assert_eq "the local branch exists but its tip is not the PR head -> not-local" \
  "refuse 210 not-local" "$(run "$tmp/moved")"

printf '1\n210\tdocs/sync-cursor-revived\t%s\tfalse\t1\t.ai/next-steps.md\n' "$other" >"$tmp/stale"
assert_eq "no local branch of that name (a revived stale remote branch) -> not-local" \
  "refuse 210 not-local" "$(run "$tmp/stale")"

printf '2\n205\tdocs/sync-cursor-x\t%s\tfalse\t1\t.ai/next-steps.md\n210\tdocs/sync-cursor-y\t%s\tfalse\t1\t.ai/next-steps.md\n' \
  "$oid_a" "$other" >"$tmp/two"
assert_eq "two candidates -> ambiguous, neither reported open" \
  "ambiguous 205 210" "$(run "$tmp/two")"

assert_eq "gh failure -> unreadable, never none" "unreadable" \
  "$(FAKE_FAIL=1 run "$tmp/open")"

# --- the projection itself, through the script's real --jq program ------
# jq stands in for gh's embedded gojq. Skipped loudly if jq is absent.
if command -v jq >/dev/null 2>&1; then
  jq_case() { # <desc> <expected> <json>
    printf '%s\n' "$3" >"$tmp/pr.json"
    assert_eq "jq projection: $1" "$2" "$(FAKE_JSON="$tmp/pr.json" run /dev/null)"
  }
  sync="\"headRefName\":\"docs/sync-cursor-x\",\"headRefOid\":\"$oid_a\",\"isCrossRepository\":false"
  jq_case "a sync PR with one file, whatever its checks and reviews say" \
    "open 210 $oid_a docs/sync-cursor-x" \
    "[{\"number\":210,$sync,\"mergeStateStatus\":\"DIRTY\",\"reviewDecision\":\"CHANGES_REQUESTED\",\"statusCheckRollup\":[],\"files\":[{\"path\":\".ai/next-steps.md\"}]}]"
  jq_case "a non-sync PR beside it is dropped by the filter" \
    "open 210 $oid_a docs/sync-cursor-x" \
    "[{\"number\":7,\"headRefName\":\"feat/x\",\"headRefOid\":\"$other\",\"isCrossRepository\":false,\"files\":[{\"path\":\"a\"}]},{\"number\":210,$sync,\"files\":[{\"path\":\".ai/next-steps.md\"}]}]"
  jq_case "two files -> files" "refuse 210 files" \
    "[{\"number\":210,$sync,\"files\":[{\"path\":\".ai/next-steps.md\"},{\"path\":\"b\"}]}]"
  jq_case "a fork -> cross-repository" "refuse 210 cross-repository" \
    "[{\"number\":210,\"headRefName\":\"docs/sync-cursor-x\",\"headRefOid\":\"$oid_a\",\"isCrossRepository\":true,\"files\":[{\"path\":\".ai/next-steps.md\"}]}]"
  jq_case "no files at all -> files" "refuse 210 files" "[{\"number\":210,$sync,\"files\":[]}]"
else
  echo "SKIP - jq not on PATH: the projection's own --jq program was NOT exercised" >&2
fi

rows 200 >"$tmp/limit"
assert_eq "the open-PR list hit its fetch limit -> unreadable, never none" \
  "unreadable" "$(run "$tmp/limit")"

: >"$tmp/nothing"
assert_eq "no count line at all -> unreadable" "unreadable" "$(run "$tmp/nothing")"

printf '0\n210\tdocs/sync-cursor-x\t%s\tfalse\t1\t.ai/next-steps.md\n' "$oid_a" >"$tmp/countlies"
assert_eq "more candidate rows than the count line claims -> unreadable" \
  "unreadable" "$(run "$tmp/countlies")"

printf '210\tdocs/sync-cursor-x\t%s\tfalse\t1\t.ai/next-steps.md\n' "$oid_a" >"$tmp/nocount"
assert_eq "a candidate row where the count line belongs -> unreadable" \
  "unreadable" "$(run "$tmp/nocount")"

printf '1\n210\tdocs/sync-cursor-x\tgggggggggggggggggggggggggggggggggggggggg\tfalse\t1\t.ai/next-steps.md\n' >"$tmp/badhex"
assert_eq "a 40-character non-hex head oid -> unreadable" "unreadable" "$(run "$tmp/badhex")"

printf '1\n210\tdocs/sync-cursor-x\t0123456789abcdef\tfalse\t1\t.ai/next-steps.md\n' >"$tmp/shortoid"
assert_eq "a short hex head oid -> unreadable" "unreadable" "$(run "$tmp/shortoid")"

printf '1\n21x\tdocs/sync-cursor-x\t%s\tfalse\t1\t.ai/next-steps.md\n' "$oid_a" >"$tmp/badnum"
assert_eq "a non-numeric PR number -> unreadable" "unreadable" "$(run "$tmp/badnum")"

printf '1\n210\tdocs/sync-cursor-x\t%s\tmaybe\t1\t.ai/next-steps.md\n' "$oid_a" >"$tmp/badcross"
assert_eq "a non-boolean isCrossRepository -> unreadable" "unreadable" "$(run "$tmp/badcross")"

printf '1\n210\tdocs/sync-cursor-x\t%s\tfalse\tone\t.ai/next-steps.md\n' "$oid_a" >"$tmp/badnfiles"
assert_eq "a non-numeric file count -> unreadable" "unreadable" "$(run "$tmp/badnfiles")"

printf '1\n210\tfeat/other\t%s\tfalse\t1\t.ai/next-steps.md\n' "$oid_a" >"$tmp/badbranch"
assert_eq "a row whose branch lacks the prefix -> unreadable" "unreadable" "$(run "$tmp/badbranch")"

printf '1\n210\tdocs/sync-cursor-x\t%s\tfalse\t1\t.ai/next-steps.md\textra\n' "$oid_a" >"$tmp/extra"
assert_eq "an extra field -> unreadable" "unreadable" "$(run "$tmp/extra")"

assert_eq "no arguments -> unreadable" "unreadable" \
  "$(PATH="$fakebin:$PATH" sh "$script" 2>/dev/null)"

assert_eq "a third argument (the retired required-checks list) -> unreadable" "unreadable" \
  "$(FAKE_ROWS="$tmp/open" PATH="$fakebin:$PATH" sh "$script" acme/widgets main lint,coupling 2>/dev/null)"

FAKE_BASE=develop
assert_eq "the base argument reaches gh (stub expects develop, script given main)" \
  "unreadable" "$(run "$tmp/open")"
FAKE_BASE=main

assert_eq "outside a git checkout -> unreadable" "unreadable" \
  "$(cd "$tmp" && FAKE_ROWS="$tmp/open" PATH="$fakebin:$PATH" sh "$script" acme/widgets main 2>/dev/null)"

# --- HEAD on a sync branch, no open candidate ---------------------------
git checkout -q docs/sync-cursor-x
export FAKE_HEAD=docs/sync-cursor-x

: >"$tmp/merged-none"
assert_eq "on a sync branch no merged PR carries (push failed / PR closed) -> unmerged" \
  "unmerged docs/sync-cursor-x" "$(FAKE_MERGED="$tmp/merged-none" run "$tmp/empty")"

printf '%s\n' "$other" >"$tmp/merged-other"
assert_eq "a merged PR on that branch, but not at this tip -> unmerged" \
  "unmerged docs/sync-cursor-x" "$(FAKE_MERGED="$tmp/merged-other" run "$tmp/empty")"

git tag docs/sync-cursor-x
assert_eq "a same-named tag does not hide the unmerged branch (no --short ambiguity)" \
  "unmerged docs/sync-cursor-x" "$(FAKE_MERGED="$tmp/merged-none" run "$tmp/empty")"
git tag -d docs/sync-cursor-x >/dev/null

printf '%s\n%s\n' "$other" "$oid_a" >"$tmp/merged-tip"
assert_eq "this tip was merged -> none" \
  "none" "$(FAKE_MERGED="$tmp/merged-tip" run "$tmp/empty")"

assert_eq "the merged-PR lookup fails -> unreadable, never none" "unreadable" \
  "$(FAKE_MERGED="$tmp/merged-tip" FAKE_MERGED_FAIL=1 run "$tmp/empty")"

git checkout -q -
export FAKE_HEAD=unset
assert_eq "back on the base branch, nothing open -> none (no merged-PR lookup made)" \
  "none" "$(run "$tmp/empty")"

if [ "$fail" -ne 0 ]; then
  echo "cursor-sync-pr.test.sh: FAILED" >&2
  exit 1
fi
echo "cursor-sync-pr.test.sh: all passed"
