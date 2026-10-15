#!/bin/sh
# Fixture tests for scripts/invariants-check.sh's check 18: the spec-task skill drafts and
# never posts -- its text carries no comment command and no `gh api` write (#611).
#
# Each case mutates a COPY of the real tree and asserts the check fires (or stays silent), so
# a check that only passes on the real tree cannot hide. Only check 18's own message is
# asserted, never the script's overall exit.
#
# Permitted toolset: POSIX sh. No jq, no yq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/scripts/invariants-check.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
MSG="the spec-task skill contains a posting form"

tree() {
  d="$tmp/$1"
  mkdir -p "$d"
  cp -R "$root_dir/plugins" "$d/plugins"
  echo "$d"
}

run() { ( cd "$1" && bash "$script" 2>&1 >/dev/null ) || true; }

assert_fires() { # <desc> <dir>
  if run "$2" | grep -qF -- "$MSG"; then
    echo "ok - $1"
  else
    echo "FAIL - $1: expected check 18 to fire" >&2
    fail=1
  fi
}

assert_silent() { # <desc> <dir>
  if run "$2" | grep -qF -- "$MSG"; then
    echo "FAIL - $1: check 18 fired" >&2
    fail=1
  else
    echo "ok - $1"
  fi
}

skill() { ls "$1"/plugins/*/skills/spec-task/SKILL.md; }

# Control: the real tree is clean.
d="$(tree control)"
assert_silent "real tree passes" "$d"

# Each posting form fires.
n=0
for form in \
  'gh issue comment 611 --body-file draft.md' \
  'gh pr comment 12 --body hi' \
  'gh   issue   comment 611 -F draft.md' \
  'gh api repos/o/r/issues/611/comments -f body=hi' \
  'gh api repos/o/r/issues/611/comments -F body=@draft.md' \
  'gh api repos/o/r/issues/611/comments --field body=hi' \
  'gh api repos/o/r/issues/611/comments --raw-field body=hi' \
  'gh api repos/o/r/issues/611/comments --input draft.json' \
  'gh api -X POST repos/o/r/issues/611/comments' \
  'gh api --method PATCH repos/o/r/issues/comments/1' \
  'gh api --method=PUT repos/o/r/issues/comments/1' \
  'gh api repos/o/r/issues/comments/1 -X post' \
  'gh api repos/o/r/issues/comments/1/reactions -f content=+1' \
  'gh api -X DELETE repos/o/r/issues/comments/1' \
  'gh api --method DELETE repos/o/r/issues/comments/1' \
  'gh api --method "POST" repos/o/r/issues/611/comments' \
  "gh api -X 'PATCH' repos/o/r/issues/comments/1" \
  'gh api repos/o/r/issues/611/comments -fbody=hi' \
  'gh api repos/o/r/issues/611/comments "-f" body=hi' \
  'gh issue -R o/r comment 611 --body-file draft.md' \
  'gh pr --repo o/r comment 12 --body hi' \
  'gh pr review 12 --comment -b hi' \
  'gh issue edit 611 --add-label x' \
  'gh issue close 611' \
  'gh issue create --title x' \
  'gh label create x' \
  'gh issue new --title x' \
  'gh pr new --title x' \
  'gh api repos/o/r/issues/1/comments "-X" POST' \
  "gh api repos/o/r/issues/1/comments '--method' PATCH" \
  'gh api -iX POST repos/o/r/issues/1/comments' \
  'gh api -if body=x repos/o/r/issues/1/comments' \
  'gh "api" repos/o/r/issues/1/comments -f body=x' \
  "gh 'issue' comment 1" \
  'gh.exe issue comment 1 --body x' \
  'GH issue comment 5 --body x' \
  'gh -R o/r issue comment 1 --body x' \
  'gh -R o/r label create x' \
  'gh -X POST api repos/o/r/issues/1/comments' \
  'gh --method POST api repos/o/r/issues/1/comments' \
  'gh -f body=x api repos/o/r/issues/1/comments' \
  'gh --repo o/r pr comment 1 --body x' \
  'gh.EXE issue comment 1 --body x' \
  'GH api -X POST repos/o/r/issues/1/comments' \
  'gh.exe api repos/o/r/issues/1/comments -f body=x' \
  'jq -n "{body:1}" | gh api repos/o/r/issues/1/comments --input -' \
  'T=$(mktemp -d) && gh api repos/o/r/issues/1/comments -X POST' \
  "gh api repos/o/r/issues/1/comments --jq '.a|.b' -f body=x" \
  "gh api 'repos/o/r/issues/1/comments?a=b&c=d' -X POST" \
  'gh pr merge 12 --squash' \
  'gh pr ready 12' \
  'gh issue pin 611' \
  'gh issue develop 611' \
  'gh pr update-branch 12' \
  'gh issue "comment" 611'; do
  n=$((n + 1))
  d="$(tree "form$n")"
  printf '%s\n' "$form" >>"$(skill "$d")"
  assert_fires "a posting form fires: $form" "$d"
done

# A wrapped command is joined before the test.
d="$(tree wrapped)"
printf '%s\n' 'gh api repos/o/r/issues/611/comments \' '  -f body=hi' >>"$(skill "$d")"
assert_fires "a wrapped gh api write fires" "$d"

d="$(tree wrappedcomment)"
printf '%s\n' 'gh issue \' '  comment 611' >>"$(skill "$d")"
assert_fires "a wrapped comment command fires" "$d"

# A CRLF checkout joins wrapped lines too.
d="$(tree crlf)"
printf 'gh api repos/o/r/issues/611/comments \\\r\n  -f body=hi\r\n' >>"$(skill "$d")"
assert_fires "a wrapped gh api write in a CRLF file fires" "$d"

# A posting form in an appendix fires too.
d="$(tree appendix)"
mkdir -p "$(dirname "$(skill "$d")")/appendices"
printf '%s\n' 'gh issue comment 611 --body-file draft.md' >"$(dirname "$(skill "$d")")/appendices/post.md"
assert_fires "a posting form in an appendix fires" "$d"

# Reads are legal: a plain fetch, a projected fetch, an unrelated -f on a non-gh line.
d="$(tree reads)"
printf '%s\n' \
  'gh api repos/o/r/issues/611 >"$T/issue.json"' \
  'gh api repos/o/r/issues/611 --jq .user.login' \
  'gh api --paginate repos/o/r/issues/611/comments' \
  'gh api repos/o/r --jq .permissions' \
  'gh repo view o/r --json defaultBranchRef --jq .defaultBranchRef.name' \
  'gh issue view 611 --json title' \
  'Check the high label on the issue, enough labels.' \
  'gh pr list --state open --json number' \
  'git fetch -q origin "+refs/heads/main:refs/remotes/origin/main"' \
  'tar -f archive.tar -x' >>"$(skill "$d")"
assert_silent "reads and non-gh -f flags are legal" "$d"

# A missing skill fails, never passes.
d="$(tree noskill)"
rm -rf "$d"/plugins/*/skills/spec-task
assert_fires "a missing spec-task skill fires" "$d"

[ "$fail" -eq 0 ]
