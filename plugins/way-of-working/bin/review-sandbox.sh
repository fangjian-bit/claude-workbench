#!/bin/sh
# Build, run PR code inside, and tear down an isolated sandbox for
# /way-of-working:architect-review's *Review by execution* step (issue #113).
#
# The step this replaces ran a PR's own code with the reviewing session's credentials
# via `git worktree add <tmp> <sha>`, which SHARES `.git` with the main checkout: PR
# code in the worktree could rewrite `.ai/project.yml` or `.git/config`'s `origin`
# before the *Compose and post* step re-read them (issue #113, from a security-critic
# finding on #98). Two design-spec revisions were posted on the issue; the first
# (a throwaway `git clone --no-local` under a stripped `env -i`) was superseded when a
# critic pass reproduced three vectors it claimed closed: `gh auth token`/`gh auth
# git-credential` reach the OS keyring regardless of what the process environment
# carries -- stripping the env removes the credential HANDLE, not the reach; PATH's
# first entry is a plantable shim directory PR code can write to; and `git clone
# <workspace>` leaves the absolute workspace path in the clone's own reflog and its
# `origin` remote config (verified live: a clone does NOT create FETCH_HEAD at all --
# that leak is specific to THIS design's single-ref fetch, below, not to clone), so
# "the attacker would have to guess the path" was false. The approved
# shape (option 1 on the issue: A+C+D; a container -- option B -- filed as #158, then
# deferred, see WB-D13's amendment) is implemented here as option A, corrected:
#
#   - `git init --template=<empty>` + a single-ref fetch FROM THE WORKSPACE replaces
#     `clone`: no local branches or tags copied, no `clone: from` reflog entry, no
#     `origin` remote to remove.
#   - The fetched ref lands at a namespace no other refspec writes
#     (`refs/review-sandbox/<N>` in the WORKSPACE, fetched from `refs/pull/<N>/head`),
#     so a concurrent review of a different PR, or a second run of this one, can't
#     collide with it.
#   - `FETCH_HEAD` is scrubbed from the sandbox immediately after the fetch, before
#     checkout -- the workspace's own path, which `fetch` records there verbatim, must
#     not be discoverable from inside code the sandbox then runs. (A single-ref fetch
#     with no destination branch, as used here, writes no reflog entry at all -- there
#     is nothing under `.git/logs` for the path to leak into. The `rm -rf .git/logs`
#     line stays as a harmless belt-and-braces no-op, not because it removes a real
#     leak.)
#   - `run` invokes the sandboxed command under a fixed, non-repo-specific env
#     allowlist (`env -i` plus PATH and a short OS-variable list) with HOME, TMP/TEMP/
#     TMPDIR and GH_CONFIG_DIR repointed inside the sandbox, `GIT_CONFIG_NOSYSTEM=1`,
#     `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_TERMINAL_PROMPT=0`, `GIT_LFS_SKIP_SMUDGE=1` --
#     never the caller's own environment forwarded wholesale.
#
# What this closes: the CWD-relative form of every vector in the issue (a test that
# runs git in its own tree, sets config, installs hooks, moves refs); the config
# credential handles this process itself would otherwise forward through `run`
# (`credential.helper`, `hosts.yml` -- see the GH_TOKEN residual below, which this does
# NOT close); the FETCH_HEAD workspace-path leak; copied local branches; LFS and
# submodule reads during BOTH `make`'s fetch+checkout and `run` -- but by DIFFERENT
# means, neither a superset nor a subset of the other: `make`'s own git calls stay in
# the CALLER's full, unstripped environment (no `env -i`, no HOME/TMP/GH_CONFIG_DIR
# repoint, no `GIT_TERMINAL_PROMPT=0` -- see the "does NOT close" list below, where this
# script says so directly), which `run` does not; `make` adds the three
# `GIT_CONFIG_NOSYSTEM`/`GIT_CONFIG_GLOBAL`/`GIT_LFS_SKIP_SMUDGE` env vars `run` also
# uses, PLUS `-c submodule.recurse=false`, neutered `-c filter.lfs.*=`, and (on BOTH the
# sandbox fetch and the checkout that follows it, identically) `-c core.hooksPath`/
# `core.fsmonitor`/`core.pager`/`core.editor`/`diff.external=`, none of which `run`
# adds. An earlier revision of this
# header called `make`'s isolation a strict SUPERSET of `run`'s -- wrong, and
# self-contradicting against its own later claim (below) that `make` runs under the
# caller's full, unstripped environment; a later revision called it merely narrower --
# also wrong, since the `-c` overrides above are `make`-only. It is DIFFERENT, not
# ranked either way against `run`'s. An earlier version of this script applied any of
# this only inside `run`, leaving `make`'s own checkout to read system/global LFS config under
# the reviewer's full environment -- three independent critic passes on #113 found
# that gap by reading `make`'s checkout call against this claim; `make` itself now
# re-verifies trust (the same read `trust` does) before building anything, so an
# untrusted PR reaching `make` -- whether by a caller's own mistake or a PR's own text
# talking a confused caller into it -- is a mechanical STOP, not a rule that exists
# only in SKILL.md prose.
#
# What this does NOT close (verified during the design and repeated rounds of
# adversarial critic review -- see docs/decisions.md's WB-D13 for what each round
# found -- several items reproduced live -- stated so a caller never treats this as
# more than it is):
#   - `gh auth token` and `gh auth git-credential` still return the invoking user's
#     real credential from the OS keyring -- the keyring is reachable by any process
#     running as that user, one command away, whatever the process environment
#     carries.
#   - `env -i` strips only the DIRECT child's environment. `GH_TOKEN` (or any other
#     credential the invoking user's own shell exported) is still readable from an
#     ancestor process's environment -- `timeout`, the subshell `run` opens, this
#     script itself -- via `/proc/<pid>/environ` on Linux and MSYS, by a same-uid
#     process, with no race and no prior compromise needed. Reproduced live during
#     review. This is not a gap in the allowlist; it is a property of what `env -i`
#     can and cannot reach, and nothing short of a different uid or namespace (a
#     container, option B -- deferred) closes it.
#   - More generally, `run`'s stripped environment only changes what a tool finds BY
#     DEFAULT -- it is not a filesystem or network sandbox. Code running under `run`
#     has the invoking user's own uid and can read any file that uid can read (its
#     real `$HOME` is trivially findable -- `/etc/passwd`, an ancestor's
#     `/proc/<pid>/environ`, or just `/home/$USER`), including
#     `~/.config/gh/hosts.yml` (a plaintext token whenever `gh` fell back from the
#     keyring), `~/.git-credentials`, `~/.ssh/id_*`, this session's own
#     `~/.claude/.credentials.json`, and an SSH agent socket -- and can send any of it
#     out over the network, which `run` does not restrict.
#   - A write that persists as the invoking user (a PATH directory, `~/.claude` or
#     `.claude/settings.local.json` hooks, a shell rc file) is not undone by `destroy`.
#     The WORKSPACE's own `.git/config` and `.git/hooks` are one instance of this class
#     worth naming directly: PR code, or a leftover process (below), can plant
#     `diff.external`, `url.<x>.insteadOf`, `core.fsmonitor`, or a filter plus
#     `.git/info/attributes` into the workspace's OWN config, which then runs under
#     the reviewer's full, unstripped environment the next time the reviewer's own
#     workspace git commands touch it (SKILL.md's own `git diff`, `make`'s `git fetch`,
#     `destroy`'s `update-ref`). The *Review by execution, in an isolated sandbox* /
#     *Compose and post* pre/post transcript snapshot (SKILL.md) only detects a
#     change to `.git/config` after the fact, and only records
#     `.git/hooks` file NAMES (`ls`, not a content hash), so it would not notice an
#     existing hook's contents being rewritten, nor a plant already present when the
#     snapshot itself is taken. A plant here is not only an EXECUTION route, either: a
#     rewritten `origin` or a planted `url.<x>.insteadOf` also REDIRECTS -- `read_trust`
#     resolves `{repo}` from `git remote get-url origin` (which `insteadOf` rewrites)
#     before either `trust` or `make` ever reads a PR, so a plant present before that
#     read can point an entirely LATER review's trust check and fetch at an
#     attacker-controlled repo, not merely execute code inside the one that planted it.
#     The pre/post snapshot is taken after that read, so it does not cover this. THE
#     SAME REDIRECT REACHES FURTHER, before this script is even invoked:
#     `bin/review-base-anchor.sh` resolves `{repo}` the identical way (`git remote
#     get-url origin`) as the FIRST thing `/way-of-working:architect-review` does, then
#     fetches and fast-forwards the reviewer's own LOCAL default branch onto whatever
#     that origin (redirected or not) actually holds, and the whole review session
#     then reads `.ai/project.yml` from that fast-forwarded tree -- verified live: a
#     plant present before that preflight runs is worse than redirecting this script
#     alone, because SKILL.md's own `{repo}` cross-check (comparing its config value
#     against this script's printed `repo=`) does NOT catch it -- both sides resolve
#     from the SAME redirected `origin`, so they agree with each other and with the
#     attacker, not with reality.
#   - The marker no longer carries the workspace path in the clear (a hash only -- see
#     `make`), but the path is discoverable other ways that need no prior compromise
#     either -- an ancestor process's cwd (`/proc/<pid>/cwd` on Linux/MSYS), or simply
#     listing the filesystem for a directory holding `refs/review-sandbox/<N>`.
#   - A leftover process from an earlier `run` that this script's best-effort kill
#     failed to reach can still act while a later `make` rebuilds the same path, from
#     `git init` through the checkout that follows -- and REPRODUCED LIVE: the
#     checkout-time config isolation above stops it from reading SYSTEM/GLOBAL config,
#     and now neuters the SPECIFIC local-config values verified reachable during
#     design (`core.fsmonitor`, `core.pager`, `core.editor`, `diff.external`), but NOT
#     the class -- a `filter.<name>.smudge` planted locally, triggered by nothing more
#     than the PR's OWN `.gitattributes` naming that filter (no local plant of the
#     trigger needed, only of the filter definition), `core.alternateRefsCommand`,
#     `url.<x>.insteadOf`, and a same-named remote's `uploadpack` were all separately
#     confirmed live and are NOT neutered -- under `make`'s full (unstripped)
#     environment. This is worse, not merely present, on the one platform this repo's
#     maintainer runs on: Git Bash's process-group kill does not reach a detached
#     child at all (`(cmd &)` survives `run` returning, reparented to PID 1; confirmed
#     live, not merely "degrades gracefully" as an earlier revision of this note
#     claimed). It is not Windows-exclusive, though: on any platform, a command that
#     escapes the process group (`setsid cmd &`, any daemonizing double-fork -- NOT
#     only a deliberate one: `git gc --auto` (its default, `gc.autoDetach=true`,
#     survives `GIT_CONFIG_GLOBAL=/dev/null` since that's a global-not-default
#     override), `gpg-agent`, `ssh-agent`, and ordinary build daemons -- Gradle,
#     Kotlin, sccache, `dotnet build-server` -- all do this routinely, with no hostile
#     intent) is reparented the same way and is just as unreachable by `run`'s
#     group-kill even where the group-kill otherwise works -- confirmed live for the
#     deliberate case; the ordinary-tool case follows from the same reparenting
#     mechanism. So a leftover process is the ORDINARY case on Windows and the
#     daemonizing case -- deliberate or not -- everywhere else, and this residual
#     should be read accordingly.
#   - `${REVIEW_SANDBOX_ROOT:-${TMPDIR:-/tmp}/review-sandbox}` defaults to a
#     predictable path under `/tmp` when `TMPDIR` is unset. On a shared, multi-user
#     Linux host (not this repo's maintainer's own machine, where `/tmp` is
#     per-user), another local user who can create or already owns that path could
#     race `make`/`run` there. Set `REVIEW_SANDBOX_ROOT` to a private, per-user
#     directory on any host where `/tmp` is shared.
#   - Closing any of the above fully needs unique-per-build paths, guaranteed
#     process-group teardown, filesystem/network sandboxing, and a different uid --
#     not attempted here, and no combination of `-c` flags on `make`'s own git
#     invocations gets there either.
# In short: this is ACCIDENT CONTAINMENT, not isolation from a deliberately hostile
# trusted-author PR. A container (option B, #158) would close that; it is not built.
# Whether that residual is acceptable depends on who a repo's trusted authors are
# relative to its reviewer -- WB-D13's amendment records one maintainer's acceptance
# for their own setup and the conditions under which it lapses; it is not a property
# of this script. `run` accepts only a sandbox `make` built (its marker check), and
# `make` STOPs on an untrusted PR, so an untrusted PR's review takes its witness from
# CI instead. A caller posting a review after
# running code through `run` should say so, in those terms, not as "no link to
# credentials".
#
# Usage:
#   review-sandbox.sh trust <N>
#     One read of the PR: gh api repos/<repo>/pulls/<N>, <repo> resolved from THIS checkout's
#     own `origin` (same derivation review-base-anchor.sh uses), never a script
#     argument. Prints `sha=<40hex> head_repo=<owner/name> base=<branch>
#     assoc=<association> loop=0|1 trusted=0|1` to stdout and exits 0 whatever the
#     verdict -- trusted=1 only when loop=0, the author is trusted AND head_repo equals the
#     resolved repo (a fork head is untrusted whoever opened the PR). The author is judged
#     by `gh-identity.sh author` over the default branch's `identities` (WB-D24, #382): a
#     declared maintainer, matched on the PR author's numeric id, is trusted and `assoc`
#     is only echoed; while `identities` is null (not cut over), assoc OWNER, MEMBER or
#     COLLABORATOR is the test. loop=1 means the PR's author login equals `orchestration.loop_identity`,
#     compared case-insensitively, a trailing `[bot]` ignored on both sides, and BEFORE
#     any association check (#235: the loop's
#     name is untrusted whatever its association says); that value is read from the
#     DEFAULT branch's committed `.ai/project.yml`, fetched from `origin` (this writes the
#     remote-tracking ref refs/remotes/origin/<default> in the checkout), never from
#     this checkout's own copy or the PR's. A failed API read, an unresolvable default
#     branch, or an unreadable copy of that file (or a missing `yq`) is a STOP (exit 1)
#     -- never a silent "no loop identity". So is an author `gh-identity.sh author` cannot
#     judge (an absent `identities` key, an id declared twice, a PR answering no author
#     id): never the association fallback. A non-numeric <N> is a malformed invocation
#     (exit 2).
#
#   review-sandbox.sh make <N> <sha>
#     <sha> must be the 40-hex value `trust` printed -- validated, along with <N>,
#     BEFORE either reaches a refspec or argv. Re-reads trust itself (the same one
#     API call `trust` makes) and STOPs on an untrusted PR or a sha that disagrees
#     with this fresh read -- this subcommand refuses to build for an untrusted PR
#     regardless of what called it or why. Fetches refs/pull/<N>/head into
#     refs/review-sandbox/<N> in the CALLING checkout (the "workspace"), builds the
#     sandbox under ${REVIEW_SANDBOX_ROOT:-${TMPDIR:-/tmp}/review-sandbox}/<N>, verifies
#     the fetched commit inside the sandbox matches <sha> exactly, scrubs the
#     workspace-path leak, checks it out detached under LFS/config isolation of its
#     own (different from, not the same as, `run`'s -- see the header's "DIFFERENT, not
#     ranked either way" note), and prints the sandbox's path. Removes an existing
#     sandbox at that
#     path first, but ONLY when a sibling marker file's hash proves it belongs to this
#     same workspace and <N> -- never another review's, and the marker never carries
#     the workspace path in the clear.
#
#   review-sandbox.sh run <path> -- <cmd...>
#     <path> must be exactly a path `make` printed (canonicalized and checked against
#     the sandbox root plus a recorded marker, so `<root>/../x` and a symlink or
#     junction out of the root are refused before <cmd> ever runs). Runs <cmd> from
#     <path> under the stripped environment above, bounded by `timeout -k`, with a
#     best-effort kill of anything still running under <path> afterward. What is
#     PRINTED BACK to the caller is capped (REVIEW_SANDBOX_OUTPUT_CAP, default
#     1MiB) -- `head -c` reads only that many bytes, when `head` is on PATH; the
#     `cat` fallback (no `head`) prints the file whole, uncapped. Either way, what
#     <cmd> writes to its own captured-output file ON DISK is not capped at all --
#     the file can grow without limit until `timeout` fires (accident containment,
#     not a resource limit; <cmd> could already do this through its own TMPDIR
#     regardless).
#     A refusal BEFORE <cmd> starts prints STOP and exits with the RESERVED code 111 --
#     reserved because once <cmd> actually starts, ITS exit status is passed through
#     unchanged (as documented usage requires), and could coincidentally equal 111 too.
#     A caller must treat a leading `STOP` line on stderr, not the exit code alone, as
#     the authoritative refusal signal once <cmd> may have run.
#
#   review-sandbox.sh destroy <path>
#     Same root/marker guard as `run`. Never invokes git in the sandbox -- a hostile
#     core.hooksPath, clean.requireForce, or similar left in the sandbox's own config
#     must not get a chance to run on the way out. A symlink or junction found INSIDE
#     the sandbox is unlinked, never followed, before the recursive removal.
#
# Malformed invocation (bad arity, a non-numeric <N>, a non-40-hex <sha>, a missing
# `--` before <cmd>) is exit 2 throughout -- the question could not even be asked, the
# same split review-base-anchor.sh uses -- except inside a review container (below),
# where the marker STOP comes first. A real STOP (well-formed but refused) is
# exit 1, except `run`'s own pre-execution refusal, which is 111 (see above).
#
# The review-container marker. A review container holds a session token in reach, so
# `make` and `run` must never build or execute PR code there. The image ships an empty,
# root-owned file at a fixed path (REVIEW_CONTAINER_MARKER, below); when it exists, or is
# a link of any kind, `make` STOPs (exit 1) and `run` refuses (111) before any argument
# check, `gh` call or filesystem change. It is a fixed root-owned file, not an
# environment variable, so a session cannot unset it. `trust` and `destroy` are
# unchanged. In a review container the marker STOP therefore comes before the exit-2
# argument checks. Residual: it guards this skill's own path only. A session can run PR
# code by hand, or edit its installed plugin copy of this check, which lives in its
# writable home. See #623.
#
# Permitted toolset: git, $REVIEW_SANDBOX_GH (default: gh), POSIX sh, `timeout`
# (ships in Git for Windows' usr/bin, same as the rest of this toolset), `sha256sum`
# or `shasum -a 256` for the marker hash,
# and `yq` for `trust`'s one read of `orchestration.loop_identity` (the permission
# review-base-anchor.sh already holds for `migration_base`), plus `gh-identity.sh author`
# (which also reads `identities` with `yq`) for who is trusted. No jq, no python.
#
# Windows note: the leftover-process kill after `run` does NOT reach a detached child
# under Git Bash -- confirmed live, not a theoretical gap: `(cmd &)` inside a `run`
# survives `run` returning, reparented to PID 1, whatever job control this script
# enables. See the "What this does NOT close" list above; this is the ordinary case on
# this platform, not an edge case. `tests/review-sandbox.test.sh`'s own leftover-
# process fixture is platform-aware: it treats a surviving leftover as this known,
# accepted residual (skip, not a silent pass) only on Windows (MSYS/MINGW/CYGWIN);
# everywhere else, where the group-kill is expected to reach an ordinary backgrounded
# child, the same finding is a FAIL. The `destroy` symlink/junction check
# (`find -type l`) is not similarly known-broken on Windows -- confirmed live that it
# DOES catch a `mklink /J` junction under Git Bash's `find`; untested by CI either way,
# see below.
#
# This repo's CI (`.github/workflows/ci.yml`) runs `tests/review-sandbox.test.sh`
# on Ubuntu only. So every
# Windows-specific path in this script (the leftover-process skip, the junction check
# above) is exercised only on a maintainer's machine, never mechanically.
set -eu

# The review entrypoint matches this exact line as its plugin floor, so do not reformat it.
REVIEW_CONTAINER_MARKER=/etc/way-of-working/review-container

: "${REVIEW_SANDBOX_GH:=gh}"

usage() {
  echo "usage: review-sandbox.sh trust <N> | make <N> <sha> | run <path> -- <cmd...> | destroy <path>" >&2
  exit 2
}

stop() {
  printf 'STOP %s\n' "$1" >&2
  exit 1
}

# Reserved for `run`'s own pre-execution refusal only -- see the header note on why
# this can't reuse plain exit 1 once a wrapped command's own status is in play.
stop_refuse() {
  printf 'STOP %s\n' "$1" >&2
  exit 111
}

is_digits() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

is_sha40() {
  [ "${#1}" -eq 40 ] || return 1
  case "$1" in
    *[!0-9a-f]*) return 1 ;;
  esac
}

# hash_str -- prints the hex sha256 of stdin. Used only so a sandbox marker never
# carries the workspace's own filesystem path in the clear (see `make`) -- PR code
# running under `run` sits one directory above the marker and can read it.
hash_str() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    return 1
  fi
}

# read_trust <N> -- the one gh api read `trust` reports and `make` re-verifies before
# building anything. Sets SHA, HEAD_REPO, BASE, ASSOC, AUTHOR, AUTHOR_ID, LOOP, TRUSTED (0/1) as script-global
# vars; the caller checks its own exit status, never a stale value from a prior call.
# {repo} is resolved from THIS checkout's own origin, never a caller-supplied value.
read_trust() {
  n="$1"
  U=$(git remote get-url origin) || { echo "cannot read this checkout's origin url" >&2; return 1; }
  R=$("$REVIEW_SANDBOX_GH" repo view "$U" --json nameWithOwner --jq .nameWithOwner) \
    || { echo "cannot resolve repo from origin url" >&2; return 1; }
  OUT=$("$REVIEW_SANDBOX_GH" api "repos/$R/pulls/$n" \
    --jq '[.head.sha, .head.repo.full_name, .base.ref, .author_association, .user.login, .user.id] | @tsv') \
    || { echo "cannot read PR #$n in $R" >&2; return 1; }
  SHA=$(printf '%s' "$OUT" | cut -f1)
  HEAD_REPO=$(printf '%s' "$OUT" | cut -f2)
  BASE=$(printf '%s' "$OUT" | cut -f3)
  ASSOC=$(printf '%s' "$OUT" | cut -f4)
  AUTHOR=$(printf '%s' "$OUT" | cut -f5)
  AUTHOR_ID=$(printf '%s' "$OUT" | cut -f6)
  [ -n "$SHA" ] && [ -n "$ASSOC" ] && [ -n "$AUTHOR" ] && [ -n "$AUTHOR_ID" ] \
    || { echo "PR #$n in $R answered no head/assoc/author/author id" >&2; return 1; }
  # The name rule (plan 8.1, 8.13d; #235): the loop's own login is untrusted BY NAME,
  # ahead of any association check -- a machine user's MEMBER or COLLABORATOR
  # association would pass one, and so would a `loop_identity` left stale after the
  # loop's login changed. Read from the DEFAULT branch's committed copy, resolved from
  # `origin` exactly as review-base-anchor.sh does, never from this checkout's own
  # file or the PR's: a PR that edits `orchestration.loop_identity` must not be the one
  # choosing which login is untrusted. Any failed step is a STOP (return 1), never a
  # silent "no loop identity" -- an unreadable copy is not an absent name.
  D=$("$REVIEW_SANDBOX_GH" repo view "$U" --json defaultBranchRef --jq '.defaultBranchRef.name // ""') \
    && [ -n "$D" ] || { echo "cannot resolve the default branch from origin" >&2; return 1; }
  TOP=$(git rev-parse --show-toplevel) || { echo "not inside a git checkout" >&2; return 1; }
  git -C "$TOP" fetch -q origin "+refs/heads/$D:refs/remotes/origin/$D" \
    || { echo "cannot fetch the default branch $D" >&2; return 1; }
  DEF_YML=$(git -C "$TOP" show "refs/remotes/origin/$D:./.ai/project.yml") \
    || { echo "cannot read .ai/project.yml on the default branch $D" >&2; return 1; }
  LOOP_ID=$(printf '%s' "$DEF_YML" | yq -r '.orchestration.loop_identity // ""') \
    || { echo "cannot read orchestration.loop_identity (is yq on PATH?)" >&2; return 1; }
  LOOP=0
  # Case-folded and `[bot]`-folded on both sides (see plan-anchor.sh's `fold`).
  fold() { printf '%s' "$1" | tr 'A-Z' 'a-z' | sed 's/\[bot\]$//'; }
  if [ -n "$LOOP_ID" ] && [ "$(fold "$AUTHOR")" = "$(fold "$LOOP_ID")" ]; then
    LOOP=1
  fi
  TRUSTED=0
  [ "$LOOP" = 1 ] && return 0
  # Trust by DECLARED identity once the repo has cut over (WB-D24, #382): the author's
  # {login, id} against the default branch's `identities`, because `author_association`
  # is viewer-relative and reads CONTRIBUTOR for the maintainer through an App token.
  # `identities: null` (not cut over) keeps the association allowlist. Any failure to
  # judge is a STOP, never "untrusted" and never the association fallback.
  # The sibling copy, and only the sibling: it ships with this script, so its semantics are
  # the ones this trust decision was written against. A `gh-identity.sh` found on PATH (an
  # older plugin pin has no `author`) or in the current directory (what `dirname` of a
  # slash-less `$0`, as in `sh review-sandbox.sh`, would resolve to) never decides trust.
  case "$0" in
    */*) GI="$(dirname "$0")/gh-identity.sh" ;;
    *) echo "run review-sandbox.sh by path or through PATH, not as 'sh <name>': cannot locate the sibling gh-identity.sh" >&2; return 1 ;;
  esac
  [ -f "$GI" ] || { echo "cannot find gh-identity.sh beside $0" >&2; return 1; }
  YF=$(mktemp) || { echo "cannot make a temp file" >&2; return 1; }
  printf '%s\n' "$DEF_YML" >"$YF"
  KIND=$(sh "$GI" author "$AUTHOR" "$AUTHOR_ID" "$YF") \
    || { rm -f "$YF"; echo "cannot judge PR #$n's author against identities" >&2; return 1; }
  rm -f "$YF"
  case "$KIND" in
    trusted) [ "$HEAD_REPO" = "$R" ] && TRUSTED=1 ;;
    untrusted) ;;
    legacy)
      case "$ASSOC" in
        OWNER|MEMBER|COLLABORATOR)
          [ "$HEAD_REPO" = "$R" ] && TRUSTED=1
          ;;
      esac ;;
    *) echo "gh-identity.sh author answered [$KIND]" >&2; return 1 ;;
  esac
  return 0
}

# canon <path> -- resolves to the REAL, symlink-free absolute path, or fails. Used on
# every path this script is handed back by a caller, so a symlink or `..` component
# can never smuggle a target outside the sandbox root past the prefix check below.
canon() {
  ( cd -P -- "$1" 2>/dev/null && pwd -P )
}

sandbox_root() {
  printf '%s' "${REVIEW_SANDBOX_ROOT:-${TMPDIR:-/tmp}/review-sandbox}"
}

# require_in_root <path-arg> -- canonicalizes both the root and <path-arg>, requires
# the latter under the former (a real `/` boundary, not merely a string prefix, so a
# sibling directory like `<root>-evil` can't pass), requires a marker recorded for
# that exact leaf name, and echoes: "<sandbox-canon> <n>". Shared by `run`/`destroy`,
# which differ only in what they do with the result and how they report a refusal.
require_in_root() {
  path_arg="$1"
  root_canon=$(canon "$(sandbox_root)") || { echo "cannot canonicalize sandbox root" >&2; return 1; }
  sbx_canon=$(canon "$path_arg") || { echo "cannot canonicalize path: $path_arg" >&2; return 1; }
  case "$sbx_canon" in
    "$root_canon"/*) : ;;
    *) echo "path is not inside the sandbox root: $path_arg" >&2; return 1 ;;
  esac
  n="${sbx_canon##*/}"
  marker="$root_canon/$n.marker"
  [ -f "$marker" ] || { echo "no marker recorded for sandbox: $path_arg" >&2; return 1; }
  marker_n=$(sed -n '2p' "$marker" 2>/dev/null || true)
  [ "$marker_n" = "$n" ] || { echo "marker does not match sandbox: $path_arg" >&2; return 1; }
  printf '%s %s\n' "$sbx_canon" "$n"
}

cmd="${1:-}"
[ -n "$cmd" ] || usage

case "$cmd" in
  trust)
    [ "$#" -eq 2 ] || usage
    N="$2"
    is_digits "$N" || usage
    read_trust "$N" || stop "trust read failed for PR #$N"
    printf 'sha=%s head_repo=%s base=%s assoc=%s loop=%s trusted=%s\n' \
      "$SHA" "$HEAD_REPO" "$BASE" "$ASSOC" "$LOOP" "$TRUSTED"
    ;;

  make)
    if [ -e "$REVIEW_CONTAINER_MARKER" ] || [ -L "$REVIEW_CONTAINER_MARKER" ]; then stop "review container: make is refused here"; fi
    [ "$#" -eq 3 ] || usage
    N="$2"; CALLER_SHA="$3"
    is_digits "$N" || usage
    is_sha40 "$CALLER_SHA" || usage

    # Re-verify trust HERE, mechanically -- never rely on the caller (a skill's own
    # prose, or a session a PR's text may have talked into calling this directly) to
    # have honored an untrusted verdict. Also re-pins the sha from this fresh read,
    # rather than trusting whatever the caller passed.
    read_trust "$N" || stop "trust read failed for PR #$N"
    [ "$TRUSTED" = 1 ] || stop "PR #$N is not trusted (assoc=$ASSOC loop=$LOOP head_repo=$HEAD_REPO) -- make refuses to build a sandbox for it"
    [ "$SHA" = "$CALLER_SHA" ] || stop "PR #$N's current head ($SHA) does not match the sha this was asked to build ($CALLER_SHA)"

    ROOT=$(sandbox_root)
    mkdir -p "$ROOT" || stop "cannot create sandbox root: $ROOT"
    ROOT_CANON=$(canon "$ROOT") || stop "cannot canonicalize sandbox root: $ROOT"
    WORKSPACE=$(git rev-parse --show-toplevel) || stop "not inside a git checkout"
    WORKSPACE_CANON=$(canon "$WORKSPACE") || stop "cannot canonicalize workspace: $WORKSPACE"
    # Hashed, never the plaintext path: a marker sits right next to the sandbox, and
    # code running under `run` can read a sibling file (`cat ../<N>.marker`) -- a
    # live finding from #113's critic pass on an earlier version of this script that
    # stored the path itself, which directly undid the FETCH_HEAD/logs scrub below.
    WORKSPACE_HASH=$(printf '%s' "$WORKSPACE_CANON" | hash_str) \
      || stop "cannot hash workspace path (no sha256sum or shasum on PATH)"

    # Fetch BEFORE touching $SBX at all -- shrinks the window a leftover process from
    # an earlier `run` (this script's own best-effort kill can fail to reach one, see
    # the header) has to plant something in $SBX between its removal and `git init`
    # recreating it. Fetches into a namespace no other refspec writes -- a concurrent
    # review of a different PR, or a second run of this one, can never collide with it.
    git fetch -q origin "+refs/pull/$N/head:refs/review-sandbox/$N" || stop "fetch of PR #$N head failed"

    SBX="$ROOT_CANON/$N"
    MARKER="$ROOT_CANON/$N.marker"
    if [ -e "$SBX" ]; then
      # A stale sandbox at this path is removed ONLY when its own marker's hash names
      # THIS workspace and N -- never another review's, and never merely because a
      # path happened to collide.
      if [ -f "$MARKER" ] \
        && [ "$(sed -n '1p' "$MARKER" 2>/dev/null)" = "$WORKSPACE_HASH" ] \
        && [ "$(sed -n '2p' "$MARKER" 2>/dev/null)" = "$N" ]; then
        rm -rf "$SBX" || stop "cannot remove stale sandbox: $SBX"
        rm -f "$MARKER"
      else
        stop "sandbox path exists and its marker does not match this workspace/N: $SBX"
      fi
    fi

    EMPTY_TEMPLATE=$(mktemp -d) || stop "mktemp failed"
    # Cleans up on ANY exit past this point, success or STOP -- a prior version left
    # EMPTY_TEMPLATE (and, on some failure paths, a half-built $SBX with no marker)
    # behind on every failure branch below, which then blocked the next `make` (STOPs
    # on "exists but marker doesn't match") and `destroy` (refuses with no marker).
    trap 'rm -rf "$EMPTY_TEMPLATE"' EXIT
    git init -q --template="$EMPTY_TEMPLATE" "$SBX" || { rm -rf "$SBX"; stop "sandbox init failed: $SBX"; }
    # init + a single-ref fetch FROM THE WORKSPACE replaces clone: no local branches
    # or tags copied, no `clone: from` reflog entry, no origin remote to remove. Both
    # calls below run under the CALLER's own full, unstripped environment (no `env -i`
    # here -- that is `run`'s job, not `make`'s) plus the same three
    # GIT_CONFIG_NOSYSTEM/GIT_CONFIG_GLOBAL/GIT_LFS_SKIP_SMUDGE env vars `run` also
    # uses, PLUS `-c` overrides on the command line itself (which env vars alone can't
    # reach a LOCAL `.git/config` value with -- see the header's residual on this: a
    # leftover process can still plant one, from `git init` right above through this
    # checkout, and these `-c` flags neuter the specific ones VERIFIED reachable
    # during design -- core.fsmonitor, core.pager, core.editor, diff.external -- but
    # NOT the class: filter.<name>.smudge (triggered by the PR's OWN `.gitattributes`,
    # needing no local plant beyond the filter definition itself), core.alternateRefsCommand,
    # url.<x>.insteadOf, and a same-named remote's uploadpack were all separately
    # confirmed live and are NOT neutered here).
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_LFS_SKIP_SMUDGE=1 \
      git -C "$SBX" -c core.hooksPath="$EMPTY_TEMPLATE" -c submodule.recurse=false \
        -c filter.lfs.process= -c filter.lfs.smudge= -c filter.lfs.clean= -c filter.lfs.required=false \
        -c core.fsmonitor=false -c core.pager=cat -c core.editor=true -c diff.external= \
        fetch -q --no-tags "$WORKSPACE" "refs/review-sandbox/$N" \
      || { rm -rf "$SBX"; stop "sandbox fetch failed"; }
    FETCHED=$(git -C "$SBX" rev-parse FETCH_HEAD) || { rm -rf "$SBX"; stop "cannot resolve sandbox FETCH_HEAD"; }
    if [ "$FETCHED" != "$SHA" ]; then
      rm -rf "$SBX"
      stop "pinned sha mismatch: fetched $FETCHED, expected $SHA"
    fi
    # Scrub the workspace path BEFORE checkout: FETCH_HEAD is where it leaks (a
    # single-ref fetch with no destination branch, as above, writes no reflog entry,
    # so there is nothing under .git/logs to leak from -- that rm stays as a harmless
    # no-op, see the header).
    rm -f "$SBX/.git/FETCH_HEAD"
    rm -rf "$SBX/.git/logs"
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_LFS_SKIP_SMUDGE=1 \
      git -C "$SBX" -c core.hooksPath="$EMPTY_TEMPLATE" -c submodule.recurse=false \
        -c filter.lfs.process= -c filter.lfs.smudge= -c filter.lfs.clean= -c filter.lfs.required=false \
        -c core.fsmonitor=false -c core.pager=cat -c core.editor=true -c diff.external= \
        checkout -q --detach "$SHA" \
      || { rm -rf "$SBX"; stop "sandbox checkout failed"; }

    {
      printf '%s\n' "$WORKSPACE_HASH"
      printf '%s\n' "$N"
    } > "$MARKER" || { rm -rf "$SBX"; stop "cannot write sandbox marker"; }

    printf '%s\n' "$SBX"
    ;;

  run)
    if [ -e "$REVIEW_CONTAINER_MARKER" ] || [ -L "$REVIEW_CONTAINER_MARKER" ]; then stop_refuse "review container: run is refused here"; fi
    [ "$#" -ge 4 ] || usage
    PATH_ARG="$2"
    [ "$3" = "--" ] || usage
    shift 3
    # "$@" is now exactly <cmd...>, function-scoped below so it survives the
    # env-var/path bookkeeping that follows.

    ERR_FILE=$(mktemp) || stop_refuse "mktemp failed"
    if RESULT=$(require_in_root "$PATH_ARG" 2>"$ERR_FILE"); then
      rm -f "$ERR_FILE"
    else
      MSG=$(cat "$ERR_FILE"); rm -f "$ERR_FILE"
      stop_refuse "$MSG"
    fi
    SBX_CANON=$(printf '%s' "$RESULT" | cut -d' ' -f1)
    N=$(printf '%s' "$RESULT" | cut -d' ' -f2)
    ROOT_CANON=$(canon "$(sandbox_root)") || stop_refuse "cannot canonicalize sandbox root"

    run_in_sandbox() {
      # $1 = sandbox dir; the rest ("$@" after the shift) is <cmd...>, safe in this
      # function's own positional-parameter scope.
      sbx="$1"; shift
      home="$sbx/.review-sandbox-home"
      tmp="$sbx/.review-sandbox-tmp"
      ghcfg="$sbx/.review-sandbox-ghcfg"
      rm -rf "$home" "$tmp" "$ghcfg"
      mkdir -p "$home" "$tmp" "$ghcfg" || stop_refuse "cannot prepare sandbox run dirs"

      # mktemp, not a name derived from $N: a predictable "$ROOT_CANON/$N.exit" sits
      # exactly one directory above $sbx ("../$N.exit" from inside it) -- a leftover
      # process from an earlier `run` (the header's own residual) could otherwise
      # overwrite it between this subshell's `echo "$st"` and the `cat` below, and a
      # planted CDFAIL there would make `run` report "never ran" for a command that
      # already ran. This NARROWS that race, it does not close it: mktemp's name
      # itself is unpredictable and unexported (not in argv, not derivable via
      # /proc/<pid>/cmdline), but the file still sits in the caller's own $TMPDIR
      # (under the default root, discoverable as `../..` from inside the sandbox),
      # and <cmd>'s own stdout IS $output_file, so `readlink /proc/self/fd/1` finds
      # that directory directly -- a same-uid leftover process can still poll for
      # fresh files there, or (no polling needed) read $status_file/$output_file's
      # names straight out of THIS shell's own process memory -- no ptrace gate on
      # Windows, and Linux only gates it when `ptrace_scope` is nonzero. Same residual
      # class as the rest of the "leftover process" entry in the header, not a new one.
      status_file=$(mktemp) || stop_refuse "cannot create status file"
      output_file=$(mktemp) || { rm -f "$status_file"; stop_refuse "cannot create output file"; }
      (
        if cd "$sbx"; then
          # Local job control so this background job gets its OWN process group
          # (led by $child below) even though the outer script is non-interactive --
          # without it, a backgrounded job here would share the script's own group,
          # and the group-kill below would target no real group at all under a shell
          # that otherwise honors `set -m`. It is not what makes the kill below reach
          # a real group, though: GNU `timeout` puts ITSELF in its own process group
          # regardless of job control, so `kill "-$child"` (NOT `kill -- "-$child"` --
          # dash rejects `--` there, see below) hits a real group even under dash with
          # no tty, where `set -m` is a documented no-op (and prints a
          # warning this script silences with `2>/dev/null`). It matters only if
          # REVIEW_SANDBOX_TIMEOUT_BIN is ever pointed at a `timeout` that does not do
          # this itself.
          set -m 2>/dev/null || true
          # A fixed, non-repo-specific allowlist -- PATH plus a short OS-variable
          # list, none of which is a credential. Every unset allowlisted var is
          # passed through empty rather than omitted (behaviorally inert for a tool
          # that checks "is this set and non-empty", and keeps this POSIX sh, no
          # arrays, no conditional argv construction).
          "${REVIEW_SANDBOX_TIMEOUT_BIN:-timeout}" -k 10 "${REVIEW_SANDBOX_RUN_TIMEOUT:-120}" \
            env -i \
            PATH="$PATH" \
            SYSTEMROOT="${SYSTEMROOT:-}" WINDIR="${WINDIR:-}" COMSPEC="${COMSPEC:-}" \
            PATHEXT="${PATHEXT:-}" TERM="${TERM:-}" LANG="${LANG:-}" \
            TMP="$tmp" TEMP="$tmp" TMPDIR="$tmp" \
            HOME="$home" USERPROFILE="$home" \
            GH_CONFIG_DIR="$ghcfg" \
            GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
            GIT_TERMINAL_PROMPT=0 GIT_LFS_SKIP_SMUDGE=1 \
            "$@" &
          child=$!
          # NOT a bare `wait "$child"; st=$?` -- under `set -e`, `wait` returning the
          # awaited command's own non-zero status aborts THIS SUBSHELL right there,
          # before `st=$?` ever runs, so a failing wrapped command's real exit code
          # was silently lost (reproduced live: `sh -c 'exit 42'` came back as the
          # status-file-missing fallback below, not 42). `|| st=$?` keeps `$?` intact
          # (it is still `wait`'s own failing status at that point) while keeping the
          # statement's own exit 0, so `set -e` never fires on it.
          st=0
          wait "$child" || st=$?
          # Best-effort: $child leads its own process group (see above) -- kill
          # anything still in it. NOT `kill -TERM -- "-$child"` -- dash's `kill`
          # builtin (Debian/Ubuntu's /bin/sh, this repo's CI shell) does not accept
          # `--` and errors on it ("Illegal number: -"), which the `2>/dev/null ||
          # true` below silently swallowed: on dash this kill was a no-op on EVERY
          # platform it runs on, not merely "untested by CI" -- reproduced live on
          # WSL Ubuntu, where a round-4 test addition (the leftover-process fixture's
          # non-Windows branch) caught it. `-$child` alone (no `--`) is POSIX-portable
          # across dash, bash-as-sh, and this repo's own Git Bash sh. Confirmed to
          # still NOT reach a detached grandchild on Git Bash regardless (reparented
          # to PID 1 before this runs -- the header's Windows note), and, on any
          # platform, not a process that itself escaped the group first (`setsid cmd
          # &` or similar) -- both remain confirmed-live residuals, stated in the
          # header.
          kill -TERM "-$child" 2>/dev/null || true
          kill -KILL "-$child" 2>/dev/null || true
        else
          # A NON-NUMERIC sentinel here means "couldn't even start" (the cd itself
          # failed) -- reported below, OUTSIDE this subshell's own 2>&1 pipe, because a
          # STOP printed INSIDE that pipe would land on the pipe's stdout, not the
          # script's real stderr, and read exactly like output <cmd> itself could have
          # printed. It MUST be non-numeric: an earlier version of this script used the
          # numeric sentinel 199 here, and a wrapped <cmd> that legitimately exits 199
          # (nothing stops one from doing so, deliberately or not) was then reported as
          # "never ran" -- reproduced live: `run <sbx> -- sh -c 'echo ran; exit 199'`
          # printed `ran` and then claimed STOP/111, contradicting the header's own
          # promise that the exit code alone is ambiguous only for the RESERVED 111,
          # never silently for an arbitrary number <cmd> chose. `$st` from `wait`
          # above is always a plain decimal exit status (0-255); `CDFAIL` can never
          # collide with one.
          st=CDFAIL
        fi
        echo "$st" > "$status_file"
      ) > "$output_file" 2>&1
      # NOT `(...) 2>&1 | head -c ...` -- a PIPE only signals EOF to its reader once
      # EVERY process holding a copy of the write end has closed it, and a detached
      # grandchild the wrapped <cmd> backgrounds inherits that copy and can hold it
      # open indefinitely. Reproduced live: `run -- sh -c '(sleep 30 &); true'`
      # blocked for the FULL 30s even though `wait "$child"` above (the only thing
      # `timeout` actually bounds) returned almost immediately -- `run`'s own
      # "bounded by timeout -k" promise was false exactly for the detached-process
      # case the leftover-process fixture exists to catch, and that fixture read
      # "ok" on this machine for the wrong reason: `run` was never actually racing
      # the kill, it was blocking until the sleep ended naturally. A FILE redirect
      # does not have this problem -- a write to a file never blocks waiting for a
      # reader, so this line returns as soon as the SUBSHELL exits, regardless of
      # what any grandchild it left behind is still doing. The kill lines above are
      # unchanged and still best-effort against that same grandchild; this fix is
      # only about `run` itself no longer hanging on one.
      st=$(cat "$status_file" 2>/dev/null || echo 1)
      rm -f "$status_file"
      # NOT merely a non-empty check: `st` came from a file this script itself
      # created empty via mktemp (narrowed, not closed -- see mktemp's own comment
      # above), so a same-uid leftover process that finds it before this read can
      # still overwrite it with non-numeric junk, not only CDFAIL. `return "$st"`
      # below requires a plain decimal 0-255 (dash and bash-as-sh both reject a
      # non-numeric or out-of-range return status, which would crash `run` with a
      # shell error instead of this script's own clean exit 1) -- so validate before
      # trusting it, the same way every other caller-reachable value in this script
      # is validated before use. (A subshell that dies before ever writing $status_file
      # is NOT the reachable case here: under `set -e`, that non-zero exit aborts the
      # whole script at the `) > "$output_file" 2>&1` line above, before this read
      # ever runs -- an earlier revision of this comment claimed that scenario as the
      # motivation, which was wrong.)
      if [ "$st" != CDFAIL ]; then
        is_digits "$st" && [ "$st" -le 255 ] || st=1
      fi
      [ "$st" = CDFAIL ] && { rm -f "$output_file"; stop_refuse "cannot cd into sandbox: $sbx"; }
      { command -v head >/dev/null 2>&1 && head -c "${REVIEW_SANDBOX_OUTPUT_CAP:-1048576}" "$output_file" \
        || cat "$output_file"; } 2>/dev/null
      rm -f "$output_file"
      return "$st"
    }

    run_in_sandbox "$SBX_CANON" "$@"
    exit $?
    ;;

  destroy)
    [ "$#" -eq 2 ] || usage
    PATH_ARG="$2"
    ERR_FILE=$(mktemp) || stop "mktemp failed"
    if RESULT=$(require_in_root "$PATH_ARG" 2>"$ERR_FILE"); then
      rm -f "$ERR_FILE"
    else
      MSG=$(cat "$ERR_FILE"); rm -f "$ERR_FILE"
      stop "$MSG"
    fi
    SBX_CANON=$(printf '%s' "$RESULT" | cut -d' ' -f1)
    N=$(printf '%s' "$RESULT" | cut -d' ' -f2)
    ROOT_CANON=$(canon "$(sandbox_root)") || stop "cannot canonicalize sandbox root"
    MARKER="$ROOT_CANON/$N.marker"

    # Never git here: a hostile core.hooksPath, clean.requireForce, or similar left
    # in the sandbox's own config must not get a chance to run on the way out.
    # Unlink a symlink or junction found INSIDE the sandbox before the recursive
    # removal, rather than following it -- `find -type l` catches a POSIX symlink, and
    # a `mklink /J` Windows junction too under Git Bash's `find` (confirmed live); the
    # header's Windows gap is the leftover-process kill above, not this check.
    find "$SBX_CANON" -type l -exec rm -f {} + 2>/dev/null || true
    rm -rf "$SBX_CANON" || stop "cannot remove sandbox: $SBX_CANON"
    rm -f "$MARKER"
    # Best-effort only, never fatal: drop `make`'s fetch ref in the CALLER's own
    # checkout (never the sandbox -- this is the one safe git call `destroy` makes,
    # since it touches the reviewer's own trusted repo, not anything read from the
    # sandbox). Left behind, it keeps this PR's objects reachable in the workspace
    # with nothing to prune them; SKILL.md always calls `destroy` from the main
    # checkout's root, but a caller elsewhere gets no error over something this
    # tidy, not load-bearing.
    git update-ref -d "refs/review-sandbox/$N" 2>/dev/null || true
    ;;

  *)
    usage
    ;;
esac
