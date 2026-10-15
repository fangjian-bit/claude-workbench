#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/review-sandbox.sh (issue #113).
#
# Real throwaway git repos drive the git-plumbing assertions (a "remote"/"origin" plus
# a "workspace" checkout, in review-base-anchor.test.sh's style) -- the bug class this
# guards against is real git behavior under a specific ref/config shape, which only
# real git plumbing can catch. `gh` is the one dependency stubbed, through
# $REVIEW_SANDBOX_GH -- `trust` AND `make` both call it now (`make` re-verifies trust
# itself before building anything; `run`/`destroy` never call `gh` at all).
#
# core.autocrlf: pinned to false on every repo before its first commit or clone, same
# reasoning as review-base-anchor.test.sh's header -- a repo that inherits this
# machine's system-wide core.autocrlf=true converts LF to CRLF on checkout, which would
# make a byte-for-byte content assertion below false-positive.
#
# THE MUTATION THAT MUST TURN THIS SUITE RED: in review-sandbox.sh's `make`, replace
# the `git init --template=<empty> <sbx> && git -C <sbx> fetch --no-tags <workspace>
# refs/review-sandbox/<N>` pair with `git worktree add <sbx> <sha>` against the
# workspace directly, AND drop (or stub out) the `FETCHED` sha-pin check right after
# it -- a plain worktree mutation alone STOPs at that check first (`git -C "$SBX"
# rev-parse FETCH_HEAD` fails: a worktree has no per-worktree FETCH_HEAD of its own).
# That does NOT abort cleanly at "make: succeeds" -- `assert_eq` just prints FAIL and
# continues, so "make: succeeds" and "sandbox is checked out" both print FAIL, and the
# suite only aborts a few lines later, under this file's OWN `set -e`, at the first
# unguarded git command against the (now-garbage) $sbx value
# (`head_sha="$(git -C "$sbx" rev-parse HEAD)"`) -- so it still reads as a suite
# failure, but not the RIGHT one, and not for the reason it looks like -- confirmed by
# running the literal, partial mutation. With both changes made, run this suite
# unmodified afterward -- the "no origin remote" and "no local branches copied"
# fixtures below must both fail, because a worktree shares the workspace's own `.git`
# outright (nothing to leak -- it has direct access) rather than merely risking a leak
# through a clone-shaped copy. (The FETCH_HEAD/reflog fixtures do NOT catch this
# mutation: in a worktree, `$sbx/.git` is a FILE, not a directory, so
# `[ -f "$sbx/.git/FETCH_HEAD" ]` and `[ -f "$sbx/.git/logs/HEAD" ]` are both false
# and those checks read "ok" either way -- confirmed by running the full mutation.
# They still guard the CURRENT design's own FETCH_HEAD leak, just not this specific
# mutation.)
#
# Permitted toolset: git, POSIX sh, real (or stubbed, per fixture) `gh` on PATH,
# `sha256sum`/`shasum` (to assert on the marker's hash, same as the script itself
# needs), and `yq` (the script reads `orchestration.loop_identity` with it, as
# review-base-anchor.sh reads `migration_base`). No jq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/plugins/way-of-working/bin/review-sandbox.sh"

if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  echo "skip - review-sandbox.sh fixtures: no sha256sum or shasum on PATH" >&2
  exit 0
fi
if ! command -v yq >/dev/null 2>&1; then
  echo "skip - review-sandbox.sh fixtures: no yq on PATH (trust reads orchestration.loop_identity)" >&2
  exit 0
fi
hash_str() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'
  else shasum -a 256 | awk '{print $1}'; fi
}

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

assert_true() {
  desc="$1"; cond="$2"
  if [ "$cond" = "1" ]; then
    echo "ok - $desc"
  else
    echo "FAIL - $desc" >&2
    fail=1
  fi
}

# --- the gh stub ---------------------------------------------------------------------
#
# Keyed by PR number via FAKE_GH_PULLS_<N>_* env vars, so each fixture sets exactly
# what it needs. Validates it is asked for `api repos/<repo>/pulls/<N>` with the
# `--jq` expression review-sandbox.sh actually sends -- a stub that ignored its own
# arguments couldn't catch a regression that dropped a field from that expression.
# Both `trust` and `make` call this now: `make` re-verifies trust itself before
# building anything, so every fixture that calls `make` must supply matching
# FAKE_GH_PULLS_<N>_* data too, not only the fixtures that call `trust` directly.
gh_stub="$tmp/fake-gh.sh"
cat > "$gh_stub" <<'STUB'
#!/bin/sh
set -eu
if [ "$1 $2" = "repo view" ]; then
  [ -n "${3:-}" ] || { echo "fake-gh: repo view got an empty URL" >&2; exit 1; }
  case "$*" in
    *defaultBranchRef*) printf '%s\n' "${FAKE_GH_DEFAULT_BRANCH-main}" ;;
    *) printf '%s\n' "${FAKE_GH_REPO:?}" ;;
  esac
  exit 0
fi
if [ "$1" = "api" ]; then
  path="$2"
  case "$path" in
    repos/*/pulls/*)
      n="${path##*/pulls/}"
      case "$*" in
        *'.head.sha'*'.head.repo.full_name'*'.base.ref'*'.author_association'*'.user.login'*'.user.id'*'@tsv'*) : ;;
        *) echo "fake-gh: unexpected pulls jq: $*" >&2; exit 1 ;;
      esac
      eval "sha=\${FAKE_GH_PULLS_${n}_SHA:-}"
      eval "hr=\${FAKE_GH_PULLS_${n}_HEAD_REPO:-}"
      eval "base=\${FAKE_GH_PULLS_${n}_BASE:-main}"
      eval "assoc=\${FAKE_GH_PULLS_${n}_ASSOC:-}"
      eval "login=\${FAKE_GH_PULLS_${n}_LOGIN-someone}"
      eval "uid=\${FAKE_GH_PULLS_${n}_UID-4242}"
      eval "shouldfail=\${FAKE_GH_PULLS_${n}_FAIL:-0}"
      [ "$shouldfail" = 0 ] || { echo "fake-gh: simulated failure for PR $n" >&2; exit 1; }
      [ -n "$sha" ] || { echo "fake-gh: no fixture data for PR $n" >&2; exit 1; }
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$sha" "$hr" "$base" "$assoc" "$login" "$uid"
      ;;
    *) echo "fake-gh: unexpected api path: $path" >&2; exit 1 ;;
  esac
  exit 0
fi
echo "fake-gh: unexpected invocation: $*" >&2
exit 1
STUB
chmod +x "$gh_stub"

# --- repo builders -------------------------------------------------------------------

# new_workspace <name> [<project-yml>] -- an "origin" bare-ish repo plus a "workspace"
# checkout cloned from it, autocrlf pinned off on both from the first commit. The
# default branch (main) commits `.ai/project.yml` -- <project-yml> verbatim, default
# `orchestration: null` (no loop here) -- which `trust` reads the loop identity from.
# Echoes the workspace dir.
new_workspace() {
  name="$1"; project_yml="${2:-orchestration: null}"
  origin="$tmp/$name-origin"
  git init -q -b main "$origin"
  (
    cd "$origin"
    git config user.email t@example.com
    git config user.name t
    git config core.autocrlf false
    echo base > base.txt
    mkdir -p .ai
    printf '%s\n' "$project_yml" > .ai/project.yml
    # `trust` judges the author against `identities` (#382); absent is the unanswered
    # question and a STOP, so a fixture that does not declare one is a pre-cutover repo.
    case "$project_yml" in *identities:*) ;; *) printf 'identities: null\n' >> .ai/project.yml ;; esac
    git add -A
    git commit -qm init
  )
  ws="$tmp/$name-workspace"
  git clone -q -c core.autocrlf=false "$origin" "$ws"
  (
    cd "$ws"
    git config user.email t@example.com
    git config user.name t
  )
  printf '%s' "$ws"
}

# pr_ref <workspace-dir> <N> -- creates a PR branch in the ORIGIN behind <workspace>,
# with one commit on top of base, and points refs/pull/<N>/head at it (simulating a
# GitHub PR ref). Echoes the commit sha.
pr_ref() {
  ws="$1"; n="$2"
  origin=$(cd "$ws" && git remote get-url origin)
  (
    cd "$origin"
    base_branch=$(git symbolic-ref --short HEAD)
    git checkout -qb "pr-$n"
    echo "pr $n change" > "pr-$n.txt"
    git add -A
    git commit -qm "pr $n"
    git update-ref "refs/pull/$n/head" HEAD
    git checkout -q "$base_branch"
    git branch -qD "pr-$n"
  )
  git -C "$ws" fetch -q origin "+refs/pull/$n/head:refs/review-fixture/$n"
  git -C "$ws" rev-parse "refs/review-fixture/$n"
}

# run_script <workspace-dir> <args...> -- runs the script from inside <workspace-dir>,
# with a scratch REVIEW_SANDBOX_ROOT unique to this call, capturing stdout+stderr and
# exit status into $out/$st.
sbx_root_counter=0
run_script() {
  ws="$1"; shift
  sbx_root_counter=$((sbx_root_counter + 1))
  root="$tmp/roots/$sbx_root_counter"
  out="" st=0
  out="$(cd "$ws" && REVIEW_SANDBOX_ROOT="$root" REVIEW_SANDBOX_GH="$gh_stub" "$@" 2>&1)" || st=$?
}

# make_trusted <workspace-dir> <N> <sha> -- run_script wrapper for the common case: a
# trusted, same-repo PR #<N> whose head is <sha>, matching what `make` will itself
# re-verify via `trust`. Sets $out/$st/$root, same as run_script.
make_trusted() {
  ws="$1"; n="$2"; sha="$3"
  run_script "$ws" env FAKE_GH_REPO=acme/repo FAKE_GH_PULLS_"${n}"_HEAD_REPO=acme/repo \
    FAKE_GH_PULLS_"${n}"_BASE=main FAKE_GH_PULLS_"${n}"_ASSOC=MEMBER \
    FAKE_GH_PULLS_"${n}"_SHA="$sha" \
    "$script" make "$n" "$sha"
}

# =========================================================================================
# --- usage: bad arity / bad shape is a malformed invocation (exit 2), not a STOP --------
# =========================================================================================

ws="$(new_workspace usage)"

out="" st=0
out="$(cd "$ws" && "$script" 2>&1)" || st=$?
assert_eq "no subcommand: exit 2" "2" "$st"

out="" st=0
out="$(cd "$ws" && "$script" bogus 2>&1)" || st=$?
assert_eq "unknown subcommand: exit 2" "2" "$st"

out="" st=0
out="$(cd "$ws" && "$script" trust abc 2>&1)" || st=$?
assert_eq "trust: non-numeric N is exit 2" "2" "$st"

out="" st=0
out="$(cd "$ws" && "$script" make 7abc deadbeefdeadbeefdeadbeefdeadbeefdeadbeef 2>&1)" || st=$?
assert_eq "make: non-numeric N is exit 2" "2" "$st"

out="" st=0
out="$(cd "$ws" && "$script" make 7 not-a-sha 2>&1)" || st=$?
assert_eq "make: a non-40-hex sha is exit 2" "2" "$st"

out="" st=0
out="$(cd "$ws" && "$script" make 7 deadbeef 2>&1)" || st=$?
assert_eq "make: a too-short sha is exit 2" "2" "$st"

out="" st=0
out="$(cd "$ws" && "$script" run /tmp/x echo hi 2>&1)" || st=$?
assert_eq "run: a missing -- before <cmd> is exit 2" "2" "$st"

out="" st=0
out="$(cd "$ws" && "$script" destroy 2>&1)" || st=$?
assert_eq "destroy: missing <path> is exit 2" "2" "$st"

# =========================================================================================
# --- trust ---------------------------------------------------------------------------
# =========================================================================================

ws="$(new_workspace trust)"

run_script "$ws" env FAKE_GH_REPO=acme/repo \
  FAKE_GH_PULLS_7_SHA=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef \
  FAKE_GH_PULLS_7_HEAD_REPO=acme/repo FAKE_GH_PULLS_7_BASE=main FAKE_GH_PULLS_7_ASSOC=MEMBER \
  "$script" trust 7
assert_eq "trust: a member's own-repo PR is trusted" \
  "sha=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef head_repo=acme/repo base=main assoc=MEMBER loop=0 trusted=1/0" \
  "$out/$st"

run_script "$ws" env FAKE_GH_REPO=acme/repo \
  FAKE_GH_PULLS_8_SHA=cafebabecafebabecafebabecafebabecafebabe \
  FAKE_GH_PULLS_8_HEAD_REPO=someone/fork FAKE_GH_PULLS_8_BASE=main FAKE_GH_PULLS_8_ASSOC=NONE \
  "$script" trust 8
assert_eq "trust: a fork head from an outside author is untrusted" \
  "sha=cafebabecafebabecafebabecafebabecafebabe head_repo=someone/fork base=main assoc=NONE loop=0 trusted=0/0" \
  "$out/$st"

# A fork head from an ACCOUNT that happens to be a collaborator elsewhere must still
# read untrusted -- trust requires the head to live in THIS repo, not just a trusted
# association on the base repo (the PR could be opened by a member from their own fork).
run_script "$ws" env FAKE_GH_REPO=acme/repo \
  FAKE_GH_PULLS_9_SHA=1111111111111111111111111111111111111111 \
  FAKE_GH_PULLS_9_HEAD_REPO=member-fork/repo FAKE_GH_PULLS_9_BASE=main FAKE_GH_PULLS_9_ASSOC=MEMBER \
  "$script" trust 9
assert_eq "trust: a member's PR from a FORK (not head_repo==repo) is untrusted" \
  "sha=1111111111111111111111111111111111111111 head_repo=member-fork/repo base=main assoc=MEMBER loop=0 trusted=0/0" \
  "$out/$st"

run_script "$ws" env FAKE_GH_REPO=acme/repo FAKE_GH_PULLS_10_FAIL=1 "$script" trust 10
assert_eq "trust: a failed API read is a STOP" "1" "$st"
# $out mixes stdout+stderr, and a failing step (here fake-gh's own diagnostic) may
# print BEFORE the STOP line -- assert a line matching it exists, not a prefix on the
# whole blob (review-base-anchor.test.sh's assert_stop makes the same distinction).
if printf '%s\n' "$out" | grep -q '^STOP '; then
  echo "ok - trust: a failed API read prints a STOP line"
else
  echo "FAIL - trust: a failed API read prints a STOP line, got [$out]" >&2; fail=1
fi

# --- the name rule (#235): the loop identity is untrusted BY NAME, before any ------------
# --- association check, read from the DEFAULT branch's committed copy -------------------

loop_yml="orchestration:
  loop_identity: loop-app[bot]"
ws_loop="$(new_workspace loopid "$loop_yml")"
sha_l=cafecafecafecafecafecafecafecafecafecafe

run_script "$ws_loop" env FAKE_GH_REPO=acme/repo FAKE_GH_PULLS_20_SHA=$sha_l \
  FAKE_GH_PULLS_20_HEAD_REPO=acme/repo FAKE_GH_PULLS_20_BASE=main FAKE_GH_PULLS_20_ASSOC=MEMBER \
  FAKE_GH_PULLS_20_LOGIN='someone-else' "$script" trust 20
assert_eq "trust: a different author is trusted when a loop_identity is declared" \
  "sha=$sha_l head_repo=acme/repo base=main assoc=MEMBER loop=0 trusted=1/0" "$out/$st"

# The failing-open case: the loop is (or was) a machine user, and its MEMBER association
# would pass the association check. The name rule fires first.
run_script "$ws_loop" env FAKE_GH_REPO=acme/repo FAKE_GH_PULLS_21_SHA=$sha_l \
  FAKE_GH_PULLS_21_HEAD_REPO=acme/repo FAKE_GH_PULLS_21_BASE=main FAKE_GH_PULLS_21_ASSOC=MEMBER \
  FAKE_GH_PULLS_21_LOGIN='loop-app[bot]' "$script" trust 21
assert_eq "trust: the loop identity is untrusted by name though its association is MEMBER" \
  "sha=$sha_l head_repo=acme/repo base=main assoc=MEMBER loop=1 trusted=0/0" "$out/$st"

run_script "$ws_loop" env FAKE_GH_REPO=acme/repo FAKE_GH_PULLS_22_SHA=$sha_l \
  FAKE_GH_PULLS_22_HEAD_REPO=acme/repo FAKE_GH_PULLS_22_BASE=main FAKE_GH_PULLS_22_ASSOC=OWNER \
  FAKE_GH_PULLS_22_LOGIN='LOOP-APP[BOT]' "$script" trust 22
assert_eq "trust: the name comparison is case-insensitive, and beats OWNER" \
  "sha=$sha_l head_repo=acme/repo base=main assoc=OWNER loop=1 trusted=0/0" "$out/$st"

# A STALE loop_identity: the declared login no longer names the loop. The rule refuses
# only the NAME it was given, so this pins both halves honestly: the stale name's own
# login is still refused (a COLLABORATOR machine user whose association would pass), and
# a DIFFERENT login is judged by association alone -- the residual the driver's
# preflight login-equality check (plan 7.3) exists to close, not this predicate.
loop_yml_stale="orchestration:
  loop_identity: old-machine-user"
ws_stale="$(new_workspace loopid-stale "$loop_yml_stale")"
run_script "$ws_stale" env FAKE_GH_REPO=acme/repo FAKE_GH_PULLS_23_SHA=$sha_l   FAKE_GH_PULLS_23_HEAD_REPO=acme/repo FAKE_GH_PULLS_23_BASE=main FAKE_GH_PULLS_23_ASSOC=COLLABORATOR   FAKE_GH_PULLS_23_LOGIN='old-machine-user' "$script" trust 23
assert_eq "trust: a stale loop_identity still refuses its own login (a COLLABORATOR machine user)"   "sha=$sha_l head_repo=acme/repo base=main assoc=COLLABORATOR loop=1 trusted=0/0" "$out/$st"

run_script "$ws_stale" env FAKE_GH_REPO=acme/repo FAKE_GH_PULLS_29_SHA=$sha_l   FAKE_GH_PULLS_29_HEAD_REPO=acme/repo FAKE_GH_PULLS_29_BASE=main FAKE_GH_PULLS_29_ASSOC=COLLABORATOR   FAKE_GH_PULLS_29_LOGIN='new-machine-user' "$script" trust 29
assert_eq "trust: a login the stale loop_identity does not name is judged by association (the stated residual)"   "sha=$sha_l head_repo=acme/repo base=main assoc=COLLABORATOR loop=0 trusted=1/0" "$out/$st"

# The REST form is `<slug>[bot]`; the bare slug (GraphQL's form) names the same App, so [bot] is folded.
run_script "$ws_loop" env FAKE_GH_REPO=acme/repo FAKE_GH_PULLS_30_SHA=$sha_l   FAKE_GH_PULLS_30_HEAD_REPO=acme/repo FAKE_GH_PULLS_30_BASE=main FAKE_GH_PULLS_30_ASSOC=MEMBER   FAKE_GH_PULLS_30_LOGIN='loop-app' "$script" trust 30
assert_eq "trust: the bare slug author is the App's name too ([bot] folded on both sides)"   "sha=$sha_l head_repo=acme/repo base=main assoc=MEMBER loop=1 trusted=0/0" "$out/$st"

# The copy read is origin's default branch, not the checkout's own commit: a local
# branch whose COMMITTED project.yml differs (HEAD != origin/main) must not decide it.
git -C "$ws_loop" checkout -q -b local-edit
printf 'orchestration:
  loop_identity: nobody
' > "$ws_loop/.ai/project.yml"
git -C "$ws_loop" commit -qam "local edit of loop_identity"
run_script "$ws_loop" env FAKE_GH_REPO=acme/repo FAKE_GH_PULLS_31_SHA=$sha_l FAKE_GH_PULLS_31_HEAD_REPO=acme/repo FAKE_GH_PULLS_31_BASE=main FAKE_GH_PULLS_31_ASSOC=MEMBER FAKE_GH_PULLS_31_LOGIN='loop-app[bot]' "$script" trust 31
assert_eq "trust: a COMMITTED local edit of project.yml does not change who is untrusted" "sha=$sha_l head_repo=acme/repo base=main assoc=MEMBER loop=1 trusted=0/0" "$out/$st"
git -C "$ws_loop" checkout -q main

# `trust` FETCHES the default branch: a loop_identity committed to origin AFTER this
# checkout last fetched must still count (a stale remote-tracking ref would read "none").
ws_fresh="$(new_workspace loopid-fresh 'orchestration: null')"
origin_fresh="$(git -C "$ws_fresh" remote get-url origin)"
printf 'orchestration:
  loop_identity: loop-app[bot]
identities: null
' > "$origin_fresh/.ai/project.yml"
git -C "$origin_fresh" commit -qam "declare loop_identity"
run_script "$ws_fresh" env FAKE_GH_REPO=acme/repo FAKE_GH_PULLS_33_SHA=$sha_l FAKE_GH_PULLS_33_HEAD_REPO=acme/repo FAKE_GH_PULLS_33_BASE=main FAKE_GH_PULLS_33_ASSOC=MEMBER FAKE_GH_PULLS_33_LOGIN='loop-app[bot]' "$script" trust 33
assert_eq "trust: fetches the default branch, so a just-declared loop_identity counts" "sha=$sha_l head_repo=acme/repo base=main assoc=MEMBER loop=1 trusted=0/0" "$out/$st"

# An unparseable default-branch copy is a STOP (yq fails), never a silent "no loop identity".
ws_bad="$(new_workspace loopid-bad 'orchestration: [unterminated')"
run_script "$ws_bad" env FAKE_GH_REPO=acme/repo FAKE_GH_PULLS_32_SHA=$sha_l FAKE_GH_PULLS_32_HEAD_REPO=acme/repo FAKE_GH_PULLS_32_BASE=main FAKE_GH_PULLS_32_ASSOC=MEMBER "$script" trust 32
assert_eq "trust: an unparseable default-branch .ai/project.yml is a STOP" "1" "$st"

# --- trust by declared identity (#382, WB-D24): `identities` a map on the default -------
# --- branch, so the author's {login, id} decides and author_association does not ---------
# Under an App token GitHub reports the maintainer's own PR as CONTRIBUTOR; the declared
# maintainer is still trusted. A MEMBER association alone is no longer enough.
id_yml="orchestration: null
identities:
  maintainer:
    - { login: alice-dev, id: 1001 }
  dev_app: { login: \"acme-dev[bot]\", id: 2001 }
  reviewer_app: null
  loop_app: null"
ws_id="$(new_workspace identity "$id_yml")"
idtrust() { # idtrust <N> <assoc> <login> <uid> <head_repo> -> trust output in $out/$st
  n="$1"
  eval "run_script \"\$ws_id\" env FAKE_GH_REPO=acme/repo FAKE_GH_PULLS_${n}_SHA=\$sha_l \
    FAKE_GH_PULLS_${n}_HEAD_REPO=$5 FAKE_GH_PULLS_${n}_BASE=main FAKE_GH_PULLS_${n}_ASSOC=$2 \
    FAKE_GH_PULLS_${n}_LOGIN='$3' FAKE_GH_PULLS_${n}_UID=$4 \"\$script\" trust $n"
}
idtrust 40 CONTRIBUTOR alice-dev 1001 acme/repo
assert_eq "trust (identities): the declared maintainer is trusted though an App token reads CONTRIBUTOR" \
  "sha=$sha_l head_repo=acme/repo base=main assoc=CONTRIBUTOR loop=0 trusted=1/0" "$out/$st"
idtrust 41 NONE ALICE-DEV 1001 acme/repo
assert_eq "trust (identities): login compared case-insensitively" \
  "sha=$sha_l head_repo=acme/repo base=main assoc=NONE loop=0 trusted=1/0" "$out/$st"
idtrust 42 MEMBER stranger 9999 acme/repo
assert_eq "trust (identities): a MEMBER association alone no longer trusts an undeclared author" \
  "sha=$sha_l head_repo=acme/repo base=main assoc=MEMBER loop=0 trusted=0/0" "$out/$st"
idtrust 43 OWNER 'acme-dev[bot]' 2001 acme/repo
assert_eq "trust (identities): the dev App's own PR is not trusted, whatever its association" \
  "sha=$sha_l head_repo=acme/repo base=main assoc=OWNER loop=0 trusted=0/0" "$out/$st"
idtrust 44 MEMBER alice-dev 9999 acme/repo
assert_eq "trust (identities): a declared login on another id is untrusted" \
  "sha=$sha_l head_repo=acme/repo base=main assoc=MEMBER loop=0 trusted=0/0" "$out/$st"
idtrust 45 CONTRIBUTOR alice-dev 1001 someone/fork
assert_eq "trust (identities): a maintainer's fork head is still untrusted" \
  "sha=$sha_l head_repo=someone/fork base=main assoc=CONTRIBUTOR loop=0 trusted=0/0" "$out/$st"
idtrust 46 MEMBER alice-renamed 1001 acme/repo
assert_eq "trust (identities): a declared id under another login is a STOP, not a guess" "1" "$st"
idtrust 47 MEMBER alice-dev '' acme/repo
assert_eq "trust (identities): a PR answering no author id is a STOP" "1" "$st"
# The sibling gh-identity.sh decides, not whatever is first on PATH: a stale or hostile copy
# that trusts everyone must not turn an undeclared author into a trusted one.
stale_bin="$tmp/stale-bin"; mkdir -p "$stale_bin"
printf '#!/bin/sh
echo trusted
' >"$stale_bin/gh-identity.sh"; chmod +x "$stale_bin/gh-identity.sh"
run_script "$ws_id" env PATH="$stale_bin:$PATH" FAKE_GH_REPO=acme/repo FAKE_GH_PULLS_49_SHA=$sha_l FAKE_GH_PULLS_49_HEAD_REPO=acme/repo FAKE_GH_PULLS_49_BASE=main FAKE_GH_PULLS_49_ASSOC=MEMBER FAKE_GH_PULLS_49_LOGIN=stranger FAKE_GH_PULLS_49_UID=9999 "$script" trust 49
assert_eq "trust (identities): a gh-identity.sh earlier on PATH does not decide trust"   "sha=$sha_l head_repo=acme/repo base=main assoc=MEMBER loop=0 trusted=0/0" "$out/$st"
ws_noid="$(new_workspace identity-absent 'orchestration: null')"
noid_origin="$(git -C "$ws_noid" remote get-url origin)"
printf 'orchestration: null\n' > "$noid_origin/.ai/project.yml"
git -C "$noid_origin" commit -qam "drop the identities key"
run_script "$ws_noid" env FAKE_GH_REPO=acme/repo FAKE_GH_PULLS_48_SHA=$sha_l FAKE_GH_PULLS_48_HEAD_REPO=acme/repo FAKE_GH_PULLS_48_BASE=main FAKE_GH_PULLS_48_ASSOC=MEMBER "$script" trust 48
assert_eq "trust (identities): an absent identities key is a STOP, never the association fallback" "1" "$st"

# `make` re-verifies mechanically: a loop-authored PR never builds, whatever the caller says.
sha_m="$(pr_ref "$ws_loop" 24)"
sbx_root_counter=$((sbx_root_counter + 1))
root="$tmp/roots/$sbx_root_counter"
out="" st=0
out="$(cd "$ws_loop" && REVIEW_SANDBOX_ROOT="$root" REVIEW_SANDBOX_GH="$gh_stub" \
  FAKE_GH_REPO=acme/repo FAKE_GH_PULLS_24_HEAD_REPO=acme/repo FAKE_GH_PULLS_24_BASE=main \
  FAKE_GH_PULLS_24_ASSOC=MEMBER FAKE_GH_PULLS_24_LOGIN='loop-app[bot]' FAKE_GH_PULLS_24_SHA="$sha_m" \
  "$script" make 24 "$sha_m" 2>&1)" || st=$?
assert_eq "make: a PR authored by the loop identity is a STOP though its association passes" "1" "$st"
assert_true "make: no sandbox is built for a loop-authored PR" \
  "$([ -e "$root/24" ] && echo 0 || echo 1)"

# A PR cannot choose which login is untrusted: a PR-side edit to the checkout's own
# `.ai/project.yml` is invisible, because the copy read is the default branch's.
printf 'orchestration:\n  loop_identity: nobody\n' > "$ws_loop/.ai/project.yml"
run_script "$ws_loop" env FAKE_GH_REPO=acme/repo FAKE_GH_PULLS_25_SHA=$sha_l \
  FAKE_GH_PULLS_25_HEAD_REPO=acme/repo FAKE_GH_PULLS_25_BASE=main FAKE_GH_PULLS_25_ASSOC=MEMBER \
  FAKE_GH_PULLS_25_LOGIN='loop-app[bot]' "$script" trust 25
assert_eq "trust: the checkout's own edited .ai/project.yml does not change who is untrusted" \
  "sha=$sha_l head_repo=acme/repo base=main assoc=MEMBER loop=1 trusted=0/0" "$out/$st"
git -C "$ws_loop" checkout -q -- .ai/project.yml

# Unreadable inputs are a STOP, never a silent "no loop identity".
ws_nofile="$tmp/nofile-workspace"
origin_nofile="$tmp/nofile-origin"
git init -q -b main "$origin_nofile"
(cd "$origin_nofile" && git config user.email t@example.com && git config user.name t \
  && git config core.autocrlf false && echo b > b.txt && git add -A && git commit -qm init)
git clone -q -c core.autocrlf=false "$origin_nofile" "$ws_nofile"
run_script "$ws_nofile" env FAKE_GH_REPO=acme/repo FAKE_GH_PULLS_26_SHA=$sha_l \
  FAKE_GH_PULLS_26_HEAD_REPO=acme/repo FAKE_GH_PULLS_26_BASE=main FAKE_GH_PULLS_26_ASSOC=MEMBER \
  "$script" trust 26
assert_eq "trust: a default branch with no .ai/project.yml is a STOP, not 'no loop identity'" "1" "$st"

run_script "$ws_loop" env FAKE_GH_REPO=acme/repo FAKE_GH_DEFAULT_BRANCH= FAKE_GH_PULLS_27_SHA=$sha_l \
  FAKE_GH_PULLS_27_HEAD_REPO=acme/repo FAKE_GH_PULLS_27_BASE=main FAKE_GH_PULLS_27_ASSOC=MEMBER \
  "$script" trust 27
assert_eq "trust: an unresolvable default branch is a STOP" "1" "$st"

run_script "$ws_loop" env FAKE_GH_REPO=acme/repo FAKE_GH_PULLS_28_SHA=$sha_l \
  FAKE_GH_PULLS_28_HEAD_REPO=acme/repo FAKE_GH_PULLS_28_BASE=main FAKE_GH_PULLS_28_ASSOC=MEMBER \
  FAKE_GH_PULLS_28_LOGIN= "$script" trust 28
assert_eq "trust: an empty author login is a STOP, never a pass" "1" "$st"

# =========================================================================================
# --- make: refuses to build for an untrusted PR, mechanically -- not by trusting the ----
# --- caller to have honored trust=0 -----------------------------------------------------
# =========================================================================================

ws="$(new_workspace make-untrusted)"
sha="$(pr_ref "$ws" 7)"

sbx_root_counter=$((sbx_root_counter + 1))
root="$tmp/roots/$sbx_root_counter"
out="" st=0
out="$(cd "$ws" && REVIEW_SANDBOX_ROOT="$root" REVIEW_SANDBOX_GH="$gh_stub" \
  FAKE_GH_REPO=acme/repo FAKE_GH_PULLS_7_HEAD_REPO=someone/fork \
  FAKE_GH_PULLS_7_BASE=main FAKE_GH_PULLS_7_ASSOC=NONE FAKE_GH_PULLS_7_SHA="$sha" \
  "$script" make 7 "$sha" 2>&1)" || st=$?
assert_eq "make: an untrusted PR (fork head, no association) is a STOP" "1" "$st"
if printf '%s\n' "$out" | grep -q '^STOP '; then
  echo "ok - make: refusing an untrusted PR prints a STOP line"
else
  echo "FAIL - make: refusing an untrusted PR prints a STOP line, got [$out]" >&2; fail=1
fi
assert_true "make: no sandbox is built for an untrusted PR" \
  "$([ -e "$root/7" ] && echo 0 || echo 1)"
assert_true "make: an untrusted PR never even reaches the fetch (no refs/review-sandbox/7 in the workspace)" \
  "$(git -C "$ws" rev-parse --verify -q refs/review-sandbox/7 >/dev/null 2>&1 && echo 0 || echo 1)"

# =========================================================================================
# --- make: a caller-supplied sha disagreeing with the fresh trust read is a STOP -------
# --- BEFORE any git operation, distinct from the fetched-ref-level check below --------
# =========================================================================================

ws="$(new_workspace make-trust-mismatch)"
sha="$(pr_ref "$ws" 7)"
claimed="1111111111111111111111111111111111111111"

sbx_root_counter=$((sbx_root_counter + 1))
root="$tmp/roots/$sbx_root_counter"
out="" st=0
out="$(cd "$ws" && REVIEW_SANDBOX_ROOT="$root" REVIEW_SANDBOX_GH="$gh_stub" \
  FAKE_GH_REPO=acme/repo FAKE_GH_PULLS_7_HEAD_REPO=acme/repo FAKE_GH_PULLS_7_BASE=main \
  FAKE_GH_PULLS_7_ASSOC=MEMBER FAKE_GH_PULLS_7_SHA="$claimed" \
  "$script" make 7 "$sha" 2>&1)" || st=$?
assert_eq "make: caller's sha != trust's fresh sha is a STOP" "1" "$st"
assert_true "make: never reaches the fetch when the trust check itself refuses" \
  "$(git -C "$ws" rev-parse --verify -q refs/review-sandbox/7 >/dev/null 2>&1 && echo 0 || echo 1)"

# =========================================================================================
# --- make: the fetched ref disagreeing with the pinned sha is ALSO a STOP (the git- -----
# --- level check, reachable when trust matches but the workspace's own ref moved) ------
# =========================================================================================

ws="$(new_workspace make-ref-mismatch)"
real_sha="$(pr_ref "$ws" 7)"
# trust "claims" a different sha than what refs/pull/7/head actually resolves to in
# this workspace's origin -- a narrow TOCTOU shape (the API's view moved, or disagrees
# with the ref the workspace can actually fetch), distinct from the trust-level check
# above, which never reaches a git operation at all.
claimed="2222222222222222222222222222222222222222"

sbx_root_counter=$((sbx_root_counter + 1))
root="$tmp/roots/$sbx_root_counter"
out="" st=0
out="$(cd "$ws" && REVIEW_SANDBOX_ROOT="$root" REVIEW_SANDBOX_GH="$gh_stub" \
  FAKE_GH_REPO=acme/repo FAKE_GH_PULLS_7_HEAD_REPO=acme/repo FAKE_GH_PULLS_7_BASE=main \
  FAKE_GH_PULLS_7_ASSOC=MEMBER FAKE_GH_PULLS_7_SHA="$claimed" \
  "$script" make 7 "$claimed" 2>&1)" || st=$?
assert_eq "make: a fetched ref that disagrees with the (trust-matching) pinned sha is a STOP" "1" "$st"
case "$out" in
  *"pinned sha mismatch"*) echo "ok - make: the git-level pinned-sha-mismatch STOP fired, not the trust one" ;;
  *) echo "FAIL - make: expected the git-level pinned-sha-mismatch STOP, got [$out]" >&2; fail=1 ;;
esac
assert_true "make: no sandbox directory survives a git-level sha-mismatch STOP" \
  "$([ -e "$root/7" ] && echo 0 || echo 1)"

# =========================================================================================
# --- make: the happy path leaves no trace of clone/worktree sharing --------------------
# =========================================================================================

ws="$(new_workspace make-happy)"
sha="$(pr_ref "$ws" 7)"

make_trusted "$ws" 7 "$sha"
assert_eq "make: succeeds and prints the sandbox path" "0" "$st"
sbx="$out"

content="$(cat "$sbx/pr-7.txt" 2>/dev/null || echo MISSING)"
assert_eq "make: the sandbox is checked out at the pinned sha's content" "pr 7 change" "$content"

head_sha="$(git -C "$sbx" rev-parse HEAD)"
assert_eq "make: the sandbox HEAD is exactly the pinned sha, detached" "$sha" "$head_sha"

branches="$(git -C "$sbx" for-each-ref refs/heads --format='%(refname)' | tr -d '\n')"
assert_eq "make: no local branches were copied" "" "$branches"

remotes="$(git -C "$sbx" remote)"
assert_eq "make: no origin remote exists in the sandbox" "" "$remotes"

assert_true "make: FETCH_HEAD is scrubbed (no workspace-path leak)" \
  "$([ -f "$sbx/.git/FETCH_HEAD" ] && echo 0 || echo 1)"

# logs/HEAD is recreated by checkout itself (an ordinary ref-move entry, sha only) --
# assert it carries no absolute path segment naming the workspace, not that it's absent.
if [ -f "$sbx/.git/logs/HEAD" ] && grep -qF "$ws" "$sbx/.git/logs/HEAD" 2>/dev/null; then
  echo "FAIL - make: the workspace path leaked into the sandbox's own reflog" >&2
  fail=1
else
  echo "ok - make: the sandbox's reflog does not name the workspace path"
fi

# Regression: the marker used to carry the workspace path in the clear, one directory
# above a sandbox PR code runs inside (`cat ../7.marker` read it straight out) --
# reproduced live by this suite's own architect critic pass. It must now be a hash,
# not the path itself, and readable-from-the-sandbox access to it must not disclose
# the path.
marker="$root/7.marker"
if [ -f "$marker" ] && grep -qF "$ws" "$marker" 2>/dev/null; then
  echo "FAIL - make: the marker still carries the workspace path in the clear" >&2
  fail=1
else
  echo "ok - make: the marker does not carry the workspace path in the clear"
fi
marker_line1="$(sed -n '1p' "$marker" 2>/dev/null || true)"
expect_hash="$(printf '%s' "$(cd "$ws" && pwd -P)" | hash_str)"
assert_eq "make: the marker's first line is the sha256 of the workspace's canonical path" \
  "$expect_hash" "$marker_line1"

REVIEW_SANDBOX_ROOT="$root" sh "$script" destroy "$sbx" || true

# =========================================================================================
# --- make: the checkout ignores the CALLER's own global git config, not just run's -----
# =========================================================================================
#
# An earlier version of this script applied the LFS/config isolation only inside
# `run`, leaving `make`'s own fetch+checkout to read the reviewer's real system/global
# git config -- three critics on #113 independently found this by reading the code,
# not by a fixture, which is exactly the gap this fixture closes.
#
# TWO earlier versions of THIS fixture were themselves vacuous, found by mutation
# (removing GIT_CONFIG_NOSYSTEM/GIT_CONFIG_GLOBAL from make's own git calls left the
# suite green): (1) it used a global `core.hooksPath` canary, which the command line's
# own `-c core.hooksPath="$EMPTY_TEMPLATE"` overrides regardless of what the ENV VAR
# points `make` at protecting against -- proving nothing about GIT_CONFIG_GLOBAL/
# NOSYSTEM at all; (2) the canary script's path was written with a raw MSYS-style
# path (`printf '%s'`), which native git.exe does not translate inside a CONFIG FILE
# value the way it translates an argv path -- the hook never would have fired even
# unprotected. Fixed shape: a global `filter.canary.smudge` (a key none of make's own
# `-c filter.lfs.*=` overrides touch, since those name `filter.lfs`, not
# `filter.canary`) triggered by a `.gitattributes` in the PR's own commit, with the
# canary script's path translated via `cygpath -m` when available -- and a POSITIVE
# CONTROL that fires the SAME config against a plain, unprotected checkout first, so
# a broken canary mechanism can never again read as "the isolation worked".

ws="$(new_workspace make-global-config)"
canary="$tmp/global-hook-canary"
rm -f "$canary"
smudge_script="$tmp/global-canary-smudge.sh"
{
  echo '#!/bin/sh'
  echo 'cat >/dev/null'
  printf 'touch %s\n' "$canary"
} > "$smudge_script"
chmod +x "$smudge_script"
if command -v cygpath >/dev/null 2>&1; then
  smudge_path="$(cygpath -m "$smudge_script")"
else
  smudge_path="$smudge_script"
fi
fake_global="$tmp/fake-global-gitconfig"
printf '[filter "canary"]\n\tsmudge = sh %s\n\trequired = false\n' "$smudge_path" > "$fake_global"

# A PR commit whose OWN .gitattributes routes a file through the canary filter --
# the same mechanism a real LFS-shaped attack (`.gitattributes` + `.lfsconfig`) would
# use, standing in for it without needing real git-lfs installed to test against.
origin=$(cd "$ws" && git remote get-url origin)
(
  cd "$origin"
  base_branch=$(git symbolic-ref --short HEAD)
  git checkout -qb pr-canary
  printf 'canary-trigger.txt filter=canary\n' > .gitattributes
  echo canary-content > canary-trigger.txt
  git add -A
  git commit -qm "pr canary"
  git update-ref refs/pull/7/head HEAD
  git checkout -q "$base_branch"
  git branch -qD pr-canary
)
sha=$(cd "$ws" && git fetch -q origin "+refs/pull/7/head:refs/review-fixture-canary/7" \
  && git rev-parse refs/review-fixture-canary/7)

# Positive control: the SAME global config, against a plain unprotected checkout of
# the SAME commit, must fire the canary -- if it doesn't, the fixture below proves
# nothing and must not be read as a pass.
control_clone="$tmp/canary-positive-control"
rm -rf "$control_clone" "$canary"
git clone -q -c core.autocrlf=false "$origin" "$control_clone" >/dev/null
GIT_CONFIG_GLOBAL="$fake_global" git -C "$control_clone" checkout -q "$sha" >/dev/null 2>&1 || true
if [ -f "$canary" ]; then
  echo "ok - make-global-config: the positive control fires the canary on an unprotected checkout"
else
  echo "FAIL - make-global-config: the positive control did NOT fire on an unprotected checkout -- this fixture cannot prove anything below" >&2
  fail=1
fi
rm -rf "$control_clone"
rm -f "$canary"

sbx_root_counter=$((sbx_root_counter + 1))
root="$tmp/roots/$sbx_root_counter"
out="" st=0
out="$(cd "$ws" && GIT_CONFIG_GLOBAL="$fake_global" REVIEW_SANDBOX_ROOT="$root" \
  REVIEW_SANDBOX_GH="$gh_stub" FAKE_GH_REPO=acme/repo FAKE_GH_PULLS_7_HEAD_REPO=acme/repo \
  FAKE_GH_PULLS_7_BASE=main FAKE_GH_PULLS_7_ASSOC=MEMBER FAKE_GH_PULLS_7_SHA="$sha" \
  "$script" make 7 "$sha" 2>&1)" || st=$?
[ "$st" = 0 ] || { echo "FAIL - make: build under a hostile caller global config failed outright (exit $st): $out" >&2; fail=1; }
if [ -f "$canary" ]; then
  echo "FAIL - make: the caller's own global git config (a hostile filter.canary.smudge) reached the checkout" >&2
  fail=1
else
  echo "ok - make: the checkout ignores the caller's own global git config (positive-controlled)"
fi
[ "$st" = 0 ] && REVIEW_SANDBOX_ROOT="$root" sh "$script" destroy "$out" || true

# =========================================================================================
# --- make: stale-sandbox reuse is scoped to the SAME workspace and N -------------------
# =========================================================================================

ws="$(new_workspace make-reuse)"
sha="$(pr_ref "$ws" 7)"
sbx_root_counter=$((sbx_root_counter + 1))
root="$tmp/roots/$sbx_root_counter"
gh_env="FAKE_GH_REPO=acme/repo FAKE_GH_PULLS_7_HEAD_REPO=acme/repo FAKE_GH_PULLS_7_BASE=main FAKE_GH_PULLS_7_ASSOC=MEMBER FAKE_GH_PULLS_7_SHA=$sha"

out="" st=0
out="$(cd "$ws" && env $gh_env REVIEW_SANDBOX_ROOT="$root" REVIEW_SANDBOX_GH="$gh_stub" \
  "$script" make 7 "$sha" 2>&1)" || st=$?
assert_eq "make: first build for N=7 succeeds" "0" "$st"

out="" st=0
out="$(cd "$ws" && env $gh_env REVIEW_SANDBOX_ROOT="$root" REVIEW_SANDBOX_GH="$gh_stub" \
  "$script" make 7 "$sha" 2>&1)" || st=$?
assert_eq "make: rebuilding N=7 from the SAME workspace succeeds (marker hash matches)" "0" "$st"

ws2="$(new_workspace make-reuse2)"
# `make` now fetches BEFORE checking the marker (shrinks the window a leftover
# process has to act between a stale-sandbox removal and rebuild -- see the script's
# own comment on this reordering), so ws2 needs ITS OWN fetchable refs/pull/7/head
# too, or the fixture would stop at "fetch failed" rather than at the marker-mismatch
# STOP this test actually means to exercise. Its own sha doesn't need to match $sha
# -- only that the ref exists for the fetch to succeed; the marker check (which
# compares WORKSPACE, not ref content) is what must fire next.
pr_ref "$ws2" 7 >/dev/null
out="" st=0
out="$(cd "$ws2" && env $gh_env REVIEW_SANDBOX_ROOT="$root" REVIEW_SANDBOX_GH="$gh_stub" \
  "$script" make 7 "$sha" 2>&1)" || st=$?
assert_eq "make: a DIFFERENT workspace claiming the same N is a STOP, not a silent reuse" \
  "1" "$st"
case "$out" in
  *"marker does not match"*) echo "ok - make: cross-workspace N collision prints the marker-mismatch STOP" ;;
  *) echo "FAIL - make: cross-workspace N collision prints a STOP line, got [$out]" >&2; fail=1 ;;
esac

REVIEW_SANDBOX_ROOT="$root" sh "$script" destroy "$root/7" 2>/dev/null || true

# =========================================================================================
# --- run: the stripped environment actually strips -------------------------------------
# =========================================================================================

ws="$(new_workspace run-env)"
sha="$(pr_ref "$ws" 7)"
make_trusted "$ws" 7 "$sha"
sbx="$out"

out="" st=0
out="$(cd "$ws" && REVIEW_SANDBOX_ROOT="$root" GH_TOKEN=super-secret \
  "$script" run "$sbx" -- sh -c 'printf "%s" "${GH_TOKEN:-unset}"' 2>&1)" || st=$?
# Scoped claim: GH_TOKEN does not reach the sandboxed command's OWN environment
# variable. It is still separately readable via /proc/<pid>/environ on an ANCESTOR
# process (timeout, this script) -- see the script's header residual; this fixture
# does not and cannot exercise that.
assert_eq "run: GH_TOKEN from the caller's environment does not reach the sandboxed command's own env var" \
  "unset/0" "$out/$st"

# Regression: an earlier version of this script used the NUMERIC sentinel 199 to
# signal "cd into the sandbox failed" internally, colliding with a <cmd> that
# legitimately exits 199 itself -- reproduced live, a command that DID run and
# printed output was reported as "never started" (STOP, exit 111). <cmd>'s own exit
# status must pass through completely unchanged, whatever number it picks, including
# ones this script also uses internally for its own signaling.
out="" st=0
out="$(cd "$ws" && REVIEW_SANDBOX_ROOT="$root" "$script" run "$sbx" -- sh -c 'echo ran; exit 199' 2>&1)" || st=$?
assert_eq "run: a wrapped command's own exit 199 passes through unchanged, never misread as a pre-execution refusal" \
  "ran/199" "$out/$st"

out="" st=0
out="$(cd "$ws" && REVIEW_SANDBOX_ROOT="$root" HOME="$tmp/fake-home" \
  "$script" run "$sbx" -- sh -c 'printf "%s" "$HOME"' 2>&1)" || st=$?
# Assert the ACTUAL repointed value, not merely "not the caller's" -- a fixture that
# only checks inequality would still pass if HOME were dropped from the allowlist
# entirely (unset prints empty, which is also != "$tmp/fake-home").
if [ "$st" = 0 ] && [ "$out" = "$sbx/.review-sandbox-home" ]; then
  echo "ok - run: HOME is repointed inside the sandbox to .review-sandbox-home, not inherited"
else
  echo "FAIL - run: HOME check failed, exit $st, expected [$sbx/.review-sandbox-home] got [$out]" >&2; fail=1
fi

# A hostile core.hooksPath planted by one `run` call IS a real, local-repo-config
# write, and WILL fire again on a later `run` (that is the spec's own stated residual
# -- SKILL.md's job is never touching the sandbox any other way, not this script's).
# What THIS script promises is narrower and still worth pinning: the hook fires under
# the SAME stripped DIRECT environment every time, so GH_TOKEN never reaches the
# hook's own environment variable, once planted, same as the plain `run` case above.
# This does NOT mean the hook "can never see real credentials" -- it runs as the
# invoking user and can still reach the OS keyring (`gh auth token`) or read GH_TOKEN
# from an ancestor process's /proc/<pid>/environ, exactly like any other command
# under `run` (see the script's header residuals). The canary hook writes out what IT
# sees GH_TOKEN AS ITS OWN ENV VAR; a second `run`, invoked with a real secret in the
# CALLER's own environment, must still show the hook reading "unset" there, not the
# secret.
canary="$tmp/hook-canary"
rm -f "$canary"
out="" st=0
out="$(cd "$ws" && REVIEW_SANDBOX_ROOT="$root" "$script" run "$sbx" -- sh -c "mkdir -p \"$tmp/hooks\" && git config core.hooksPath \"$tmp/hooks\" && printf '#!/bin/sh\\nprintf \"GH_TOKEN=%%s\" \"\${GH_TOKEN:-unset}\" > $canary\\n' > \"$tmp/hooks/post-checkout\" && chmod +x \"$tmp/hooks/post-checkout\"" 2>&1)" || st=$?
[ "$st" = 0 ] || { echo "FAIL - run: could not plant the hostile hook (exit $st): $out" >&2; fail=1; }
out="" st=0
out="$(cd "$ws" && REVIEW_SANDBOX_ROOT="$root" GH_TOKEN=super-secret \
  "$script" run "$sbx" -- git checkout -q --detach HEAD 2>&1)" || st=$?
[ "$st" = 0 ] || { echo "FAIL - run: the checkout meant to trigger the hook itself failed (exit $st): $out" >&2; fail=1; }
if [ -f "$canary" ] && [ "$(cat "$canary")" = "GH_TOKEN=unset" ]; then
  echo "ok - run: a hook planted by an earlier run still executes under the stripped env, its own GH_TOKEN var never the caller's real one"
else
  echo "FAIL - run: the re-triggered hook saw [$(cat "$canary" 2>/dev/null || echo "<no canary>")], expected GH_TOKEN=unset" >&2
  fail=1
fi

# A detached background process should be dead once `run` returns. Two things were
# wrong with an earlier version of this fixture, both found live: (1) it checked with
# `pgrep`, absent under Git Bash, so it silently reported "ok" without checking
# anything at all; (2) it backgrounded the probe WITHOUT redirecting its own stdio
# away from the inherited pipe -- back when `run` piped its output through `head -c`
# directly, a lingering grandchild holding that pipe open made `run` itself BLOCK
# until the probe's full 30s sleep finished naturally, so by the time this fixture
# got to check, the probe had already exited on its own and "ok" was true for the
# wrong reason (`run` never raced the kill at all). `run` no longer pipes its output
# (see review-sandbox.sh's own comment on that fix), so it should now return almost
# immediately regardless of the probe -- but the probe still redirects its own stdio
# here anyway, so this fixture does not depend on that other fix to mean what it says.
uname_s="$(uname -s 2>/dev/null || echo unknown)"
case "$uname_s" in
  MINGW*|MSYS*|CYGWIN*) is_windowsish=1 ;;
  *) is_windowsish=0 ;;
esac

sleep_marker="review-sandbox-leftover-probe-$$"
marker_script="$tmp/$sleep_marker.sh"
printf '#!/bin/sh\nsleep 30\n' > "$marker_script"
chmod +x "$marker_script"
run_started="$(date +%s 2>/dev/null || echo 0)"
out="" st=0
out="$(cd "$ws" && REVIEW_SANDBOX_ROOT="$root" "$script" run "$sbx" -- \
  sh -c "(\"$marker_script\" >/dev/null 2>&1 </dev/null &); true" 2>&1)" || st=$?
run_ended="$(date +%s 2>/dev/null || echo 0)"
[ "$st" = 0 ] || { echo "FAIL - run: the detach-a-child command itself failed (exit $st): $out" >&2; fail=1; }
if [ "$run_started" != 0 ] && [ $((run_ended - run_started)) -ge 25 ]; then
  echo "FAIL - run: took $((run_ended - run_started))s to return -- the detached probe blocked it, the pipe-blocking bug is back" >&2
  fail=1
fi
sleep 1
if command -v pgrep >/dev/null 2>&1; then
  leftover="$(pgrep -f "$sleep_marker" 2>/dev/null || true)"
elif command -v ps >/dev/null 2>&1; then
  leftover="$(ps -ef 2>/dev/null | grep -F "$sleep_marker" | grep -v grep || true)"
else
  leftover=""
  echo "skip - run: leftover-process check (neither pgrep nor ps on PATH)"
fi
if [ -n "$leftover" ]; then
  if [ "$is_windowsish" = 1 ]; then
    # KNOWN, DOCUMENTED residual, not a silent pass: confirmed live during #113's
    # review that Git Bash's process-group kill does not reach a detached child at
    # all (reparented to PID 1) -- the script's own header states this plainly as
    # the ordinary case on Windows, not an edge case. This fixture's job is to keep
    # that claim HONEST (never silently read as closed), not to force a fix this
    # platform's tooling doesn't support from POSIX sh + timeout alone.
    echo "skip - run: a detached child process survives on $uname_s (known residual, see the script's header) -- NOT silently reported ok"
  else
    # Everywhere else, real process groups mean `run`'s own kill lines (not
    # `timeout`, which never fires here -- the wrapped command exits normally,
    # well before its timeout) are what reaps this. A surviving leftover here is a
    # REGRESSION in that kill, not the documented Windows-only residual -- and this
    # branch already caught a real one, not merely a hypothetical: on first
    # addition it failed red on WSL Ubuntu, because `run`'s kill used `kill -TERM
    # -- "-$child"`, and dash (Ubuntu's /bin/sh) rejects `--` there and silently
    # errors (swallowed by `2>/dev/null || true`), so the kill was a no-op on
    # every dash-based Linux host until fixed. An earlier version of this fixture
    # (before the platform branch above existed) would have printed "skip" for
    # that exact failure and hidden it.
    echo "FAIL - run: a detached child process survived run returning on $uname_s -- the group-kill is expected to reach it here (the documented residual is Windows-only)" >&2
    fail=1
  fi
  pkill -9 -f "$sleep_marker" 2>/dev/null || true
else
  echo "ok - run: no detached child process survives run returning"
fi

# --- run: a detached child that does NOT redirect its own stdio must not block `run`
# --- from returning -- this is the exact shape of the fix `run`'s own comment
# --- describes: it used to pipe its subshell's output through `head -c`, and a
# --- grandchild inheriting that pipe's write end (by NOT redirecting its own stdio
# --- away, unlike the leftover-process probe above) could hold it open indefinitely,
# --- so `head -c` never saw EOF and `run` blocked for the child's full lifetime. The
# --- fixture above redirects its probe's stdio to /dev/null, so it does NOT exercise
# --- this path; confirmed by mutation (reverting `run`'s file-redirect fix back to a
# --- piped `head -c` leaves the suite green without a probe like this one).
pipe_marker="review-sandbox-pipe-probe-$$"
pipe_script="$tmp/$pipe_marker.sh"
printf '#!/bin/sh\nsleep 30\n' > "$pipe_script"
chmod +x "$pipe_script"
run_started="$(date +%s 2>/dev/null || echo 0)"
out="" st=0
out="$(cd "$ws" && REVIEW_SANDBOX_ROOT="$root" "$script" run "$sbx" -- \
  sh -c "(\"$pipe_script\" &); true" 2>&1)" || st=$?
run_ended="$(date +%s 2>/dev/null || echo 0)"
[ "$st" = 0 ] || { echo "FAIL - run: the detach-without-redirecting-stdio command itself failed (exit $st): $out" >&2; fail=1; }
if [ "$run_started" != 0 ] && [ $((run_ended - run_started)) -ge 25 ]; then
  echo "FAIL - run: took $((run_ended - run_started))s to return with a non-redirected detached child -- the pipe-blocking bug is back" >&2
  fail=1
else
  echo "ok - run: returns promptly even when a detached child inherits run's own stdio"
fi
sleep 1
pkill -9 -f "$pipe_marker" 2>/dev/null || true

REVIEW_SANDBOX_ROOT="$root" sh "$script" destroy "$sbx" || true

# =========================================================================================
# --- run/destroy: a path outside the sandbox root is refused before anything runs ------
# =========================================================================================
#
# Two things were wrong with an earlier version of this fixture, found by mutation
# (deleting the `case "$sbx_canon" in "$root_canon"/*) ... *) return 1 ;; esac`
# boundary check in `require_in_root` left the suite green): (1) `run`/`destroy` were
# called with NO `$REVIEW_SANDBOX_ROOT` set, so `sandbox_root()` fell back to the
# UNRELATED default root, and the refusal that fired came from `canon` failing on
# THAT nonexistent root, never reaching the boundary check at all; (2) the escape
# target's own leaf name didn't match any real marker, so even with a root set the
# refusal could come from the marker lookup instead. Both bugs let the fixture pass
# for the wrong reason regardless of whether the boundary check itself worked.
#
# Fixed shape: reuse the SAME root a real sandbox was just built in (so a REAL
# "7.marker" exists there), and escape to a directory OUTSIDE that root whose OWN
# leaf name is also "7" -- so if the boundary check is the only thing standing in the
# way (which is exactly what this fixture must prove), `require_in_root`'s marker
# lookup (`$root_canon/$n.marker`, keyed only by leaf name) would otherwise happily
# find the real sandbox's own marker and let it through. This is the shape that
# actually goes red under the mutation above; the previous one did not.

ws="$(new_workspace escape)"
sha="$(pr_ref "$ws" 7)"
make_trusted "$ws" 7 "$sha"
sbx="$out"

canary="$tmp/escape-canary"
rm -f "$canary"
mkdir -p "$tmp/outside-root-parent"
outside="$tmp/outside-root-parent/7"
mkdir -p "$outside"
out="" st=0
out="$(cd "$ws" && REVIEW_SANDBOX_ROOT="$root" "$script" run "$outside" -- sh -c "touch $canary" 2>&1)" || st=$?
assert_eq "run: an outside path sharing a real sandbox's own leaf name is still refused (exit 111)" "111" "$st"
if printf '%s\n' "$out" | grep -q '^STOP '; then
  echo "ok - run: path-escape refusal prints a STOP line"
else
  echo "FAIL - run: path-escape refusal prints a STOP line, got [$out]" >&2; fail=1
fi
assert_true "run: the escaped command never actually ran" "$([ -f "$canary" ] && echo 0 || echo 1)"

out="" st=0
out="$(cd "$ws" && REVIEW_SANDBOX_ROOT="$root" "$script" destroy "$outside" 2>&1)" || st=$?
if [ "$st" = 0 ]; then
  echo "FAIL - destroy: an outside path sharing a real sandbox's own leaf name must be refused, got exit 0" >&2
  fail=1
else
  echo "ok - destroy: an outside path sharing a real sandbox's own leaf name is refused"
fi
# The workspace must be untouched by the refused destroy -- a real sandbox, "7",
# still exists at $root/7 (never removed by the misdirected call above).
assert_true "destroy: the REAL sandbox (same N) was untouched by the refused escape" \
  "$([ -d "$root/7" ] && echo 1 || echo 0)"

out="" st=0
out="$(cd "$ws" && REVIEW_SANDBOX_ROOT="$root" "$script" destroy /tmp/never-a-sandbox 2>&1)" || st=$?
if [ "$st" = 0 ]; then
  echo "FAIL - destroy: an unrecognized path (no marker at all) must be refused, got exit 0" >&2
  fail=1
else
  echo "ok - destroy: an unrecognized path (no marker at all) is refused"
fi

REVIEW_SANDBOX_ROOT="$root" sh "$script" destroy "$sbx" || true

# =========================================================================================
# --- destroy: a symlink inside the sandbox is unlinked, never followed -----------------
# =========================================================================================

ws="$(new_workspace symlink)"
sha="$(pr_ref "$ws" 7)"
make_trusted "$ws" 7 "$sha"
sbx="$out"

if ln -s "$ws" "$sbx/escape-link" 2>/dev/null && [ -L "$sbx/escape-link" ]; then
  # Some filesystems accept `ln -s`'s exit 0 but silently COPY instead of linking
  # (observed on this machine under Git Bash without Developer Mode) -- `[ -L ]`
  # confirms a REAL symlink was made, not just that the command didn't error.
  dst_out="" dst_st=0
  dst_out="$(REVIEW_SANDBOX_ROOT="$root" sh "$script" destroy "$sbx" 2>&1)" || dst_st=$?
  if [ "$dst_st" != 0 ]; then
    echo "FAIL - destroy: failed outright on a sandbox containing a symlink (exit $dst_st): $dst_out" >&2
    fail=1
  elif [ -d "$ws" ] && [ -f "$ws/base.txt" ]; then
    echo "ok - destroy: a symlink inside the sandbox pointing at the workspace is unlinked, workspace intact"
  else
    echo "FAIL - destroy: the workspace was damaged by following a symlink inside the sandbox" >&2
    fail=1
  fi
else
  rm -rf "$sbx/escape-link"
  echo "skip - destroy: symlink fixture (ln -s does not create a real symlink on this filesystem)"
  REVIEW_SANDBOX_ROOT="$root" sh "$script" destroy "$sbx" || true
fi

# =========================================================================================
# --- destroy: best-effort cleans up the workspace-side fetch ref -----------------------
# =========================================================================================

ws="$(new_workspace destroy-ref)"
sha="$(pr_ref "$ws" 7)"
make_trusted "$ws" 7 "$sha"
sbx="$out"
if git -C "$ws" rev-parse --verify -q refs/review-sandbox/7 >/dev/null 2>&1; then before=1; else before=0; fi
assert_true "destroy-ref: the fetch ref exists in the workspace right after make" "$before"
( cd "$ws" && REVIEW_SANDBOX_ROOT="$root" sh "$script" destroy "$sbx" ) || true
if git -C "$ws" rev-parse --verify -q refs/review-sandbox/7 >/dev/null 2>&1; then after=0; else after=1; fi
assert_true "destroy: removes the workspace-side refs/review-sandbox/<N> when run from the workspace" "$after"

# =========================================================================================

# =========================================================================================
# --- the review-container marker (#634) -------------------------------------------------
# =========================================================================================

# The unmodified script has exactly one line matching the pattern the review entrypoint's plugin
# floor greps for (scripts/identity/review/entrypoint.sh): reformatting it would silently lower the floor.
n=$(grep -c '^REVIEW_CONTAINER_MARKER=/etc/way-of-working/review-container$' "$script" || true)
assert_eq "marker line: exactly one line matches the entrypoint's floor pattern" "1" "$n"
n=$(grep -c '^REVIEW_CONTAINER_MARKER=' "$script" || true)
assert_eq "marker line: the variable is assigned once" "1" "$n"

# A copy whose marker line points at a temp path, beside a copy of gh-identity.sh, run by path.
mk_marker_copy() { # mk_marker_copy <dir> <marker-path>
  mkdir -p "$1"
  sed "s|^REVIEW_CONTAINER_MARKER=.*\$|REVIEW_CONTAINER_MARKER=$2|" "$script" >"$1/review-sandbox.sh"
  chmod +x "$1/review-sandbox.sh"
  cp "$root_dir/plugins/way-of-working/bin/gh-identity.sh" "$1/gh-identity.sh"
  grep -q "^REVIEW_CONTAINER_MARKER=$2\$" "$1/review-sandbox.sh" || { echo "FAIL - marker: could not substitute the marker path" >&2; fail=1; }
}
marker_gh="$tmp/marker-gh.sh"
cat > "$marker_gh" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$MARKER_GH_LOG"
exit 1
STUB
chmod +x "$marker_gh"

ws="$(new_workspace marker)"
sha="$(pr_ref "$ws" 31)"
# The unmodified script builds a sandbox first, so `destroy` has something to remove below.
make_trusted "$ws" 31 "$sha"
assert_eq "marker setup: the unmodified script builds a sandbox" "0" "$st"
built_sbx="$out"; built_root="$root"

marker_file="$tmp/marker-present"; : >"$marker_file"
mk_marker_copy "$tmp/marker-copy" "$marker_file"
mcopy="$tmp/marker-copy/review-sandbox.sh"
: >"$tmp/marker-gh-log"
ran_flag="$tmp/marker-ran"
mrun() { # mrun <args...>: run the marked copy from the workspace, capturing stdout+stderr and status
  out="" st=0
  out="$(cd "$ws" && MARKER_GH_LOG="$tmp/marker-gh-log" REVIEW_SANDBOX_ROOT="$tmp/marker-root" REVIEW_SANDBOX_GH="$marker_gh" "$@" 2>&1)" || st=$?
}
check_refused() { # check_refused <label> <status-wanted>
  assert_eq "marker present: $1 exits $2" "$2" "$st"
  case "$out" in STOP*) echo "ok - marker present: $1 prints a leading STOP" ;; *) echo "FAIL - marker present: $1 leading STOP, got [$out]" >&2; fail=1 ;; esac
  assert_true "marker present: $1 makes no gh call" "$([ ! -s "$tmp/marker-gh-log" ] && echo 1 || echo 0)"
  assert_true "marker present: $1 builds nothing" "$([ ! -e "$tmp/marker-root" ] && echo 1 || echo 0)"
}
mrun "$mcopy" make 31 "$sha";                                  check_refused "make" 1
mrun "$mcopy" run "$built_sbx" -- sh -c ": >'$ran_flag'";      check_refused "run" 111
assert_true "marker present: the wrapped command never ran" "$([ ! -e "$ran_flag" ] && echo 1 || echo 0)"
# The marker STOP comes before the argument checks (the header says so).
mrun "$mcopy" make not-a-number not-a-sha;                     check_refused "make with bad arguments" 1
mrun "$mcopy" run;                                             check_refused "run with bad arguments" 111

# `trust` behaves as without the marker.
run_script "$ws" env FAKE_GH_REPO=acme/repo FAKE_GH_PULLS_7_SHA=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef \
  FAKE_GH_PULLS_7_HEAD_REPO=acme/repo FAKE_GH_PULLS_7_BASE=main FAKE_GH_PULLS_7_ASSOC=MEMBER "$script" trust 7
plain_trust="$out/$st"
run_script "$ws" env FAKE_GH_REPO=acme/repo FAKE_GH_PULLS_7_SHA=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef \
  FAKE_GH_PULLS_7_HEAD_REPO=acme/repo FAKE_GH_PULLS_7_BASE=main FAKE_GH_PULLS_7_ASSOC=MEMBER "$mcopy" trust 7
assert_eq "marker present: trust behaves as without the marker" "$plain_trust" "$out/$st"

# `destroy` removes a sandbox the unmodified script built under the same REVIEW_SANDBOX_ROOT.
out="" st=0
out="$(cd "$ws" && REVIEW_SANDBOX_ROOT="$built_root" "$mcopy" destroy "$built_sbx" 2>&1)" || st=$?
assert_eq "marker present: destroy exits 0" "0" "$st"
assert_true "marker present: destroy removes the sandbox" "$([ ! -e "$built_sbx" ] && echo 1 || echo 0)"

# A dangling symlink at the marker path counts too (under the link guard).
dangling="$tmp/marker-dangling"
if ln -s "$tmp/no-such-target" "$dangling" 2>/dev/null && [ -L "$dangling" ]; then
  mk_marker_copy "$tmp/marker-copy2" "$dangling"
  mcopy="$tmp/marker-copy2/review-sandbox.sh"
  rm -rf "$tmp/marker-root"; : >"$tmp/marker-gh-log"
  mrun "$mcopy" make 31 "$sha";                                check_refused "a dangling marker link: make" 1
  mrun "$mcopy" run "$built_sbx" -- true;                      check_refused "a dangling marker link: run" 111
else
  echo "SKIP - a symlink cannot be made here; the dangling-marker fixtures did not run" >&2
fi

# Marker absent: a copy pointing at a path that does not exist behaves as the unmodified script (the
# existing fixtures above run the unmodified script, whose real marker path is absent on this machine).
mk_marker_copy "$tmp/marker-copy3" "$tmp/no-such-marker"
mrun "$tmp/marker-copy3/review-sandbox.sh" make not-a-number not-a-sha
assert_eq "marker absent: bad arguments are still exit 2" "2" "$st"

if [ "$fail" -ne 0 ]; then
  echo "review-sandbox.sh fixtures: FAILED" >&2
  exit 1
fi
echo "review-sandbox.sh fixtures: all passed"
echo "NOTE: the OS-keyring vector (gh auth token / gh auth git-credential reaching the" >&2
echo "invoking user's real credential from inside the stripped env) is stated as" >&2
echo "untestable offline and is not asserted by any fixture above." >&2
