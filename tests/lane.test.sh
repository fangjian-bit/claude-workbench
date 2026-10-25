#!/bin/sh
# Fixture tests for scripts/lanes/lane.sh: prepare and clean up one coder lane (#727).
#
# Each case builds a scratch repository with a local bare `origin` (no network) whose path
# carries a sentinel. Its default branch commits an .ai/project.yml and a
# plugins/way-of-working/bin/ holding stub scripts (spec-find.sh prints a canned line) plus the
# real prune-verdict.sh. A stub `gh` and a logging `git` wrapper go first on PATH. The stub gh
# holds canned RAW API JSON and applies the caller's own --jq argument with the real `jq -r`,
# the way tests/invariants-files-filter.test.sh reads a canned page, so the script's filters are
# what is tested. (gh's own --jq is gojq; the filters used here behave the same in both.) What
# GitHub filters on the server cannot be checked by canned JSON, so those cases assert the exact
# argument list in the gh log. The git wrapper can fail a subcommand (FX_GIT_FAIL) or run one
# extra git command first (FX_PRE), to stage a race.
# No case's stdout or stderr, and no prompt file, may contain the sentinel planted in the
# issue's title, body, user.login and milestone title, the PR rows' unused fields, and the
# origin path. Not-owned cannot be faked without privilege, so the `test -O` leg is not covered.
# Needs git, yq and jq; skips, loudly, without any of them.
# Permitted toolset: POSIX sh, plus git, yq, jq, sed, awk, grep, cmp and stat as the cases need.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/scripts/lanes/lane.sh"
pv="$root_dir/plugins/way-of-working/bin/prune-verdict.sh"

for tool in git yq jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "SKIP - $tool not on PATH; lane.test.sh needs it" >&2
    exit 0
  fi
done
real_git="$(command -v git)"
real_ln="$(command -v ln)"
real_jq="$(command -v jq)"

tmp="$(cd -P "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
: >"$tmp/allout"

fail=0
assert_eq() { # <desc> <want> <got>
  if [ "$2" = "$3" ]; then
    echo "ok - $1"
  else
    echo "FAIL - $1: expected [$2], got [$3]" >&2
    fail=1
  fi
}
assert_has() { # <desc> <file> <fixed string>
  if grep -F -- "$3" "$2" >/dev/null 2>&1; then
    echo "ok - $1"
  else
    echo "FAIL - $1: [$3] not in $2" >&2
    fail=1
  fi
}
assert_empty_file() { # <desc> <file>
  if [ ! -s "$2" ]; then
    echo "ok - $1"
  else
    echo "FAIL - $1: $2 is not empty" >&2
    fail=1
  fi
}

SENT="SENTINEL-7c2d41e9"
ISSUE=727
MS=19
BR=feat/x
CR=architect,security-critic
OTHER_OID=1111111111111111111111111111111111111111
FOUND='found 5001 2026-10-18T00:00:00Z'

cn=0
put() { mkdir -p "$(dirname "$R/$1")" && printf '%s\n' "$2" >"$R/$1"; }
bump() { $real_git -C "$R" add -A && $real_git -C "$R" commit -q -m b && $real_git -C "$R" push -q origin refs/heads/main:refs/heads/main; }
setyml() { # a yq expression applied to the committed project file, then committed and pushed
  yq -i "$1" "$R/.ai/project.yml"
  bump
}
canon() { # rewrite the canned issue with a jq expression
  "$real_jq" "$1" "$CAN/issue.json" >"$CAN/issue.new" && mv "$CAN/issue.new" "$CAN/issue.json"
}

# nc: a fresh driver checkout on `main` with a local bare origin, the stubs, and the canned JSON.
nc() {
  cn=$((cn + 1))
  D="$tmp/c$cn"
  R="$D/work"
  O="$D/origin-$SENT.git"
  FB="$D/fb"
  CAN="$D/canned"
  LD="$D/lanes"
  CWD="$R"
  mkdir -p "$D" "$FB" "$CAN"
  $real_git init -q --bare "$O"
  $real_git -C "$O" symbolic-ref HEAD refs/heads/main
  $real_git init -q "$R"
  $real_git -C "$R" symbolic-ref HEAD refs/heads/main
  $real_git -C "$R" config user.name t
  $real_git -C "$R" config user.email t@example.invalid
  $real_git -C "$R" config commit.gpgsign false
  $real_git -C "$R" remote add origin "$O"
  cat >"$tmp/project.yml.tpl" <<'YML'
repo: glunk-works/claude-workbench
pr_base: main
backlog:
  kind: github_issues
  repo: null
identities:
  maintainer:
    - { login: m, id: 1001 }
  dev_app:
    { login: d, id: 2001 }
YML
  mkdir -p "$R/.ai" "$R/plugins/way-of-working/bin" "$R/dir"
  cp "$tmp/project.yml.tpl" "$R/.ai/project.yml"
  printf '#!/bin/sh\nout=$(cat "$FX_FIND_FILE")\nprintf "%%s\\n" "$out"\nexit "${FX_FIND_RC:-0}"\n' >"$R/plugins/way-of-working/bin/spec-find.sh"
  printf '#!/bin/sh\necho stub\n' >"$R/plugins/way-of-working/bin/gh-identity.sh"
  printf '#!/bin/sh\necho stub\n' >"$R/plugins/way-of-working/bin/spec-reaction.sh"
  printf '#!/bin/sh\necho stub\n' >"$R/plugins/way-of-working/bin/declared-ids.sh"
  cp "$pv" "$R/plugins/way-of-working/bin/prune-verdict.sh"
  put dir/f one
  $real_git -C "$R" add -A && $real_git -C "$R" commit -q -m a
  $real_git -C "$R" push -q origin refs/heads/main:refs/heads/main
  $real_git -C "$R" fetch -q origin
  # canned raw API JSON, with the sentinel in every field the script must never read
  cat >"$CAN/repo.json" <<EOF
{"nameWithOwner":"glunk-works/claude-workbench","defaultBranchRef":{"name":"main"},"description":"$SENT"}
EOF
  cat >"$CAN/issue.json" <<EOF
{"number":$ISSUE,"state":"open","title":"$SENT","body":"$SENT","user":{"login":"$SENT","id":9},"milestone":{"number":$MS,"title":"$SENT"}}
EOF
  printf '[]\n' >"$CAN/prs.json"
  printf '%s\n' "$FOUND" >"$CAN/find.txt"
  # the logging git wrapper, the stub gh and a stub ln
  cat >"$FB/git" <<'FAKE_GIT'
#!/bin/sh
printf '%s\n' "$*" >>"$FX_LOG"
if [ -n "${FX_GIT_FAIL:-}" ]; then
  case " $* " in *"$FX_GIT_FAIL"*) echo "git: $FX_SENT $FX_ORIGIN" >&2; exit 1 ;; esac
fi
if [ -n "${FX_PRE_SH:-}" ]; then
  case " $* " in *"${FX_PRE_ON:-never-matches}"*) eval "$FX_PRE_SH" || : ;; esac
fi
if [ -n "${FX_PRE:-}" ]; then
  case " $* " in *"${FX_PRE_ON:-never-matches}"*) "$FX_REAL_GIT" $FX_PRE >/dev/null 2>&1 || : ;; esac
fi
exec "$FX_REAL_GIT" "$@"
FAKE_GIT
  cat >"$FB/gh" <<'FAKE_GH'
#!/bin/sh
printf '%s\n' "$*" >>"$FX_GHLOG"
filt= prev=
for a in "$@"; do
  [ "$prev" = --jq ] && filt=$a
  prev=$a
done
case "$1 $2" in
  "repo view") [ "${FX_FAIL:-}" != repoview ] || { echo "gh: $FX_SENT $FX_ORIGIN" >&2; exit 1; }; f=$FX_CANNED/repo.json ;;
  "pr list") [ "${FX_FAIL:-}" != prlist ] || { echo "gh: $FX_SENT $FX_ORIGIN" >&2; exit 1; }; f=$FX_CANNED/prs.json ;;
  api\ repos/*/issues/*) [ "${FX_FAIL:-}" != issue ] || { echo "gh: $FX_SENT $FX_ORIGIN" >&2; exit 1; }; f=$FX_CANNED/issue.json ;;
  *) echo "stub gh: unexpected: $*" >&2; exit 1 ;;
esac
exec jq -r "$filt" "$f"
FAKE_GH
  cat >"$FB/ln" <<'FAKE_LN'
#!/bin/sh
[ -z "${FX_LN_FAIL:-}" ] || exit 1
exec "$FX_REAL_LN" "$@"
FAKE_LN
  chmod +x "$FB/git" "$FB/gh" "$FB/ln"
  FX_LOG="$D/gitlog"
  FX_GHLOG="$D/ghlog"
  : >"$FX_LOG"
  : >"$FX_GHLOG"
  FX_REAL_GIT=$real_git
  FX_REAL_LN=$real_ln
  FX_CANNED=$CAN
  FX_FIND_FILE=$CAN/find.txt
  FX_SENT=$SENT FX_ORIGIN=$O
  export FX_SENT FX_ORIGIN
  FX_FIND_RC=0 FX_GIT_FAIL= FX_PRE_SH= FX_PRE= FX_PRE_ON= FX_FAIL= FX_LN_FAIL=
  export FX_PRE_SH FX_LOG FX_GHLOG FX_REAL_GIT FX_REAL_LN FX_CANNED FX_FIND_FILE FX_FIND_RC FX_GIT_FAIL FX_PRE FX_PRE_ON FX_FAIL FX_LN_FAIL
}

run_lane() {
  rc=0
  (cd "$CWD" && WOW_LANES_DIR="$LD" PATH="$FB:$PATH" "$script" "$@") >"$D/out" 2>"$D/err" || rc=$?
  out=$(cat "$D/out")
  err=$(cat "$D/err")
  cat "$D/out" "$D/err" >>"$tmp/allout"
}

snap() {
  {
    $real_git -C "$R" for-each-ref --format='%(refname) %(objectname)' refs/heads
    $real_git -C "$R" config --get-regexp '^branch\.' || :
    $real_git -C "$R" worktree list --porcelain
    if [ -e "$LD" ] || [ -L "$LD" ]; then
      echo "lanes $(stat -c %a "$LD")"
      ls -A "$LD" 2>/dev/null || :
    else
      echo nolanes
    fi
  } 2>&1
}

# stop_case: run, expect <rc> and the exact stdout <word>, and nothing else changed.
stop_case() { # <desc> <rc> <word> <args...>
  d=$1 wrc=$2 word=$3
  shift 3
  before=$(snap)
  run_lane "$@"
  after=$(snap)
  assert_eq "$d: exit" "$wrc" "$rc"
  assert_eq "$d: stdout" "$word" "$out"
  assert_eq "$d: nothing changed" "$before" "$after"
}

PREP="$ISSUE $MS $BR $CR"
prep_ok() { # a normal successful prep in the current case
  run_lane prep $PREP
  assert_eq "prep ok: exit" 0 "$rc"
}

# ---- the script is executable in the index -------------------------------------------------
assert_eq "lane.sh is committed as 100755" 100755 "$($real_git -C "$root_dir" ls-files -s scripts/lanes/lane.sh | awk '{print $1}')"

# ---- arguments: exit 2, no output, no git or gh call ---------------------------------------
nc
nl() { printf '%s\n%s' "$1" "$2"; }
argcase() { # <desc> <args...>
  d=$1
  shift
  : >"$FX_LOG"
  : >"$FX_GHLOG"
  run_lane "$@"
  assert_eq "arg $d: exit" 2 "$rc"
  assert_eq "arg $d: stdout" "" "$out"
  assert_empty_file "arg $d: git log" "$FX_LOG"
  assert_empty_file "arg $d: gh log" "$FX_GHLOG"
}
for v in 0 012 abc ''; do
  argcase "N [$v]" prep "$v" $MS $BR $CR
  argcase "M [$v]" prep $ISSUE "$v" $BR $CR
done
argcase "N newline" prep "$(nl 7 8)" $MS $BR $CR
argcase "M newline" prep $ISSUE "$(nl 7 8)" $BR $CR
argcase "done N 0" done 0
argcase "done N newline" done "$(nl 7 8)"
argcase "no mode"
argcase "bad mode" frob 1
argcase "prep arg count" prep $ISSUE $MS $BR
argcase "done arg count" done 1 2
for v in main feat/ sprint/1-x feat/A feat/a.b style/x feat/-a feat/a/b ''; do
  argcase "BRANCH [$v]" prep $ISSUE $MS "$v" $CR
done
argcase "BRANCH newline" prep $ISSUE $MS "$(nl feat/a feat/b)" $CR
for v in '' bogus architect,architect architect, ,architect architect,,docs-consistency; do
  argcase "CRITICS [$v]" prep $ISSUE $MS $BR "$v"
done
argcase "CRITICS newline" prep $ISSUE $MS $BR "$(nl architect architect)"
LD_SAVE=$LD
for v in rel/x '/a/$(id)' / /a/ /a//b /a/./b /a/../b /a/.. '/a b' ''; do
  LD=$v
  argcase "WOW_LANES_DIR [$v]" prep $PREP
done
LD=$(nl /a /b)
argcase "WOW_LANES_DIR newline" prep $PREP
LD=$LD_SAVE

# ---- the main-worktree check ---------------------------------------------------------------
nc
$real_git -C "$R" worktree add -q "$D/other" -b other
CWD="$D/other"
run_lane prep $PREP
assert_eq "not-main from a linked worktree (prep): exit" 1 "$rc"
assert_eq "not-main from a linked worktree (prep): stdout" not-main "$out"
run_lane done $ISSUE
assert_eq "not-main from a linked worktree (done): stdout" not-main "$out"
assert_empty_file "not-main: gh log" "$FX_GHLOG"
CWD="$D"
run_lane prep $PREP
assert_eq "not-main outside a work tree: stdout" not-main "$out"
nc
mkdir -p "$D/lanes"
$real_git -C "$R" worktree add -q "$D/lanes/1" -b lane1
CWD="$D/lanes/1"
run_lane prep $PREP
assert_eq "not-main from inside LANES: stdout" not-main "$out"

# ---- the default-branch read ---------------------------------------------------------------
nc
FX_FAIL=repoview
stop_case "failed repo view" 1 unreadable prep $PREP
nc
FX_GIT_FAIL=" fetch "
stop_case "failed fetch" 1 unreadable prep $PREP
nc
FX_GIT_FAIL=" archive "
stop_case "failed git archive" 1 unreadable prep $PREP
nc
setyml '.pr_base = "-x"'
stop_case "bad pr_base" 1 unreadable prep $PREP
nc
setyml '.pr_base = "a b"'
stop_case "pr_base with a space" 1 unreadable prep $PREP
nc
setyml '.backlog.repo = "a/b/c"'
stop_case "bad backlog.repo" 1 unreadable prep $PREP
nc
setyml '.backlog.repo = "a/.."'
stop_case "backlog.repo with a .. part" 1 unreadable prep $PREP
nc
$real_git -C "$R" rm -q -r plugins/way-of-working/bin
mkdir -p "$R/elsewhere" "$R/plugins/way-of-working"
printf 'x\n' >"$R/elsewhere/spec-find.sh"
ln -s ../../elsewhere "$R/plugins/way-of-working/bin"
bump
stop_case "committed bin/ is a symbolic link" 1 unreadable prep $PREP
nc
$real_git -C "$R" rm -q plugins/way-of-working/bin/spec-find.sh
ln -s gh-identity.sh "$R/plugins/way-of-working/bin/spec-find.sh"
bump
stop_case "committed spec-find.sh is a symbolic link" 1 unreadable prep $PREP
nc
$real_git -C "$R" rm -q plugins/way-of-working/bin/spec-reaction.sh
bump
stop_case "a required script is missing" 1 unreadable prep $PREP
nc
$real_git -C "$R" rm -q plugins/way-of-working/bin/declared-ids.sh
bump
stop_case "a required script is missing (declared-ids.sh)" 1 unreadable prep $PREP
nc
setyml '.repo = "other/repo"'
stop_case "repo-mismatch" 1 repo-mismatch prep $PREP
nc
setyml '.identities = null'
stop_case "not-map under identities: null" 1 not-map prep $PREP
nc
setyml '.identities = null'
cp "$tmp/project.yml.tpl" "$R/.ai/project.yml"
stop_case "not-map when only the working tree has a map" 1 not-map prep $PREP
nc
prep_ok
assert_has "backlog.repo: null makes the issue path use .repo" "$FX_GHLOG" "api repos/glunk-works/claude-workbench/issues/$ISSUE --jq "
nc
setyml '.backlog.repo = "glunk-works/backlog"'
prep_ok
assert_has "backlog.repo names the issue path" "$FX_GHLOG" "api repos/glunk-works/backlog/issues/$ISSUE --jq "
assert_has "backlog.repo: the prompt makes no milestone write" "$LD/$ISSUE-prompt.md" "5. Make no milestone write: milestone \`$MS\` is in the backlog repository"
if grep -F "PATCH" "$LD/$ISSUE-prompt.md" >/dev/null; then
  echo "FAIL - backlog.repo: the prompt carries a PATCH" >&2
  fail=1
else
  echo "ok - backlog.repo: the prompt carries no PATCH"
fi

nc
put .ai/project.yml "$(yq '.identities = null' "$R/.ai/project.yml")"
$real_git -C "$R" add -A && $real_git -C "$R" commit -q -m local-only
prep_ok
assert_eq "trust root: an unpushed local edit to the project file is not read" "worktree=$LD/$ISSUE" "$(printf '%s\n' "$out" | awk 'NR==1')"
nc
mkdir -p "$D/lanes"
$real_git clone -q "$O" "$D/lanes/clone"
CWD="$D/lanes/clone"
run_lane prep $PREP
assert_eq "not-main from a main worktree under LANES: stdout" not-main "$out"
assert_eq "not-main from a main worktree under LANES: exit" 1 "$rc"

# ---- the trust root ------------------------------------------------------------------------
nc
printf 'none\n' >"$CAN/find.txt"
printf '#!/bin/sh\necho "found 9 2026-10-18T00:00:00Z"\n' >"$R/plugins/way-of-working/bin/spec-find.sh"
mkdir -p "$R/bin"
printf '#!/bin/sh\ntouch "%s/gh-ran"\n' "$D" >"$R/bin/gh"
chmod +x "$R/bin/gh" "$R/plugins/way-of-working/bin/spec-find.sh"
stop_case "trust root: the working tree's spec-find.sh is not used" 1 "finder: none" prep $PREP
# The script never puts a checkout directory on PATH, so this only guards against it starting to.
assert_eq "trust root: a working-tree bin/gh is not run" no "$([ -e "$D/gh-ran" ] && echo yes || echo no)"

# ---- the milestone step names the M passed to prep -----------------------------------------
nc
canon '.milestone.number = 23'
run_lane prep $ISSUE 23 $BR $CR
assert_eq "milestone 23: exit" 0 "$rc"
assert_has "milestone 23: the read names 23" "$LD/$ISSUE-prompt.md" "gh api repos/glunk-works/claude-workbench/milestones/23 --jq .state"
assert_has "milestone 23: the PATCH names 23" "$LD/$ISSUE-prompt.md" "issues/\$P -F milestone=23 --jq .milestone.number"
if grep -F "milestone=$MS " "$LD/$ISSUE-prompt.md" >/dev/null; then
  echo "FAIL - milestone 23: the prompt still names $MS" >&2
  fail=1
else
  echo "ok - milestone 23: the prompt does not name $MS"
fi

# ---- prep with found -----------------------------------------------------------------------
nc
prep_ok
BOID=$($real_git -C "$R" rev-parse refs/remotes/origin/main)
prompt="$LD/$ISSUE-prompt.md"
want=$(printf 'worktree=%s\nbranch=%s\nfound=5001 2026-10-18T00:00:00Z\nmilestone=%s\nprompt=%s\nprompt-sha256=%s' "$LD/$ISSUE" "$BR" "$MS" "$prompt" "$(sha256sum "$prompt" | awk '{print $1}')")
assert_eq "prep: the six output lines" "$want" "$out"
assert_eq "prep: worktree is on BRANCH" "$BR" "$($real_git -C "$LD/$ISSUE" symbolic-ref --short HEAD)"
assert_eq "prep: worktree is at origin/main's commit" "$BOID" "$($real_git -C "$LD/$ISSUE" rev-parse HEAD)"
if $real_git -C "$LD/$ISSUE" rev-parse '@{u}' >/dev/null 2>&1; then
  echo "FAIL - prep: the branch has an upstream" >&2
  fail=1
else
  echo "ok - prep: the branch has no upstream"
fi
assert_eq "prep: LANES is mode 700" 700 "$(stat -c %a "$LD")"
assert_eq "prep: no group or world access to the prompt" 0 "$(($(printf '0%s' "$(stat -c %a "$prompt")") & 077))"
assert_eq "prep: no temp name left in LANES" "$ISSUE
$ISSUE-prompt.md" "$(ls -A "$LD")"
sed -e "s#@LANES@#$LD#g" >"$D/golden" <<'GOLDEN'
# Lane prompt: glunk-works/claude-workbench#727

You are a **lane**. For this one task you act as the `coder` defined in `plugins/way-of-working/agents/coder.md` in this worktree. The driver session that ran `lane.sh prep` is your spawner.

## Task

- **Task:** `glunk-works/claude-workbench#727`, on milestone `19`.
- **Missing state file:** this worktree has no `.ai/state.json`. Wherever `coder.md` refers to `plan_anchor.task_issue`, use `727`. Wherever it refers to the anchor's milestone, use `19`.
- **Mode:** `map`.
- **Spec:** the spawner names the found pair `found 5001 2026-10-18T00:00:00Z`. The pin is `PIN_ID='5001'` and `PIN_UP='2026-10-18T00:00:00Z'`.

## PATH: on every Bash call that runs a plugin script

A Bash tool call does not keep exports from earlier calls. So every Bash call that runs a plugin `bin/` script (`spec-find.sh`, `spec-comment.sh`, `spec-fresh.sh`, `gh-identity.sh`, `spec-reaction.sh` and the rest) starts with this line, which also checks that the worktree's scripts, not the installed plugin's older ones, are the ones found:

    export PATH='@LANES@/727/plugins/way-of-working/bin':"$PATH" && [ "$(command -v spec-find.sh)" = @LANES@/727/plugins/way-of-working/bin/spec-find.sh ] || { echo "PATH check failed"; exit 1; }

If that check fails, stop and report.

## Order of work

1. Build the task per `coder.md`.
2. Run every `gates.green` entry in `.ai/project.yml`, then `bash scripts/test-all.sh` in its own Bash call with the tool's maximum timeout (600000 ms); if that call times out, stop and report.
3. Run `/way-of-working:critic-gate` as written and let its own proposal stand. The driver expects the critics `architect,security-critic`. If critic-gate's proposal differs, show both lists to the human in the pick-list. That list is not the explicit-names shortcut, which only names the human types count for.
4. Commit and open the PR with `/way-of-working:ship`. This is the explicit instruction to commit and push that `coder.md` asks for.
5. Set this PR's milestone, only when ship's author check passed and ship reported the PR URL; `P` is the number at the end of that URL. In one Bash call, capture each value into a variable, check it is non-empty and chain with `&&`: require `P` to be digits with no leading zero; require `gh api repos/glunk-works/claude-workbench/pulls/$P --jq .head.ref` to print what `git branch --show-current` prints; require `gh api repos/glunk-works/claude-workbench/milestones/19 --jq .state` to print `open`; then run `gh api -X PATCH repos/glunk-works/claude-workbench/issues/$P -F milestone=19 --jq .milestone.number`, setting no other field. The milestone is set only when that last call prints `19`. Any other outcome (a `P` that is not digits, a branch mismatch, a closed milestone, a failed read, a PATCH that failed or the session refused, another number printed) is no further write. Report the outcome in your final message either way, and never retry with another value or another command.

## Lane rules

- Never run `/way-of-working:resume`, `/way-of-working:handoff`, `/way-of-working:plan-sprint` or `/way-of-working:archive-sprint`. Never write anything under `.ai/`.
- Never merge, approve or force-push.
- Work only in `@LANES@/727`, never in `/workspace`'s working tree.
- A session that read the issue body or drafted the spec never builds the issue.
- Every PR needs a code-owner approval, and approving a PR with auto-merge armed merges it.

## Identity

- Do not prefix commands with `GH_TOKEN`.
- Commits are unsigned (`WB-D25`).
GOLDEN
if cmp -s "$D/golden" "$prompt"; then
  echo "ok - prep: the prompt matches the golden file byte for byte"
else
  echo "FAIL - prep: the prompt differs from the golden file" >&2
  diff "$D/golden" "$prompt" >&2 || :
  fail=1
fi
assert_has "prep: the PATH line has a literal \$PATH" "$prompt" "/plugins/way-of-working/bin':\"\$PATH\" && [ \"\$(command -v spec-find.sh)\" = "
if grep -F "$SENT" "$prompt" >/dev/null; then
  echo "FAIL - the sentinel is in the prompt" >&2
  fail=1
else
  echo "ok - the sentinel is not in the prompt"
fi
assert_eq "prep: the logged git calls start from the top level" 0 "$(grep -v "^-C " "$FX_LOG" | grep -vc "^rev-parse --show-toplevel$" || :)"

nc
CWD="$R/dir"
prep_ok
assert_eq "prep from a subdirectory: the six lines" 6 "$(printf '%s\n' "$out" | awk 'END {print NR}')"
assert_eq "prep from a subdirectory: the worktree" "worktree=$LD/$ISSUE" "$(printf '%s\n' "$out" | awk 'NR==1')"

# ---- prep, finder lines --------------------------------------------------------------------
finder_case() { # <desc> <expected stdout> <find.txt content> [rc]
  nc
  printf '%s' "$3" >"$CAN/find.txt"
  FX_FIND_RC=${4:-0}
  export FX_FIND_RC
  stop_case "finder $1" 1 "$2" prep $PREP
  assert_eq "finder $1: no prompt file" no "$([ -e "$LD/$ISSUE-prompt.md" ] && echo yes || echo no)"
}
finder_case none "finder: none" 'none
'
finder_case unreacted "finder: unreacted" 'unreacted 5
'
finder_case escalated "finder: escalated" 'escalated 5
'
finder_case ambiguous "finder: ambiguous" 'ambiguous 5,6
'
finder_case moved "finder: moved" 'moved 5
'
finder_case unreadable "finder: unreadable" 'unreadable
'
finder_case "an empty output" "finder: unreadable" ''
finder_case "a non-zero exit" "finder: unreadable" 'none
' 1
finder_case "a found line with a leading zero" "finder: unreadable" 'found 05 2026-10-18T00:00:00Z
'
finder_case "a found line with two fields" "finder: unreadable" 'found 5
'
finder_case "a found line with a bad time" "finder: unreadable" 'found 5 2026-10-18
'
finder_case "two lines" "finder: unreadable" 'found 5 2026-10-18T00:00:00Z
found 6 2026-10-18T00:00:00Z
'
finder_case "an unknown word" "finder: unreadable" 'frob 5
'

# ---- prep, exists --------------------------------------------------------------------------
exists_case() { # <desc> <setup function>
  nc
  mkdir -m 700 "$LD"
  $2
  stop_case "exists: $1" 1 exists prep $PREP
}
s_wtpath() { mkdir "$LD/$ISSUE"; }
s_promptfile() { : >"$LD/$ISSUE-prompt.md"; }
s_dangling() { ln -s "$D/nowhere" "$LD/$ISSUE-prompt.md"; }
s_gonewt() {
  $real_git -C "$R" worktree add -q "$LD/$ISSUE" -b other
  rm -rf "${LD:?}/$ISSUE"
}
s_localbranch() { $real_git -C "$R" branch "$BR"; }
s_remotebranch() { $real_git -C "$R" push -q origin "HEAD:refs/heads/$BR"; }
s_trackingref() { $real_git -C "$R" update-ref "refs/remotes/origin/$BR" HEAD; }
s_config() { $real_git -C "$R" config "branch.$BR.merge" refs/heads/foo; }
exists_case "an existing worktree path" s_wtpath
exists_case "an existing prompt file" s_promptfile
exists_case "a dangling symbolic link at the prompt path" s_dangling
exists_case "a registered worktree whose directory is gone" s_gonewt
exists_case "an existing local branch" s_localbranch
exists_case "an existing remote branch" s_remotebranch
exists_case "a lingering refs/remotes/origin/BRANCH" s_trackingref
exists_case "a leftover branch.BRANCH.merge key" s_config

# ---- prep, the lanes directory -------------------------------------------------------------
nc
mkdir "$D/real"
ln -s "$D/real" "$LD"
stop_case "LANES is a symbolic link to a directory" 1 unsafe-dir prep $PREP
nc
: >"$LD"
stop_case "LANES is a regular file" 1 unsafe-dir prep $PREP
nc
LD="$D/nope/lanes"
stop_case "LANES has a missing parent" 1 unsafe-dir prep $PREP
nc
mkdir "$D/q'q" "$D/q'q/lanes"
ln -s "$D/q'q" "$D/linkp"
LD="$D/linkp/lanes"
stop_case "a parent link to a directory whose name has a quote (LANES exists)" 1 unsafe-dir prep $PREP
nc
mkdir "$D/q'q"
ln -s "$D/q'q" "$D/linkp"
LD="$D/linkp/lanes"
run_lane prep $PREP
assert_eq "a parent link to a directory whose name has a quote (LANES new): stdout" unsafe-dir "$out"
assert_eq "a parent link to a quoted directory: nothing created" "" "$(ls -A "$D/q'q")"
nc
mkdir -m 755 "$LD"
printf 'none\n' >"$CAN/find.txt"
stop_case "a stop before step 7 keeps LANES at 755" 1 "finder: none" prep $PREP
assert_eq "a stop before step 7: still 755" 755 "$(stat -c %a "$LD")"
nc
mkdir -m 755 "$LD"
prep_ok
assert_eq "an existing LANES at 755 is 700 after prep" 700 "$(stat -c %a "$LD")"
nc
printf 'none\n' >"$CAN/find.txt"
stop_case "a stop before step 7 with no LANES leaves none" 1 "finder: none" prep $PREP

# ---- prep, the issue -----------------------------------------------------------------------
issue_case() { # <desc> <word> <jq expression>
  nc
  canon "$3"
  stop_case "issue $1" 1 "$2" prep $PREP
}
issue_case "closed" bad-issue '.state = "closed"'
issue_case "a pull request" bad-issue '. + {pull_request: {url: "x"}}'
issue_case "on another milestone" bad-issue '.milestone.number = 3'
issue_case "with no milestone" bad-issue '.milestone = null'
issue_case "with another number" bad-issue '.number = 728'
nc
FX_FAIL=issue
stop_case "issue read failed" 1 unreadable prep $PREP

# ---- prep, rollback ------------------------------------------------------------------------
nc
FX_GIT_FAIL=" worktree add "
stop_case "rollback: a failing worktree add" 1 failed prep $PREP
nc
FX_GIT_FAIL=" rev-parse --verify -q HEAD "
stop_case "rollback: a failing HEAD check" 1 failed prep $PREP
assert_eq "rollback: no worktree directory after a HEAD check" no "$([ -e "$LD/$ISSUE" ] && echo yes || echo no)"
nc
FX_LN_FAIL=1
stop_case "rollback: a failing ln" 1 failed prep $PREP
assert_eq "rollback: no worktree directory after ln" no "$([ -e "$LD/$ISSUE" ] && echo yes || echo no)"
nc
mkdir -m 700 "$LD"
FX_LN_FAIL=1
stop_case "rollback: an existing LANES survives a failing ln" 1 failed prep $PREP
nc
put dir/g two
$real_git -C "$R" add -A && $real_git -C "$R" commit -q -m other
OTHER=$($real_git -C "$R" rev-parse HEAD)
FX_PRE="update-ref refs/heads/$BR $OTHER"
FX_PRE_ON=" worktree add "
export FX_PRE FX_PRE_ON
run_lane prep $PREP
assert_eq "rollback: another process's branch: stdout" failed "$out"
assert_eq "rollback: another process's branch is not deleted" "$OTHER" "$($real_git -C "$R" rev-parse --verify -q "refs/heads/$BR" || echo gone)"

nc
FX_PRE="worktree add -q $D/racer -b $BR refs/remotes/origin/main"
FX_PRE_ON=" worktree add --no-track "
export FX_PRE FX_PRE_ON
run_lane prep $PREP
assert_eq "rollback: a branch another prep has checked out: stdout" failed "$out"
assert_eq "rollback: a branch checked out elsewhere is not deleted" "$($real_git -C "$R" rev-parse refs/remotes/origin/main)" "$($real_git -C "$R" rev-parse --verify -q "refs/heads/$BR" || echo gone)"

nc
FX_PRE_SH="mkdir $D/evil && ln -s $D/evil $LD/$ISSUE"
FX_PRE_ON=" worktree add "
export FX_PRE_SH FX_PRE_ON
run_lane prep $PREP
assert_eq "rollback: a link planted at the worktree path: stdout" failed "$out"
assert_eq "rollback: a link planted at the worktree path: no branch left" gone "$($real_git -C "$R" rev-parse --verify -q "refs/heads/$BR" || echo gone)"
assert_eq "rollback: a link planted at the worktree path: no prompt file" no "$([ -e "$LD/$ISSUE-prompt.md" ] && echo yes || echo no)"
nc
FX_PRE="worktree add -q $LD/$ISSUE -b racer refs/remotes/origin/main"
FX_PRE_ON=" worktree add --no-track "
export FX_PRE FX_PRE_ON
mkdir -m 700 "$LD"
run_lane prep $PREP
assert_eq "rollback: a racing worktree at the path: stdout" failed "$out"
assert_eq "rollback: a racing worktree at the path survives" yes "$([ -d "$LD/$ISSUE" ] && echo yes || echo no)"
assert_eq "rollback: a racing worktree at the path is still listed" 1 "$($real_git -C "$R" worktree list --porcelain | grep -Fxc "worktree $LD/$ISSUE")"
assert_eq "rollback: a racing worktree at the path: our branch is gone" gone "$($real_git -C "$R" rev-parse --verify -q "refs/heads/$BR" || echo gone)"

nc
FX_PRE_SH='kill -TERM $PPID'
FX_PRE_ON=" worktree add "
export FX_PRE_SH FX_PRE_ON
before=$(snap)
run_lane prep $PREP
assert_eq "rollback: a signal during the add: stdout" failed "$out"
assert_eq "rollback: a signal during the add: nothing left" "$before" "$(snap)"
FX_PRE_SH=
export FX_PRE_SH

# ---- done ----------------------------------------------------------------------------------
# lane_ready: prep, then a commit on the lane's branch that "merged" (the canned PR row).
lane_ready() {
  nc
  prep_ok
  $real_git -C "$LD/$ISSUE" commit -q --allow-empty -m work
  TIP=$($real_git -C "$LD/$ISSUE" rev-parse HEAD)
  $real_git -C "$R" config "branch.$BR.remote" origin
  $real_git -C "$R" config "branch.$BR.merge" "refs/heads/$BR"
  pr_rows "$TIP"
}
pr_rows() { # <oid>
  cat >"$CAN/prs.json" <<EOF
[{"number":9,"headRefOid":"$1","isCrossRepository":false,"title":"$SENT"}]
EOF
}
lane_ready
run_lane done $ISSUE
assert_eq "done: exit" 0 "$rc"
assert_eq "done: the three lines" "removed-worktree $LD/$ISSUE
deleted-branch $BR
removed-prompt $LD/$ISSUE-prompt.md" "$out"
assert_eq "done: the worktree is gone" no "$([ -e "$LD/$ISSUE" ] && echo yes || echo no)"
assert_eq "done: the branch is gone" gone "$($real_git -C "$R" rev-parse --verify -q "refs/heads/$BR" || echo gone)"
assert_eq "done: every branch.X.* key is gone" "" "$($real_git -C "$R" config --get-regexp '^branch\.feat/x\.' || :)"
assert_eq "done: the prompt file is gone" no "$([ -e "$LD/$ISSUE-prompt.md" ] && echo yes || echo no)"
assert_has "done: the exact pr list arguments" "$FX_GHLOG" "pr list --repo glunk-works/claude-workbench --base main --head $BR --state merged --json number,headRefOid,isCrossRepository --jq "

lane_ready
CWD="$R/dir"
run_lane done $ISSUE
assert_eq "done from a subdirectory: the first line" "removed-worktree $LD/$ISSUE" "$(printf '%s\n' "$out" | awk 'NR==1')"

lane_ready
rm -f "$LD/$ISSUE-prompt.md"
run_lane done $ISSUE
assert_eq "done: no prompt file" "removed-worktree $LD/$ISSUE
deleted-branch $BR
no-prompt" "$out"

lane_ready
$real_git -C "$R" worktree add -q -f "$D/second" "$BR"
stop_case "done: checked out elsewhere (nothing removed)" 1 "kept $BR checked-out" done $ISSUE
assert_eq "done: checked out elsewhere: the branch survives" "$TIP" "$($real_git -C "$R" rev-parse "refs/heads/$BR")"
assert_eq "done: checked out elsewhere: the lane worktree stays" yes "$([ -d "$LD/$ISSUE" ] && echo yes || echo no)"

lane_ready
FX_PRE="-C $R worktree add -q -f $D/second $BR"
FX_PRE_ON=" worktree remove "
export FX_PRE FX_PRE_ON
run_lane done $ISSUE
assert_eq "done: checked out during the run: stdout" "kept $BR checked-out" "$out"
assert_eq "done: checked out during the run: the worktree is gone" no "$([ -e "$LD/$ISSUE" ] && echo yes || echo no)"
assert_eq "done: checked out during the run: the branch survives" "$TIP" "$($real_git -C "$R" rev-parse "refs/heads/$BR")"
assert_eq "done: checked out during the run: the prompt file stays" yes "$([ -e "$LD/$ISSUE-prompt.md" ] && echo yes || echo no)"

lane_ready
$real_git -C "$LD/$ISSUE" commit -q --allow-empty -m ahead
stop_case "done: a local commit the merged head lacks" 1 "kept $BR skip-ahead" done $ISSUE
lane_ready
pr_rows deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
stop_case "done: an oid absent from origin" 1 "kept $BR skip-unfetchable" done $ISSUE
lane_ready
printf '[]\n' >"$CAN/prs.json"
stop_case "done: no merged PR" 1 not-merged done $ISSUE
lane_ready
cat >"$CAN/prs.json" <<EOF
[{"number":9,"headRefOid":"$TIP","isCrossRepository":true,"title":"$SENT"}]
EOF
stop_case "done: only a cross-repository PR" 1 not-merged done $ISSUE
lane_ready
cat >"$CAN/prs.json" <<EOF
[{"number":9,"headRefOid":"$TIP","isCrossRepository":false},{"number":10,"headRefOid":"$TIP","isCrossRepository":false}]
EOF
stop_case "done: two rows" 1 ambiguous done $ISSUE
lane_ready
pr_rows abc123
stop_case "done: a short oid" 1 unreadable done $ISSUE
lane_ready
FX_FAIL=prlist
stop_case "done: a failed gh" 1 unreadable done $ISSUE
nc
stop_case "done: an absent lane" 1 no-lane done $ISSUE
lane_ready
$real_git -C "$LD/$ISSUE" checkout -q --detach
stop_case "done: a detached lane" 1 no-lane done $ISSUE
lane_ready
$real_git -C "$LD/$ISSUE" checkout -q --ignore-other-worktrees main
stop_case "done: a lane switched to main" 1 no-lane done $ISSUE
lane_ready
rm -rf "${LD:?}/$ISSUE"
stop_case "done: a lane whose directory is gone" 1 missing done $ISSUE
lane_ready
: >"$LD/$ISSUE/untracked"
stop_case "done: a dirty worktree" 1 dirty done $ISSUE
assert_eq "done: dirty: the prompt file is still there" yes "$([ -e "$LD/$ISSUE-prompt.md" ] && echo yes || echo no)"

lane_ready
FX_PRE="-C $LD/$ISSUE commit -q --allow-empty -m late"
FX_PRE_ON=" worktree remove "
export FX_PRE FX_PRE_ON
run_lane done $ISSUE
assert_eq "done: a commit after the verdict: stdout" "kept $BR moved" "$out"
assert_eq "done: a commit after the verdict: exit" 1 "$rc"
assert_eq "done: moved: the branch survives with that commit" "late" "$($real_git -C "$R" log -1 --format=%s "refs/heads/$BR")"
assert_eq "done: moved: the worktree is gone" no "$([ -e "$LD/$ISSUE" ] && echo yes || echo no)"
assert_eq "done: moved: the prompt file is still present" yes "$([ -e "$LD/$ISSUE-prompt.md" ] && echo yes || echo no)"

lane_ready
setyml '.identities = null'
stop_case "done: not-map removes nothing" 1 not-map done $ISSUE
lane_ready
setyml '.repo = "other/repo"'
stop_case "done: repo-mismatch removes nothing" 1 repo-mismatch done $ISSUE

# ---- the sentinel --------------------------------------------------------------------------
if grep -F "$SENT" "$tmp/allout" >/dev/null; then
  echo "FAIL - the sentinel appears in some stdout or stderr" >&2
  fail=1
else
  echo "ok - the sentinel appears in no stdout or stderr"
fi

exit "$fail"
