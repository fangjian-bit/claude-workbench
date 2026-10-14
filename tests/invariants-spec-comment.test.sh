#!/bin/sh
# Fixture tests for scripts/invariants-check.sh's check 17: the anchored spec comment is
# printed only after its checks pass -- resume, architect-review and the coder each call
# spec-comment.sh, and none fetches the comment unprojected and unredirected (#614).
#
# Each case mutates a COPY of the real tree and asserts the check fires (or stays silent), so
# a check that only passes on the real tree cannot hide. Only check 17's own message is
# asserted, never the script's overall exit.
#
# Permitted toolset: POSIX sh. No jq, no yq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/scripts/invariants-check.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
MSG="the anchored spec comment may reach context before its checks pass"

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
d="$(tree control)"
assert_silent "real tree passes" "$d"

# Each of the three readers no longer calling the script fires.
for pat in skills/resume/SKILL.md skills/architect-review/SKILL.md agents/coder.md; do
  d="$(tree "nocall-$(basename "$(dirname "$pat")")")"
  f="$(ls "$d"/plugins/*/"$pat")"
  sed 's/spec-comment\.sh/some-other-check.sh/g' "$f" >"$f.new" && mv "$f.new" "$f"
  assert_fires "$pat without a spec-comment.sh call fires" "$d"
done

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

[ "$fail" -eq 0 ]
