#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/spec-fresh.sh: the freshness check that stops a
# build from a spec whose listed files changed on the base since its commit (#663, WB-D31).
#
# Each case builds a scratch repository with a local bare `origin` (no network): commit A on the
# base is the spec's `sha=`, a later commit B is the base tip. A logging `git` wrapper first on
# PATH runs the real git, so a case can show which arguments git was given. No case's stdout or
# stderr may contain the sentinel planted in the body, a listed path and the origin URL.
# Needs yq (mikefarah v4) and git; skips, loudly, without either.
# Permitted toolset: POSIX sh, plus git, yq, awk, sed, grep and tr as the cases need.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/plugins/way-of-working/bin/spec-fresh.sh"

for tool in yq git; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "SKIP - $tool not on PATH; spec-fresh.test.sh needs it" >&2
    exit 0
  fi
done
real_git="$(command -v git)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
assert_eq() { # <desc> <want> <got>
  if [ "$2" = "$3" ]; then
    echo "ok - $1"
  else
    echo "FAIL - $1: expected [$2], got [$3]" >&2
    fail=1
  fi
}

SENT="SENTINEL-7c2d41e9"
ISSUE=663
fakebin="$tmp/fakebin"
mkdir -p "$fakebin"
cat >"$fakebin/git" <<'FAKE_GIT'
#!/bin/sh
printf '%s\n' "$*" >>"$FX_LOG"
exec "$FX_REAL_GIT" "$@"
FAKE_GIT
chmod +x "$fakebin/git"

cn=0
put() { mkdir -p "$(dirname "$R/$1")" && printf '%s\n' "$2" >"$R/$1"; }
bump() { git -C "$R" add -A && git -C "$R" commit -q -m b && git -C "$R" push -q origin refs/heads/main:refs/heads/main; }

# nc: a fresh repository with commit A pushed to a local bare origin, a logging wrapper log and
# a project file naming the base.
nc() {
  cn=$((cn + 1))
  D="$tmp/c$cn"
  R="$D/work"
  O="$D/origin-$SENT.git"
  mkdir -p "$D"
  git init -q --bare "$O"
  git -C "$O" symbolic-ref HEAD refs/heads/main
  git init -q "$R"
  git -C "$R" symbolic-ref HEAD refs/heads/main
  git -C "$R" config user.name t
  git -C "$R" config user.email t@example.invalid
  git -C "$R" config commit.gpgsign false
  git -C "$R" remote add origin "$O"
  put f1 one
  put f2 two
  put dir/x ex
  put a/b ab
  put a/bc abc
  put doc.md doc
  put .ai/next-steps.md ns
  put .ai/parked/p.md pk
  put .github/wf.yml wf
  put "zz-$SENT/f" sf
  mkdir -p "$R/dir2"
  printf 'u\n' >"$R/dir2/$(printf '\303\251').txt"
  git -C "$R" add -A && git -C "$R" commit -q -m a && git -C "$R" push -q origin refs/heads/main:refs/heads/main
  SHA="$(git -C "$R" rev-parse HEAD)"
  LOG="$D/git.log"
  : >"$LOG"
  PRBASE=main
  writeyml
}
writeyml() { printf 'repo: acme/app\npr_base: %s\n' "$PRBASE" >"$D/project.yml"; }

# mk <marker-line> <section-text>: the comment body into BODY, then the JSON into $D/c.json.
mk() {
  BODY="$(printf '%s\n\n### Goal\n\nx\n\n### Files touched\n\n%s\n\n### Done when\n\nx\n\n### Tests\n\nx\n' "$1" "$2")"
  tojson
}
tojson() { BODY="$BODY" yq -n -o=json '.body = strenv(BODY)' >"$D/c.json"; }
marker() { printf 'spec-task: issue=%s base=%s sha=%s' "${1:-$ISSUE}" "${2:-main}" "${3:-$SHA}"; }

run() { # run the check in the scratch repo
  rc=0
  out="$(cd "$R" && PATH="$fakebin:$PATH" FX_LOG="$LOG" FX_REAL_GIT="$real_git" sh "$script" check "$D/c.json" "$ISSUE" "$D/project.yml" 2>"$D/err" </dev/null)" || rc=$?
  err="$(cat "$D/err")"
}
expect() { # <desc> <want> [want-rc]
  want_rc="${3:-0}"
  assert_eq "$1" "$2|$want_rc" "$out|$rc"
  case "$out$err" in
    *"$SENT"*) echo "FAIL - $1: the sentinel reached an output stream" >&2; fail=1 ;;
  esac
}
# shape <section-text>: the shape mode over a plain draft
shape() {
  printf '# title\n\n### Goal\n\nx\n\n### Files touched\n\n%s\n\n### Done when\n\nx\n' "$1" >"$D/draft.md"
  rc=0
  out="$(PATH="$fakebin:$PATH" FX_LOG="$LOG" FX_REAL_GIT="$real_git" sh "$script" shape "$D/draft.md" 2>"$D/err" </dev/null)" || rc=$?
  err="$(cat "$D/err")"
}

# --- fresh / stale -----------------------------------------------------------------------
S1='- `f1`'
nc; put f2 changed; bump; mk "$(marker)" "$S1"; run
expect "fresh: a listed file unchanged between A and B" "fresh"

nc; put f1 changed; bump; mk "$(marker)" "$S1"; run
expect "stale: a listed file changed in B" "stale 1"

nc; put dir/x changed; bump; mk "$(marker)" '- `dir`'; run
expect "stale: a listed directory with a file changed under it" "stale 1"

nc; put dir/x changed; bump; mk "$(marker)" '- `dir/`'; run
expect "stale: a listed directory with a trailing slash" "stale 1"

nc; put newdir/new n; bump; mk "$(marker)" '- `newdir/new`'; run
expect "stale: a listed path created in B" "stale 1"

nc; git -C "$R" rm -q f1; bump; mk "$(marker)" "$S1"; run
expect "stale: a listed file deleted in B" "stale 1"

nc; git -C "$R" mv f1 f1-renamed; bump; mk "$(marker)" "$S1"; run
expect "stale: a listed file renamed in B" "stale 1"

nc; put f1 changed; put f2 changed; bump; mk "$(marker)" '- `f1`
- `f2`
- `doc.md`'; run
expect "stale: two listed files changed" "stale 2"

nc; put f1 changed; bump; mk "$(marker)" '- `f1`
- `f1`'; run
expect "stale: a path listed twice counts once" "stale 1"

nc; put f1 changed; bump; mk "$(marker)" '- `f1` **(append)**'; run
expect "fresh: a listed file whose bullet carries (append) changed" "fresh"

nc; put f1 changed; bump; mk "$(marker)" '- `f1` **(append)**: one line added'; run
expect "fresh: (append) followed by a colon" "fresh"

nc; put a/bc changed; bump; mk "$(marker)" '- `a/b`'; run
expect "fresh: a changed path that only shares a string prefix with a listed path" "fresh"

nc; put dir/x changed; bump; mk "$(marker)" '- `f1`
  - `dir/x` is mentioned in a sub-bullet'; run
expect "fresh: a path cited only in a two-space sub-bullet" "fresh"

nc; put dir/x changed; bump
BODY="$(printf '%s\n\n### Goal\n\nSee `dir/x` here.\n\n### Files touched\n\n- `f1`\n\n### Done when\n\nx\n' "$(marker)")"; tojson; run
expect "fresh: a path cited only outside Files touched" "fresh"

nc; put .ai/next-steps.md changed; put .ai/parked/p.md changed; bump; mk "$(marker)" '- `.ai/next-steps.md`
- `.ai/parked/`'; run
expect "fresh: only the cursor-sync files changed, both listed" "fresh"

nc; put dir2/other.txt n; printf 'v\n' >"$R/dir2/$(printf '\303\251').txt"; bump; mk "$(marker)" '- `dir2`'; run
expect "stale: a changed file with a non-ASCII name under a listed directory" "stale 1"

nc; put f1 changed; bump
BODY="$(printf '%s\n\n### Goal\n\nx\n\n### Files touched   \n\n- `f1`\n\n### Done when\t\n\nx\n' "$(marker)" | sed 's/$/\r/')"; tojson; run
expect "stale: CRLF line ends and trailing blanks on the headings" "stale 1"

nc; put f1 changed; bump; mk "$(marker)" '- `f1` x **(append)**'; run
expect "stale: (append) not right after the closing backtick" "stale 1"

nc; put f1 changed; bump; mk "$(marker)" '- `f1`  **(append)**'; run
expect "stale: (append) after two spaces" "stale 1"

nc; put .github/wf.yml changed; bump; mk "$(marker)" '- `.github/wf.yml` **(append)**'; run
expect "stale: a .github path marked (append)" "stale 1"

nc; put f1 changed; bump; mk "$(marker)" '- `f1`
- `zz-'"$SENT"'/f`'; run
expect "stale: a listed sentinel path never reaches the output" "stale 1"

nc; put f2 changed; bump; mk "$(marker)" '- `zz-'"$SENT"'/f`
  '"$SENT"' in a nested detail line'; run
expect "fresh: a sentinel path and body text never reach the output" "fresh"

nc; git -C "$R" tag main "$SHA"; git -C "$R" push -q origin refs/tags/main; put f1 changed; bump; mk "$(marker)" "$S1"; run
expect "stale: a tag named like the base pointing at A does not decide, the branch does" "stale 1"

nc; put f1 changed; bump; BODY="$(printf '%s\r\n\n### Goal\n\nx\n\n### Files touched\n\n- `f1`\n\n### Done when\n\nx\n' "$(marker)")"; tojson; run
expect "stale: a first line ending in one CR is accepted" "stale 1"

nc; PRBASE=release/1.x; writeyml; git -C "$R" checkout -q -b release/1.x; put f1 changed; git -C "$R" add -A; git -C "$R" commit -q -m b; git -C "$R" push -q origin release/1.x
mk "$(marker "$ISSUE" release/1.x)" "$S1"; run
expect "stale: a pr_base other than main" "stale 1"

# --- bad-marker --------------------------------------------------------------------------
nc; BODY="$(printf 'no marker here\n\n### Goal\n\nx\n\n### Files touched\n\n- `f1`\n\n### Done when\n\nx\n')"; tojson; run
expect "bad-marker: a body with no marker" "bad-marker"

nc; mk "spec-task: issue=$ISSUE base=main sha=${SHA%?}" "$S1"; run
expect "bad-marker: a 39-character sha" "bad-marker"

nc; BODY="$(printf '\n%s\n\n### Goal\n\nx\n\n### Files touched\n\n- `f1`\n\n### Done when\n\nx\n' "$(marker)")"; tojson; run
expect "bad-marker: the marker not on the first line" "bad-marker"

nc; mk "$(marker 8)" "$S1"; run
expect "bad-marker: another issue" "bad-marker"

nc; mk "$(marker "$ISSUE" other)" "$S1"; run
expect "bad-marker: another base" "bad-marker"

nc; mk "$(marker) extra" "$S1"; run
expect "bad-marker: trailing text after the marker" "bad-marker"

nc; BODY=""; tojson; run
expect "bad-marker: an empty body" "bad-marker"

# --- bad-sha -----------------------------------------------------------------------------
nc; mk "$(marker "$ISSUE" main bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb)" "$S1"; run
expect "bad-sha: the sha is not in the repository" "bad-sha"

nc; git -C "$R" checkout -q -b side; put side n; git -C "$R" add -A; git -C "$R" commit -q -m side; side="$(git -C "$R" rev-parse HEAD)"; git -C "$R" checkout -q main
mk "$(marker "$ISSUE" main "$side")" "$S1"; run
expect "bad-sha: the sha is not an ancestor of the base tip" "bad-sha"

# --- bad-shape: shape mode ---------------------------------------------------------------
nc
shape '- `f1`
  - nested detail
    - deeper detail
- `f2`'
expect "shape ok: a valid draft with nested sub-bullets" "ok"
shape '- `f1`

    a four-space detail line after a blank line'
expect "shape ok: a bullet, a blank line, then a 4-space detail line" "ok"
shape 'Paths are relative to the root.

- `f1` **(new)**'
expect "shape ok: prose before the first bullet" "ok"
shape 'Prose only, no bullet.'
expect "shape bad: a section with no bullet" "bad-shape"
shape '* `f1`'
expect "shape bad: a * item at column 0" "bad-shape"
shape '+ `f1`'
expect "shape bad: a + item at column 0" "bad-shape"
shape '1. `f1`'
expect "shape bad: a 1. item at column 0" "bad-shape"
shape '- `f1`
 - `f2`'
expect "shape bad: a - item at one space of indent" "bad-shape"
shape '- `f1`
Some prose.
  - `f2`'
expect "shape bad: a two-space item directly after prose" "bad-shape"
shape '- `f1`
```
code
```'
expect "shape bad: a code fence in the section" "bad-shape"
shape '- `f1`
~~~
code
~~~'
expect "shape bad: a tilde fence in the section" "bad-shape"
shape '- `f1`
```
### Done when
```'
expect "shape bad: a fence holding a ### line" "bad-shape"
shape '- `f1`
#### Sub'
expect "shape bad: a #### heading in the section" "bad-shape"
shape '- `f1`
### Tests'
expect "shape bad: another required heading before Done when" "bad-shape"
shape "-	\`f1\`"
expect "shape bad: a tab after the dash" "bad-shape"
shape '- `f1`
> - `f2`'
expect "shape bad: a quoted bullet" "bad-shape"
shape '<ul><li>`f1`</li></ul>'
expect "shape bad: an HTML list" "bad-shape"
shape '| a | b |'
expect "shape bad: a table row" "bad-shape"
shape '- `f1`
<script>x</script>'
expect "shape bad: a <script> line" "bad-shape"
shape "- \`f1\`$(printf '\342\200\213')"
expect "shape bad: a zero-width space in the section" "bad-shape"
shape "- \`f1\`$(printf '\342\200\256')"
expect "shape bad: a bidi override in the section" "bad-shape"
shape "- \`f1\`$(printf '\357\273\277')"
expect "shape bad: a byte order mark in the section" "bad-shape"
shape "- \`f1\`$(printf '\330\234')"
expect "shape bad: an Arabic letter mark in the section" "bad-shape"
shape "-$(printf '\302\240')\`f1\`"
expect "shape bad: a no-break space after the dash" "bad-shape"
shape '- `f1`
[link]: x'
expect "shape bad: a link reference line" "bad-shape"
shape '- `a b`'
expect "shape bad: a span with a space" "bad-shape"
shape '- `a/../b`'
expect "shape bad: a span with a .. segment" "bad-shape"
shape '- `a//b`'
expect "shape bad: a span with an empty segment" "bad-shape"
shape '- `./a`'
expect "shape bad: a span with a . segment" "bad-shape"
shape '- `-x`'
expect "shape bad: a span beginning with a dash" "bad-shape"
shape '- `/etc/passwd`'
expect "shape bad: an absolute span" "bad-shape"
shape '- `f1'
expect "shape bad: a bullet with no closing backtick" "bad-shape"
shape '- ``'
expect "shape bad: an empty span" "bad-shape"

printf '# t\n\n### Goal\n\nx\n\n### Done when\n\nx\n' >"$D/draft.md"
out="$(sh "$script" shape "$D/draft.md" 2>/dev/null)"; assert_eq "shape bad: no Files touched section" "bad-shape" "$out"
printf '# t\n\n### Goal\n\nx\n\n### Files touched\n\n- `f1`\n\n### Files touched\n\n- `f2`\n\n### Done when\n\nx\n' >"$D/draft.md"
out="$(sh "$script" shape "$D/draft.md" 2>/dev/null)"; assert_eq "shape bad: two Files touched headings" "bad-shape" "$out"
printf '# t\n\n### Goal\n\nx\n\n### Files touched\n\n- `f1`\n' >"$D/draft.md"
out="$(sh "$script" shape "$D/draft.md" 2>/dev/null)"; assert_eq "shape bad: no Done when heading" "bad-shape" "$out"
printf '# t\n\n### Done when\n\nx\n\n### Files touched\n\n- `f1`\n' >"$D/draft.md"
out="$(sh "$script" shape "$D/draft.md" 2>/dev/null)"; assert_eq "shape bad: Done when before Files touched" "bad-shape" "$out"
printf '# t\n\n### Goal\n\nx\n\n### Files touched\n\n- `f1`\n\n### Done when\n\nx\n\n### Done when\n\ny\n' >"$D/draft.md"
out="$(sh "$script" shape "$D/draft.md" 2>/dev/null)"; assert_eq "shape bad: two Done when headings" "bad-shape" "$out"
printf '# t\n\n### Goal\n\nx %s hidden\n\n### Files touched\n\n- `f1`\n\n### Done when\n\nx\n' "<!--" >"$D/draft.md"
out="$(sh "$script" shape "$D/draft.md" 2>/dev/null)"; assert_eq "shape bad: an HTML comment opener outside the section" "bad-shape" "$out"
printf '# t\n\n%s\n### Goal\n\n### Files touched\n\n- `f1`\n\n### Done when\n\nx\n-->\n' "<!--" >"$D/draft.md"
out="$(sh "$script" shape "$D/draft.md" 2>/dev/null)"; assert_eq "shape bad: an HTML comment hiding headings" "bad-shape" "$out"
: >"$D/empty.md"
out="$(sh "$script" shape "$D/empty.md" 2>/dev/null)"; assert_eq "shape bad: an empty draft" "bad-shape" "$out"
mkdir -p "$D/adir"
out="$(sh "$script" shape "$D/adir" 2>/dev/null)"; assert_eq "shape unreadable: a directory" "unreadable" "$out"

# --- bad-shape: check mode, and no git argument carries the bad span ----------------------
nc; put f1 changed; bump; : >"$LOG"; mk "$(marker)" '- `zzmark/../x`'; run
expect "bad-shape: a span with a .. segment" "bad-shape"
assert_eq "bad-shape: no git call was made" "" "$(cat "$LOG")"

nc; put f1 changed; bump; : >"$LOG"; mk "$(marker)" '- `-zzmark`'; run
expect "bad-shape: a span beginning with a dash" "bad-shape"
assert_eq "bad-shape: no git argument contains the span" "" "$(grep zzmark "$LOG" || true)"

nc; mk "$(marker)" '- `zz mark`'; run
expect "bad-shape: a span failing the allowlist" "bad-shape"

nc; BODY="$(printf '%s\n\n### Goal\n\nx %s y\n\n### Files touched\n\n- `f1`\n\n### Done when\n\nx\n' "$(marker)" "<!--")"; tojson; run
expect "bad-shape: an HTML comment opener anywhere in the body" "bad-shape"

nc; BODY="$(printf '%s\n\n### Goal\n\nx\n\n### Done when\n\nx\n' "$(marker)")"; tojson; run
expect "bad-shape: no Files touched section in a comment" "bad-shape"

nc; put f1 changed; bump; BODY="$(printf '%s\n\n### Goal\n\nx\n\n### Files touched\n\n- `f2`\r- `f1`\n\n### Done when\n\nx\n' "$(marker)")"; tojson; run
expect "bad-shape: a bare CR that would hide a bullet from the check" "bad-shape"

# --- unreadable --------------------------------------------------------------------------
nc; PRBASE='"a b"'; writeyml; mk "$(marker)" "$S1"; run
expect "unreadable: a pr_base with a space" "unreadable"

nc; PRBASE='-x'; writeyml; mk "$(marker)" "$S1"; run
expect "unreadable: a pr_base beginning with a dash" "unreadable"

nc; printf 'repo: acme/app\n' >"$D/project.yml"; mk "$(marker)" "$S1"; run
expect "unreadable: no pr_base" "unreadable"

nc; mk "$(marker)" "$S1"; git -C "$R" remote set-url origin "$D/no-such-origin-$SENT.git"; run
expect "unreadable: an unreachable origin" "unreadable"

nc; printf '{ not json' >"$D/c.json"; run
expect "unreadable: invalid JSON" "unreadable"

nc; printf '{"id": 5}' >"$D/c.json"; run
expect "unreadable: no body" "unreadable"

nc; printf '{"body": null}' >"$D/c.json"; run
expect "unreadable: a null body" "unreadable"

nc; printf '{"body": 7}' >"$D/c.json"; run
expect "unreadable: a non-string body" "unreadable"

# --- exit 2, nothing on stdout -----------------------------------------------------------
nc; mk "$(marker)" "$S1"
rc=0; out="$(cd "$R" && sh "$script" check "$D/c.json" 0663 "$D/project.yml" 2>/dev/null)" || rc=$?
assert_eq "exit 2: an issue with a leading zero" "|2" "$out|$rc"
rc=0; out="$(cd "$R" && sh "$script" check "$D/c.json" abc "$D/project.yml" 2>/dev/null)" || rc=$?
assert_eq "exit 2: a non-digit issue" "|2" "$out|$rc"
rc=0; out="$(cd "$R" && sh "$script" check "$D/c.json" "$ISSUE" 2>/dev/null)" || rc=$?
assert_eq "exit 2: a wrong argument count" "|2" "$out|$rc"
rc=0; out="$(cd "$R" && sh "$script" show "$D/c.json" "$ISSUE" "$D/project.yml" 2>/dev/null)" || rc=$?
assert_eq "exit 2: an unknown mode" "|2" "$out|$rc"
rc=0; out="$(cd "$R" && sh "$script" check "$D/no-such.json" "$ISSUE" "$D/project.yml" 2>/dev/null)" || rc=$?
assert_eq "exit 2: a missing comment file" "|2" "$out|$rc"
rc=0; out="$(cd "$R" && sh "$script" check "$D/c.json" "$ISSUE" "$D/no-such.yml" 2>/dev/null)" || rc=$?
assert_eq "exit 2: a missing project file" "|2" "$out|$rc"
rc=0; out="$(sh "$script" shape "$D/no-such.md" 2>/dev/null)" || rc=$?
assert_eq "exit 2: shape with a missing file" "|2" "$out|$rc"
rc=0; out="$(cd "$(dirname "$script")" && sh spec-fresh.sh check "$D/c.json" "$ISSUE" "$D/project.yml" 2>/dev/null)" || rc=$?
assert_eq "exit 2: a slash-less \$0" "|2" "$out|$rc"

[ "$fail" -eq 0 ]
