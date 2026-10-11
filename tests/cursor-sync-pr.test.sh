#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/cursor-sync-pr.sh.
#
# Issue #215: /way-of-working:resume offers to merge a forgotten handoff cursor-sync
# PR. This predicate decides which PR, if any, may be offered -- and whether HEAD is
# on a sync branch nobody merged.
#
# `gh` is stubbed in two modes. By default, as tests/plan-gather.test.sh stubs it, it
# does NOT interpret --jq: it returns pre-formed TSV standing in for what the real --jq
# would emit, so those cases test the script's own shell code -- the shape
# checks, the candidate count, each refusal, the local-branch binding -- not GitHub's
# field semantics. With FAKE_JSON set it instead runs the script's REAL --jq program
# under jq over a JSON fixture trimmed to the fields --json asked for (as real gh
# would return), so the green predicate itself, and the fields it depends on, are under
# test. The stub also asserts the call's own arguments (the repo, the base, the state,
# the --jq projection's column anchors, whose order the parser depends on, and that
# --json carries both fields the green predicate reads), so a regression there fails a
# fixture instead of passing silently.
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
if [ "$1" = api ]; then
  # The bypass check (#250). Like the pr-list stub, --jq is not interpreted: the stub
  # returns what the real program would emit, after asserting the call's own shape.
  # FAKE_API_FAIL=rules fails the rules/branches call, =rulesets the rulesets/<id> call.
  case "${FAKE_API_FAIL:-}:$*" in
    rules:*"/rules/branches/"* | rulesets:*"/rulesets/"*) echo "fake gh: HTTP 502" >&2; exit 1 ;;
  esac
  case " $* " in
    *" --paginate repos/$FAKE_REPO/rules/branches/$FAKE_BASE --jq "*'select(.type == "update") | .ruleset_id'*)
      for id in ${FAKE_UPDATE_IDS:-}; do echo "$id"; done ;;
    *" repos/$FAKE_REPO/rulesets/"*" --jq "*'.current_user_can_bypass'*)
      id="${2##*/}"
      eval "v=\${FAKE_BYPASS_$id:-\${FAKE_BYPASS:-}}"
      echo "$v" ;;
    *) echo "fake gh: unexpected api call: $*" >&2; exit 1 ;;
  esac
  exit 0
fi
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
      *'[.number, .headRefName, .headRefOid, .isCrossRepository, .mergeStateStatus,'*'(.files | length),'*'else "0" end),'*'(.files[0].path // "")]'*) ;;
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
    # The green column is computed from these two fields. Dropping statusCheckRollup
    # makes it always 0 (every BLOCKED PR refused again); dropping reviewDecision makes
    # it silently ignore a blocking review -- the dangerous direction. Check the --json
    # list itself, never the whole argument text (which includes the --jq program that
    # names both fields).
    case ",$fields," in *,statusCheckRollup,*) ;; *) echo "fake gh: --json lacks statusCheckRollup" >&2; exit 1 ;; esac
    case ",$fields," in *,reviewDecision,*) ;; *) echo "fake gh: --json lacks reviewDecision" >&2; exit 1 ;; esac
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
# One restrict-updates ruleset (id 7) applies to the base; the active identity can
# bypass it for pull requests. Cases below override these.
export FAKE_UPDATE_IDS=7 FAKE_BYPASS=pull_requests_only

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

us="$(printf '\037')"

# The names column the script's --jq emits: the green checks' names, each wrapped in
# the unit separator. NAMES overrides it; the default carries both required checks.
# rows <total> then one candidate row per remaining group of seven args
rows() {
  printf '%s\n' "$1"; shift
  while [ "$#" -ge 7 ]; do
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "${GREEN:-1}" \
      "${NAMES-${us}lint${us}coupling${us}}" "$7"
    shift 7
  done
}

run() { FAKE_ROWS="$1" PATH="$fakebin:$PATH" sh "$script" acme/widgets main "${REQ-lint,coupling}" 2>/dev/null; }

good="docs/sync-cursor-x $oid_a false"

rows 0 >"$tmp/empty"
assert_eq "no open PRs -> none" "none" "$(run "$tmp/empty")"

rows 4 >"$tmp/nocand"
assert_eq "open PRs, none of them sync branches -> none" "none" "$(run "$tmp/nocand")"

rows 1 210 $good CLEAN 1 .ai/next-steps.md >"$tmp/clean"
assert_eq "one same-repo, one-file, local, CLEAN PR -> offer with its branch" \
  "offer 210 $oid_a docs/sync-cursor-x" "$(run "$tmp/clean")"

{ printf '1\n'; printf '210\tdocs/sync-cursor-x\t%s\tfalse\tCLEAN\t1\t1\t%s\t.ai/next-steps.md' "$oid_a" "${us}lint${us}coupling${us}"; } >"$tmp/nonl"
assert_eq "a last row with no trailing newline is still read" \
  "offer 210 $oid_a docs/sync-cursor-x" "$(run "$tmp/nonl")"

rows 1 210 docs/sync-cursor-x "$oid_a" true CLEAN 1 .ai/next-steps.md >"$tmp/fork"
assert_eq "a fork PR is refused, whatever else it passes" \
  "refuse 210 cross-repository" "$(run "$tmp/fork")"

rows 1 210 $good CLEAN 2 .ai/next-steps.md >"$tmp/twofiles"
assert_eq "a PR touching more than the cursor (e.g. park/unpark) is refused" \
  "refuse 210 files" "$(run "$tmp/twofiles")"

rows 1 210 $good CLEAN 1 docs/decisions.md >"$tmp/otherfile"
assert_eq "a one-file PR on some other file is refused" \
  "refuse 210 files" "$(run "$tmp/otherfile")"

rows 1 210 docs/sync-cursor-x "$other" false CLEAN 1 .ai/next-steps.md >"$tmp/moved"
assert_eq "the local branch exists but its tip is not the PR head -> not-local" \
  "refuse 210 not-local" "$(run "$tmp/moved")"

rows 1 210 docs/sync-cursor-revived "$other" false CLEAN 1 .ai/next-steps.md >"$tmp/stale"
assert_eq "no local branch of that name (a revived stale remote branch) -> not-local" \
  "refuse 210 not-local" "$(run "$tmp/stale")"

for st in BEHIND BLOCKED DIRTY DRAFT UNSTABLE UNKNOWN HAS_HOOKS; do
  lower="$(printf '%s' "$st" | tr 'A-Z' 'a-z')"
  rows 1 210 $good "$st" 1 .ai/next-steps.md >"$tmp/state"
  case "$st" in
    BLOCKED) want="offer 210 $oid_a docs/sync-cursor-x"; why="BLOCKED with every check green (only the restriction unmet) is offered" ;;
    *) want="refuse 210 state-$lower"; why="$st is refused with its name" ;;
  esac
  assert_eq "$why" "$want" "$(run "$tmp/state")"
done

# Whatever the state, a PR whose present checks are not all green is never offered.
# (Only BLOCKED actually reaches the green test; every other state is refused before it.)
GREEN=0; rows 1 210 $good BLOCKED 1 .ai/next-steps.md >"$tmp/state"; GREEN=1
assert_eq "BLOCKED with a red, pending or empty check set is refused" \
  "refuse 210 state-blocked" "$(run "$tmp/state")"

rows 1 210 $good CLEAN 0 "" >"$tmp/nofiles"
assert_eq "a sync PR with zero files is refused as files, not unreadable (empty path field)" \
  "refuse 210 files" "$(run "$tmp/nofiles")"

GREEN=0; rows 1 210 $good CLEAN 1 .ai/next-steps.md >"$tmp/cleanred"; GREEN=1
assert_eq "CLEAN is offered whatever the green column says (CLEAN needs no bypass)" \
  "offer 210 $oid_a docs/sync-cursor-x" "$(run "$tmp/cleanred")"

# --- the active identity must be able to perform the --admin merge (#250) ---
rows 1 210 $good BLOCKED 1 .ai/next-steps.md >"$tmp/blk"
for v in always pull_requests_only exempt; do
  FAKE_BYPASS=$v
  assert_eq "BLOCKED + update rule + current_user_can_bypass $v -> offer" \
    "offer 210 $oid_a docs/sync-cursor-x" "$(run "$tmp/blk")"
done
FAKE_BYPASS=never
assert_eq "BLOCKED + update rule + current_user_can_bypass never -> refuse, reason named" \
  "refuse 210 bypass-never" "$(run "$tmp/blk")"
FAKE_BYPASS=pull_requests_only FAKE_UPDATE_IDS="7 8"; export FAKE_BYPASS_8=never
assert_eq "two update rulesets, one of them never -> refuse" \
  "refuse 210 bypass-never" "$(run "$tmp/blk")"
unset FAKE_BYPASS_8
FAKE_BYPASS=
assert_eq "an empty current_user_can_bypass -> unreadable, not an offer" \
  "unreadable" "$(run "$tmp/blk")"
FAKE_BYPASS=sometimes
assert_eq "an unknown current_user_can_bypass value -> unreadable" \
  "unreadable" "$(run "$tmp/blk")"
FAKE_BYPASS=pull_requests_only FAKE_UPDATE_IDS=
assert_eq "BLOCKED with no update rule on the base -> the restriction does not explain it" \
  "refuse 210 state-blocked" "$(run "$tmp/blk")"
FAKE_UPDATE_IDS=x
assert_eq "a non-numeric ruleset id -> unreadable" "unreadable" "$(run "$tmp/blk")"
FAKE_UPDATE_IDS=7
assert_eq "a failed rules/branches lookup -> unreadable" "unreadable" "$(FAKE_API_FAIL=rules run "$tmp/blk")"
assert_eq "a failed rulesets/<id> lookup -> unreadable, never an offer" "unreadable" \
  "$(FAKE_API_FAIL=rulesets run "$tmp/blk")"
FAKE_BYPASS=never
assert_eq "CLEAN needs no bypass: never is not consulted" \
  "offer 210 $oid_a docs/sync-cursor-x" "$(run "$tmp/clean")"
FAKE_BYPASS=pull_requests_only

# --- the required-check list (#245), at the shell level ---
rows 1 210 $good BLOCKED 1 .ai/next-steps.md >"$tmp/blk"
NAMES="${us}lint${us}"; rows 1 210 $good BLOCKED 1 .ai/next-steps.md >"$tmp/lacks"; unset NAMES
assert_eq "BLOCKED, every present check green, a listed required check absent from the rollup -> refused" \
  "refuse 210 state-blocked" "$(run "$tmp/lacks")"
assert_eq "BLOCKED with no third argument (no list) -> refused, never offered" \
  "refuse 210 state-blocked" "$(FAKE_ROWS="$tmp/blk" PATH="$fakebin:$PATH" sh "$script" acme/widgets main 2>/dev/null)"
assert_eq "BLOCKED with an empty list -> refused" \
  "refuse 210 state-blocked" "$(REQ= run "$tmp/blk")"
assert_eq "four arguments -> unreadable" "unreadable" \
  "$(FAKE_ROWS="$tmp/blk" PATH="$fakebin:$PATH" sh "$script" acme/widgets main a b 2>/dev/null)"
NAMES=lint; rows 1 210 $good BLOCKED 1 .ai/next-steps.md >"$tmp/badnames"; unset NAMES
assert_eq "a names column without the unit-separator wrapping -> unreadable" "unreadable" \
  "$(run "$tmp/badnames")"
NAMES="${us}${us}"; rows 1 210 $good CLEAN 1 .ai/next-steps.md >"$tmp/cleannone"; unset NAMES
assert_eq "CLEAN with a required check absent from the rollup is still offered (CLEAN needs no bypass)" \
  "offer 210 $oid_a docs/sync-cursor-x" "$(run "$tmp/cleannone")"

GREEN=maybe; rows 1 210 $good BLOCKED 1 .ai/next-steps.md >"$tmp/badgreen"; GREEN=1
assert_eq "a non-0/1 green column -> unreadable" "unreadable" "$(run "$tmp/badgreen")"
GREEN=2; rows 1 210 $good BLOCKED 1 .ai/next-steps.md >"$tmp/await"; GREEN=1
assert_eq "BLOCKED with every check green but a review required -> awaiting-approval (#384)"   "refuse 210 awaiting-approval" "$(run "$tmp/await")"
GREEN=2; NAMES="${us}lint${us}"; rows 1 210 $good BLOCKED 1 .ai/next-steps.md >"$tmp/awaitlacks"; unset NAMES; GREEN=1
assert_eq "awaiting-approval still needs every required check present -> state-blocked"   "refuse 210 state-blocked" "$(run "$tmp/awaitlacks")"
GREEN=3; rows 1 210 $good BLOCKED 1 .ai/next-steps.md >"$tmp/green3"; GREEN=1
assert_eq "a green column of 3 -> unreadable" "unreadable" "$(run "$tmp/green3")"

# --- the green predicate itself, through the script's real --jq program ------
# jq stands in for gh's embedded gojq. Skipped loudly if jq is absent.
if command -v jq >/dev/null 2>&1; then
  pr_json() { # <state> <rollup-json> <reviewDecision>
    printf '[{"number":210,"headRefName":"docs/sync-cursor-x","headRefOid":"%s","isCrossRepository":false,"mergeStateStatus":"%s","files":[{"path":".ai/next-steps.md"}],"statusCheckRollup":%s,"reviewDecision":%s}]\n' \
      "$oid_a" "$1" "$2" "$3"
  }
  jq_case() { # <desc> <expected> <state> <rollup> <reviewDecision>
    pr_json "$3" "$4" "$5" >"$tmp/pr.json"
    assert_eq "jq predicate: $1" "$2" "$(REQ="${REQ-lint}" FAKE_JSON="$tmp/pr.json" run /dev/null)"
  }
  jq_req() { # <required list> then jq_case's arguments
    REQ="$1"; shift
    jq_case "$@"
    unset REQ
  }
  offer="offer 210 $oid_a docs/sync-cursor-x"; blocked=refuse\ 210\ state-blocked
  ok='{"__typename":"CheckRun","name":"lint","status":"COMPLETED","conclusion":"SUCCESS"}'
  jq_case "all-green CheckRuns + StatusContext, no review rule" "$offer" BLOCKED \
    "[$ok,{\"__typename\":\"StatusContext\",\"state\":\"SUCCESS\"}]" '""'
  jq_case "NEUTRAL and SKIPPED count as green" "$offer" BLOCKED \
    '[{"__typename":"CheckRun","name":"lint","status":"COMPLETED","conclusion":"NEUTRAL"},{"__typename":"CheckRun","name":"coupling","status":"COMPLETED","conclusion":"SKIPPED"}]' null
  jq_case "APPROVED review is fine" "$offer" BLOCKED "[$ok]" '"APPROVED"'
  jq_case "empty rollup is no evidence" "$blocked" BLOCKED '[]' '""'
  jq_case "null rollup is no evidence" "$blocked" BLOCKED null '""'
  jq_case "an in-progress run" "$blocked" BLOCKED \
    "[$ok,{\"__typename\":\"CheckRun\",\"status\":\"IN_PROGRESS\",\"conclusion\":null}]" '""'
  for c in FAILURE CANCELLED TIMED_OUT ACTION_REQUIRED STARTUP_FAILURE STALE; do
    jq_case "a $c run" "$blocked" BLOCKED \
      "[$ok,{\"__typename\":\"CheckRun\",\"status\":\"COMPLETED\",\"conclusion\":\"$c\"}]" '""'
  done
  jq_case "a pending StatusContext" "$blocked" BLOCKED \
    "[$ok,{\"__typename\":\"StatusContext\",\"state\":\"PENDING\"}]" '""'
  jq_case "an unknown __typename" "$blocked" BLOCKED \
    "[$ok,{\"__typename\":\"Mystery\",\"status\":\"COMPLETED\",\"conclusion\":\"SUCCESS\"}]" '""'
  awaiting=refuse\ 210\ awaiting-approval
  jq_case "REVIEW_REQUIRED with every check green -> awaiting-approval" "$awaiting" BLOCKED "[$ok]" '"REVIEW_REQUIRED"'
  jq_case "REVIEW_REQUIRED with a red check -> state-blocked, not awaiting-approval" "$blocked" BLOCKED \
    "[$ok,{\"__typename\":\"CheckRun\",\"name\":\"other\",\"status\":\"COMPLETED\",\"conclusion\":\"FAILURE\"}]" '"REVIEW_REQUIRED"'
  jq_case "REVIEW_REQUIRED with an empty rollup -> state-blocked" "$blocked" BLOCKED '[]' '"REVIEW_REQUIRED"'
  jq_req lint,coupling "REVIEW_REQUIRED with a required check never reported -> state-blocked" "$blocked" BLOCKED "[$ok]" '"REVIEW_REQUIRED"'
  jq_case "REVIEW_REQUIRED in a state other than BLOCKED is refused by its state" "refuse 210 state-behind" BEHIND "[$ok]" '"REVIEW_REQUIRED"'
  jq_case "CHANGES_REQUESTED" "$blocked" BLOCKED "[$ok]" '"CHANGES_REQUESTED"'
  jq_case "CLEAN needs no green evidence" "$offer" CLEAN '[]' '""'
  # Required checks (#245): every listed name must be in the rollup as a green entry.
  ctx='{"__typename":"StatusContext","context":"ci/build","state":"SUCCESS"}'
  jq_req lint,coupling "all green but a listed required check never reported" "$blocked" BLOCKED "[$ok]" '""'
  jq_req lint,ci/build "a required StatusContext is matched by its context" "$offer" BLOCKED "[$ok,$ctx]" '""'
  jq_req lint,ci/build "a required context that is absent is refused" "$blocked" BLOCKED "[$ok]" '""'
  jq_req lin "a required name is matched whole, not as a substring" "$blocked" BLOCKED "[$ok]" '""'
  jq_req LINT "a required name is matched case-sensitively" "$blocked" BLOCKED "[$ok]" '""'
  jq_req 'lint,' "a trailing comma adds no requirement" "$offer" BLOCKED "[$ok]" '""'
  jq_req ',lint' "an empty entry before a name is refused" "$blocked" BLOCKED "[$ok]" '""'
  jq_req 'lint,,' "an empty entry is refused, not skipped" "$blocked" BLOCKED "[$ok]" '""'
  jq_req '' "an empty required list is no evidence" "$blocked" BLOCKED "[$ok]" '""'
  jq_req , "a list of only separators is no evidence" "$blocked" BLOCKED "[$ok]" '""'
  jq_req '*' "a glob in the list is matched literally" "$blocked" BLOCKED "[$ok]" '""'
  jq_req lint "an unnamed green entry cannot satisfy a requirement" "$blocked" BLOCKED \
    '[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"}]' '""'
  jq_req lint "a name carrying a control character is never matched" "$blocked" BLOCKED \
    "[{\"__typename\":\"CheckRun\",\"name\":\"li\\u001fnt\",\"status\":\"COMPLETED\",\"conclusion\":\"SUCCESS\"}]" '""'
  jq_req lint "a green required name beside a red unrelated check is refused" "$blocked" BLOCKED \
    "[$ok,{\"__typename\":\"CheckRun\",\"name\":\"other\",\"status\":\"COMPLETED\",\"conclusion\":\"FAILURE\"}]" '""'
  jq_req '' "CLEAN needs no required-check evidence either" "$offer" CLEAN "[$ok]" '""'
else
  echo "SKIP - jq not on PATH: the green predicate's own --jq program was NOT exercised" >&2
fi

rows 2 205 $good CLEAN 1 .ai/next-steps.md 210 docs/sync-cursor-y "$other" false CLEAN 1 .ai/next-steps.md >"$tmp/two"
assert_eq "two candidates -> ambiguous, neither offered" \
  "ambiguous 205 210" "$(run "$tmp/two")"

assert_eq "gh failure -> unreadable, never none" "unreadable" \
  "$(FAKE_FAIL=1 run "$tmp/clean")"

rows 200 >"$tmp/limit"
assert_eq "the open-PR list hit its fetch limit -> unreadable, never none" \
  "unreadable" "$(run "$tmp/limit")"

: >"$tmp/nothing"
assert_eq "no count line at all -> unreadable" "unreadable" "$(run "$tmp/nothing")"

rows 0 210 $good CLEAN 1 .ai/next-steps.md >"$tmp/countlies"
assert_eq "more candidate rows than the count line claims -> unreadable" \
  "unreadable" "$(run "$tmp/countlies")"

rows 1 21 $good CLEAN 1 .ai/next-steps.md | sed 1d >"$tmp/nocount"
assert_eq "a candidate row where the count line belongs -> unreadable" \
  "unreadable" "$(run "$tmp/nocount")"

rows 1 210 docs/sync-cursor-x gggggggggggggggggggggggggggggggggggggggg false CLEAN 1 .ai/next-steps.md >"$tmp/badhex"
assert_eq "a 40-character non-hex head oid -> unreadable" "unreadable" "$(run "$tmp/badhex")"

rows 1 210 docs/sync-cursor-x 0123456789abcdef false CLEAN 1 .ai/next-steps.md >"$tmp/shortoid"
assert_eq "a short hex head oid -> unreadable" "unreadable" "$(run "$tmp/shortoid")"

rows 1 21x $good CLEAN 1 .ai/next-steps.md >"$tmp/badnum"
assert_eq "a non-numeric PR number -> unreadable" "unreadable" "$(run "$tmp/badnum")"

rows 1 210 docs/sync-cursor-x "$oid_a" maybe CLEAN 1 .ai/next-steps.md >"$tmp/badcross"
assert_eq "a non-boolean isCrossRepository -> unreadable" "unreadable" "$(run "$tmp/badcross")"

rows 1 210 $good CLEAN one .ai/next-steps.md >"$tmp/badnfiles"
assert_eq "a non-numeric file count -> unreadable" "unreadable" "$(run "$tmp/badnfiles")"

rows 1 210 feat/other "$oid_a" false CLEAN 1 .ai/next-steps.md >"$tmp/badbranch"
assert_eq "a row whose branch lacks the prefix -> unreadable" "unreadable" "$(run "$tmp/badbranch")"

{ printf '1\n'; printf '210\tdocs/sync-cursor-x\t%s\tfalse\tCLEAN\t1\t1\t%s\t.ai/next-steps.md\textra\n' "$oid_a" "${us}lint${us}coupling${us}"; } >"$tmp/extra"
assert_eq "an extra field -> unreadable" "unreadable" "$(run "$tmp/extra")"

assert_eq "no arguments -> unreadable" "unreadable" \
  "$(PATH="$fakebin:$PATH" sh "$script" 2>/dev/null)"

FAKE_BASE=develop
assert_eq "the base argument reaches gh (stub expects develop, script given main)" \
  "unreadable" "$(run "$tmp/clean")"
FAKE_BASE=main

assert_eq "outside a git checkout -> unreadable" "unreadable" \
  "$(cd "$tmp" && FAKE_ROWS="$tmp/clean" PATH="$fakebin:$PATH" sh "$script" acme/widgets main 2>/dev/null)"

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
assert_eq "this tip was merged (the human merged on GitHub) -> none" \
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
