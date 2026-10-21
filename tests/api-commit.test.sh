#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/api-commit.sh (#601, WB-D36): the checks that
# run before any POST or PATCH, the writes it makes (order, modes, deletions, messages, no
# author or committer), the ref write, the per-commit tree-equality check and the reconcile,
# against a scratch repository, a local bare "remote" and a stub gh that really builds the
# objects it is asked for in that bare repository. A stub git sends every fetch to the bare
# repository, so no test reaches the network.
#
# Permitted toolset: POSIX sh, git, jq, yq and base64 (the script's own, plus the stubs').
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/plugins/way-of-working/bin/api-commit.sh"

for tool in git jq yq base64; do
  command -v "$tool" >/dev/null 2>&1 || { echo "skip - $tool not on PATH"; exit 0; }
done

fail=0

assert_eq() {
  desc="$1"
  expected="$2"
  actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "ok - $desc"
  else
    echo "FAIL - $desc: expected [$expected], got [$actual]" >&2
    fail=1
  fi
}

real_git="$(command -v git)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM
mkdir "$work/bin" "$work/home"
export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z'
"$real_git" config --global init.defaultBranch main
"$real_git" config --global commit.gpgsign false
"$real_git" config --global protocol.file.allow always

bare="$work/bare.git"
repo="$work/repo"
log="$work/gh.log"

# A stub git: `fetch -q <remote> <refspec>` fetches the refspec from the bare repository.
cat >"$work/bin/git" <<EOF
#!/bin/sh
if [ "\${1:-}" = fetch ]; then
  [ "\$#" -eq 4 ] && [ "\$2" = -q ] || { echo "stub git: unexpected fetch shape: \$*" >&2; exit 97; }
  exec "$real_git" fetch -q "$bare" "\$4"
fi
exec "$real_git" "\$@"
EOF
chmod +x "$work/bin/git"

# A stub gh. Logs "METHOD endpoint bodyfile" per call (bodyfile is - when there is none) and
# builds real objects in the bare repository: blobs, trees (on base_tree), commits (from the
# message, byte for byte, with every parent sent) and refs. STUB_TREE_WRONG answers a commit with the empty tree;
# STUB_SWAP builds the commit on the empty tree but answers with the requested one.
cat >"$work/bin/gh" <<'EOF'
#!/bin/sh
set -eu
[ "$1" = api ] && [ "$2" = --hostname ] && [ "$3" = github.com ] || { echo "NOHOST $*" >>"$STUB_LOG"; exit 98; }
echo "GH_HOST=[${GH_HOST:-}] GH_ENTERPRISE_TOKEN=[${GH_ENTERPRISE_TOKEN:-}]" >>"$STUB_LOG.env"
shift 3
method=GET input=- jqf=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -X) method="$2"; shift 2 ;;
    --input) input="$2"; shift 2 ;;
    --jq) jqf="$2"; shift 2 ;;
    *) endpoint="$1"; shift ;;
  esac
done
n=$(wc -l <"$STUB_LOG" | tr -d ' ')
saved=-
if [ "$input" != - ]; then saved="$STUB_LOG.d/$n.json"; cp "$input" "$saved"; fi
echo "$method $endpoint $saved" >>"$STUB_LOG"
export GIT_DIR="$STUB_BARE"
empty=4b825dc642cb6eb9a060e54bf8d69288fbee4904
out() { if [ -n "$jqf" ]; then jq -r "$jqf"; else cat; fi; }
case "$method $endpoint" in
  "GET repos/o/r")
    echo '{"default_branch":"main"}' | out ;;
  "GET repos/o/r/git/ref/heads/"*)
    [ -z "${STUB_REF_FAIL:-}" ] || { echo "gh: Server Error (HTTP 500)" >&2; exit 1; }
    b="${endpoint#repos/o/r/git/ref/heads/}"
    if sha=$(git rev-parse -q --verify "refs/heads/$b"); then
      printf '{"ref":"refs/heads/%s","object":{"sha":"%s"}}\n' "$b" "$sha"
    else
      echo "gh: Not Found (HTTP 404)" >&2; exit 1
    fi ;;
  "POST repos/o/r/git/blobs")
    sha=$(jq -r .content "$saved" | base64 -d | git hash-object -w --stdin)
    printf '{"sha":"%s"}\n' "$sha" ;;
  "POST repos/o/r/git/trees")
    export GIT_INDEX_FILE="$STUB_BARE/stub.idx"
    rm -f "$GIT_INDEX_FILE"
    git read-tree "$(jq -r .base_tree "$saved")"
    jq -r '.tree[] | if .sha == null then "0 0000000000000000000000000000000000000000\t\(.path)" else "\(.mode) \(.sha)\t\(.path)" end' "$saved" |
      sed 's/^\([0-9]*\) \([0-9a-f]*\)\t/\1 \2 0\t/' | git update-index --index-info
    printf '{"sha":"%s"}\n' "$(git write-tree)" ;;
  "POST repos/o/r/git/commits")
    jq -j .message "$saved" >"$saved.msg"
    want=$(jq -r .tree "$saved")
    git hash-object -t tree -w /dev/null >/dev/null
    built="$want"
    [ -z "${STUB_SWAP:-}" ] || built="$empty"
    [ -z "${STUB_TREE_WRONG:-}" ] || { built="$empty"; want="$empty"; }
    set -- "$built"
    for p in $(jq -r '.parents[]' "$saved"); do set -- "$@" -p "$p"; done
    sha=$(GIT_AUTHOR_NAME=bot GIT_COMMITTER_NAME=bot git commit-tree "$@" -F "$saved.msg")
    printf '{"sha":"%s","tree":{"sha":"%s"}}\n' "$sha" "$want" ;;
  "POST repos/o/r/git/refs")
    git update-ref "$(jq -r .ref "$saved")" "$(jq -r .sha "$saved")"; echo '{}' ;;
  "PATCH repos/o/r/git/refs/heads/"*)
    git update-ref "refs/heads/${endpoint#repos/o/r/git/refs/heads/}" "$(jq -r .sha "$saved")"; echo '{}' ;;
  *) echo "stub gh: unexpected $method $endpoint" >&2; exit 99 ;;
esac
EOF
chmod +x "$work/bin/gh"

# fresh [project.yml text]: a bare "remote" with main, and a clone with origin pointed at a
# github.com URL (the stub git never lets it be dialled), checked out on main.
fresh() {
  rm -rf "$bare" "$repo" "$log" "$log.d" "$log.env"
  mkdir "$log.d"
  : >"$log"
  "$real_git" init -q --bare "$bare"
  "$real_git" init -q "$repo"
  (
    cd "$repo"
    mkdir .ai
    printf '%s\n' "${1:-pr_base: main
migration_base: null}" >.ai/project.yml
    printf 'keep\n' >keep.txt
    printf 'del\n' >del.txt
    "$real_git" add -A
    "$real_git" commit -q -m base
    "$real_git" remote add origin https://github.com/o/r.git
    "$real_git" push -q "$bare" main
  )
}

commit_file() { # <name> <content> <message>
  printf '%s\n' "$2" >"$1"
  "$real_git" add -A
  "$real_git" commit -q -m "$3"
}

run() { # <args...>: prints the exit code; stdout and stderr to $work/out
  rc=0
  (cd "$repo" && PATH="$work/bin:$PATH" STUB_LOG="$log" STUB_BARE="$bare" GH_HOST=evil.example GH_ENTERPRISE_TOKEN=x sh "$script" "$@") >"$work/out" 2>&1 || rc=$?
  echo "$rc"
}

writes() { grep -E '^(POST|PATCH) ' "$log" | sed 's/^\([A-Z]*\) repos\/o\/r\/git\/\([a-z]*\).*/\1 \2/' | tr '\n' ',' ; }

refused() { # <desc> <args...>: exit 2 and no POST or PATCH
  desc="$1"
  shift
  assert_eq "$desc exits 2" "2" "$(run "$@")"
  assert_eq "$desc sent no POST or PATCH" "" "$(writes)"
}

# --- usage and the remote ---------------------------------------------------------------
fresh
(cd "$repo" && "$real_git" checkout -q -b feat/x && commit_file a.txt a one)
refused "no arguments"
refused "one argument" origin
refused "three arguments" origin feat/x extra
refused "a URL as the remote" https://github.com/o/r.git feat/x
assert_eq "a URL remote is not echoed" "no" "$(grep -q github.com "$work/out" && echo yes || echo no)"
refused "an ssh-style remote" git@github.com:o/r.git feat/x
refused "a path as the remote" ../bare feat/x
refused "an unconfigured remote" nowhere feat/x
# remote_case <desc> <git args...>: a fresh repository whose origin was changed by the git args.
remote_case() {
  desc="$1"
  shift
  fresh
  (cd "$repo" && "$real_git" checkout -q -b feat/x && commit_file a.txt a one && "$real_git" "$@")
  refused "$desc" origin feat/x
}
remote_case "an ssh URL" remote set-url origin git@github.com:o/r.git
remote_case "a non-github.com URL" remote set-url origin https://example.com/o/r.git
assert_eq "a refusal names the remote, not the URL" "no" "$(grep -q 'example.com' "$work/out" && echo yes || echo no)"
remote_case "two fetch URLs" remote set-url --add origin https://github.com/o/r2.git
remote_case "fetch and push URLs naming different repositories" remote set-url --push origin https://github.com/o/other.git
fresh
(cd "$repo" && "$real_git" checkout -q -b feat/x && commit_file a.txt a one && "$real_git" config --add remote.origin.pushurl https://github.com/o/r.git && "$real_git" config --add remote.origin.pushurl https://github.com/o/r.git)
refused "two push URLs" origin feat/x
remote_case "a remote with vcs set" config remote.origin.vcs evil
remote_case "a URL with a path below the repository" remote set-url origin https://github.com/o/r/extra.git
remote_case "a repository named .." remote set-url origin 'https://github.com/o/..'
remote_case "an http URL" remote set-url origin http://github.com/o/r.git

# --- the branch -------------------------------------------------------------------------
refused "a branch outside the charset" origin 'feat/a b'
refused "a branch starting with a dash" origin -feat
refused "a branch that is not checked out" origin other
refused "the default branch as the branch" origin main
(cd "$repo" && "$real_git" checkout -q main)
refused "the default branch checked out" origin main
fresh 'pr_base: integration
migration_base: mig'
"$real_git" -C "$repo" push -q "$bare" main:integration main:mig
for b in integration mig; do
  (cd "$repo" && "$real_git" checkout -q -b "$b" && commit_file "$b.txt" "$b" "$b commit")
  refused "the base-set branch $b" origin "$b"
  (cd "$repo" && "$real_git" checkout -q main)
done
assert_eq "base-set refusals fetched pr_base and migration_base" "yes" "$("$real_git" -C "$repo" rev-parse -q --verify refs/remotes/origin/integration >/dev/null && echo yes || echo no)"
fresh 'pr_base: 123
migration_base: null'
(cd "$repo" && "$real_git" checkout -q -b feat/x && commit_file a.txt a one)
refused "a pr_base that is not a string" origin feat/x
fresh 'pr_base: has space
migration_base: null'
(cd "$repo" && "$real_git" checkout -q -b feat/x && commit_file a.txt a one)
refused "a pr_base outside the charset" origin feat/x
fresh 'roadmap: x'
(cd "$repo" && "$real_git" checkout -q -b feat/x && commit_file a.txt a one)
assert_eq "no pr_base and no migration_base is allowed" "0" "$(run origin feat/x)"

# --- an empty range ---------------------------------------------------------------------
fresh
(cd "$repo" && "$real_git" checkout -q -b feat/empty)
refused "a new branch with no commits" origin feat/empty
fresh
(cd "$repo" && "$real_git" checkout -q -b feat/x && commit_file a.txt a one)
"$real_git" -C "$repo" push -q "$bare" feat/x
assert_eq "an existing branch with an empty range exits 0" "0" "$(run origin feat/x)"
assert_eq "an empty range sends nothing" "" "$(writes)"

# --- the commits in the range -----------------------------------------------------------
fresh
(cd "$repo" && "$real_git" checkout -q --orphan feat/root && "$real_git" rm -rfq . && commit_file r.txt r root)
refused "a root commit" origin feat/root
fresh
(
  cd "$repo"
  "$real_git" checkout -q -b side && commit_file s.txt s side
  "$real_git" checkout -q main && "$real_git" checkout -q -b feat/merge && commit_file m.txt m main-side
  "$real_git" merge -q --no-ff -m merge side
)
refused "a merge commit" origin feat/merge
assert_eq "the merge-commit refusal names the second parent" "yes" "$(grep -q 'on no base-set branch' "$work/out" && echo yes || echo no)"
fresh
(cd "$repo" && "$real_git" checkout -q -b feat/wf && mkdir -p .github/workflows && commit_file .github/workflows/ci.yml x wf)
refused "a workflow path" origin feat/wf
fresh
(cd "$repo" && "$real_git" checkout -q -b feat/wf2 && mkdir -p .github/workflows && printf 'x\n' >.github/workflows/ci.yml && "$real_git" add -A && "$real_git" commit -q -m add && "$real_git" rm -q .github/workflows/ci.yml && "$real_git" commit -q -m del)
refused "a workflow path deleted in a later commit" origin feat/wf2
fresh
(cd "$repo" && "$real_git" checkout -q -b feat/link && ln -s keep.txt l && "$real_git" add -A && "$real_git" commit -q -m link)
refused "a symlink" origin feat/link
fresh
(cd "$repo" && "$real_git" checkout -q -b feat/sub && "$real_git" update-index --add --cacheinfo 160000,1234567890123456789012345678901234567890,sub && "$real_git" commit -q -m sub)
refused "a submodule" origin feat/sub
fresh
(cd "$repo" && "$real_git" checkout -q -b feat/enc && printf 'e\n' >e.txt && "$real_git" add -A && "$real_git" -c i18n.commitEncoding=latin1 commit -q -m enc)
refused "a message with an encoding header" origin feat/enc
fresh
(
  cd "$repo"
  "$real_git" checkout -q -b feat/u8 && commit_file e.txt e ok
  # git re-encodes a message on commit, so build the commit object by hand.
  { "$real_git" cat-file commit HEAD | sed '/^$/q'; printf 'bad \377 byte\n'; } >"$work/bad-commit"
  "$real_git" reset -q --hard "$("$real_git" hash-object -t commit -w --literally "$work/bad-commit")"
)
refused "a message that is not valid UTF-8" origin feat/u8
fresh
(cd "$repo" && "$real_git" checkout -q -b feat/nl && commit_file "$(printf 'a\nb')" x nl)
refused "a path with a newline" origin feat/nl

# --- an existing remote branch that diverged --------------------------------------------
fresh
(
  cd "$repo"
  "$real_git" checkout -q -b feat/div && commit_file d1.txt d1 local
  "$real_git" checkout -q main && "$real_git" checkout -q -b tmp && commit_file d2.txt d2 remote
  "$real_git" push -q "$bare" tmp:feat/div
  "$real_git" checkout -q feat/div
)
refused "a remote branch that is not an ancestor" origin feat/div
fresh
(cd "$repo" && "$real_git" checkout -q -b feat/x && commit_file a.txt a one)
rc=0
(cd "$repo" && PATH="$work/bin:$PATH" STUB_LOG="$log" STUB_BARE="$bare" STUB_REF_FAIL=1 sh "$script" origin feat/x) >"$work/out" 2>&1 || rc=$?
assert_eq "an unreadable ref (not a 404) exits 1" "1" "$rc"
assert_eq "an unreadable ref sent no write" "" "$(writes)"

# --- a new branch, two commits: modes, a deletion, messages, the write order ------------
fresh
(
  cd "$repo"
  "$real_git" checkout -q -b feat/x
  printf '#!/bin/sh\n' >run.sh && chmod +x run.sh
  printf 'a\n' >a.txt
  printf 'keep changed\n' >keep.txt
  "$real_git" add -A
  "$real_git" commit -q -m 'first' -m 'body line

Co-Authored-By: Someone <s@example.com>'
  "$real_git" rm -q del.txt
  mkdir 'sub dir' && printf 'u\n' >'sub dir/ü.txt'
  "$real_git" add -A
  printf 'second: no trailing newline' | "$real_git" commit -q --cleanup=verbatim -F -
)
tip_before=$("$real_git" -C "$repo" rev-parse feat/x)
assert_eq "a new branch publishes" "0" "$(run origin feat/x)"
assert_eq "writes: blobs for changed paths only, a tree, a commit, per commit, then one ref write" \
  "POST blobs,POST blobs,POST blobs,POST trees,POST commits,POST blobs,POST trees,POST commits,POST refs," "$(writes)"
assert_eq "every call is pinned and GH_HOST and GH_ENTERPRISE_TOKEN are unset" "" "$(grep -c NOHOST "$log" | grep -vx 0 || true)"
assert_eq "gh saw no GH_HOST or GH_ENTERPRISE_TOKEN" "1" "$(sort -u "$log.env" | grep -cx 'GH_HOST=\[\] GH_ENTERPRISE_TOKEN=\[\]')"
trees=$(grep '^POST repos/o/r/git/trees' "$log" | awk '{print $3}')
t1=$(printf '%s\n' "$trees" | sed -n 1p)
t2=$(printf '%s\n' "$trees" | sed -n 2p)
assert_eq "the first tree is based on the local parent's tree" "$("$real_git" -C "$repo" rev-parse main^{tree})" "$(jq -r .base_tree "$t1")"
assert_eq "the first tree entries carry the local modes" \
  "a.txt 100644,keep.txt 100644,run.sh 100755" "$(jq -r '.tree | sort_by(.path) | map("\(.path) \(.mode)") | join(",")' "$t1")"
assert_eq "the second tree is based on the first API commit's tree" "$("$real_git" -C "$repo" rev-parse "$tip_before^^{tree}")" "$(jq -r .base_tree "$t2")"
assert_eq "a deletion is sent with sha null" "del.txt null" "$(jq -r '.tree[] | select(.sha == null) | "\(.path) \(.sha)"' "$t2")"
assert_eq "a path with a space and a non-ASCII name survives" "sub dir/ü.txt" "$(jq -r '.tree[] | select(.sha != null) | .path' "$t2")"
commits=$(grep '^POST repos/o/r/git/commits' "$log" | awk '{print $3}')
c1=$(printf '%s\n' "$commits" | sed -n 1p)
c2=$(printf '%s\n' "$commits" | sed -n 2p)
assert_eq "no commit request carries author or committer" "false" "$(jq -r 'has("author") or has("committer")' "$c1" "$c2" | sort -u)"
assert_eq "the first commit's parent is the local parent" "$("$real_git" -C "$repo" rev-parse main)" "$(jq -r '.parents[0]' "$c1")"
first_local=$("$real_git" -C "$repo" rev-parse "$tip_before^")
"$real_git" -C "$repo" cat-file commit "$first_local" | sed '1,/^$/d' >"$work/m1"
"$real_git" -C "$repo" cat-file commit "$tip_before" | sed '1,/^$/d' >"$work/m2"
jq -j .message "$c1" >"$work/r1"
jq -j .message "$c2" >"$work/r2"
assert_eq "the first message is sent byte for byte" "yes" "$(cmp -s "$work/m1" "$work/r1" && echo yes || echo no)"
assert_eq "the second message (no trailing newline) is sent byte for byte" "yes" "$(cmp -s "$work/m2" "$work/r2" && echo yes || echo no)"
assert_eq "the second commit's parent is the first API commit" "$("$real_git" --git-dir="$bare" rev-parse feat/x^)" "$(jq -r '.parents[0]' "$c2")"
assert_eq "a new branch is a POST to git/refs" "ref refs/heads/feat/x" "$(jq -r '"ref \(.ref)"' "$(grep '^POST repos/o/r/git/refs' "$log" | awk '{print $3}')")"
assert_eq "the reconcile put the local branch on the remote tip" "$("$real_git" --git-dir="$bare" rev-parse feat/x)" "$("$real_git" -C "$repo" rev-parse feat/x)"
assert_eq "the reconcile set the upstream" "origin/feat/x" "$("$real_git" -C "$repo" rev-parse --abbrev-ref feat/x@{upstream})"
assert_eq "the local branch's tree is unchanged" "$("$real_git" --git-dir="$bare" rev-parse 'feat/x^{tree}')" "$("$real_git" -C "$repo" rev-parse 'feat/x^{tree}')"
assert_eq "the local branch moved off the unsigned commits" "no" "$([ "$("$real_git" -C "$repo" rev-parse feat/x)" = "$tip_before" ] && echo yes || echo no)"
assert_eq "the 100755 mode survived in the remote tree" "100755" "$("$real_git" --git-dir="$bare" ls-tree feat/x run.sh | cut -d' ' -f1)"
assert_eq "the worktree is clean after the reconcile" "" "$("$real_git" -C "$repo" status --porcelain)"
assert_eq "a re-run is empty and sends nothing" "0" "$(: >"$log"; run origin feat/x)"
assert_eq "a re-run wrote nothing" "" "$(writes)"

# --- an existing branch: PATCH with force false, only the new commits --------------------
fresh
(
  cd "$repo"
  "$real_git" checkout -q -b feat/y && commit_file y1.txt y1 'y one'
  "$real_git" push -q "$bare" feat/y
  commit_file y2.txt y2 'y two'
)
assert_eq "an existing branch publishes" "0" "$(run origin feat/y)"
assert_eq "writes: one commit's blob, tree, commit, then a PATCH" "POST blobs,POST trees,POST commits,PATCH refs," "$(writes)"
assert_eq "the existing branch's ref is moved with force false" "false" "$(jq -r .force "$(grep '^PATCH ' "$log" | awk '{print $3}')")"
assert_eq "the remote parent of the first replayed commit is the remote tip" "$("$real_git" --git-dir="$bare" rev-parse feat/y^)" "$(jq -r '.parents[0]' "$(grep '^POST repos/o/r/git/commits' "$log" | awk '{print $3}')")"
assert_eq "the existing branch is reconciled" "$("$real_git" --git-dir="$bare" rev-parse feat/y)" "$("$real_git" -C "$repo" rev-parse feat/y)"

# --- a merge of the base into the branch (#811) ----------------------------------------
# merge_fixture <branch> <published>: a branch with one commit (pushed to the bare repository
# when <published> is yes), the base advanced and pushed there, then the base merged in.
merge_fixture() {
  fresh
  (
    cd "$repo"
    "$real_git" checkout -q -b "$1" && commit_file a.txt a one
    [ "$2" != yes ] || "$real_git" push -q "$bare" "$1"
    "$real_git" checkout -q main && commit_file b.txt b advance
    "$real_git" push -q "$bare" main
    "$real_git" checkout -q "$1"
    "$real_git" merge -q --no-ff -m 'merge main' main
  )
}
merge_fixture feat/m no
base_tip=$("$real_git" -C "$repo" rev-parse main)
assert_eq "a new branch with a merge of the base publishes" "0" "$(run origin feat/m)"
assert_eq "writes: the feature commit, then the merge, then one ref write" \
  "POST blobs,POST trees,POST commits,POST blobs,POST trees,POST commits,POST refs," "$(writes)"
mcommits=$(grep '^POST repos/o/r/git/commits' "$log" | awk '{print $3}')
m1=$(printf '%s\n' "$mcommits" | sed -n 1p)
m2=$(printf '%s\n' "$mcommits" | sed -n 2p)
assert_eq "the feature commit is sent with one parent" "1" "$(jq '.parents | length' "$m1")"
assert_eq "the merge is sent with two parents" "2" "$(jq '.parents | length' "$m2")"
assert_eq "the merge's second parent is the base tip" "$base_tip" "$(jq -r '.parents[1]' "$m2")"
assert_eq "the merge's first parent is the API commit the first request made" "one" "$("$real_git" --git-dir="$bare" log -1 --format=%s "$(jq -r '.parents[0]' "$m2")")"
assert_eq "that API commit sits on the original base" "$("$real_git" -C "$repo" rev-parse main^)" "$("$real_git" --git-dir="$bare" rev-parse "$(jq -r '.parents[0]' "$m2")^")"
assert_eq "no merge-fixture commit request carries author or committer" "false" "$(jq -r 'has("author") or has("committer")' "$m1" "$m2" | sort -u)"
assert_eq "the remote tip has both parents" "$("$real_git" --git-dir="$bare" rev-parse feat/m^1) $base_tip" "$("$real_git" --git-dir="$bare" rev-parse feat/m^1 feat/m^2 | tr '\n' ' ' | sed 's/ $//')"
assert_eq "the remote tip's tree equals the local tip's" "$("$real_git" --git-dir="$bare" rev-parse 'feat/m^{tree}')" "$("$real_git" -C "$repo" rev-parse 'feat/m^{tree}')"
assert_eq "the merge reconcile put the local branch on the remote tip" "$("$real_git" --git-dir="$bare" rev-parse feat/m)" "$("$real_git" -C "$repo" rev-parse feat/m)"
assert_eq "the merge reconcile set the upstream" "origin/feat/m" "$("$real_git" -C "$repo" rev-parse --abbrev-ref feat/m@{upstream})"
merge_fixture feat/me yes
remote_tip=$("$real_git" --git-dir="$bare" rev-parse feat/me)
assert_eq "an existing branch with a merge of the base publishes" "0" "$(run origin feat/me)"
assert_eq "writes: one commit for the merge, then a PATCH" "POST blobs,POST trees,POST commits,PATCH refs," "$(writes)"
mc=$(grep '^POST repos/o/r/git/commits' "$log" | awk '{print $3}')
assert_eq "exactly one commit request" "1" "$(grep -c '^POST repos/o/r/git/commits' "$log")"
assert_eq "its first parent is the remote tip" "$remote_tip" "$(jq -r '.parents[0]' "$mc")"
assert_eq "its second parent is the base tip" "$("$real_git" -C "$repo" rev-parse main)" "$(jq -r '.parents[1]' "$mc")"
assert_eq "the merge's ref is moved with force false" "false" "$(jq -r .force "$(grep '^PATCH ' "$log" | awk '{print $3}')")"
assert_eq "the merge reconciled onto an existing branch" "$("$real_git" --git-dir="$bare" rev-parse feat/me)" "$("$real_git" -C "$repo" rev-parse feat/me)"
fresh
(
  cd "$repo"
  "$real_git" checkout -q -b feat/o && commit_file a.txt a one
  "$real_git" checkout -q main && commit_file b.txt b advance
  "$real_git" push -q "$bare" main
  "$real_git" checkout -q feat/o
  "$real_git" reset -q --hard "$("$real_git" commit-tree -p HEAD -p main -p main^ -m octopus 'HEAD^{tree}')"
)
refused "an octopus merge" origin feat/o
assert_eq "the octopus refusal names the parent count" "yes" "$(grep -q 'no parent or more than two' "$work/out" && echo yes || echo no)"
fresh
(
  cd "$repo"
  "$real_git" checkout -q -b feat/w && commit_file a.txt a one
  "$real_git" checkout -q main && mkdir -p .github/workflows && commit_file .github/workflows/ci.yml x wf
  "$real_git" push -q "$bare" main
  "$real_git" checkout -q feat/w
  "$real_git" merge -q --no-ff -m 'merge main' main
)
refused "a merge that brings in a workflow file" origin feat/w
assert_eq "the workflow refusal names .github/workflows/" "yes" "$(grep -q '\.github/workflows/' "$work/out" && echo yes || echo no)"
fresh
(
  cd "$repo"
  "$real_git" checkout -q -b feat/rev && commit_file a.txt a one
  "$real_git" push -q "$bare" feat/rev
  "$real_git" checkout -q main && commit_file b.txt b other
  "$real_git" merge -q --no-ff -m 'merge PR' feat/rev
  "$real_git" push -q "$bare" main
  "$real_git" checkout -q -B feat/rev main && commit_file c.txt c later
)
refused "an existing branch whose first-parent chain skips the remote tip" origin feat/rev
assert_eq "the skipped-tip refusal names the remote tip" "yes" "$(grep -q 'does not follow the remote tip' "$work/out" && echo yes || echo no)"

fresh
(
  cd "$repo"
  "$real_git" checkout -q -b side && commit_file s.txt s side
  "$real_git" checkout -q main && "$real_git" checkout -q -b feat/g && commit_file m.txt m main-side
  "$real_git" merge -q --no-ff -m merge side
  "$real_git" replace --graft HEAD HEAD^1 main
)
refused "a merge whose second parent a replace ref makes look like the base" origin feat/g
assert_eq "the replace-ref refusal names the second parent" "yes" "$(grep -q 'on no base-set branch' "$work/out" && echo yes || echo no)"

# --- tree equality: a mismatch moves no ref and leaves the branch alone -------------------
fresh
(cd "$repo" && "$real_git" checkout -q -b feat/x && commit_file a.txt a one)
tip=$("$real_git" -C "$repo" rev-parse feat/x)
rc=0
(cd "$repo" && PATH="$work/bin:$PATH" STUB_LOG="$log" STUB_BARE="$bare" STUB_TREE_WRONG=1 sh "$script" origin feat/x) >"$work/out" 2>&1 || rc=$?
assert_eq "a tree mismatch exits 1" "1" "$rc"
assert_eq "a tree mismatch names the local commit" "yes" "$(grep -q "$(printf '%s' "$tip" | cut -c1-7)" "$work/out" && echo yes || echo no)"
assert_eq "a tree mismatch records no ref write" "POST blobs,POST trees,POST commits," "$(writes)"
assert_eq "a tree mismatch leaves the local branch where it was" "$tip" "$("$real_git" -C "$repo" rev-parse feat/x)"
assert_eq "a tree mismatch created no remote branch" "no" "$("$real_git" --git-dir="$bare" rev-parse -q --verify refs/heads/feat/x >/dev/null && echo yes || echo no)"

# --- reconcile: a tree that differs after the ref moved leaves the branch untouched -------
fresh
(cd "$repo" && "$real_git" checkout -q -b feat/x && commit_file a.txt a one)
tip=$("$real_git" -C "$repo" rev-parse feat/x)
rc=0
(cd "$repo" && PATH="$work/bin:$PATH" STUB_LOG="$log" STUB_BARE="$bare" STUB_SWAP=1 sh "$script" origin feat/x) >"$work/out" 2>&1 || rc=$?
assert_eq "a reconcile tree mismatch exits 1" "1" "$rc"
assert_eq "a reconcile tree mismatch has written the ref" "POST blobs,POST trees,POST commits,POST refs," "$(writes)"
assert_eq "a reconcile tree mismatch leaves the local branch untouched" "$tip" "$("$real_git" -C "$repo" rev-parse feat/x)"
assert_eq "a reconcile tree mismatch sets no upstream" "no" "$("$real_git" -C "$repo" rev-parse -q --verify feat/x@{upstream} >/dev/null 2>&1 && echo yes || echo no)"
assert_eq "and a re-run is refused (the remote branch now holds commits)" "2" "$(: >"$log"; run origin feat/x)"
assert_eq "the re-run sent no write" "" "$(writes)"

# --- a path with leading or trailing spaces keeps them -----------------------------------
fresh
(cd "$repo" && "$real_git" checkout -q -b feat/sp && commit_file ' sp ace ' x spaces)
assert_eq "a path with edge spaces publishes" "0" "$(run origin feat/sp)"
assert_eq "the edge spaces survive in the remote tree" " sp ace " "$("$real_git" --git-dir="$bare" ls-tree --name-only feat/sp | grep 'sp ace')"

# --- static: the script's own shape -----------------------------------------------------
assert_eq "the script is stored with mode 100755" "100755" "$("$real_git" -C "$root_dir" ls-files -s plugins/way-of-working/bin/api-commit.sh | cut -d' ' -f1)"
assert_eq "every gh call goes through the pinned wrapper" "0" "$(grep -n 'gh api' "$script" | grep -v -- '--hostname github.com' | grep -vc '^[0-9]*:#' || true)"
assert_eq "the script never builds an author or committer field" "0" "$(grep -v '^#' "$script" | grep -cE 'author|committer' || true)"

exit "$fail"
