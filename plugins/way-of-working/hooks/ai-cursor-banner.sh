#!/usr/bin/env bash
# SessionStart hook: surface the .ai/ dev-workflow cursor at the top of every
# session so the ASSIGNED model/persona for the next action can't be missed.
# Automates the manual "you're on the wrong model for this" reminder — the
# role->model routing lives in the `models` key of the consuming repo's
# .ai/project.yml, and this plugin's reference/workflow.md explains the
# role split the cursor's fields carry.
#
# Reads .ai/state.json (relative to the session cwd = project root). Emits a
# SessionStart additionalContext block. No-ops silently outside the repo root
# or if jq/the cursor file is missing — a hook that errors is worse than none.
#
# Every interpolated value (the cursor fields and the Parked id list) is capped
# at 200 characters each (`cap` in the jq program), and next_action is also
# trimmed to its first sentence: in a cloned untrusted repo this text becomes
# model context at session start, so it must not be unbounded. `cap` cuts to 200
# characters first (jq's gsub is superlinear in the match count, and the hook
# has a 10s timeout), then replaces each line-breaking or control character
# (newline, carriage return, tab, the C0/C1 ranges, DEL, U+2028/U+2029) with a
# space, so a field cannot start a forged banner line of its own; the banner's
# line count is fixed. next_action goes through `cap` before the first-sentence
# split, so a non-string value cannot kill the banner either.
#
# Two lines are appended after the cursor lines (WB-D24, #390): who is acting, and
# whether an admin token is live. The admin token is the host-minted file the
# container mounts read-only at /run/wow/admin-token (token on line 1, expires_at
# on line 2; only line 2 is ever echoed). That default path is ALWAYS checked, whatever
# the environment says: $WOW_ADMIN_TOKEN_FILE (which a repo's settings can set) names a
# second candidate and exists for the fixtures, so it can add a warning, never remove
# one. That holds against the repo-named candidate only: a repo that controls the session's
# settings (BASH_ENV, PATH, disableAllHooks, a hook of its own) can suppress ANY hook, this one
# included, and that residual is out of scope here. A candidate inside the checkout (compared by inode, so letter case and links do
# not matter) is ignored: a repo cannot commit its own (a link or other non-regular file is
# never followed, so one inside the checkout reads `unverified`, which only over-warns). The default path is never filtered,
# and git runs without the repo-settable GIT_DIR/GIT_WORK_TREE. A candidate that exists but
# token-check.sh does not call live reads `present but not verified`, never `off`: for
# a warning, over-warning is the safe direction. A candidate that is not a regular file is
# never read (a device would hang the hook). Unlike the cursor lines, an admin
# line other than `off` is said even with no .ai/state.json or no jq: a live token
# elevates everything in the container, and a missing cursor is when it is least expected.
# `Acting as:` follows conventions.md's "Acting identity and reach" (GET /user, then
# the installation probe) on github.com only, each gh call bounded at 3 seconds and no
# new call started after 4 seconds of the hook's 10, and prints `unknown` on any failure
# -- never a guessed login. The no-cursor case makes no network call.
set -euo pipefail
SECONDS=0   # an inherited value would move the 4-second probe cutoff

here="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Is directory $1 the checkout (the session cwd or the git toplevel), or inside it?
inside_checkout() {
  local p="$1" n top roots=("$PWD") g
  g="$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -z "$g" ] || roots+=("$g")
  while :; do
    for top in "${roots[@]}"; do
      [ "$p" -ef "$top" ] && return 0
    done
    [ "$p" = / ] || [ "$p" = . ] && return 1
    n="$(dirname -- "$p")"
    [ "$n" != "$p" ] || return 1   # MSYS: dirname of a UNC path is itself
    p="$n"
  done
}

# Prints `live <expiry>`, `unverified`, or nothing, for the admin token file $1. $2 is
# `filter` for a candidate a repo can name (ignored when inside the checkout) and `fixed`
# for the default path, which a repo cannot commit into and so is never filtered.
admin_candidate() {
  local f="$1" mode="$2" d exp
  # A relative path is anchored, so a leading `-` is never read as an option by sed or token-check.sh.
  case "$f" in /*) ;; *) f="./$f" ;; esac
  [ -e "$f" ] || [ -L "$f" ] || return 0
  # Anything but a regular file (a device, a FIFO, a link) is never read: reading /dev/zero hangs.
  if [ ! -f "$f" ] || [ -L "$f" ]; then echo unverified; return 0; fi
  d="$(CDPATH= cd -P -- "$(dirname -- "$f")" 2>/dev/null && pwd)" || { echo unverified; return 0; }
  if [ "$mode" = filter ] && inside_checkout "$d"; then return 0; fi
  exp="$(sed -n 2p "$f" 2>/dev/null || true)"
  # The value printed is shape-checked here, not trusted from a separate read by token-check.sh.
  case "$exp" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;;
    *) echo unverified; return 0 ;;
  esac
  if [ "$(sh "$here/../bin/token-check.sh" file "$f" 2>/dev/null)" = live ]; then
    if [ "$(sed -n 2p "$f" 2>/dev/null || true)" = "$exp" ]; then echo "live $exp"; return 0; fi
  fi
  echo unverified
}

# The admin line: live beats unverified beats off. Several candidates, so a repo-set
# override can add a warning but never hide the default path's.
admin_line() {
  local f r best=off
  for f in /run/wow/admin-token "${WOW_ADMIN_TOKEN_FILE:-}"; do
    [ -n "$f" ] || continue
    if [ "$f" = /run/wow/admin-token ]; then
      r="$(admin_candidate "$f" fixed)"
    elif [ "$best" = off ]; then
      r="$(admin_candidate "$f" filter)"   # only when the default path said nothing
    else
      continue
    fi
    case "$r" in
      "live "*) echo "Admin mode: ADMIN MODE until ${r#live }; everything in this container is elevated."; return 0 ;;
      unverified) best=unverified ;;
    esac
  done
  if [ "$best" = unverified ]; then
    echo "Admin mode: an admin token file is present but not verified live; treat this container as possibly elevated."
  else
    echo "Admin mode: off."
  fi
}

# One bounded gh call against github.com: a failure or a hang prints nothing.
bounded_gh() { env -u GH_HOST -u GH_ENTERPRISE_TOKEN -u GH_REPO -u GIT_DIR -u GIT_WORK_TREE timeout 3 gh "$@" 2>/dev/null || true; }

acting_line() {
  local login rest repo recs reached
  if command -v gh >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
    login="$(bounded_gh api user --hostname github.com --jq .login)"
    rest="${login%\[bot\]}"
    case "$rest" in
      ''|-*|*-|*--*|*[!A-Za-z0-9-]*) login= ;;
    esac
    if [ -n "$login" ] && [ "${#login}" -le 45 ]; then
      echo "Acting as: $login."
      return 0
    fi
    if [ "$SECONDS" -lt 4 ]; then
      repo="$(bounded_gh repo view --json nameWithOwner --jq .nameWithOwner)"
      case "$repo" in
        ''|*[!A-Za-z0-9._/-]*) repo= ;;
      esac
    else
      repo=
    fi
    if [ -n "$repo" ] && [ "$SECONDS" -lt 4 ]; then
      recs="$(bounded_gh api --hostname github.com --paginate installation/repositories --jq '.repositories[].full_name')"
      if [ -n "$recs" ]; then
        reached="$(printf '%s\n' "$recs" | sh "$here/../bin/gh-identity.sh" reach "$repo" 2>/dev/null || true)"
        if [ "$reached" = reached ]; then
          echo "Acting as: an installation token that reaches $repo; which App is not established."
          return 0
        fi
      fi
    fi
  fi
  echo "Acting as: unknown (could not establish the actor)."
}

admin="$(admin_line)"
admin_json='{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n'

state=".ai/state.json"
if [ ! -f "$state" ] || ! command -v jq >/dev/null 2>&1; then
  # No cursor (or no jq to build the banner): only an admin line other than `off` is said.
  # It is fixed text plus a timestamp token-check.sh has validated, so printf is safe.
  [ "$admin" = "Admin mode: off." ] || printf "$admin_json" "$admin"
  exit 0
fi
acting="$(acting_line)"

# Parked sprints (/way-of-working:park-sprint) live as tracked snapshots in
# .ai/parked/<id>-state.json. Derive the id list from the directory, never from
# a field: the directory is the authority. Empty when there are none; the
# `-e` test is what keeps an unmatched glob from echoing its own pattern.
parked=""
for f in .ai/parked/*-state.json; do
  [ -e "$f" ] || continue
  id="${f##*/}"
  id="${id%-state.json}"
  parked="${parked:+$parked, }$id"
done

banner="$(jq -n --arg parked "$parked" --arg acting "$acting" --arg admin "$admin" '
def cap: tostring | .[0:200] | gsub("[\u0000-\u001f\u007f-\u009f\u2028\u2029]"; " ");
input | {
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: (
      "[.ai cursor] Assigned: \(.assigned_persona | cap)/\(.assigned_model | cap) for \(.current_sprint_id | cap) (sprint_status: \(.sprint_status | cap)).\n"
      + "Next action: \((.next_action // "unset") | cap | split(". ")[0]).\n"
      + (if $parked == "" then "" else "Parked: \($parked | cap) (restore with /way-of-working:unpark-sprint <id>).\n" end)
      + "If THIS session is not running \(.assigned_model | cap), it is the wrong session for planning/review/architecture work: /way-of-working:handoff -> new session -> /model \(.assigned_model | cap) -> /way-of-working:resume (`models` in .ai/project.yml). Mechanical/coder tasks are fine on any model.\n"
      + $acting + "\n" + $admin
    )
  }
}' "$state" 2>/dev/null)" || banner=
# A cursor jq cannot read must not silence a live admin token: say only the admin line then.
if [ -n "$banner" ]; then
  printf '%s\n' "$banner"
elif [ "$admin" != "Admin mode: off." ]; then
  printf "$admin_json" "$admin"
fi
exit 0
