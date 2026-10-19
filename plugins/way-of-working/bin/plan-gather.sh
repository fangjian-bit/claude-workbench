#!/bin/sh
# The read-only gather step behind /way-of-working:plan-sprint's recommendation table
# and placement dialogue
# (reference/project-schema.md § `planning`) -- open issues with no milestone, open
# milestones in due-date order, every milestone's title (for a naming-collision
# check), and a specific milestone's own open issues (for the denied-write
# fallback-comment location). The sprint that requested this skill required this
# gather step to be a `bin/` script with fixtures, not skill prose -- the dialogue
# that CONSUMES this data stays in the skill body; this script only fetches and
# sorts it.
#
# Usage:
#   plan-gather.sh unmilestoned <repo>
#     Prints TSV, one row per open TRUE issue (pull requests excluded) with no
#     milestone: number\tupdated_at\tauthor_association\tauthor_login\tauthor_id\t
#     title (the login and numeric id are what `gh-identity.sh task-author` judges, through
#     `authors` below, since
#     `author_association` is viewer-relative -- WB-D24, #382). Sorted ascending
#     by issue number. Empty stdout + exit 0 legitimately means none.
#   plan-gather.sh milestones <repo>
#     Prints TSV, one row per OPEN milestone: number\ttitle\tdue_on-or-none\t
#     open_issues\tclosed_issues. Sorted by due date ascending, undated LAST.
#     Empty stdout + exit 0 legitimately means no open milestones.
#   plan-gather.sh titles <repo>
#     Prints TSV, one row per milestone (OPEN AND CLOSED): number\tstate\ttitle.
#     For the naming-collision check before proposing a new milestone title --
#     GitHub enforces title uniqueness across open and closed together, so the
#     `milestones` subcommand's open-only scope is not enough for this check.
#     Sorted ascending by number. Empty stdout + exit 0 legitimately means none.
#   plan-gather.sh milestone-issues <repo> <milestone-number>
#     Prints TSV, one row per open TRUE issue (pull requests excluded) already ON
#     the given milestone: number\ttitle. Sorted ascending by issue number. Empty
#     stdout + exit 0 legitimately means none. `<milestone-number>` must be
#     digits-only -- this is the read the denied-write fallback-comment location
#     needs and the milestone's own `open_issues` COUNT cannot answer, since that
#     count includes milestoned PRs and names no issue numbers at all.
#   plan-gather.sh authors <rows-file> <project.yml>
#     Prints TSV, one row per non-empty row of <rows-file> (`unmilestoned` output, six
#     TSV fields): number\tword. The word is the sibling `gh-identity.sh task-author
#     <login> <id> <project.yml>` stdout when it exits 0 and prints exactly one of
#     `trusted`, `agent`, `untrusted` or `legacy`; anything else (exit 2, another word,
#     empty output) is `unjudged`. <project.yml> is the default branch's committed
#     `.ai/project.yml`, already written to a file by the caller. Sorted ascending by
#     number. Display only (WB-D32, #710): plan-sprint gates nothing on the word. Makes
#     no `gh` call and writes nothing outside its own temp dir. Exits 1 with a stderr
#     line and nothing on stdout for a bad argument count, an unreadable file, a
#     non-digit number, no yq on PATH, a slash-less $0 or no `gh-identity.sh` beside this script.
#     Empty rows file: empty stdout, exit 0.
#
# Exit-code convention -- deliberately DIFFERENT from plan-anchor.sh/cursor-drift.sh's
# "always exit 0, the verdict is on stdout": this script has no match/drift/
# unreadable verdict to encode. A failed `gh api` call exits non-zero with a
# stderr message and prints nothing further on stdout; the caller must check the
# exit code, never infer failure from empty output, since empty output is also
# the legitimate "zero rows" answer.
#
# Why the sort happens HERE, in the shell, and not inside `gh api --jq`: `gh api
# --paginate ... --jq 'sort_by(...)'` runs the --jq filter ONCE PER PAGE, not once
# over the whole paginated result (verified live: a --per_page=1 call printed a
# distinct filter result for each page). A `sort_by` inside such a filter only
# sorts within each page, which is silently wrong the moment a repo has enough
# open milestones to paginate -- "due-date order, undated last" would stay true on
# page 1 and false everywhere after it. `--slurp` is not supported together with
# `--jq` either. So every subcommand below fetches the full, unsorted result via
# direct redirection to a file (checking gh's own exit code before trusting the
# file), and sorts it with a single `LC_ALL=C sort` pass over the complete data.
#
# The `C` locale sort is why `none` (the undated sentinel `milestones` prints,
# never GitHub's own null) sorts after every real ISO-8601 date with no numeric
# sentinel needed: under byte-value ordering, every ASCII digit (0x30-0x39, the
# first character of any ISO date) sorts before the lowercase letter `n` (0x6E).
#
# Milestone DESCRIPTIONS and issue BODIES are deliberately not part of any
# subcommand's output -- a multi-line text cannot be a TSV field. The calling
# skill fetches each one individually (every open milestone's description and
# every unmilestoned issue's body, up front, as the evidence its recommendation
# cites), via the same direct-redirection pattern used below (never `$(...)`,
# which strips a trailing newline and would make a later edit's read-back
# disagree with what was actually written).
#
# Permitted toolset: POSIX sh, `gh` (using only its own embedded --jq), and
# whatever sort ships on the machine, invoked under `LC_ALL=C` for deterministic
# byte-value ordering -- same bar as plan-anchor.sh and cursor-drift.sh. `authors`
# alone also uses `cut` and the sibling `gh-identity.sh` (which needs yq), run as `sh`
# and found only as `$(dirname "$0")/gh-identity.sh`; the other four subcommands do not.
set -eu

tmp="$(mktemp -d)" || { echo "plan-gather.sh: could not create a temp dir" >&2; exit 1; }
trap 'rm -rf "$tmp"' EXIT

tab="$(printf '\t')"

is_digits() { # is_digits <s> -- true iff <s> is one or more ASCII digits
  case "$1" in
    '' | *[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

usage() {
  echo "plan-gather.sh: usage: plan-gather.sh unmilestoned <repo>" >&2
  echo "                       plan-gather.sh milestones   <repo>" >&2
  echo "                       plan-gather.sh titles       <repo>" >&2
  echo "                       plan-gather.sh milestone-issues <repo> <milestone-number>" >&2
  echo "                       plan-gather.sh authors      <rows-file> <project.yml>" >&2
}

mode="${1:-}"
case "$mode" in
  unmilestoned | milestones | titles | milestone-issues | authors) shift ;;
  *) usage; exit 1 ;;
esac

case "$mode" in
  authors)
    if [ "$#" -ne 2 ]; then
      echo "plan-gather.sh: authors needs <rows-file> <project.yml>" >&2
      exit 1
    fi
    rows_file="$1"; yml_file="$2"
    ;;
  milestone-issues)
    if [ "$#" -ne 2 ]; then
      echo "plan-gather.sh: milestone-issues needs <repo> <milestone-number>" >&2
      exit 1
    fi
    repo="$1"; milestone="$2"
    if ! is_digits "$milestone"; then
      echo "plan-gather.sh: milestone-issues needs a digits-only milestone number" >&2
      exit 1
    fi
    ;;
  *)
    if [ "$#" -ne 1 ]; then
      echo "plan-gather.sh: $mode needs exactly one argument, <repo>" >&2
      exit 1
    fi
    repo="$1"
    ;;
esac

# =============================================================================
if [ "$mode" = authors ]; then
  case "$0" in
    */*) gi="$(dirname "$0")/gh-identity.sh" ;;
    *)
      echo "plan-gather.sh: authors must be run by path (a slash-less \$0 cannot locate gh-identity.sh)" >&2
      exit 1
      ;;
  esac
  if [ ! -f "$gi" ]; then
    echo "plan-gather.sh: gh-identity.sh not beside this script" >&2
    exit 1
  fi
  if [ ! -f "$rows_file" ] || [ ! -r "$rows_file" ]; then
    echo "plan-gather.sh: authors: rows file is not a readable file" >&2
    exit 1
  fi
  if [ ! -f "$yml_file" ] || [ ! -r "$yml_file" ]; then
    echo "plan-gather.sh: authors: project file is not a readable file" >&2
    exit 1
  fi
  if ! command -v yq >/dev/null 2>&1; then
    echo "plan-gather.sh: authors: yq not on PATH (gh-identity.sh needs it)" >&2
    exit 1
  fi
  : >"$tmp/out"
  # Fields by position with cut (-s: a row with no tab has no login or id, so it reads unjudged), never read with a tab IFS: a tab is IFS whitespace, so an
  # empty field would shift every field after it.
  while IFS= read -r row || [ -n "$row" ]; do
    [ -n "$row" ] || continue
    num="$(printf '%s\n' "$row" | cut -f1)"
    login="$(printf '%s\n' "$row" | cut -s -f4)"
    uid="$(printf '%s\n' "$row" | cut -s -f5)"
    if ! is_digits "$num"; then
      echo "plan-gather.sh: authors: a row's issue number is not digits only" >&2
      exit 1
    fi
    word=""
    if word="$(sh "$gi" task-author "$login" "$uid" "$yml_file" 2>/dev/null)"; then
      case "$word" in
        trusted | agent | untrusted | legacy) ;;
        *) word=unjudged ;;
      esac
    else
      word=unjudged
    fi
    printf '%s\t%s\n' "$num" "$word" >>"$tmp/out"
  done <"$rows_file"
  LC_ALL=C sort -t "$tab" -k1,1n "$tmp/out"
  exit 0
fi

# =============================================================================
if [ "$mode" = unmilestoned ]; then
  if ! gh api --paginate "repos/$repo/issues?state=open&milestone=none" --jq \
       '.[] | select(has("pull_request") | not) |
        [.number, .updated_at, .author_association, .user.login, .user.id, .title] | @tsv' \
       >"$tmp/rows" 2>"$tmp/err"; then
    echo "plan-gather.sh: gh api failed fetching unmilestoned issues for $repo:" >&2
    cat "$tmp/err" >&2
    exit 1
  fi
  # Ascending issue number is mechanized here rather than left to skill prose --
  # the script already has the whole result in a file to check gh's exit status,
  # so sorting it too is free.
  LC_ALL=C sort -t "$tab" -k1,1n "$tmp/rows"
  exit 0
fi

# =============================================================================
if [ "$mode" = milestones ]; then
  if ! gh api --paginate "repos/$repo/milestones?state=open" --jq \
       '.[] | [.number, .title, (.due_on // "none"), (.open_issues|tostring),
               (.closed_issues|tostring)] | @tsv' \
       >"$tmp/rows" 2>"$tmp/err"; then
    echo "plan-gather.sh: gh api failed fetching open milestones for $repo:" >&2
    cat "$tmp/err" >&2
    exit 1
  fi
  # Field 3 (due_on-or-none), then field 1 (milestone number) as the tie-break
  # for same-date rows.
  LC_ALL=C sort -t "$tab" -k3,3 -k1,1n "$tmp/rows"
  exit 0
fi

# =============================================================================
if [ "$mode" = titles ]; then
  if ! gh api --paginate "repos/$repo/milestones?state=all" --jq \
       '.[] | [.number, .state, .title] | @tsv' \
       >"$tmp/rows" 2>"$tmp/err"; then
    echo "plan-gather.sh: gh api failed fetching all milestones for $repo:" >&2
    cat "$tmp/err" >&2
    exit 1
  fi
  LC_ALL=C sort -t "$tab" -k1,1n "$tmp/rows"
  exit 0
fi

# =============================================================================
# mode = milestone-issues
if ! gh api --paginate "repos/$repo/issues?milestone=$milestone&state=open" --jq \
     '.[] | select(has("pull_request") | not) | [.number, .title] | @tsv' \
     >"$tmp/rows" 2>"$tmp/err"; then
  echo "plan-gather.sh: gh api failed fetching open issues on milestone $milestone for $repo:" >&2
  cat "$tmp/err" >&2
  exit 1
fi
LC_ALL=C sort -t "$tab" -k1,1n "$tmp/rows"
exit 0
