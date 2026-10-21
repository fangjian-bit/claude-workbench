#!/bin/sh
# The one writer of the review container's outbox, and the one test for "is this a review
# container" (WB-D24, #636). Under an App-mode repo the host launcher starts a per-review
# container, runs `/way-of-working:architect-review` in it, and reads the outbox this script
# writes; the session itself never posts and never files. The launcher is host config
# (scripts/identity/wow-review), never read from the repo.
#
# What this does NOT close: it checks only shape. The launcher re-checks every outbox file on the
# host, and a session can write the outbox by hand or edit its installed copy of this script. A
# refusal here is a convenience (the session learns of it while it can still fix the text), not a
# boundary.
#
# Two fixed lines below, never read from the environment, written so a `grep -qxF` can match
# them. The first is byte-identical to review-sandbox.sh's; the second is the outbox the
# launcher mounts. Tests run a sed-substituted copy.
#
# Usage:
#   review-outbox.sh where
#   review-outbox.sh outcome <kind> <N> <sha> [<reason>]
#   review-outbox.sh body <file> <sha> <default>
#   review-outbox.sh findings <file>
#   review-outbox.sh verdict <pass|changes-needed> <sha>
#
# where     prints `container` when the marker exists or is a link of any kind, else `host`.
#           Exit 0, no other output. Needs only sh.
# outcome   writes one newline-terminated line to the outcome file: `<kind> <N> <sha>`, or
#           `stopped <N> <sha> <reason>`. <kind> is review, exempt, already-reviewed or stopped;
#           <reason> is given with stopped only, and is one of head-moved, checks-pending,
#           checks-red, base-override or needs-human (the session reasons the launcher accepts).
#           <N> is digits with no leading zero, <sha> 40 lowercase hex. Both must equal
#           $WOW_REVIEW_PR and $WOW_REVIEW_SHA (an accident guard: the line always carries the
#           pinned SHA, a moved head included); either variable unset or empty is exit 2. The
#           file is created directly under `set -C`, never through a temp file, so the first
#           outcome wins.
# body      copies <file> to review.md only if it passes, in order, the checks the launcher and
#           its outbox reader apply. A refusal prints one reason word: not-regular, too-big (over
#           64000 bytes), bad-utf8, control, header, no-head-line, mention, secret or host-line.
#           The header and attestation are read with `yq -er` from the default branch's
#           .ai/project.yml as the remote-tracking ref holds it (never the working tree's copy),
#           in the current repository's top level; <default> is that branch, filled by the caller
#           from the base anchor. <sha> gets the same environment-equality guard as outcome. Needs
#           git, yq and jq.
# findings  copies <file> to findings.json only if it passes the launcher's findings rules plus
#           the outbox reader's file cap. A refusal prints one reason word: not-regular, too-big,
#           control, unreadable, shape, count, title, body, type, area, mention or secret. Needs jq.
# verdict   writes the word and a newline to the outbox file `verdict`: `pass`, or `changes-needed`
#           when the review has at least one blocking finding. Any other word, or a malformed <sha>, is
#           exit 2. <sha> gets the same environment-equality guard as outcome (a wrong one refuses
#           mismatch). The host launcher validates the file again and carries the word on the
#           posted review as one fixed line; a second call before the outcome replaces the file.
#
# Every write subcommand checks in this order: usage, then the host (exit 2), then an existing
# outcome file (exit 1), then content (exit 1). Besides the words above, a refusal may print
# outcome-exists, mismatch (the argument differs from the environment), schema (the gate strings
# are unreadable, empty or span lines) or dest (the destination is a link or not a regular file, or a write to the outbox or a scratch directory failed);
# none of those is fixed by rewriting the text. body, findings and verdict are written through a temp file
# in the outbox, then `mv`, from a copy that was itself the thing checked.
#
# Exit codes: 0 written, 1 refused (with one reason word, except on an unguarded I/O failure), 2 usage or not in a review
# container. Permitted toolset: POSIX sh plus git, yq, jq, mktemp and timeout.
set -eu
set -f
LC_ALL=C; export LC_ALL

REVIEW_CONTAINER_MARKER=/etc/way-of-working/review-container
REVIEW_OUTBOX=/review-out

die() { printf 'review-outbox.sh: %s\n' "$1" >&2; exit "${2:-2}"; }
refuse() { printf '%s\n' "$1"; exit 1; }

usage() { die "usage: review-outbox.sh where | outcome <kind> <N> <sha> [<reason>] | body <file> <sha> <default> | findings <file> | verdict <pass|changes-needed> <sha> ($1)"; }

in_container() { [ -e "$REVIEW_CONTAINER_MARKER" ] || [ -L "$REVIEW_CONTAINER_MARKER" ]; }

is_sha() { # is_sha <value>: 40 lowercase hex
  case $1 in ''|*[!0-9a-f]*) return 1 ;; esac
  [ "${#1}" -eq 40 ]
}

is_num() { # is_num <value>: digits, no leading zero
  case $1 in ''|0*|*[!0-9]*) return 1 ;; esac
  return 0
}

# Phases shared by the write subcommands, after usage: the host, then an existing outcome.
need_container() {
  in_container || die "not in a review container; nothing written"
  [ -d "$REVIEW_OUTBOX" ] || die "the outbox $REVIEW_OUTBOX is not a directory"
}
need_no_outcome() {
  if [ -e "$REVIEW_OUTBOX/outcome" ] || [ -L "$REVIEW_OUTBOX/outcome" ]; then refuse outcome-exists; fi
}
need_env() { # need_env <sha>: the pinned values must be set (usage) and equal (refusal)
  [ -n "${WOW_REVIEW_PR:-}" ] && [ -n "${WOW_REVIEW_SHA:-}" ] || die "WOW_REVIEW_PR and WOW_REVIEW_SHA must be set"
}

has_mention() { # has_mention <file>
  LC_ALL=C grep -Eq '(^|[^A-Za-z0-9_])@[A-Za-z0-9]' "$1" && return 0
  LC_ALL=C grep -Eiq '&#0*64([^0-9]|$)|&#x0*40([^0-9a-f]|$)|&commat;' "$1" && return 0
  return 1
}
has_secret() { # has_secret <file>
  LC_ALL=C grep -Eq 'gh[spour]_[A-Za-z0-9._-]{36,}|github_pat_[A-Za-z0-9_]{22,}|sk-ant-[A-Za-z0-9_-]{20,}' "$1"
}

SCRATCH=
TMPOUT=
cleanup() {
  [ -z "$SCRATCH" ] || rm -rf "$SCRATCH"
  [ -z "$TMPOUT" ] || rm -f "$TMPOUT"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

# copy_checked <file> <cap> <dest>: refuse a non-regular or linked source, then copy at most
# cap+1 bytes to <dest> and refuse one over the cap. Every later check reads the copy.
copy_checked() {
  if [ -L "$1" ] || [ ! -f "$1" ]; then refuse not-regular; fi
  timeout 10 head -c $(($2 + 1)) <"$1" >"$3" 2>/dev/null || refuse not-regular
  [ "$(wc -c <"$3" | tr -d ' ')" -le "$2" ] || refuse too-big
}

# control_free <file>: no byte outbox-read refuses for a body or findings file.
control_free() {
  [ "$(LC_ALL=C tr -d '\011\012\040-\176\200-\377' <"$1" | wc -c | tr -d ' ')" -eq 0 ] || return 1
  if LC_ALL=C od -An -v -tx1 "$1" | tr -d '\n' | LC_ALL=C grep -Eq ' c2 (8[0-9a-f]|9[0-9a-f])'; then
    return 1
  fi
  return 0
}

# publish <copy> <name>: temp file in the outbox, then mv. A link or non-file destination is refused.
publish() {
  dest=$REVIEW_OUTBOX/$2
  if [ -L "$dest" ] || { [ -e "$dest" ] && [ ! -f "$dest" ]; }; then refuse dest; fi
  TMPOUT=$(mktemp "$REVIEW_OUTBOX/.w.XXXXXX") || { echo "review-outbox.sh: cannot make a temp file in the outbox" >&2; refuse dest; }
  cp "$1" "$TMPOUT" || { echo "review-outbox.sh: cannot write the outbox" >&2; refuse dest; }
  mv -f "$TMPOUT" "$dest" || { echo "review-outbox.sh: cannot write the outbox" >&2; refuse dest; }
  TMPOUT=
}

[ "$#" -ge 1 ] || usage "no subcommand"
cmd=$1
shift

case $cmd in
  where)
    [ "$#" -eq 0 ] || usage "where takes no arguments"
    if in_container; then echo container; else echo host; fi
    exit 0 ;;

  outcome)
    [ "$#" -ge 3 ] && [ "$#" -le 4 ] || usage "outcome takes <kind> <N> <sha> [<reason>]"
    kind=$1 num=$2 sha=$3 reason=${4:-}
    case $kind in
      review|exempt|already-reviewed) [ "$#" -eq 3 ] || usage "only stopped takes a reason" ;;
      stopped)
        [ "$#" -eq 4 ] || usage "stopped needs a reason"
        case $reason in
          head-moved|checks-pending|checks-red|base-override|needs-human) ;;
          *) usage "unknown reason" ;;
        esac ;;
      *) usage "unknown kind" ;;
    esac
    is_num "$num" || usage "<N> must be digits with no leading zero"
    is_sha "$sha" || usage "<sha> must be 40 lowercase hex"
    need_env
    need_container
    need_no_outcome
    [ "$num" = "$WOW_REVIEW_PR" ] && [ "$sha" = "$WOW_REVIEW_SHA" ] || refuse mismatch
    if [ "$kind" = stopped ]; then line="stopped $num $sha $reason"; else line="$kind $num $sha"; fi
    ( set -C; printf '%s\n' "$line" >"$REVIEW_OUTBOX/outcome" ) 2>/dev/null || { [ -e "$REVIEW_OUTBOX/outcome" ] || [ -L "$REVIEW_OUTBOX/outcome" ] || refuse dest; refuse outcome-exists; }
    exit 0 ;;

  body)
    [ "$#" -eq 3 ] || usage "body takes <file> <sha> <default>"
    file=$1 sha=$2 default=$3
    is_sha "$sha" || usage "<sha> must be 40 lowercase hex"
    case $default in
      ''|-*|/*|*/|*[!A-Za-z0-9._/-]*|..|../*|*/..|*/../*) usage "<default> is not a plain branch name" ;;
    esac
    need_env
    need_container
    need_no_outcome
    [ "$sha" = "$WOW_REVIEW_SHA" ] || refuse mismatch

    SCRATCH=$(mktemp -d) || { echo "review-outbox.sh: cannot make a scratch directory" >&2; refuse dest; }
    B=$SCRATCH/body
    copy_checked "$file" 64000 "$B"

    # Valid UTF-8: jq replaces an invalid byte with U+FFFD, so a clean round trip is the proof.
    # Carriage returns come off both sides here; control refuses them next.
    jq -j -R -s . <"$B" >"$SCRATCH/rt" 2>/dev/null || refuse bad-utf8
    tr -d '\r' <"$SCRATCH/rt" >"$SCRATCH/rt2"
    tr -d '\r' <"$B" | cmp -s - "$SCRATCH/rt2" || refuse bad-utf8

    control_free "$B" || refuse control

    top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "review-outbox.sh: not inside a git repository" >&2; refuse schema; }
    git -C "$top" show "refs/remotes/origin/$default:./.ai/project.yml" >"$SCRATCH/def.yml" 2>/dev/null || refuse schema
    HDR=$(yq -er '.review.ci_gate.header' "$SCRATCH/def.yml" 2>/dev/null) || refuse schema
    ATT=$(yq -er '.review.ci_gate.attestation' "$SCRATCH/def.yml" 2>/dev/null) || refuse schema
    nl='
'
    for v in "$HDR" "$ATT"; do
      case $v in ''|*"$nl"*) refuse schema ;; esac
    done
    if [ "$(sed -n 1p "$B")" != "$HDR" ] || [ -n "$(sed -n 2p "$B")" ] || [ "$(sed -n 3p "$B")" != "$ATT" ] || [ "$(sed -n '$=' "$B")" -lt 3 ]; then
      refuse header
    fi
    if ! LC_ALL=C grep -qxF "Reviewed against head $sha" "$B"; then refuse no-head-line; fi
    if has_mention "$B"; then refuse mention; fi
    if has_secret "$B"; then refuse secret; fi
    # A forged host footer: a line that reads "Host:" once leading space, markup and zero-width characters are ignored.
    zw1=$(printf '\342\200'); zwlo=$(printf '\213'); zwhi=$(printf '\217'); bom=$(printf '\357\273\277')
    if LC_ALL=C grep -q '^Host: ' "$B" || LC_ALL=C grep -Eq "^([[:space:]*_>#\`~|-]|${zw1}[${zwlo}-${zwhi}]|${bom})*Host: (no findings to file|findings not filed|[0-9]+ findings will be filed)" "$B"; then refuse host-line; fi

    publish "$B" review.md
    exit 0 ;;

  verdict)
    [ "$#" -eq 2 ] || usage "verdict takes <pass|changes-needed> <sha>"
    word=$1 sha=$2
    case $word in pass|changes-needed) ;; *) usage "the verdict is pass or changes-needed" ;; esac
    is_sha "$sha" || usage "<sha> must be 40 lowercase hex"
    need_env
    need_container
    need_no_outcome
    [ "$sha" = "$WOW_REVIEW_SHA" ] || refuse mismatch

    SCRATCH=$(mktemp -d) || { echo "review-outbox.sh: cannot make a scratch directory" >&2; refuse dest; }
    printf '%s\n' "$word" >"$SCRATCH/verdict"
    publish "$SCRATCH/verdict" verdict
    exit 0 ;;

  findings)
    [ "$#" -eq 1 ] || usage "findings takes <file>"
    file=$1
    need_container
    need_no_outcome

    SCRATCH=$(mktemp -d) || { echo "review-outbox.sh: cannot make a scratch directory" >&2; refuse dest; }
    F=$SCRATCH/findings
    copy_checked "$file" 32768 "$F"
    control_free "$F" || refuse control
    nf() { refuse "$1"; }
    jq -e . <"$F" >/dev/null 2>&1 || nf unreadable
    jq -e -s 'length == 1 and (.[0] | type) == "array"' <"$F" >/dev/null 2>&1 || nf shape
    jq -e 'all(.[]; type == "object"
        and ((keys - ["area"]) | sort) == ["body", "title", "type"]
        and (.title | type) == "string" and (.body | type) == "string" and (.type | type) == "string"
        and ((has("area") | not) or (.area | type) == "string"))' <"$F" >/dev/null 2>&1 || nf shape
    jq -e 'length <= 5' <"$F" >/dev/null 2>&1 || nf count
    jq -e 'all(.[]; (.title | length) >= 1 and (.title | length) <= 120)' <"$F" >/dev/null 2>&1 || nf title
    jq -e 'all(.[]; (.body | utf8bytelength) <= 4000)' <"$F" >/dev/null 2>&1 || nf body
    jq -e 'all(.[]; .type == "bug" or .type == "feature" or .type == "chore" or .type == "docs")' <"$F" >/dev/null 2>&1 || nf type
    jq -e 'all(.[]; (has("area") | not) or (.area | test("\\Aarea/[a-z0-9-]+\\z")))' <"$F" >/dev/null 2>&1 || nf area
    jq -e 'all(.[]; ((.title | explode | any(. < 32 or (. >= 127 and . <= 159))) or (.body | explode | any((. < 32 and . != 9 and . != 10) or (. >= 127 and . <= 159)))) | not)' <"$F" >/dev/null 2>&1 || nf control
    jq -r '.[] | .title, .body' <"$F" >"$SCRATCH/text" 2>/dev/null || nf unreadable
    if has_mention "$SCRATCH/text"; then nf mention; fi
    if has_secret "$SCRATCH/text"; then nf secret; fi

    publish "$F" findings.json
    exit 0 ;;

  *) usage "unknown subcommand" ;;
esac
