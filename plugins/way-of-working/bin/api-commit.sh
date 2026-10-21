#!/bin/sh
# The second App-mode publishing route: replay a branch's local commits through the REST git
# data API as the dev App, then reconcile the local branch onto the commits GitHub made.
#
# WB-D36 (#601), WB-D25 (#588): on a repo whose default branch requires signed commits, a PR
# whose branch commits are unsigned reads BLOCKED, and neither the merge box nor an armed
# auto-merge merges it. Dev-container commits are unsigned by rule. A commit created through
# the git data API as the dev App, with no `author` or `committer` field, is signed by GitHub,
# keeps file modes, and lets the PR read CLEAN (#588, route D). `app-push.sh` is the `git`
# route; this is the `api` route. A repo selects one with `identities.dev_app.commit_route`
# (`git` | `api`, undeclared is `git`), read by the pushing skills (reference/conventions.md,
# Push identity). This script makes no decision about the mode: the caller has already named
# the actor.
#
# Usage: api-commit.sh <remote> <branch>
# Exit 0 on success, 1 on any API or git failure, 2 on bad usage or a refused input. On exit
# 2, no POST or PATCH request has been sent. Every `gh api` call is pinned with
# `--hostname github.com`, with GH_HOST and GH_ENTERPRISE_TOKEN unset; request payloads go to
# files in a temp directory removed on exit and are sent with `--input`.
#
# Refused, all before any POST or PATCH:
#   - the remote: not a configured remote NAME, `remote.<name>.vcs` set, not exactly one fetch
#     and one push URL, or either not `https://github.com/<owner>/<repo>[.git]` naming the same
#     repository (a refusal names the remote, never the URL);
#   - the branch: outside `A-Za-z0-9._/-`, starting with `-`, not the branch checked out in this
#     worktree (the reconcile resets it), or in the base set. The base set is the default
#     branch (asked of the API), plus `pr_base` and a non-null `migration_base` read from the
#     fetched default branch's `.ai/project.yml`;
#   - a remote branch that is not an ancestor of the local one (existing branch), or an empty
#     range on a new branch;
#   - a commit in the range with other than one parent, any path under `.github/workflows/` (the
#     dev App holds no `workflows` permission, #588 test 5), a mode 120000 or 160000 entry, a
#     path with a newline or invalid UTF-8, or a message with an `encoding` header or invalid
#     UTF-8 (JSON cannot carry those byte for byte).
#
# Publishing, per commit, oldest first: a blob for each added or changed path (content from
# the local commit through `git cat-file`, never the working tree), a tree on `base_tree` (the
# remote parent's tree; modes from the local tree, `sha: null` for a deletion), then a commit
# with the local message, that tree and the remote parent, and no `author` or `committer`
# (setting either makes the commit unsigned, #588 test 1). The response's tree must equal the
# local commit's tree (#588 test 7), else exit 1 naming the local commit, no ref moved. Then
# the ref moves once: POST git/refs for a new branch, PATCH with force:false for an existing
# one.
#
# Reconcile: fetch the branch, check the fetched tip is the commit the ref write set and that
# its tree equals the local tip's, then `git reset --keep` to the remote-tracking ref and set
# it as upstream (as `app-push.sh -u` would). A failed check leaves the local branch untouched
# and exits 1; the ref has already moved, so a re-run is refused: recover by a manual fetch, the
# same tree check, then `git reset --keep`. The fetches use git's ambient credential and write
# nothing remote.
#
# Permitted toolset: POSIX sh, git, gh, jq, yq and base64.
set -eu

unset GH_HOST GH_ENTERPRISE_TOKEN

refuse() {
  echo "api-commit.sh: $1" >&2
  exit 2
}

fail() {
  echo "api-commit.sh: $1" >&2
  exit 1
}

ghapi() {
  gh api --hostname github.com "$@" </dev/null
}

# name_ok <string>: non-empty, only A-Za-z0-9._/-, not starting with '-'.
name_ok() {
  case "$1" in
    ''|-*|*[!A-Za-z0-9._/-]*) return 1 ;;
  esac
  return 0
}

sha_ok() {
  case "$1" in
    *[!0-9a-f]*|'') return 1 ;;
  esac
  [ "${#1}" -eq 40 ]
}

# utf8_ok <file>: a jq round trip reproduces the bytes only when they are valid UTF-8.
utf8_ok() {
  jq -Rsj . <"$1" >"$T/utf8.out" 2>/dev/null && cmp -s "$1" "$T/utf8.out"
}

[ "$#" -eq 2 ] || refuse "usage: api-commit.sh <remote> <branch>"
remote="$1"
branch="$2"

# --- the remote -------------------------------------------------------------------------
case "$remote" in
  ''|-*|*://*|*@*:*|/*|./*|../*|*[!A-Za-z0-9._-]*) refuse "the remote argument is not a configured remote name" ;;
esac
git config --get "remote.$remote.url" >/dev/null 2>&1 || refuse "remote '$remote' is not configured"
[ -z "$(git config --get "remote.$remote.vcs" 2>/dev/null || true)" ] || refuse "remote '$remote' sets a remote helper (remote.$remote.vcs)"
furls=$(git remote get-url --all "$remote" 2>/dev/null) || refuse "cannot read the URLs of remote '$remote'"
purls=$(git remote get-url --push --all "$remote" 2>/dev/null) || refuse "cannot read the push URLs of remote '$remote'"
[ "$(printf '%s\n' "$furls" | wc -l | tr -d ' ')" -eq 1 ] || refuse "remote '$remote' has more than one fetch URL"
[ "$(printf '%s\n' "$purls" | wc -l | tr -d ' ')" -eq 1 ] || refuse "remote '$remote' has more than one push URL"

# slug_of <url>: print owner/repo for https://github.com/<owner>/<repo>[.git], else nothing.
slug_of() {
  rest="${1#https://github.com/}"
  [ "$rest" != "$1" ] || return 1
  rest="${rest%.git}"
  owner="${rest%%/*}"
  repo="${rest#*/}"
  [ "$owner/$repo" = "$rest" ] || return 1
  case "$owner" in ''|*[!A-Za-z0-9-]*) return 1 ;; esac
  case "$repo" in ''|.|..|*[!A-Za-z0-9._-]*) return 1 ;; esac
  printf '%s/%s' "$owner" "$repo"
}
fslug=$(slug_of "$furls") || refuse "remote '$remote' fetch URL is not https://github.com/<owner>/<repo>"
pslug=$(slug_of "$purls") || refuse "remote '$remote' push URL is not https://github.com/<owner>/<repo>"
[ "$fslug" = "$pslug" ] || refuse "remote '$remote' fetch and push URLs name different repositories"
slug="$fslug"

# --- the branch -------------------------------------------------------------------------
name_ok "$branch" || refuse "the branch argument is outside A-Za-z0-9._/- or starts with '-'"
git check-ref-format "refs/heads/$branch" || refuse "branch '$branch' is not a valid branch name"
[ "$(git symbolic-ref -q --short HEAD 2>/dev/null || true)" = "$branch" ] || refuse "branch '$branch' is not the branch checked out here"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
trap 'exit 1' INT TERM HUP

# --- the base set -----------------------------------------------------------------------
default=$(ghapi "repos/$slug" --jq .default_branch) || fail "cannot read the default branch of remote '$remote'"
name_ok "$default" || refuse "the default branch name of remote '$remote' is outside A-Za-z0-9._/-"
git fetch -q "$remote" "+refs/heads/$default:refs/remotes/$remote/$default" || fail "cannot fetch '$default' from remote '$remote'"
git show "refs/remotes/$remote/$default:.ai/project.yml" >"$T/project.yml" 2>/dev/null || refuse "cannot read .ai/project.yml on the default branch of remote '$remote'"
bases="$default"
for key in pr_base migration_base; do
  tag=$(yq -r ".$key | tag" "$T/project.yml" 2>/dev/null) || refuse "cannot parse .ai/project.yml on the default branch of remote '$remote'"
  case "$tag" in
    '!!null') continue ;;
    '!!str') ;;
    *) refuse "$key in .ai/project.yml is not a branch name" ;;
  esac
  val=$(yq -r ".$key" "$T/project.yml")
  name_ok "$val" || refuse "$key in .ai/project.yml is not a branch name"
  case " $bases " in *" $val "*) ;; *) bases="$bases $val" ;; esac
done
notrefs=
for b in $bases; do
  [ "$b" != "$branch" ] || refuse "branch '$branch' is in the base set"
  if [ "$b" != "$default" ]; then
    git fetch -q "$remote" "+refs/heads/$b:refs/remotes/$remote/$b" || fail "cannot fetch '$b' from remote '$remote'"
  fi
  notrefs="$notrefs refs/remotes/$remote/$b"
done

# --- new or existing --------------------------------------------------------------------
existing=
if ghapi "repos/$slug/git/ref/heads/$branch" >"$T/ref.json" 2>"$T/ref.err"; then
  [ "$(jq -r .ref "$T/ref.json")" = "refs/heads/$branch" ] || refuse "the remote answered a different ref for branch '$branch'"
  rsha=$(jq -r .object.sha "$T/ref.json")
  sha_ok "$rsha" || fail "the remote returned no commit for branch '$branch'"
  git fetch -q "$remote" "+refs/heads/$branch:refs/remotes/$remote/$branch" || fail "cannot fetch '$branch' from remote '$remote'"
  tip=$(git rev-parse -q --verify "refs/remotes/$remote/$branch^{commit}") || fail "fetched no commit for branch '$branch'"
  [ "$tip" = "$rsha" ] || refuse "the fetched tip of '$branch' is not the commit the remote reported"
  git merge-base --is-ancestor "$tip" "refs/heads/$branch" || refuse "the remote '$branch' is not an ancestor of the local branch"
  existing=1
elif grep -q 'HTTP 404' "$T/ref.err"; then
  :
else
  fail "cannot read branch '$branch' on remote '$remote'"
fi

# --- the range, oldest first ------------------------------------------------------------
if [ -n "$existing" ]; then
  # shellcheck disable=SC2086
  git rev-list --topo-order --reverse "refs/heads/$branch" --not "$tip" >"$T/range"
else
  # shellcheck disable=SC2086
  git rev-list --topo-order --reverse "refs/heads/$branch" --not $notrefs >"$T/range"
fi
if [ ! -s "$T/range" ]; then
  [ -z "$existing" ] || exit 0
  refuse "branch '$branch' has no commits beyond the base set"
fi

# --- the commits in the range -----------------------------------------------------------
prev=
while read -r c; do
  parents=$(git rev-list --parents -n 1 "$c")
  # shellcheck disable=SC2086
  set -- $parents
  [ "$#" -eq 2 ] || refuse "commit $(git rev-parse --short "$c") does not have exactly one parent"
  [ -z "$prev" ] || [ "$2" = "$prev" ] || refuse "commit $(git rev-parse --short "$c") does not follow the one before it"
  prev="$c"
  git diff-tree -r -z --no-renames "$2" "$c" >"$T/diff.z"
  [ "$(tr -cd '\n' <"$T/diff.z" | wc -c | tr -d ' ')" -eq 0 ] || refuse "commit $(git rev-parse --short "$c") changes a path with a newline"
  tr '\0' '\n' <"$T/diff.z" >"$T/diff.txt"
  utf8_ok "$T/diff.txt" || refuse "commit $(git rev-parse --short "$c") changes a path that is not valid UTF-8"
  while read -r smode dmode _ _ _ && IFS= read -r path; do
    case "$smode$dmode" in
      *120000*|*160000*) refuse "commit $(git rev-parse --short "$c") has a symlink or submodule entry" ;;
    esac
    case "$path" in
      .github/workflows/*) refuse "commit $(git rev-parse --short "$c") changes a path under .github/workflows/" ;;
    esac
  done <"$T/diff.txt"
  git cat-file commit "$c" >"$T/raw"
  hdr=$(sed -n '/^$/{=;q;}' "$T/raw")
  if [ -n "$hdr" ]; then
    head -n "$((hdr - 1))" "$T/raw" | grep -q '^encoding ' && refuse "commit $(git rev-parse --short "$c") has an encoding header"
    tail -n "+$((hdr + 1))" "$T/raw" >"$T/msg"
  else
    : >"$T/msg"
  fi
  utf8_ok "$T/msg" || refuse "commit $(git rev-parse --short "$c") has a message that is not valid UTF-8"
done <"$T/range"

# --- publishing -------------------------------------------------------------------------
first=$(sed -n 1p "$T/range")
remote_parent=$(git rev-parse "$first^")
base_tree=$(git rev-parse "$remote_parent^{tree}")
last=
while read -r c; do
  short=$(git rev-parse --short "$c")
  git diff-tree -r -z --no-renames "$(git rev-parse "$c^")" "$c" | tr '\0' '\n' >"$T/diff.txt"
  printf '[]' >"$T/entries.json"
  while read -r smode dmode _ dsha status && IFS= read -r path; do
    s=${status%%[0-9]*}
    if [ "$s" = D ]; then
      jq --arg p "$path" --arg m "${smode#:}" '. + [{path: $p, mode: $m, type: "blob", sha: null}]' "$T/entries.json" >"$T/entries.new"
    else
      git cat-file blob "$dsha" | base64 | tr -d '\n' >"$T/blob.b64"
      jq -n --rawfile c "$T/blob.b64" '{content: $c, encoding: "base64"}' >"$T/blob.json"
      ghapi -X POST "repos/$slug/git/blobs" --input "$T/blob.json" >"$T/blob.resp" || fail "cannot post a blob for commit $short"
      bsha=$(jq -r .sha "$T/blob.resp")
      sha_ok "$bsha" || fail "the blob response for commit $short carried no sha"
      jq --arg p "$path" --arg m "$dmode" --arg s "$bsha" '. + [{path: $p, mode: $m, type: "blob", sha: $s}]' "$T/entries.json" >"$T/entries.new"
    fi
    mv "$T/entries.new" "$T/entries.json"
  done <"$T/diff.txt"
  if [ "$(jq length "$T/entries.json")" -eq 0 ]; then
    tree="$base_tree"
  else
    jq --arg b "$base_tree" '{base_tree: $b, tree: .}' "$T/entries.json" >"$T/tree.json"
    ghapi -X POST "repos/$slug/git/trees" --input "$T/tree.json" >"$T/tree.resp" || fail "cannot post a tree for commit $short"
    tree=$(jq -r .sha "$T/tree.resp")
    sha_ok "$tree" || fail "the tree response for commit $short carried no sha"
  fi
  git cat-file commit "$c" >"$T/raw"
  hdr=$(sed -n '/^$/{=;q;}' "$T/raw")
  if [ -n "$hdr" ]; then tail -n "+$((hdr + 1))" "$T/raw" >"$T/msg"; else : >"$T/msg"; fi
  jq -n --rawfile m "$T/msg" --arg t "$tree" --arg p "$remote_parent" '{message: $m, tree: $t, parents: [$p]}' >"$T/commit.json"
  ghapi -X POST "repos/$slug/git/commits" --input "$T/commit.json" >"$T/commit.resp" || fail "cannot post commit $short"
  csha=$(jq -r .sha "$T/commit.resp")
  ctree=$(jq -r .tree.sha "$T/commit.resp")
  sha_ok "$csha" || fail "the commit response for $short carried no sha"
  [ "$ctree" = "$(git rev-parse "$c^{tree}")" ] || fail "tree mismatch for local commit $short: the API commit's tree is not the local tree; no ref moved"
  remote_parent="$csha"
  base_tree="$ctree"
  last="$csha"
done <"$T/range"

# --- moving the ref, once ---------------------------------------------------------------
if [ -n "$existing" ]; then
  jq -n --arg s "$last" '{sha: $s, force: false}' >"$T/ref.json"
  ghapi -X PATCH "repos/$slug/git/refs/heads/$branch" --input "$T/ref.json" >/dev/null || fail "cannot move branch '$branch' on remote '$remote'"
else
  jq -n --arg r "refs/heads/$branch" --arg s "$last" '{ref: $r, sha: $s}' >"$T/ref.json"
  ghapi -X POST "repos/$slug/git/refs" --input "$T/ref.json" >/dev/null || fail "cannot create branch '$branch' on remote '$remote'"
fi

# --- reconcile --------------------------------------------------------------------------
git fetch -q "$remote" "+refs/heads/$branch:refs/remotes/$remote/$branch" || fail "the ref moved but cannot fetch '$branch' back; reconcile by hand"
rtip=$(git rev-parse -q --verify "refs/remotes/$remote/$branch^{commit}") || fail "the ref moved but the fetch returned no commit; reconcile by hand"
[ "$rtip" = "$last" ] || fail "the ref moved but the fetched tip is not the commit written; reconcile by hand"
[ "$(git rev-parse "$rtip^{tree}")" = "$(git rev-parse "refs/heads/$branch^{tree}")" ] || fail "the ref moved but its tree differs from the local tip's; local branch untouched, reconcile by hand"
git reset -q --keep "refs/remotes/$remote/$branch" || fail "the ref moved but the local reset failed; reconcile by hand"
git branch -q --set-upstream-to="$remote/$branch" "$branch" || fail "the branch was reconciled but its upstream could not be set"
