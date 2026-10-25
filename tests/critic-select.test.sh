#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/critic-select.sh (#1109, WB-D41).
#
# Each case builds a throwaway git repo with a local bare remote as `origin`, a committed
# `.ai/project.yml`-shaped file and one change, then asserts the one line the REAL script
# prints (and its exit code). Needs `yq` (mikefarah v4) and `git`; skips loudly without them.
#
# Permitted toolset: POSIX sh, real `yq` and `git` on PATH.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/plugins/way-of-working/bin/critic-select.sh"

for tool in yq git; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "SKIP - critic-select.sh fixtures: no $tool on PATH" >&2
    exit 0
  fi
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0

assert_eq() {
  if [ "$2" = "$3" ]; then echo "ok - $1"; else echo "FAIL - $1: expected [$2], got [$3]" >&2; fail=1; fi
}

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

# yml <rule-line> -- the config the script is given
yml() {
  cat <<YML
pr_base: main
code_paths:
  - plugins/
  - scripts/
load_bearing_docs:
  - README.md
  - docs/*.txt
agents:
  enabled: [architect, security-critic, docs-consistency, coder, extra]
$1
YML
}

# fresh <name> -- a clone `$tmp/<name>/w` of a bare origin with one commit on main
fresh() {
  d="$tmp/$1"; mkdir -p "$d"
  git init -q --bare -b main "$d/o.git"
  git clone -q "$d/o.git" "$d/w" 2>/dev/null
  (
    cd "$d/w"
    git checkout -q -b main 2>/dev/null || true
    mkdir -p plugins scripts docs other
    echo a >plugins/a.sh; echo a >scripts/s.sh; echo a >docs/n.txt; echo a >other/o.txt
    echo a >README.md; echo a >tests.txt
    git add -A; git commit -q -m base; git push -q origin main 2>/dev/null
  )
  W="$d/w"
}

# run <yml-file> [name...] -- stdout, then ` rc=N`, from inside $W
run() {
  y="$1"; shift
  out=$(cd "${CWD:-$W}" && sh "$script" "$y" "$@" 2>/dev/null) && rc=0 || rc=$?
  printf '%s rc=%s' "$out" "$rc"
}

# --- null ------------------------------------------------------------------
fresh null; y="$tmp/null.yml"; yml "  diff_rule: null" >"$y"
echo x >>"$W/plugins/a.sh"
assert_eq "diff_rule null prints propose, whatever the diff" "propose rc=0" "$(run "$y")"

# --- docs -------------------------------------------------------------------
fresh docs; y="$tmp/docs.yml"; yml "  diff_rule: []" >"$y"
echo x >>"$W/other/n.md"
assert_eq "a changed .md outside every list selects docs-consistency" "critics docs-consistency rc=0" "$(run "$y")"
git -C "$W" clean -fdq; echo x >>"$W/docs/n.txt"
assert_eq "a load_bearing_docs glob match selects docs-consistency" "critics docs-consistency rc=0" "$(run "$y")"
git -C "$W" checkout -q .; echo x >>"$W/README.md"
assert_eq "an exact load_bearing_docs match selects docs-consistency" "critics docs-consistency rc=0" "$(run "$y")"

# --- code -------------------------------------------------------------------
fresh code; y="$tmp/code.yml"; yml "  diff_rule: [tests/]" >"$y"
echo x >>"$W/plugins/a.sh"
assert_eq "a code_paths change selects architect,security-critic" "critics architect,security-critic rc=0" "$(run "$y")"
git -C "$W" checkout -q .; mkdir -p "$W/tests"; echo x >"$W/tests/t.sh"
assert_eq "a diff_rule path selects architect,security-critic" "critics architect,security-critic rc=0" "$(run "$y")"
yml "  diff_rule: []" >"$tmp/empty.yml"
assert_eq "an empty diff_rule list selects on code_paths alone (tests/ selects nothing)" "none rc=0" "$(run "$tmp/empty.yml")"
echo x >>"$W/plugins/a.sh"; echo x >"$W/z.md"
assert_eq "code plus a .md prints all three" "critics architect,security-critic,docs-consistency rc=0" "$(run "$tmp/empty.yml")"

# --- what counts as changed ---------------------------------------------------
fresh untr; y="$tmp/untr.yml"; yml "  diff_rule: []" >"$y"; echo x >"$W/scripts/new.sh"
assert_eq "an untracked file counts" "critics architect,security-critic rc=0" "$(run "$y")"
fresh staged; y="$tmp/staged.yml"; yml "  diff_rule: []" >"$y"; echo x >>"$W/scripts/s.sh"; git -C "$W" add -A
assert_eq "a staged-only change counts" "critics architect,security-critic rc=0" "$(run "$y")"
fresh idx; y="$tmp/idx.yml"; yml "  diff_rule: []" >"$y"; echo x >>"$W/scripts/s.sh"; git -C "$W" add -A; git -C "$W" show HEAD:scripts/s.sh >"$W/scripts/s.sh"
assert_eq "a change in the index only (working tree reverted) counts" "critics architect,security-critic rc=0" "$(run "$y")"
fresh del; y="$tmp/del.yml"; yml "  diff_rule: []" >"$y"; rm "$W/scripts/s.sh"
assert_eq "a deleted file counts" "critics architect,security-critic rc=0" "$(run "$y")"
fresh ren1; y="$tmp/ren1.yml"; yml "  diff_rule: []" >"$y"; git -C "$W" mv scripts/s.sh other/s.txt
assert_eq "a rename's source side counts" "critics architect,security-critic rc=0" "$(run "$y")"
fresh ren2; y="$tmp/ren2.yml"; yml "  diff_rule: []" >"$y"; git -C "$W" mv other/o.txt scripts/o.txt
assert_eq "a rename's destination side counts" "critics architect,security-critic rc=0" "$(run "$y")"
fresh committed; y="$tmp/committed.yml"; yml "  diff_rule: []" >"$y"
echo x >>"$W/plugins/a.sh"; git -C "$W" commit -q -am work
assert_eq "a committed change counts" "critics architect,security-critic rc=0" "$(run "$y")"

fresh sub; y="$tmp/sub.yml"; yml "  diff_rule: []" >"$y"
git -C "$W" config diff.relative true; echo x >"$W/scripts/new.sh"; echo x >>"$W/plugins/a.sh"
CWD="$W/other"
assert_eq "from a subdirectory with diff.relative set, paths elsewhere still select" "critics architect,security-critic rc=0" "$(run "$y")"
unset CWD

# --- nothing / names ------------------------------------------------------------
fresh none; y="$tmp/none.yml"; yml "  diff_rule: []" >"$y"; echo x >>"$W/other/o.txt"
assert_eq "a path selecting nothing prints none" "none rc=0" "$(run "$y")"
assert_eq "with a name it prints that name alone" "critics extra rc=0" "$(run "$y" extra)"
echo x >>"$W/plugins/a.sh"
assert_eq "names union with the rule's set" "critics architect,security-critic,extra rc=0" "$(run "$y" extra)"
assert_eq "a name already in the set adds no duplicate" "critics architect,security-critic rc=0" "$(run "$y" architect)"
assert_eq "a name in the fixed three keeps the fixed order" "critics architect,security-critic,docs-consistency rc=0" "$(run "$y" docs-consistency architect)"
assert_eq "coder as a name is left out" "critics architect,security-critic rc=0" "$(run "$y" coder)"
yml "  diff_rule: []" | sed 's/enabled: .*/enabled: [architect]/' >"$tmp/en.yml"
assert_eq "a critic not in agents.enabled is left out" "critics architect rc=0" "$(run "$tmp/en.yml" extra)"

# --- usage ---------------------------------------------------------------------
r=$(cd "$W" && sh "$script" 2>/dev/null) && c=0 || c=$?
assert_eq "no arguments exit 2 with nothing on stdout" "[] 2" "[$r] $c"
r=$(cd "$W" && sh "$script" "$y" 'Bad;name' 2>/dev/null) && c=0 || c=$?
assert_eq "a bad name exits 2 with nothing on stdout" "[] 2" "[$r] $c"

# --- unreadable ------------------------------------------------------------------
yml "" | grep -v '^$' >"$tmp/absent.yml"
assert_eq "an absent agents.diff_rule prints unreadable" "unreadable rc=0" "$(run "$tmp/absent.yml")"
yml "  diff_rule: tests/" >"$tmp/scalar.yml"
assert_eq "a scalar agents.diff_rule prints unreadable" "unreadable rc=0" "$(run "$tmp/scalar.yml")"
yml "  diff_rule: []" | sed 's/^code_paths:/code_paths_x:/' >"$tmp/nocode.yml"
assert_eq "a missing code_paths prints unreadable" "unreadable rc=0" "$(run "$tmp/nocode.yml")"
assert_eq "a missing file prints unreadable" "unreadable rc=0" "$(run "$tmp/nope.yml")"
yml "  diff_rule: []" | sed 's/^pr_base: main/pr_base: nobranch/' >"$tmp/nobr.yml"
assert_eq "a failed fetch prints unreadable" "unreadable rc=0" "$(run "$tmp/nobr.yml")"

yml "  diff_rule: []" | sed 's#^  - plugins/#  - plugins/*#' >"$tmp/glob.yml"
assert_eq "a code_paths entry with a glob character prints unreadable" "unreadable rc=0" "$(run "$tmp/glob.yml")"
yml "  diff_rule: [./tests/]" >"$tmp/dot.yml"
assert_eq "a diff_rule entry with a leading ./ prints unreadable" "unreadable rc=0" "$(run "$tmp/dot.yml")"
r=$(cd "$W" && sh "$script" rel.yml 2>/dev/null) && c=0 || c=$?
assert_eq "a relative project.yml path exits 2 with nothing on stdout" "[] 2" "[$r] $c"

# --- only the file argument is read ------------------------------------------------
fresh tree; y="$tmp/tree.yml"; yml "  diff_rule: []" >"$y"
mkdir -p "$W/.ai"; yml "  diff_rule: null" >"$W/.ai/project.yml"; echo x >>"$W/plugins/a.sh"
assert_eq "a working-tree .ai/project.yml is ignored" "critics architect,security-critic rc=0" "$(run "$y")"

# --- a newline in a name ------------------------------------------------------------
fresh nl; y="$tmp/nl.yml"; yml "  diff_rule: []" >"$y"
nlp="plugins/odd
name.txt"
printf x >"$W/$nlp"
o=$(run "$y")
assert_eq "a code path with a newline in its name is still selected, and no path is printed" "critics architect,security-critic rc=0" "$o"

[ "$fail" = 0 ]
