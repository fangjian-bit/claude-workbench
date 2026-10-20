#!/bin/sh
# Is an approved spec comment still current against the base it was drafted on? (#663, WB-D31)
#
# A spec is drafted on one commit (the `sha=` of its `spec-task:` marker) and the base moves on.
# Before a build uses a found spec, the paths the spec lists under its *Files touched* section
# are compared between that commit and the current tip of the base. If any changed, the spec is
# stale and the build does not use it. Callers: /way-of-working:resume's map body read (and its stale branch's re-run) and the
# coder agent's, each after `spec-comment.sh check` says `ok` and before `spec-comment.sh body`;
# /way-of-working:spec-task runs the `shape` mode on a draft before posting it.
#
# Usage: spec-fresh.sh check <comment.json> <issue> <project.yml>
#        spec-fresh.sh shape <draft.md>
#
#   <comment.json>  the caller's own fetch of the ONE spec comment, to a file (the same file
#                   spec-comment.sh reads), never piped in
#   <issue>         the task issue number, digits with no leading zero
#   <project.yml>   the DEFAULT branch's committed copy (the callers' $DEF_YML_FILE)
#   <draft.md>      a plain markdown file: no marker, no git. `shape` runs only the CR strip and
#                   the Shape stage below and prints `ok`, `bad-shape` or `unreadable`.
#
# Prints exactly one line to stdout and exits 0:
#   fresh        -- no checked path changed (or none is checked)
#   stale <n>    -- <n> checked paths changed between the marker's commit and the base tip
#   bad-marker   -- the first line is not a marker for <issue> on the project file's `pr_base`
#   bad-shape    -- the body carries a refused form on some line (see the Shape rules below) or a stray
#                   CR (a HID character on the marker line reads bad-marker), or the *Files touched*
#                   section has a shape this check cannot read
#   bad-sha      -- the marker's commit is not a commit, or not an ancestor of the base tip
#   unreadable   -- a config value, the JSON, a fetch or a git read failed
# It exits 2, with a usage line on stderr and nothing on stdout, for a bad argument (the wrong
# count, an unknown mode, an issue with a leading zero or non-digits), a missing file, or a
# slash-less $0. It never prints the body, a path or git's output. Every git and yq call's
# stderr goes to /dev/null. Nothing is evaluated; the body is data.
#
# Stages, in this order:
#   Config   `pr_base` from <project.yml>: a string passing spec-find.sh's branch-name check.
#   Body     `.body` from <comment.json> (yq -p=json): a string. Every later test sees each
#            line with one trailing CR removed.
#   Marker   the first line (up to the first LF, one trailing CR removed) matches
#            `spec-task: issue=<N> base=<B> sha=<40 hex>` with <N> = <issue>, <B> = pr_base.
#   Shape    no refused form (the Shape rules below) or stray CR on any line, and the *Files touched*
#            section (from the one `### Files touched` heading to the one `### Done when` heading
#            after it) is readable: see below.
#   Fetch    `git fetch` of the base into refs/remotes/origin/<base>, then rev-parse of it.
#   Commit   the sha is a commit and an ancestor of the base tip, before any other git command
#            uses it.
#   Changed  `git diff --name-only -z <sha> <tip>`, NUL-split, minus the cursor-sync set that
#            cursor-drift.sh knows (.ai/next-steps.md and everything under .ai/parked/).
#   Compare  a checked path changed when a changed path equals it or begins with it and a `/`.
#            Strings only: a path is never passed to git.
#
# The Shape rules. Bullets: `- ` at column 0 then a backtick opens an item; its span is the text
# between its line's first and second backtick and must match
# `^[A-Za-z0-9._][A-Za-z0-9._/-]*$` with no empty, `.` or `..` segment after one trailing `/`
# is removed. A bullet whose closing backtick is followed by exactly ` **(append)**` is skipped
# (an entry added to a shared file), unless the path is under `.github/`. Nested detail (two or
# more spaces of indent while an item is open) is ignored. Prose (column 0, not starting with a
# list, quote, table, link, heading, code, tab or ordered-list character) closes an item.
# Blank lines neither open nor close one. Anything else, a code fence, a line starting with `#`
# or `<` (inside the section), a CR that is not the last character of its line, not exactly one of
# each heading, or no bullet at all, is bad-shape. So is any of these on any line of the body, after
# one trailing CR is removed: an opener (a `<` followed by `!` or `?`, or a `<` and a slash followed
# by a character that is not an ASCII letter or by the end of the line, which inside an HTML block
# starts a bogus comment); a one-line link reference definition (LDEF below, a footnote definition
# too); a numeric character reference (HREF below, with or without its semicolon); a named reference
# that decodes only to an invisible character (the seventeen HREF names, `shy` included); and a
# character from HID, which is exactly Unicode's Default_Ignorable_Code_Point set (U+00AD, U+034F,
# U+061C, U+115F-1160, U+17B4-17B5, U+180B-180F, U+200B-200F, U+202A-202E, U+2060-206F, U+3164,
# U+FE00-FE0F, U+FEFF, U+FFA0, U+FFF0-FFF8, U+1BCA0-1BCA3, U+1D173-1D17A, U+E0000-E0FFF; Unicode 15.0
# data). HID, HREF and LDEF are byte-for-byte copies in spec-issue.sh and spec-post.sh (#757); the
# opener and CR tests are inline in each awk program. Other hiding forms stay open (WB-D31 residual 19).
#
# Permitted toolset: POSIX sh, git, yq (mikefarah v4), awk, mktemp and tr. Runs under LC_ALL=C.
# No gh, no eval.
set -eu
LC_ALL=C
export LC_ALL

usage() {
  echo "usage: spec-fresh.sh check <comment.json> <issue> <project.yml> | spec-fresh.sh shape <draft.md>" >&2
  exit 2
}
[ "$#" -ge 1 ] || usage
mode="$1"
case "$mode" in
  check) [ "$#" -eq 4 ] || usage ;;
  shape) [ "$#" -eq 2 ] || usage ;;
  *) usage ;;
esac
case "$0" in
  */*) : ;;
  *) echo "spec-fresh.sh: must be run by path" >&2; exit 2 ;;
esac
if [ "$mode" = check ]; then
  cj="$2" issue="$3" yml="$4"
  case "$issue" in '' | 0* | *[!0-9]*) echo "spec-fresh.sh: issue must be digits with no leading zero" >&2; exit 2 ;; esac
  [ -f "$cj" ] || { echo "spec-fresh.sh: no such comment file" >&2; exit 2; }
  [ -f "$yml" ] || { echo "spec-fresh.sh: no such project file" >&2; exit 2; }
else
  draft="$2"
  [ -e "$draft" ] || { echo "spec-fresh.sh: no such draft file" >&2; exit 2; }
fi

tmp="$(mktemp -d)" || { echo "spec-fresh.sh: no temp directory" >&2; exit 2; }
trap 'rm -rf "$tmp"' EXIT

out() {
  printf '%s\n' "$*"
  exit 0
}

# The Shape stage over a file whose lines may end in CR. On a pass it writes the checked paths,
# one per line, to the second argument and returns 0; otherwise it returns 1.
HID="$(printf '\302\255|\315\217|\330\234|\341\205[\237-\240]|\341\236[\264-\265]|\341\240[\213-\217]|\342\200[\213-\217]|\342\200[\252-\256]|\342\201[\240-\257]|\343\205\244|\357\270[\200-\217]|\357\273\277|\357\276\240|\357\277[\260-\270]|\360\233\262[\240-\243]|\360\235\205[\263-\272]|\363\240[\200-\277][\200-\277]')"
HREF='&#[0-9xX]|&shy|&(zwnj|zwj|lrm|rlm|ZeroWidthSpace|NegativeVeryThinSpace|NegativeThinSpace|NegativeMediumSpace|NegativeThickSpace|NoBreak|ApplyFunction|af|InvisibleTimes|it|InvisibleComma|ic);'
LDEF='^ ? ? ?\[[^]]+\]:'
shape_stage() { # <in> <paths-out>
  FRESH_HID="$HID" FRESH_HREF="$HREF" FRESH_LDEF="$LDEF" awk '
    BEGIN {
      hid = ENVIRON["FRESH_HID"]
      href = ENVIRON["FRESH_HREF"]; ldef = ENVIRON["FRESH_LDEF"]
      state = 0; nf = 0; nd = 0; bad = 0; item = 0; nb = 0
    }
    {
      line = $0
      sub(/\r$/, "", line)
      # An opener: < then ! or ?, or < and a slash then a non-letter or the end of the line (a bogus
      # comment inside an HTML block hides text up to the next >).
      if (line ~ /<[!?]/ || line ~ /<\/[^A-Za-z]/ || line ~ /<\/$/) bad = 1
      # A CR left after the strip is a line break to a Markdown renderer but not to awk, so a
      # bullet could render as two and be checked as one.
      if (index(line, "\r") > 0) bad = 1
      if (line ~ hid) bad = 1
      if (line ~ href) bad = 1
      if (line ~ ldef) bad = 1
      if (line ~ /^### Files touched[ \t]*$/) {
        nf++
        if (state == 0) state = 1
        next
      }
      if (line ~ /^### Done when[ \t]*$/) {
        nd++
        if (state == 1) state = 2; else bad = 1
        next
      }
      if (state != 1) next
      if (line ~ /^[ \t]*$/) next
      if (line ~ /^[ \t]*[#<]/ || line ~ /^[ \t]*(```|~~~)/) { bad = 1; next }
      c = substr(line, 1, 1)
      if (line ~ /^- `/) {
        item = 1
        s = substr(line, 4)
        k = index(s, "`")
        if (k == 0) { bad = 1; next }
        span = substr(s, 1, k - 1)
        rest = substr(s, k + 1)
        if (span !~ "^[A-Za-z0-9._][A-Za-z0-9._/-]*$") { bad = 1; next }
        orig = span
        if (substr(span, length(span), 1) == "/") span = substr(span, 1, length(span) - 1)
        m = split(span, seg, "/")
        for (j = 1; j <= m; j++) if (seg[j] == "" || seg[j] == "." || seg[j] == "..") bad = 1
        nb++
        skip = (index(rest, " **(append)**") == 1 && orig != ".github" && substr(orig, 1, 8) != ".github/")
        if (!skip && !(span in seen)) { seen[span] = 1; paths[++np] = span }
        next
      }
      if (c == " ") {
        if (item && line ~ /^  /) next
        bad = 1; next
      }
      if (c == "-" || c == "*" || c == "+" || c == ">" || c == "|" || c == "[" || c == "`" || c == "~" || c == "\t") { bad = 1; next }
      if (line ~ /^[0-9]+[.)]/) { bad = 1; next }
      item = 0
    }
    END {
      if (bad || nf != 1 || nd != 1 || state != 2 || nb == 0) exit 1
      for (j = 1; j <= np; j++) print paths[j]
    }
  ' <"$1" >"$2" 2>/dev/null
}

if [ "$mode" = shape ]; then
  { [ -f "$draft" ] && [ -r "$draft" ]; } || out unreadable
  if shape_stage "$draft" "$tmp/paths"; then out ok; fi
  out bad-shape
fi

# --- Config ------------------------------------------------------------------------------
base="$(yq -r 'explode(.) | .pr_base | select(tag == "!!str")' "$yml" 2>/dev/null)" || out unreadable
case "$base" in '' | -* | *[!A-Za-z0-9._/-]*) out unreadable ;; esac

# --- Body --------------------------------------------------------------------------------
[ "$(yq -p=json -r '.body | tag' "$cj" 2>/dev/null)" = '!!str' ] || out unreadable
yq -p=json -r '.body' "$cj" >"$tmp/body" 2>/dev/null || out unreadable

# --- Marker ------------------------------------------------------------------------------
awk 'NR == 1 { sub(/\r$/, ""); print; exit }' "$tmp/body" >"$tmp/first" 2>/dev/null || out unreadable
parsed="$(FRESH_ISSUE="$issue" FRESH_BASE="$base" awk '
  {
    if ($0 !~ /^spec-task: issue=[1-9][0-9]* base=[A-Za-z0-9._\/][A-Za-z0-9._\/-]* sha=[0-9a-f]+$/) exit
    split($0, f, " ")
    iss = substr(f[2], 7); b = substr(f[3], 6); sha = substr(f[4], 5)
    if (length(sha) != 40) exit
    if (iss "" != ENVIRON["FRESH_ISSUE"] "" || b "" != ENVIRON["FRESH_BASE"] "") exit
    print sha
  }
' "$tmp/first" 2>/dev/null)" || out bad-marker
case "$parsed" in
  '' | *[!0-9a-f]*) out bad-marker ;;
esac
[ "${#parsed}" -eq 40 ] || out bad-marker
sha="$parsed"

# --- Shape -------------------------------------------------------------------------------
shape_stage "$tmp/body" "$tmp/paths" || out bad-shape

# --- Fetch -------------------------------------------------------------------------------
top="$(git rev-parse --show-toplevel 2>/dev/null)" || out unreadable
[ -n "$top" ] || out unreadable
git -C "$top" fetch -q --no-tags origin "+refs/heads/$base:refs/remotes/origin/$base" >/dev/null 2>&1 </dev/null || out unreadable
tip="refs/remotes/origin/$base"
git -C "$top" rev-parse --verify "$tip^{commit}" >/dev/null 2>&1 </dev/null || out unreadable

# --- Commit ------------------------------------------------------------------------------
git -C "$top" cat-file -e "$sha^{commit}" >/dev/null 2>&1 </dev/null || out bad-sha
git -C "$top" merge-base --is-ancestor "$sha" "$tip" >/dev/null 2>&1 </dev/null || out bad-sha

# --- Changed paths -----------------------------------------------------------------------
git -C "$top" -c core.quotePath=false -c diff.relative=false diff --no-ext-diff --no-renames --name-only -z "$sha" "$tip" -- >"$tmp/changed.z" 2>/dev/null </dev/null || out unreadable
tr '\0' '\n' <"$tmp/changed.z" >"$tmp/changed" 2>/dev/null || out unreadable

# --- Compare -----------------------------------------------------------------------------
n="$(FRESH_CHANGED="$tmp/changed" awk '
  BEGIN {
    f = ENVIRON["FRESH_CHANGED"]
    while ((r = (getline l < f)) > 0) {
      if (l == ".ai/next-steps.md" || substr(l, 1, 11) == ".ai/parked/") continue
      ch[++nc] = l
    }
    if (r < 0) { bad = 1; exit 1 }
    cnt = 0
  }
  {
    p = $0
    for (i = 1; i <= nc; i++) {
      if (ch[i] == p || substr(ch[i], 1, length(p) + 1) == p "/") { cnt++; break }
    }
  }
  END { if (bad) exit 1; print cnt + 0 }
' "$tmp/paths" 2>/dev/null)" || out unreadable
case "$n" in '' | *[!0-9]*) out unreadable ;; esac
[ "$n" -eq 0 ] && out fresh
out "stale $n"
