#!/bin/sh
# Prepare and clean up one coder lane: a worktree under /tmp/lanes/N and the prompt file its
# session reads (docs/identity/DEV-CONTAINER.md, Lanes). Issue #727. It lives under scripts/,
# like the orchestrator driver (WB-D23): tooling for this repository's dev container, not
# shared plugin code.
#
# Usage:
#   lane.sh prep N M BRANCH CRITICS
#   lane.sh done N
#
#   N        the task issue number, digits with no leading zero
#   M        the milestone number the driver expects the task to be on (the driver's own
#            anchored milestone); the container clone has no .ai/state.json to name it
#   BRANCH   TYPE/SLUG: TYPE a commit type of reference/conventions.md, SLUG one or more of
#            a-z, 0-9 and `-`, starting with a letter or digit
#   CRITICS  a comma list of architect, security-critic, docs-consistency; no repeats
#
# Environment: WOW_LANES_DIR overrides /tmp/lanes (the tests only): a slash, then one or
# more of A-Za-z0-9._/-, with no `//`, no `.` or `..` component and no trailing slash.
#
# Output. Every stop prints exactly one line on stdout and exits 1; a bad argument prints a
# usage line on stderr, nothing on stdout, and exits 2, before any git or gh call. No stderr
# of git or gh is ever shown: the origin URL and gh's error text never print.
#   not-main         both modes: not run from the main worktree (a linked worktree, a lane's
#                    own tree, or outside a git work tree)
#   unsafe-dir       the lanes directory (or its resolved path) is a link, not a directory,
#                    not owned by this user, or could not be made
#   unreadable       a read failed or had an unexpected shape (the default-branch read, the
#                    existence probes, the verdict inputs)
#   repo-mismatch    the default branch's .repo is not the origin's nameWithOwner
#   not-map          `identities` is not a map; lanes rely on the finder
#   exists           prep: the worktree path, prompt file, branch or branch config is taken
#   finder: WORD     prep: the finder printed WORD (none, unreacted, escalated, ambiguous,
#                    moved or unreadable) instead of `found`
#   bad-issue        prep: the task is closed, a pull request, off milestone M, or not N
#   failed           prep: a step from the base fetch on (or a signal from the lanes
#                    directory step on) failed and what this run did was
#                    undone as far as it could be; done: the branch config probe or removal,
#                    or the prompt file removal, failed (after the branch was deleted)
#   no-lane          done: no worktree LANES/N on a branch that is neither BASE nor the
#                    default branch
#   missing          done: the lane's worktree is listed but its directory is gone; run
#                    `git worktree prune --dry-run -v` first
#   not-merged       done: no same-repository PR from that branch merged into BASE
#   ambiguous        done: more than one such PR
#   kept X WORD      done: prune-verdict.sh said WORD (not `delete`), or WORD is `moved` or
#                    `checked-out`; the branch is kept. `checked-out` stops before anything is
#                    removed unless the checkout appears between the pre-removal re-read and
#                    the post-removal re-read; then, and always for `moved`, the worktree is
#                    already gone and the prompt file stays. An `unreadable` from the
#                    post-removal re-read leaves the same state (worktree gone, branch, config
#                    and prompt file kept; finish by hand)
#   dirty            done: git refused to remove the worktree (unclean or locked)
# Success. prep prints worktree=, branch=, found=ID UP, milestone=, prompt= and
# prompt-sha256= lines; done prints removed-worktree PATH, deleted-branch X, then
# removed-prompt PATH or no-prompt.
#
# Trust. The project file and the plugin's bin/ scripts are read from the default branch's
# committed copy, resolved ONCE to an oid, never from the working tree: the finder and
# prune-verdict.sh run from a git-archive extraction of that commit, by absolute path.
#
# Residuals (stated, not fixed):
#   - Every lane runs as the same user in the shared /tmp. Once a lane has checked the hash
#     and read its copy, another same-user process can still change that lane's worktree.
#   - A post-checkout hook that fails makes `git worktree add` exit non-zero with the worktree
#     still registered; rollback then removes nothing and prep prints `failed`, so a re-run
#     stops with `exists`. A branch checked out between done's last re-read and its
#     `update-ref -d` is deleted, since update-ref has no checked-out guard.
#   - Every lane session is such a same-user process, and the least trusted one.
#   - The shared /workspace/.git, and the git config on the home volume (~/.gitconfig,
#     ~/.config/git/), are also this script's trust root. A same-user process can
#     edit it: its config (insteadOf, the remote URL), its hooks (a reference-transaction
#     hook runs during the driver's fetch), info/attributes and core.attributesFile
#     (export-ignore drops files from git archive, which then fails closed as unreadable; eol,
#     ident, export-subst and a configured filter can rewrite the extracted scripts' content),
#     and its refs. That is outside what this script can guard.
#   - /way-of-working:ship never sets a PR's milestone. The lane sets it to M after ship when
#     the backlog is the repo and M is still open; the driver confirms it.
#   - The lane's PATH line runs the plugin scripts from the worktree it is editing. A task
#     that changes bin/spec-find.sh therefore checks its own pin with its own edited copy.
#   - The M the driver types ties the task to the driver's milestone. Whether that milestone
#     is the active sprint stays the driver's call.
#
# Permitted toolset: POSIX sh plus `test -O` and `-ef`, git 2.31 or later, gh (with its own --jq), yq
# (mikefarah v4), tar, sha256sum, awk, cut, sed, tr, grep, mktemp, mkdir, ln, chmod, rm, rmdir.
set -eu
set -f
umask 077
LC_ALL=C
GIT_TERMINAL_PROMPT=0
GCM_INTERACTIVE=never
export LC_ALL GIT_TERMINAL_PROMPT GCM_INTERACTIVE

TMP=
trap '[ -z "$TMP" ] || rm -rf "$TMP"' EXIT
# dash does not run the EXIT trap on a signal; exiting from a signal trap does.
trap 'exit 1' INT TERM HUP

usage() {
  echo "usage: lane.sh prep N M BRANCH CRITICS | lane.sh done N" >&2
  exit 2
}

stop() {
  printf '%s\n' "$*"
  exit 1
}

# ---- argument checks (whole-string `case`, so a value carrying a newline fails) ----------

num_ok() { # digits with no leading zero
  case "$1" in
    '' | 0* | *[!0-9]*) return 1 ;;
  esac
  return 0
}

hex40() {
  case "$1" in
    *[!0-9a-f]*) return 1 ;;
  esac
  [ "${#1}" -eq 40 ]
}

branch_ok() { # TYPE/SLUG
  case "$1" in
    */*) ;;
    *) return 1 ;;
  esac
  b_type=${1%%/*}
  b_slug=${1#*/}
  case "$b_type" in
    feat | fix | docs | test | refactor | perf | chore | ci | revert) ;;
    *) return 1 ;;
  esac
  case "$b_slug" in
    '' | -* | *[!a-z0-9-]*) return 1 ;;
  esac
  return 0
}

critics_ok() {
  case "$1" in
    *[!a-z,-]*) return 1 ;;
  esac
  c_list="$1,"
  c_seen=,
  while [ -n "$c_list" ]; do
    c_item=${c_list%%,*}
    c_list=${c_list#*,}
    case "$c_item" in
      architect | security-critic | docs-consistency) ;;
      *) return 1 ;;
    esac
    case "$c_seen" in
      *,"$c_item",*) return 1 ;;
    esac
    c_seen="$c_seen$c_item,"
  done
  return 0
}

lanes_shape_ok() { # an absolute path of A-Za-z0-9._/-, no //, no . or .. component, no trailing /
  case "$1" in
    /*) ;;
    *) return 1 ;;
  esac
  case "$1" in
    *[!A-Za-z0-9._/-]* | *// | */) return 1 ;;
  esac
  case "$1/" in
    *//* | */./* | */../*) return 1 ;;
  esac
  return 0
}

ref_shape_ok() { # a branch name as spec-find.sh's pr_base rule has it
  case "$1" in
    '' | -* | *[!A-Za-z0-9._/-]*) return 1 ;;
  esac
  return 0
}

repo_shape_ok() { # owner/name, no . or .. part
  case "$1" in
    '' | /* | */ | */*/* | *[!A-Za-z0-9._/-]*) return 1 ;;
    */*) ;;
    *) return 1 ;;
  esac
  r_owner=${1%%/*}
  r_name=${1#*/}
  case "$r_owner" in '' | . | ..) return 1 ;; esac
  case "$r_name" in '' | . | ..) return 1 ;; esac
  return 0
}

[ "$#" -ge 1 ] || usage
MODE=$1
case "$MODE" in
  prep)
    [ "$#" -eq 5 ] || usage
    N=$2
    M=$3
    BRANCH=$4
    CRITICS=$5
    num_ok "$N" && num_ok "$M" && branch_ok "$BRANCH" && critics_ok "$CRITICS" || usage
    ;;
  done)
    [ "$#" -eq 2 ] || usage
    N=$2
    num_ok "$N" || usage
    ;;
  *) usage ;;
esac
if [ "${WOW_LANES_DIR+set}" = set ]; then
  lanes_shape_ok "$WOW_LANES_DIR" || usage
  LANES=$WOW_LANES_DIR
else
  LANES=/tmp/lanes
fi

# ---- the main worktree --------------------------------------------------------------------

TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null) || stop not-main
[ -n "$TOPLEVEL" ] || stop not-main
dirs=$(git -C "$TOPLEVEL" rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null) || stop not-main
gd=$(printf '%s\n' "$dirs" | awk 'NR==1')
gc=$(printf '%s\n' "$dirs" | awk 'NR==2')
[ -n "$gd" ] && [ "$gd" = "$gc" ] || stop not-main
if [ -d "$LANES" ]; then
  lanes_phys=$(cd -P "$LANES" 2>/dev/null && pwd -P) || lanes_phys=$LANES
else
  lanes_phys=$LANES
fi
case "$TOPLEVEL/" in
  "$lanes_phys"/*) stop not-main ;;
esac

TMP=$(mktemp -d) || stop unreadable

# ---- the lanes directory -------------------------------------------------------------------

LANES_RESOLVED=

# lanes_check: LANES exists as a plain directory this user owns, and its resolved path is
# safe to put in a prompt. Sets LANES to the resolved value and returns 1 on any failure.
lanes_check() {
  [ ! -L "$LANES" ] || return 1
  [ -d "$LANES" ] || return 1
  [ -O "$LANES" ] || return 1
  lc_res=$(cd -P "$LANES" 2>/dev/null && pwd -P) || return 1
  lanes_shape_ok "$lc_res" || return 1
  if [ -n "$LANES_RESOLVED" ] && [ "$lc_res" != "$LANES_RESOLVED" ]; then
    return 1
  fi
  LANES=$lc_res
  LANES_RESOLVED=$lc_res
  return 0
}

# ---- the default-branch read ---------------------------------------------------------------

NAME= D= DOID= DEFFILE= BIN= BACKLOG= BASE=

read_default() {
  rd_url=$(git -C "$TOPLEVEL" remote get-url origin 2>/dev/null) || stop unreadable
  case "$rd_url" in '' | -*) stop unreadable ;; esac
  gh repo view "$rd_url" --json nameWithOwner,defaultBranchRef \
    --jq '[.nameWithOwner, (.defaultBranchRef.name // "")] | @tsv' >"$TMP/rv.tsv" 2>/dev/null || stop unreadable
  awk -F'\t' 'NR>1 {bad=1} NF!=2 || $1=="" || $2=="" {bad=1} END {exit (bad || NR!=1)}' "$TMP/rv.tsv" || stop unreadable
  NAME=$(cut -f1 "$TMP/rv.tsv")
  D=$(cut -f2 "$TMP/rv.tsv")
  repo_shape_ok "$NAME" || stop unreadable
  ref_shape_ok "$D" || stop unreadable
  git -C "$TOPLEVEL" fetch -q origin "+refs/heads/$D:refs/remotes/origin/$D" >/dev/null 2>&1 || stop unreadable
  DOID=$(git -C "$TOPLEVEL" rev-parse --verify -q "refs/remotes/origin/$D^{commit}" 2>/dev/null) || stop unreadable
  hex40 "$DOID" || stop unreadable
  DEFFILE=$TMP/project.yml
  git -C "$TOPLEVEL" show "$DOID:.ai/project.yml" >"$DEFFILE" 2>/dev/null || stop unreadable
  git -C "$TOPLEVEL" archive -o "$TMP/bin.tar" "$DOID" plugins/way-of-working/bin >/dev/null 2>&1 || stop unreadable
  tar -x -f "$TMP/bin.tar" -C "$TMP" >/dev/null 2>&1 || stop unreadable
  BIN=$TMP/plugins/way-of-working/bin
  [ ! -L "$TMP/plugins" ] && [ ! -L "$TMP/plugins/way-of-working" ] || stop unreadable
  [ -d "$BIN" ] && [ ! -L "$BIN" ] || stop unreadable
  for rd_s in spec-find.sh gh-identity.sh spec-reaction.sh prune-verdict.sh declared-ids.sh; do
    [ -f "$BIN/$rd_s" ] && [ ! -L "$BIN/$rd_s" ] || stop unreadable
  done
  rd_repo=$(yq -r '.repo' "$DEFFILE" 2>/dev/null) || stop unreadable
  [ "$rd_repo" = "$NAME" ] || stop repo-mismatch
  rd_id=$(yq -r 'has("identities"), (.identities | tag)' "$DEFFILE" 2>/dev/null) || stop unreadable
  rd_id=$(printf '%s' "$rd_id" | tr '\n' ' ')
  [ "$rd_id" = "true !!map" ] || stop not-map
  rd_tags=$(yq -r 'explode(.) | [(.pr_base | tag), ((.backlog.repo // .repo) | tag)] | join(" ")' "$DEFFILE" 2>/dev/null) || stop unreadable
  [ "$rd_tags" = "!!str !!str" ] || stop unreadable
  BASE=$(yq -r 'explode(.) | .pr_base' "$DEFFILE" 2>/dev/null) || stop unreadable
  BACKLOG=$(yq -r 'explode(.) | (.backlog.repo // .repo)' "$DEFFILE" 2>/dev/null) || stop unreadable
  ref_shape_ok "$BASE" || stop unreadable
  repo_shape_ok "$BACKLOG" || stop unreadable
}

# probe_branch_config: 0 when branch.X.* keys exist, 1 when none, 2 on any other exit.
probe_branch_config() {
  pc_rc=0
  git -C "$TOPLEVEL" config --get-regexp "^branch\\.$1\\." >/dev/null 2>&1 || pc_rc=$?
  case "$pc_rc" in 0) return 0 ;; 1) return 1 ;; *) return 2 ;; esac
}

# wt_state: print the worktree list for LANES/N as `none`, `detached` or `branch REF`.
wt_state() {
  git -C "$TOPLEVEL" worktree list --porcelain >"$TMP/wt.txt" 2>/dev/null || return 1
  awk -v w="$LANES/$N" '
    $0 == "worktree " w { listed = 1; found = 1; next }
    /^worktree / { listed = 0 }
    listed && /^branch / { br = substr($0, 8) }
    END {
      if (!found) print "none"
      else if (br == "") print "detached"
      else print "branch " br
    }
  ' "$TMP/wt.txt"
}

# ---- prep -----------------------------------------------------------------------------------

WT_ATTEMPTED= WT_ADDED= CREATED_LANES= TMPNAME= PROMPT_MADE= BOID=

rollback() {
  trap '' INT TERM HUP
  # The prompt name is ours when the link to the temp name exists, even if a signal came
  # between `ln` and the flag.
  if [ -n "$TMPNAME" ] && [ "$LANES/$N-prompt.md" -ef "$TMPNAME" ]; then
    rm -f "$LANES/$N-prompt.md" 2>/dev/null || true
  fi
  [ -z "$TMPNAME" ] || rm -f "$TMPNAME" 2>/dev/null || true
  [ -z "$PROMPT_MADE" ] || rm -f "$LANES/$N-prompt.md" 2>/dev/null || true
  rb_gone=1
  if [ -n "$WT_ADDED" ]; then
    git -C "$TOPLEVEL" worktree remove --force "$LANES/$N" >/dev/null 2>&1 || rb_gone=
  fi
  # Another prep with the same BRANCH may have won the race and have it checked out: update-ref
  # has no checked-out guard, so look first.
  rb_listed=
  if [ -n "$WT_ATTEMPTED" ] && [ -n "$rb_gone" ] \
    && git -C "$TOPLEVEL" worktree list --porcelain >"$TMP/rb.txt" 2>/dev/null \
    && ! grep -Fx -- "branch refs/heads/$BRANCH" "$TMP/rb.txt" >/dev/null; then
    if [ -n "$(git -C "$TOPLEVEL" for-each-ref --format=x "refs/heads/$BRANCH" 2>/dev/null)" ]; then
      if git -C "$TOPLEVEL" update-ref -d "refs/heads/$BRANCH" "$BOID" >/dev/null 2>&1; then
        pb_rc=0
        probe_branch_config "$BRANCH" || pb_rc=$?
        [ "$pb_rc" -ne 0 ] || git -C "$TOPLEVEL" config --remove-section "branch.$BRANCH" >/dev/null 2>&1 || true
      fi
    fi
  fi
  [ -z "$CREATED_LANES" ] || rmdir "$LANES" 2>/dev/null || true
}

# Undo what this run did, then stop; stdout is fd 3 because a signal can land inside a redirect.
on_signal() {
  rollback
  trap - EXIT
  [ -z "$TMP" ] || rm -rf "$TMP"
  echo failed >&3
  exit 1
}

fail() {
  rollback
  stop failed
}

emit_prompt_sed() {
  sed -e "s#@BACKLOG@#$BACKLOG#g" -e "s#@N@#$N#g" -e "s#@M@#$M#g" \
    -e "s#@ID@#$FID#g" -e "s#@UP@#$FUP#g" -e "s#@LANES@#$LANES#g" \
    -e "s#@CRITICS@#$CRITICS#g"
}

# The prompt is three quoted heredocs, each through the same sed expressions, the fifth step chosen
# in between: the chosen text is sed's input like the rest of the template, never a replacement
# string. Every part must succeed (the caller's `||` turns set -e off), so a failed early part
# cannot leave a truncated prompt that reads as success.
emit_prompt() {
  emit_prompt_sed <<'PROMPT' || return 1
# Lane prompt: @BACKLOG@#@N@

You are a **lane**. For this one task you act as the `coder` defined in `plugins/way-of-working/agents/coder.md` in this worktree. The driver session that ran `lane.sh prep` is your spawner.

## Task

- **Task:** `@BACKLOG@#@N@`, on milestone `@M@`.
- **Missing state file:** this worktree has no `.ai/state.json`. Wherever `coder.md` refers to `plan_anchor.task_issue`, use `@N@`. Wherever it refers to the anchor's milestone, use `@M@`.
- **Mode:** `map`.
- **Spec:** the spawner names the found pair `found @ID@ @UP@`. The pin is `PIN_ID='@ID@'` and `PIN_UP='@UP@'`.

## PATH: on every Bash call that runs a plugin script

A Bash tool call does not keep exports from earlier calls. So every Bash call that runs a plugin `bin/` script (`spec-find.sh`, `spec-comment.sh`, `spec-fresh.sh`, `gh-identity.sh`, `spec-reaction.sh` and the rest) starts with this line, which also checks that the worktree's scripts, not the installed plugin's older ones, are the ones found:

    export PATH='@LANES@/@N@/plugins/way-of-working/bin':"$PATH" && [ "$(command -v spec-find.sh)" = @LANES@/@N@/plugins/way-of-working/bin/spec-find.sh ] || { echo "PATH check failed"; exit 1; }

If that check fails, stop and report.

## Order of work

1. Build the task per `coder.md`.
2. Run every `gates.green` entry in `.ai/project.yml`, then `bash scripts/test-all.sh` in its own Bash call with the tool's maximum timeout (600000 ms); if that call times out, stop and report.
3. Run `/way-of-working:critic-gate` as written and let its own proposal stand. The driver expects the critics `@CRITICS@`. If critic-gate's proposal differs, show both lists to the human in the pick-list. That list is not the explicit-names shortcut, which only names the human types count for.
4. Commit and open the PR with `/way-of-working:ship`. This is the explicit instruction to commit and push that `coder.md` asks for.
PROMPT
  if [ "$BACKLOG" = "$NAME" ]; then
    emit_prompt_sed <<'STEP5' || return 1
5. Set this PR's milestone, only when ship's author check passed and ship reported the PR URL; `P` is the number at the end of that URL. In one Bash call, capture each value into a variable, check it is non-empty and chain with `&&`: require `P` to be digits with no leading zero; require `gh api repos/@BACKLOG@/pulls/$P --jq .head.ref` to print what `git branch --show-current` prints; require `gh api repos/@BACKLOG@/milestones/@M@ --jq .state` to print `open`; then run `gh api -X PATCH repos/@BACKLOG@/issues/$P -F milestone=@M@ --jq .milestone.number`, setting no other field. The milestone is set only when that last call prints `@M@`. Any other outcome (a `P` that is not digits, a branch mismatch, a closed milestone, a failed read, a PATCH that failed or the session refused, another number printed) is no further write. Report the outcome in your final message either way, and never retry with another value or another command.
STEP5
  else
    emit_prompt_sed <<'STEP5' || return 1
5. Make no milestone write: milestone `@M@` is in the backlog repository, not this PR's. Say so in your final message.
STEP5
  fi
  emit_prompt_sed <<'PROMPT' || return 1

## Lane rules

- Never run `/way-of-working:resume`, `/way-of-working:handoff`, `/way-of-working:plan-sprint` or `/way-of-working:archive-sprint`. Never write anything under `.ai/`.
- Never merge, approve or force-push.
- Work only in `@LANES@/@N@`, never in `/workspace`'s working tree.
- A session that read the issue body or drafted the spec never builds the issue.
- Every PR needs a code-owner approval, and approving a PR with auto-merge armed merges it.

## Identity

- Do not prefix commands with `GH_TOKEN`.
- Commits are unsigned (`WB-D25`).
PROMPT
}

prep() {
  # 2. the lanes directory, if it exists
  if [ -e "$LANES" ] || [ -L "$LANES" ]; then
    lanes_check || stop unsafe-dir
  fi
  # 3. exists
  [ ! -e "$LANES/$N" ] && [ ! -L "$LANES/$N" ] && [ ! -e "$LANES/$N-prompt.md" ] && [ ! -L "$LANES/$N-prompt.md" ] || stop exists
  git -C "$TOPLEVEL" worktree list --porcelain >"$TMP/wt.txt" 2>/dev/null || stop unreadable
  wt_rc=0
  grep -Fx -- "worktree $LANES/$N" "$TMP/wt.txt" >/dev/null 2>&1 || wt_rc=$?
  case "$wt_rc" in 0) stop exists ;; 1) ;; *) stop unreadable ;; esac
  refs=$(git -C "$TOPLEVEL" for-each-ref --format=x "refs/heads/$BRANCH" "refs/remotes/origin/$BRANCH" 2>/dev/null) || stop unreadable
  [ -z "$refs" ] || stop exists
  pb_rc=0
  probe_branch_config "$BRANCH" || pb_rc=$?
  case "$pb_rc" in 0) stop exists ;; 1) ;; *) stop unreadable ;; esac
  lsr=$(git -C "$TOPLEVEL" ls-remote --heads origin "refs/heads/$BRANCH" 2>/dev/null) || stop unreadable
  [ -z "$lsr" ] || stop exists
  # 4. the default-branch read
  read_default
  # 5. the finder
  fd_rc=0
  fd_out=$(sh "$BIN/spec-find.sh" find "$N" "$DEFFILE" 2>/dev/null) || fd_rc=$?
  [ "$fd_rc" -eq 0 ] || stop "finder: unreadable"
  case "$fd_out" in
    *'
'*) stop "finder: unreadable" ;;
  esac
  case "$fd_out" in
    found\ *)
      fd_rest=${fd_out#found }
      case "$fd_rest" in *\ *) ;; *) stop "finder: unreadable" ;; esac
      FID=${fd_rest%% *}
      FUP=${fd_rest#* }
      num_ok "$FID" || stop "finder: unreadable"
      case "$FUP" in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;;
        *) stop "finder: unreadable" ;;
      esac
      ;;
    *)
      fd_w=${fd_out%% *}
      case "$fd_w" in
        none | unreacted | escalated | ambiguous | moved) stop "finder: $fd_w" ;;
        *) stop "finder: unreadable" ;;
      esac
      ;;
  esac
  # 6. the task issue
  gh api "repos/$BACKLOG/issues/$N" \
    --jq '[(.number|tostring), .state, (if has("pull_request") then "1" else "0" end), ((.milestone.number // 0)|tostring)] | @tsv' \
    >"$TMP/issue.tsv" 2>/dev/null || stop unreadable
  awk -F'\t' 'NR>1 {bad=1} NF!=4 {bad=1} END {exit (bad || NR!=1)}' "$TMP/issue.tsv" || stop unreadable
  is_n=$(cut -f1 "$TMP/issue.tsv")
  is_state=$(cut -f2 "$TMP/issue.tsv")
  is_pr=$(cut -f3 "$TMP/issue.tsv")
  is_ms=$(cut -f4 "$TMP/issue.tsv")
  [ "$is_n" = "$N" ] && [ "$is_state" = open ] && [ "$is_pr" = 0 ] && [ "$is_ms" = "$M" ] || stop bad-issue
  # 7. the worktree
  # From here on a signal undoes what this run did, then stops.
  exec 3>&1
  trap on_signal INT TERM HUP
  prev_resolved=$LANES_RESOLVED
  if [ ! -e "$LANES" ] && [ ! -L "$LANES" ]; then
    mkdir -m 700 "$LANES" >/dev/null 2>&1 || stop unsafe-dir
    CREATED_LANES=1
  else
    lanes_check || stop unsafe-dir
    chmod 700 "$LANES" >/dev/null 2>&1 || stop unsafe-dir
  fi
  if ! lanes_check; then
    [ -z "$CREATED_LANES" ] || rmdir "$LANES" 2>/dev/null || true
    stop unsafe-dir
  fi
  if [ -n "$prev_resolved" ] && [ "$prev_resolved" != "$LANES_RESOLVED" ]; then
    stop unsafe-dir
  fi
  git -C "$TOPLEVEL" fetch -q origin "+refs/heads/$BASE:refs/remotes/origin/$BASE" >/dev/null 2>&1 || fail
  BOID=$(git -C "$TOPLEVEL" rev-parse --verify -q "refs/remotes/origin/$BASE^{commit}" 2>/dev/null) || fail
  hex40 "$BOID" || fail
  [ ! -e "$LANES/$N" ] && [ ! -L "$LANES/$N" ] || fail
  WT_ATTEMPTED=1
  # A signal during the add only sets a flag, so WT_ADDED always follows git's exit status;
  # git itself still receives a terminal's Ctrl-C and cleans up its half-made worktree.
  SIG=
  trap 'SIG=1' INT TERM HUP
  add_rc=0
  git -C "$TOPLEVEL" worktree add --no-track -b "$BRANCH" "$LANES/$N" "$BOID" >/dev/null 2>&1 || add_rc=$?
  [ "$add_rc" -ne 0 ] || WT_ADDED=1
  trap on_signal INT TERM HUP
  [ -z "$SIG" ] || on_signal
  [ "$add_rc" -eq 0 ] || fail
  # git follows a symbolic link planted at the path and records the resolved one.
  [ ! -L "$LANES/$N" ] || fail
  git -C "$TOPLEVEL" worktree list --porcelain >"$TMP/wt.txt" 2>/dev/null || fail
  grep -Fx -- "worktree $LANES/$N" "$TMP/wt.txt" >/dev/null || fail
  head=$(git -C "$LANES/$N" rev-parse --verify -q HEAD 2>/dev/null) || fail
  [ "$head" = "$BOID" ] || fail
  # 8. the prompt file
  TMPNAME=$(mktemp "$LANES/.prompt.XXXXXX" 2>/dev/null) || fail
  emit_prompt >"$TMPNAME" || fail
  ln "$TMPNAME" "$LANES/$N-prompt.md" >/dev/null 2>&1 || fail
  PROMPT_MADE=1
  rm -f "$TMPNAME" || fail
  TMPNAME=
  hex=$(sha256sum "$LANES/$N-prompt.md" | awk '{print $1}') || fail
  [ "${#hex}" -eq 64 ] || fail
  trap 'exit 1' INT TERM HUP
  # 9. print
  printf '%s\n' "worktree=$LANES/$N" "branch=$BRANCH" "found=$FID $FUP" "milestone=$M" \
    "prompt=$LANES/$N-prompt.md" "prompt-sha256=$hex"
}

# ---- done -----------------------------------------------------------------------------------

lane_done() {
  read_default
  if [ -e "$LANES" ] || [ -L "$LANES" ]; then
    lanes_check || stop unsafe-dir
  fi
  # 2. the lane
  st=$(wt_state) || stop unreadable
  case "$st" in
    "branch refs/heads/"*) X=${st#branch refs/heads/} ;;
    *) stop no-lane ;;
  esac
  branch_ok "$X" && [ "$X" != "$BASE" ] && [ "$X" != "$D" ] || stop no-lane
  [ -d "$LANES/$N" ] || stop missing
  # 3. the merged PR
  gh pr list --repo "$NAME" --base "$BASE" --head "$X" --state merged \
    --json number,headRefOid,isCrossRepository \
    --jq '.[] | select(.isCrossRepository == false) | [(.number|tostring), .headRefOid] | @tsv' \
    >"$TMP/pr.tsv" 2>/dev/null || stop unreadable
  awk -F'\t' 'NF!=2 {bad=1} END {exit bad}' "$TMP/pr.tsv" || stop unreadable
  rows=$(awk 'END {print NR}' "$TMP/pr.tsv")
  [ "$rows" -ne 0 ] || stop not-merged
  [ "$rows" -eq 1 ] || stop ambiguous
  OID=$(cut -f2 "$TMP/pr.tsv")
  hex40 "$OID" || stop unreadable
  # 4. the verdict
  TIP=$(git -C "$TOPLEVEL" rev-parse --verify -q "refs/heads/$X^{commit}" 2>/dev/null) || stop unreadable
  hex40 "$TIP" || stop unreadable
  verdict=$(cd "$TOPLEVEL" && sh "$BIN/prune-verdict.sh" "$X" "$OID" 2>/dev/null) || verdict=unreadable
  case "$verdict" in
    delete | skip-ahead | skip-unfetchable | unreadable) ;;
    *) verdict=unreadable ;;
  esac
  # 5.
  [ "$verdict" = delete ] || stop "kept $X $verdict"
  # 6. A branch checked out in a second worktree stops here, with nothing removed.
  git -C "$TOPLEVEL" worktree list --porcelain >"$TMP/wt.txt" 2>/dev/null || stop unreadable
  rows_rc=0
  rows=$(grep -Fx -c -- "branch refs/heads/$X" "$TMP/wt.txt") || rows_rc=$?
  case "$rows_rc" in 0 | 1) ;; *) stop unreadable ;; esac
  [ "$rows" -le 1 ] || stop "kept $X checked-out"
  git -C "$TOPLEVEL" worktree remove "$LANES/$N" >/dev/null 2>&1 || stop dirty
  # 7.
  git -C "$TOPLEVEL" worktree list --porcelain >"$TMP/wt.txt" 2>/dev/null || stop unreadable
  rows_rc=0
  grep -Fx -- "branch refs/heads/$X" "$TMP/wt.txt" >/dev/null 2>&1 || rows_rc=$?
  case "$rows_rc" in 0) stop "kept $X checked-out" ;; 1) ;; *) stop unreadable ;; esac
  git -C "$TOPLEVEL" update-ref -d "refs/heads/$X" "$TIP" >/dev/null 2>&1 || stop "kept $X moved"
  pb_rc=0
  probe_branch_config "$X" || pb_rc=$?
  case "$pb_rc" in
    0) git -C "$TOPLEVEL" config --remove-section "branch.$X" >/dev/null 2>&1 || stop failed ;;
    1) ;;
    *) stop failed ;;
  esac
  # 8.
  removed=
  if [ -e "$LANES/$N-prompt.md" ] || [ -L "$LANES/$N-prompt.md" ]; then
    rm -f "$LANES/$N-prompt.md" || stop failed
    removed=1
  fi
  # 9.
  printf '%s\n' "removed-worktree $LANES/$N" "deleted-branch $X"
  if [ -n "$removed" ]; then
    printf '%s\n' "removed-prompt $LANES/$N-prompt.md"
  else
    echo no-prompt
  fi
}

FID= FUP=
case "$MODE" in
  prep) prep ;;
  done) lane_done ;;
esac
