#!/bin/sh
# Fixture tests for scripts/invariants-check.sh's check 17: the spec comment is printed only
# after its checks pass -- resume, architect-review and the coder each call spec-comment.sh,
# none fetches the comment unprojected and unredirected (#614), each names spec-find.sh and none
# lists a task issue's comments (WB-D30).
# resume and the coder also name spec-fresh.sh, which exists and makes no gh call (#663).
#
# Each case mutates a COPY of the real tree and asserts the check fires (or stays silent), so
# a check that only passes on the real tree cannot hide. Only check 17's own message is
# asserted, never the script's overall exit.
#
# Every case but the first control runs just check 17 (`--only 17`); that control runs the full checker.
#
# Permitted toolset: POSIX sh. No jq, no yq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/scripts/invariants-check.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
MSG="the spec comment may reach context before its checks pass"

tree() {
  d="$tmp/$1"
  mkdir -p "$d"
  cp -R "$root_dir/plugins" "$d/plugins"
  echo "$d"
}

sel="--only 17"

run() { ( cd "$1" || exit 1; rc=0; bash "$script" $sel 2>&1 >/dev/null || rc=$?; [ "$rc" -ne 2 ] || : >"$tmp/usage-exit" ) || true; }

assert_fires() { # <desc> <dir>
  if run "$2" | grep -qF -- "$MSG"; then
    echo "ok - $1"
  else
    echo "FAIL - $1: expected check 17 to fire" >&2
    fail=1
  fi
}

assert_silent() { # <desc> <dir>
  if run "$2" | grep -qF -- "$MSG"; then
    echo "FAIL - $1: check 17 fired" >&2
    fail=1
  else
    echo "ok - $1"
  fi
}

# Control: the real tree is clean.
sel=
d="$(tree control)"
assert_silent "real tree passes" "$d"
sel="--only 17"

# Each of the three readers no longer calling the script fires.
for pat in skills/resume/SKILL.md skills/architect-review/SKILL.md agents/coder.md; do
  d="$(tree "nocall-$(basename "$(dirname "$pat")")")"
  f="$(ls "$d"/plugins/*/"$pat")"
  sed 's/spec-comment\.sh/some-other-check.sh/g' "$f" >"$f.new" && mv "$f.new" "$f"
  assert_fires "$pat without a spec-comment.sh call fires" "$d"
done

# Each of the three readers no longer naming spec-find.sh fires (WB-D30).
for pat in skills/resume/SKILL.md skills/architect-review/SKILL.md agents/coder.md; do
  d="$(tree "nofind-$(basename "$(dirname "$pat")")")"
  f="$(ls "$d"/plugins/*/"$pat")"
  sed 's/spec-find\.sh/some-other-finder.sh/g' "$f" >"$f.new" && mv "$f.new" "$f"
  assert_fires "$pat without a spec-find.sh mention fires" "$d"
done

# A comment listing, in each reader, fires -- every form check 17 names.
for pat in skills/resume/SKILL.md skills/architect-review/SKILL.md agents/coder.md; do
  d="$(tree "list-$(basename "$(dirname "$pat")")")"
  f="$(ls "$d"/plugins/*/"$pat")"
  printf '%s\n' 'List them with gh api repos/{backlog.repo}/issues/$N/comments --paginate.' >>"$f"
  assert_fires "$pat with an issue comment listing fires" "$d"
done
for form in 'gh api repos/{backlog.repo}/issues/<N>/comments --paginate' \
  'gh issue view 12 --comments' \
  'gh issue view 12 --json title,comments' \
  'gh issue view 12 --repo o/r --json comments --jq .comments' \
  'query { repository { issue(number: 12) { comments(first: 5) { nodes { id } } } } }' \
  'query { repository { issue(number: 12) { comments { nodes { id } } } } }' \
  'gh api repos/{backlog.repo}/issues/comments --paginate' \
  'gh api "repos/{backlog.repo}/issues/comments?per_page=100"' \
  'gh api repos/{backlog.repo}/issues/comments' \
  'gh api repos/{backlog.repo}/issues/$N/timeline --paginate'; do
  d="$(tree "listform-$(printf '%s' "$form" | cksum | cut -d' ' -f1)")"
  f="$(ls "$d"/plugins/*/agents/coder.md)"
  printf '%s\n' "$form" >>"$f"
  assert_fires "a comment listing form fires: $form" "$d"
done

# The $CID spellings of the fetch are held to the same allow-list.
for form in 'gh api repos/{backlog.repo}/issues/comments/$CID --jq .body' \
  'gh api "repos/{backlog.repo}/issues/comments/$CID" --jq .body' \
  'gh api repos/{backlog.repo}/issues/comments/${CID}|jq -r .body' \
  'gh api repos/{backlog.repo}/issues/comments/$CID'; do
  d="$(tree "cidform-$(printf '%s' "$form" | cksum | cut -d' ' -f1)")"
  f="$(ls "$d"/plugins/*/agents/coder.md)"
  printf '%s\n' "$form" >>"$f"
  assert_fires "an unprojected \$CID fetch fires: $form" "$d"
done

d="$(tree cidlegal)"
f="$(ls "$d"/plugins/*/agents/coder.md)"
printf '%s\n' \
  'Redirected: gh api "repos/{backlog.repo}/issues/comments/$CID" >"$T/c.json" then check it.' \
  'Braced: gh api "repos/{backlog.repo}/issues/comments/${CID}" >"$T/c.json" then check it.' \
  'Reactions: gh api "repos/{backlog.repo}/issues/comments/$CID/reactions" --paginate >"$T/rx.tsv".' >>"$f"
assert_silent "the \$CID fetches redirected into the temp directory are legal" "$d"

# A bare fetch, in each reader, fires: closing backtick right after the id.
for pat in skills/resume/SKILL.md skills/architect-review/SKILL.md agents/coder.md; do
  d="$(tree "bare-$(basename "$(dirname "$pat")")")"
  f="$(ls "$d"/plugins/*/"$pat")"
  printf '%s\n' 'Fetch it with `gh api repos/{backlog.repo}/issues/comments/<id>` and read the body.' >>"$f"
  assert_fires "$pat with a bare spec-comment fetch fires" "$d"
done

# A fetch followed by some other argument fires; the legal forms do not.
d="$(tree otherarg)"
f="$(ls "$d"/plugins/*/agents/coder.md)"
printf '%s\n' 'Run gh api repos/{backlog.repo}/issues/comments/<id> -i and read it.' >>"$f"
assert_fires "a fetch followed by another argument fires" "$d"

for form in 'gh api repos/{backlog.repo}/issues/comments/<id> --jq .body' \
  'gh api repos/{backlog.repo}/issues/comments/<id>|jq -r .body' \
  'gh api repos/{backlog.repo}/issues/comments/<id> --jq .updated_at,.body' \
  'gh api repos/{backlog.repo}/issues/comments/<id> >/dev/stdout' \
  'gh api repos/{backlog.repo}/issues/comments/<id> >&2' \
  'gh api repos/{backlog.repo}/issues/comments/<id>'; do
  d="$(tree "form-$(printf '%s' "$form" | cksum | cut -d' ' -f1)")"
  f="$(ls "$d"/plugins/*/agents/coder.md)"
  printf '%s\n' "$form" >>"$f"
  assert_fires "an unchecked fetch form fires: $form" "$d"
done

d="$(tree legalforms)"
f="$(ls "$d"/plugins/*/agents/coder.md)"
printf '%s\n' \
  'Redirected: gh api repos/{backlog.repo}/issues/comments/<id> >"$T/c.json" then check it.' \
  'Projected: gh api repos/{backlog.repo}/issues/comments/<id> --jq .updated_at to re-check.' \
  'Reactions: gh api "repos/{backlog.repo}/issues/comments/<id>/reactions" --paginate.' >>"$f"
assert_silent "redirected, projected and reactions fetches are legal" "$d"

# A missing reader or script fails, never passes.
d="$(tree noscript)"
rm -f "$d"/plugins/*/bin/spec-comment.sh
assert_fires "a missing spec-comment.sh fires" "$d"

d="$(tree noresume)"
rm -rf "$d"/plugins/*/skills/resume
assert_fires "a missing resume skill fires" "$d"

d="$(tree noreview)"
rm -rf "$d"/plugins/*/skills/architect-review
assert_fires "a missing architect-review skill fires" "$d"

d="$(tree nocoder)"
rm -f "$d"/plugins/*/agents/coder.md
assert_fires "a missing coder agent fires" "$d"


# bin/spec-find.sh (#662): the listing must keep its projection and stay one line.
sf=plugins/way-of-working/bin/spec-find.sh
d="$(tree sfcontrol)"
assert_silent "spec-find.sh as shipped passes" "$d"

d="$(tree sfnoprojection)"
f="$d/$sf"
sed 's#split("\\n")\[0\]#split("\\n")[1]#' "$f" >"$f.new" && mv "$f.new" "$f"
assert_fires "a listing without the first-line projection fires" "$d"

d="$(tree sfnotest)"
f="$d/$sf"
sed 's#select(\$l | test(#select($l | contains(#' "$f" >"$f.new" && mv "$f.new" "$f"
assert_fires "a listing without the test( marker match fires" "$d"

d="$(tree sftwolistings)"
f="$d/$sf"
printf '%s\n' 'gh api --paginate "repos/$backlog/issues/$issue/comments" --jq ".[] | .id" >"$tmp/second.tsv"' >>"$f"
assert_fires "two listings fire" "$d"

d="$(tree sfsplit)"
f="$d/$sf"
awk '{ i = index($0, " --jq "); if (index($0, "issues/$issue/comments") && i) { print substr($0, 1, i) "\\"; print substr($0, i + 1) } else print }' "$f" >"$f.new" && mv "$f.new" "$f"
assert_fires "a listing split over a continuation line fires" "$d"

d="$(tree sfbody)"
f="$d/$sf"
printf '%s\n' 'x="$(gh api "repos/$backlog/issues/comments/1" --jq .body)"' >>"$f"
assert_fires "a .body read on another line fires" "$d"

d="$(tree sfcommentbody)"
f="$d/$sf"
printf '%s\n' '# never read .body here' >>"$f"
assert_silent "a .body named in a comment is silent" "$d"

d="$(tree sfgone)"
rm -f "$d/$sf"
assert_fires "a missing spec-find.sh fires" "$d"

# bin/spec-fresh.sh (#663): resume and the coder name it, it exists and it makes no gh call.
sfr=plugins/way-of-working/bin/spec-fresh.sh
d="$(tree sfrcontrol)"
assert_silent "spec-fresh.sh as shipped passes" "$d"

for pat in skills/resume/SKILL.md agents/coder.md; do
  d="$(tree "nofresh-$(basename "$(dirname "$pat")")")"
  f="$(ls "$d"/plugins/*/"$pat")"
  sed 's/spec-fresh\.sh/some-other-check.sh/g' "$f" >"$f.new" && mv "$f.new" "$f"
  assert_fires "$pat without a spec-fresh.sh mention fires" "$d"
done

d="$(tree sfrgh)"
f="$d/$sfr"
printf '%s\n' 'gh api repos/o/r/issues/1' >>"$f"
assert_fires "a spec-fresh.sh with a gh call fires" "$d"

d="$(tree sfrghcomment)"
f="$d/$sfr"
printf '%s\n' '# never call gh api here' >>"$f"
assert_silent "a gh call named in a spec-fresh.sh comment is silent" "$d"

d="$(tree sfrgone)"
rm -f "$d/$sfr"
assert_fires "a missing spec-fresh.sh fires" "$d"

[ ! -e "$tmp/usage-exit" ] || { echo "FAIL - the checker exited 2 (usage) in at least one case" >&2; fail=1; }

[ "$fail" -eq 0 ]
