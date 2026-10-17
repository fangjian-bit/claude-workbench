#!/bin/sh
# Fixture tests for scripts/loop/driver-core.sh (issue #319).
#
# Hermetic: the origin is a local bare repo, `docker` is a stub that answers from
# STUB_DOCKER, `gh` is a stub that records any call and fails, and `git` is a shim that
# logs where it ran then runs the real one. Nothing here talks to a Docker daemon or GitHub.
#
# Cases: happy path, deletion mirrored, rename out of / into a human-only path (and case),
# protected predicates and fixtures (edit, delete, rename out, move over, mixed-case list entry,
# any .gitattributes and its NTFS aliases, a broken or empty list),
# nested .git, escaping and interior-.. symlinks (skipped where symlinks cannot be made),
# planted token prefix in content, path and message, liveness, fixture rule, message grammar
# with closing keywords and trailers, empty diff, special file, and that no git ever ran in
# the session tree and gh never ran at all.
#
# Permitted toolset: POSIX sh, its standard utilities, bash (the script is bash), git, tar, jq.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/scripts/loop/driver-core.sh"

for tool in git jq tar bash; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "SKIP - $tool not on PATH; driver-core fixtures not run" >&2
    exit 0
  fi
done

tmp="$(mktemp -d)"
trap 'chmod -R u+rwx "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT
real_git="$(command -v git)"
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

assert_has() { # desc, haystack, needle
  case "$2" in
    *"$3"*) echo "ok - $1" ;;
    *) echo "FAIL - $1: [$2] lacks [$3]" >&2; fail=1 ;;
  esac
}

# --- stubs ---------------------------------------------------------------------------------
stubs="$tmp/stubs"
mkdir -p "$stubs"
cat >"$stubs/docker" <<EOF
#!/bin/sh
echo "\$*" >>"$tmp/docker.log"
case "\${STUB_DOCKER:-none}" in
  fail)  echo "daemon down" >&2; exit 1 ;;
  alive) echo abc123def456 ;;
esac
exit 0
EOF
cat >"$stubs/gh" <<EOF
#!/bin/sh
echo "\$*" >>"$tmp/gh.log"
exit 1
EOF
cat >"$stubs/git" <<EOF
#!/bin/sh
echo "cwd=\$PWD args=\$*" >>"$tmp/git.log"
case " \$* " in *" interpret-trailers "*) [ "\${STUB_GIT_FAIL:-}" != trailers ] || exit 1 ;; esac
exec "$real_git" "\$@"
EOF
chmod +x "$stubs/docker" "$stubs/gh" "$stubs/git"

# Seed the origin with real git, outside the shim and the driver's pinned config.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
seed="$tmp/seed"
mkdir -p "$seed/.ai" "$seed/docs" "$seed/scripts" "$seed/tests" "$seed/plugins/way-of-working/bin"
echo readme >"$seed/README.md"
echo state >"$seed/.ai/state.md"
echo doc >"$seed/docs/a.md"
echo tool >"$seed/scripts/tool.sh"
echo t >"$seed/tests/t.test.sh"
echo p >"$seed/plugins/way-of-working/bin/plan-anchor.sh"
echo p >"$seed/plugins/way-of-working/bin/other.sh"
echo p >"$seed/tests/plan-anchor.test.sh"
echo '*.log' >"$seed/.gitignore"
echo '*.txt working-tree-encoding=UTF-16LE' >"$seed/.gitattributes"   # on the base, so unchanged by the encoding fixture
(
  cd "$seed"
  git init -q -b main
  git add -A
  git -c user.name=seed -c user.email=seed@example.invalid commit -q -m "chore: seed"
)
origin="$tmp/origin.git"
git clone -q --bare "$seed" "$origin"

# Can this machine make symlinks (Git Bash without developer mode copies instead)?
can_link=1
ln -s target "$tmp/probe-link" 2>/dev/null || can_link=0
[ -L "$tmp/probe-link" ] || can_link=0

# --- helpers -------------------------------------------------------------------------------
n=0
new_session() { # -> prints a fresh session dir holding a copy of the seed tree, no .git
  d=$(mktemp -d "$tmp/sess.XXXXXX")
  cp -R "$seed/." "$d/"
  rm -rf "$d/.git"
  printf '%s' "$d"
}

stop_json() { # message -> path of a stop-output file
  sj=$(mktemp "$tmp/stop.XXXXXX")
  jq -n --arg m "$1" '{status: "done", summary: "s", commit_message: $m}' >"$sj"
  printf '%s' "$sj"
}

hostile="$tmp/hostile.gitconfig"
mkdir -p "$tmp/hostile-hooks"
for h in pre-commit commit-msg post-commit; do
  printf '#!/bin/sh\ntouch "%s/hook-ran"\n' "$tmp" >"$tmp/hostile-hooks/$h"
  chmod +x "$tmp/hostile-hooks/$h"
done
cat >"$hostile" <<EOF
[commit]
	gpgsign = true
[gpg]
	program = false
[user]
	name = maintainer
	email = maintainer@example.invalid
[core]
	hooksPath = $tmp/hostile-hooks
EOF

prot="$root_dir/scripts/loop/protected-paths.txt"
good_msg="$(printf 'feat(loop): add the thing\n\nWhy this exists.\n')"

out= rc=0 wd=
drive() { # session stopfile [extra args...] -> sets out, rc, wd
  sess="$1"; stop="$2"; shift 2
  n=$((n + 1))
  wd="$tmp/wd$n"
  rc=0
  # The caller's global git config is hostile: signing on with a program that fails, another
  # identity, and a hooks directory whose hooks leave a marker. A loop commit must ignore it.
  out=$(PATH="$stubs:$PATH" GIT_CONFIG_GLOBAL="$hostile" bash "$script" run \
    --session-tree "$sess" --session-id sess1 --origin "$origin" --base main \
    --workdir "$wd" --branch task/x --stop-json "$stop" \
    --author-name 'glunk-loop[bot]' --author-email 'loop@example.invalid' \
    --human-only-path .ai/ --human-only-path CLAUDE.md --protected-paths-file "${prot_file:-$prot}" \
    "$@" 2>"$tmp/err") || rc=$?
}

committed_files() { "$real_git" -C "$wd" ls-tree -r --name-only HEAD; }

# --- happy path ----------------------------------------------------------------------------
s=$(new_session); echo "new doc" >"$s/docs/b.md"; echo changed >"$s/docs/a.md"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "happy: exit 0" 0 "$rc"
assert_has "happy: committed line" "$out" "committed "
assert_has "happy: branch named" "$out" " task/x"
assert_eq "happy: new file in commit" "docs/b.md" "$(committed_files | grep '^docs/b.md$')"
assert_eq "happy: author" "glunk-loop[bot] <loop@example.invalid>" \
  "$("$real_git" -C "$wd" log -1 --format='%an <%ae>')"
assert_eq "happy: committer" "glunk-loop[bot] <loop@example.invalid>" \
  "$("$real_git" -C "$wd" log -1 --format='%cn <%ce>')"
assert_eq "happy: unsigned" "N" "$("$real_git" -C "$wd" log -1 --format=%G?)"
assert_eq "happy: subject" "feat(loop): add the thing" "$("$real_git" -C "$wd" log -1 --format=%s)"
assert_eq "happy: on the task branch" "task/x" "$("$real_git" -C "$wd" branch --show-current)"
assert_eq "happy: .gitignore content survives" "*.log" "$("$real_git" -C "$wd" show HEAD:.gitignore)"
[ ! -e "$tmp/hook-ran" ] && r=absent || r=present
assert_eq "happy: the caller's hostile global config never reached the commit (no hook ran)" absent "$r"
assert_has "happy: docker asked for the session label" "$(cat "$tmp/docker.log")" "label=loop.session=sess1"

# --- deleted file is mirrored --------------------------------------------------------------
s=$(new_session); rm "$s/docs/a.md"; echo x >"$s/docs/c.md"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "deletion: exit 0" 0 "$rc"
assert_eq "deletion: removed file gone from the commit" "" "$(committed_files | grep '^docs/a.md$' || true)"

# --- empty diff ----------------------------------------------------------------------------
s=$(new_session)
drive "$s" "$(stop_json "$good_msg")"
assert_eq "empty: exit 0" 0 "$rc"
assert_eq "empty: says empty" "empty" "$out"

# --- human-only paths, both sides of a rename ----------------------------------------------
s=$(new_session); mkdir "$s/notes"; mv "$s/.ai/state.md" "$s/notes/state.md"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "rename out of a human-only path: exit 3" 3 "$rc"
assert_has "rename out of a human-only path: names the rule" "$out" "refused human-only"

s=$(new_session); mv "$s/docs/a.md" "$s/.ai/a.md"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "rename into a human-only path: exit 3" 3 "$rc"

s=$(new_session); echo "# edit" >>"$s/.ai/state.md"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "edit in a human-only path: exit 3" 3 "$rc"

s=$(new_session); echo "x" >"$s/CLAUDE.md"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "exact-file human-only entry: exit 3" 3 "$rc"

s=$(new_session)
if mkdir "$s/.AI" 2>/dev/null; then
  echo x >"$s/.AI/y"
  drive "$s" "$(stop_json "$good_msg")"
  assert_eq "human-only match is case-folded: exit 3" 3 "$rc"
else
  echo "SKIP - case-insensitive filesystem; case-fold fixture not run" >&2
fi

s=$(new_session); echo x >"$s/CLAUDE.md.bak"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "exact-file entry does not match a longer name" 0 "$rc"

# --- protected paths: the trust predicates and their fixtures (#296) -------------------------
s=$(new_session); echo "# edit" >>"$s/plugins/way-of-working/bin/plan-anchor.sh"; echo "# t" >>"$s/tests/t.test.sh"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "edit to a protected predicate: exit 3" 3 "$rc"
assert_has "edit to a protected predicate: names the rule" "$out" "refused protected"

s=$(new_session); echo "# edit" >>"$s/tests/plan-anchor.test.sh"; echo "# s" >>"$s/scripts/tool.sh"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "edit to a protected fixture: exit 3" 3 "$rc"
assert_has "edit to a protected fixture: names the rule" "$out" "refused protected"

# The fixture the issue asks for: a rename out of a protected path lists the old path as a
# deletion (rename detection off), so it is caught even though a --name-only diff with
# rename detection would show only the destination.
s=$(new_session); mkdir "$s/notes"; mv "$s/plugins/way-of-working/bin/plan-anchor.sh" "$s/notes/plan-anchor.sh"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "rename out of a protected path: exit 3" 3 "$rc"
assert_has "rename out of a protected path: names the rule" "$out" "refused protected"
assert_has "rename out of a protected path: names the old path" "$out" "bin/plan-anchor.sh"

s=$(new_session); rm "$s/tests/plan-anchor.test.sh"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "deleting a protected fixture: exit 3" 3 "$rc"
assert_has "deleting a protected fixture: names the rule" "$out" "refused protected"

s=$(new_session); mv "$s/docs/a.md" "$s/plugins/way-of-working/bin/plan-anchor.sh"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "moving a file over a protected path: exit 3" 3 "$rc"
assert_has "moving a file over a protected path: names the rule" "$out" "refused protected"

s=$(new_session)
if mkdir -p "$s/Plugins/Way-Of-Working/Bin" 2>/dev/null && [ ! -f "$s/Plugins/Way-Of-Working/Bin/plan-anchor.sh" ]; then
  echo x >"$s/Plugins/Way-Of-Working/Bin/PLAN-ANCHOR.sh"; echo "# t" >>"$s/tests/t.test.sh"   # a tests/ change, so the fixture rule cannot be what fires
  drive "$s" "$(stop_json "$good_msg")"
  assert_eq "protected match is case-folded: exit 3" 3 "$rc"
  assert_has "protected match is case-folded: names the rule" "$out" "refused protected"
else
  echo "SKIP - case-insensitive filesystem; session-side protected case-fold fixture not run" >&2
fi

# A mixed-case list entry still matches the lowercase path (runs on case-insensitive filesystems too).
echo 'Plugins/Way-Of-Working/BIN/Plan-Anchor.sh' >"$tmp/mixed-list"
s=$(new_session); echo "# edit" >>"$s/plugins/way-of-working/bin/plan-anchor.sh"
prot_file="$tmp/mixed-list"; drive "$s" "$(stop_json "$good_msg")"; prot_file=
assert_eq "a mixed-case list entry is case-folded: exit 3" 3 "$rc"
assert_has "a mixed-case list entry is case-folded: names the rule" "$out" "refused protected"

# A .gitattributes at any depth can rewrite a protected file's bytes at checkout without its
# own path appearing in the diff, so touching one is refused as `protected`.
s=$(new_session); echo 'other.sh -text' >"$s/plugins/way-of-working/bin/.gitattributes"; echo "# t" >>"$s/tests/t.test.sh"   # unlisted file, and a tests/ change: only the rule can fire
drive "$s" "$(stop_json "$good_msg")"
assert_eq "a new nested .gitattributes: exit 3" 3 "$rc"
assert_has "a new nested .gitattributes: names the rule" "$out" "can rewrite protected files"
s=$(new_session); echo 'x' >"$s/docs/.gitattributes."
drive "$s" "$(stop_json "$good_msg")"
assert_eq "a .gitattributes with a trailing dot: exit 3" 3 "$rc"
case "$out" in
  "refused copy"*) echo "SKIP - host git refuses to stage a trailing-dot name; the protected rule is not reached" >&2 ;;
  *) assert_has "a .gitattributes with a trailing dot: names the rule" "$out" "can rewrite protected files" ;;
esac
for alias in GITATT~1 GI7D29~1 gitatt~12; do
  s=$(new_session); mkdir "$s/sub"; echo '* -text' >"$s/sub/$alias"
  drive "$s" "$(stop_json "$good_msg")"
  assert_eq "NTFS alias [$alias] of .gitattributes: exit 3" 3 "$rc"
  assert_has "NTFS alias [$alias] of .gitattributes: names the rule" "$out" "refused protected"
done
s=$(new_session); echo x >"$s/docs/.gitattributes.bak"; echo x >"$s/docs/gitattributes.md"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "names that merely contain gitattributes are not refused: exit 0" 0 "$rc"
s=$(new_session); echo '*.sh text eol=crlf' >>"$s/.gitattributes"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "an edited root .gitattributes: exit 3" 3 "$rc"
assert_has "an edited root .gitattributes: names the rule" "$out" "refused protected"
s=$(new_session); rm "$s/.gitattributes"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "a deleted root .gitattributes: exit 3" 3 "$rc"
assert_has "a deleted root .gitattributes: names the rule" "$out" "can rewrite protected files"

# The rest of bin/ and tests/ stays open: only the named files are frozen.
s=$(new_session); echo "# edit" >>"$s/plugins/way-of-working/bin/other.sh"; echo "# t" >>"$s/tests/t.test.sh"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "an unlisted bin script and fixture are not frozen: exit 0" 0 "$rc"

s=$(new_session); echo x >"$s/tests/plan-anchor.test.sh.bak"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "a protected entry does not match a longer name: exit 0" 0 "$rc"

# The shipped list parses and names files that exist: a renamed predicate must not leave a
# stale entry that silently protects nothing.
n_entries=0
while IFS= read -r p; do
  case "$p" in ''|'#'*) continue ;; esac
  n_entries=$((n_entries + 1))
  [ -f "$root_dir/$p" ] && r=exists || r=missing
  assert_eq "protected-paths.txt entry exists: $p" exists "$r"
done <"$prot"
assert_eq "protected-paths.txt names the fifteen predicates, the push pin and their seventeen fixtures" 33 "$n_entries"

# A hostile or broken list is a usage fault, never an empty (or partial) protection.
printf '# only a comment\n\n' >"$tmp/empty-list"
s=$(new_session); echo x >"$s/docs/d.md"
prot_file="$tmp/empty-list"; drive "$s" "$(stop_json "$good_msg")"; prot_file=
assert_eq "an empty protected list: exit 2" 2 "$rc"
assert_has "an empty protected list: stderr is a driver-core fault" "$(cat "$tmp/err")" "driver-core.sh:"
printf 'docs/*\n' >"$tmp/glob-list"
prot_file="$tmp/glob-list"; drive "$s" "$(stop_json "$good_msg")"; prot_file=
assert_eq "a glob in the protected list: exit 2" 2 "$rc"
assert_has "a glob in the protected list: stderr is a driver-core fault" "$(cat "$tmp/err")" "driver-core.sh:"
printf '../x\n' >"$tmp/dots-list"
prot_file="$tmp/dots-list"; drive "$s" "$(stop_json "$good_msg")"; prot_file=
assert_eq "a .. in the protected list: exit 2" 2 "$rc"
assert_has "a .. in the protected list: stderr is a driver-core fault" "$(cat "$tmp/err")" "driver-core.sh:"
mkdir -p "$tmp/dir-list"
prot_file="$tmp/dir-list"; drive "$s" "$(stop_json "$good_msg")"; prot_file=
assert_eq "a directory as the protected list: exit 2 (and no hang)" 2 "$rc"
assert_has "a directory as the protected list: stderr is a driver-core fault" "$(cat "$tmp/err")" "driver-core.sh:"
prot_file="$tmp/no-such-list"; drive "$s" "$(stop_json "$good_msg")"; prot_file=
assert_eq "an unreadable protected list: exit 2" 2 "$rc"
assert_has "an unreadable protected list: stderr is a driver-core fault" "$(cat "$tmp/err")" "driver-core.sh:"
printf 'docs\r\n' >"$tmp/crlf-list"
prot_file="$tmp/crlf-list"; drive "$s" "$(stop_json "$good_msg")"; prot_file=
assert_eq "a CRLF protected list still protects: exit 3" 3 "$rc"
assert_has "a CRLF protected list still protects: names the rule" "$out" "refused protected"

# --- nested .git, and no git in the session tree -------------------------------------------
: >"$tmp/git.log"
s=$(new_session)
mkdir -p "$s/.git/hooks" "$s/sub/.git" "$s/deep/er"
printf '[core]\n\tfsmonitor = touch %s/fsmonitor-ran\n' "$tmp" >"$s/.git/config"
printf '[core]\n\tfsmonitor = touch %s/fsmonitor-ran\n' "$tmp" >"$s/sub/.git/config"
echo 'gitdir: /elsewhere' >"$s/deep/er/.git"
echo keep >"$s/sub/.gitkeep"
echo planted >"$s/.git/MARK"; echo planted >"$s/sub/.git/MARK"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "nested .git: exit 0" 0 "$rc"
[ ! -e "$wd/.git/MARK" ] && r=absent || r=present
assert_eq "nested .git: the top-level .git was not copied over the clone's" absent "$r"
[ ! -e "$wd/sub/.git" ] && r=absent || r=present
assert_eq "nested .git: sub/.git was not copied" absent "$r"
[ ! -e "$wd/deep/er/.git" ] && r=absent || r=present
assert_eq "nested .git: a gitdir file was not copied" absent "$r"
assert_has "nested .git: the clone's own config is intact" "$(cat "$wd/.git/config")" "[remote \"origin\"]"
assert_eq "nested .git: none in the commit" "" "$(committed_files | grep '\.git/\|/\.git$' || true)"
assert_eq "nested .git: .gitkeep is not excluded" "sub/.gitkeep" "$(committed_files | grep '^sub/.gitkeep$')"
[ ! -e "$tmp/fsmonitor-ran" ] && r=absent || r=present
assert_eq "nested .git: a planted fsmonitor never ran" absent "$r"
assert_eq "no git ran in the session tree" "" "$(grep -F "$s" "$tmp/git.log" || true)"
assert_eq "session .git left untouched" "[core]" "$(head -n 1 "$s/.git/config")"

# --- symlinks ------------------------------------------------------------------------------
if [ "$can_link" -eq 1 ]; then
  s=$(new_session); ln -s ../../etc/passwd "$s/docs/esc"
  drive "$s" "$(stop_json "$good_msg")"
  assert_eq "escaping symlink: exit 3" 3 "$rc"
  assert_has "escaping symlink: names the rule" "$out" "refused tree-scan"

  s=$(new_session); ln -s /etc/passwd "$s/abs"
  drive "$s" "$(stop_json "$good_msg")"
  assert_eq "absolute symlink: exit 3" 3 "$rc"

  s=$(new_session); mkdir -p "$s/a/b"; ln -s a/../../x "$s/mid"
  drive "$s" "$(stop_json "$good_msg")"
  assert_eq ".. after a plain component: exit 3" 3 "$rc"

  s=$(new_session); mkdir -p "$s/a/b"; ln -s ../docs/a.md "$s/a/b/ok"
  drive "$s" "$(stop_json "$good_msg")"
  assert_eq "symlink staying inside: exit 0" 0 "$rc"
  assert_eq "symlink staying inside: stored as a link, not dereferenced" "120000" \
    "$("$real_git" -C "$wd" ls-tree HEAD a/b/ok | cut -d' ' -f1)"

  s=$(new_session); ln -s ../../../x "$s/a-too-deep"
  drive "$s" "$(stop_json "$good_msg")"
  assert_eq "symlink with more .. than depth: exit 3" 3 "$rc"
else
  echo "SKIP - cannot create symlinks here; symlink fixtures not run" >&2
fi

# --- special file --------------------------------------------------------------------------
s=$(new_session)
if mkfifo "$s/pipe" 2>/dev/null && [ -p "$s/pipe" ]; then
  drive "$s" "$(stop_json "$good_msg")"
  assert_eq "fifo in the tree: exit 3" 3 "$rc"
  assert_has "fifo in the tree: names the rule" "$out" "refused tree-scan"
else
  echo "SKIP - cannot create a fifo here" >&2
fi

# --- newline in a path ---------------------------------------------------------------------
s=$(new_session)
nl_name="$(printf 'docs/x\ny.md')"
nl_probe="$tmp/nl-probe"; mkdir -p "$nl_probe/docs"; "$real_git" init -q "$nl_probe"; echo x >"$nl_probe/$nl_name" 2>/dev/null || true
if echo x >"$s/$nl_name" 2>/dev/null && [ -f "$s/$nl_name" ] \
   && [ "$("$real_git" -C "$nl_probe" ls-files -o -z 2>/dev/null | tr -cd '\n' | wc -c)" -eq 1 ]; then
  drive "$s" "$(stop_json "$good_msg")"
  assert_eq "newline in a path: exit 3" 3 "$rc"
else
  echo "SKIP - cannot create a path with a newline here" >&2
fi

# --- token prefix --------------------------------------------------------------------------
tok='sk-ant-oat01-FAKEFAKEFAKEFAKEFAKE'
s=$(new_session); echo "key=$tok" >"$s/docs/leak.md"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "token in a file: exit 3" 3 "$rc"
assert_has "token in a file: names the rule" "$out" "refused token"
assert_eq "token in a file: the refusal does not echo the token" "" "$(printf '%s' "$out" | grep -F "$tok" || true)"

s=$(new_session)
printf '\000\001%s\002' "$tok" >"$s/docs/blob.bin"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "token in a binary file: exit 3" 3 "$rc"

s=$(new_session); echo x >"$s/docs/$tok.md"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "token in a path: exit 3" 3 "$rc"

s=$(new_session); echo x >"$s/docs/d.md"
drive "$s" "$(stop_json "$(printf 'feat(loop): add a thing\n\nThe key is %s.\n' "$tok")")"
assert_eq "token in the message: exit 3" 3 "$rc"

s=$(new_session); echo x >"$s/docs/d.md"
drive "$s" "$(stop_json "$good_msg")" --token-prefix zzz-custom-
assert_eq "a custom prefix that is absent passes" 0 "$rc"

# --- liveness ------------------------------------------------------------------------------
s=$(new_session); echo x >"$s/docs/d.md"
STUB_DOCKER=alive drive "$s" "$(stop_json "$good_msg")"
assert_eq "session container still running: exit 3" 3 "$rc"
assert_has "session container still running: names the rule" "$out" "refused liveness"
[ ! -e "$wd/.git" ] && r=none || r=cloned
assert_eq "liveness refusal happens before any clone" none "$r"

STUB_DOCKER=fail drive "$s" "$(stop_json "$good_msg")"
assert_eq "docker error reads as not dead: exit 3" 3 "$rc"
assert_has "docker error: names the rule" "$out" "refused liveness"

# --- fixture rule --------------------------------------------------------------------------
s=$(new_session); echo more >>"$s/scripts/tool.sh"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "scripts/ changed with no fixture: exit 3" 3 "$rc"
assert_has "scripts/ changed with no fixture: names the rule" "$out" "refused fixture"

s=$(new_session); echo more >>"$s/scripts/tool.sh"; echo more >>"$s/tests/t.test.sh"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "scripts/ changed with a changed fixture: exit 0" 0 "$rc"

s=$(new_session); mkdir -p "$s/plugins/p/bin"; echo x >"$s/plugins/p/bin/q.sh"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "plugins/*/bin/ added with no fixture: exit 3" 3 "$rc"

s=$(new_session); rm "$s/tests/t.test.sh"; echo more >>"$s/scripts/tool.sh"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "a deleted fixture does not count: exit 3" 3 "$rc"

# --- commit message ------------------------------------------------------------------------
msg_case() { # desc expected-rc message
  s=$(new_session); echo "$n" >"$s/docs/m.md"
  drive "$s" "$(stop_json "$3")"
  assert_eq "message: $1" "$2" "$rc"
}
msg_case "unknown type"            3 "$(printf 'style(x): tidy\n')"
msg_case "no type"                 3 "$(printf 'add the thing\n')"
msg_case "capitalised description" 3 "$(printf 'feat(x): Add the thing\n')"
msg_case "trailing period"         3 "$(printf 'feat(x): add the thing.\n')"
msg_case "subject over 72"         3 "feat(x): $(printf 'a%.0s' $(seq 1 70))"
msg_case "no blank after subject"  3 "$(printf 'feat(x): add\nbody\n')"
msg_case "closing keyword in subject" 3 "$(printf 'fix(x): fixes #12 properly\n')"
msg_case "empty message"           3 ""
msg_case "breaking mark and no scope" 0 "$(printf 'feat!: drop the thing\n')"

s=$(new_session); echo x >"$s/docs/m.md"
drive "$s" "$(stop_json "$(printf 'fix(loop): handle the edge\n\nCloses #12 and the rest.\nWhy it broke: a race.\nResolves owner/repo#7\n\nSprint: 12\nCo-Authored-By: Someone <s@example.invalid>\n')")"
assert_eq "strip: exit 0" 0 "$rc"
body="$("$real_git" -C "$wd" log -1 --format=%B)"
assert_eq "strip: closing lines and trailers gone, prose kept" \
  "$(printf 'fix(loop): handle the edge\n\nWhy it broke: a race.')" "$body"

s=$(new_session); echo x >"$s/docs/m.md"
printf '%s' '{"status":"blocked","summary":"s","commit_message":"feat(x): add"}' >"$tmp/blocked.json"
drive "$s" "$tmp/blocked.json"
assert_eq "stop status blocked: exit 3" 3 "$rc"
printf '%s' '{"status":"done","summary":"s"}' >"$tmp/nomsg.json"
drive "$s" "$tmp/nomsg.json"
assert_eq "stop output without commit_message: exit 3" 3 "$rc"


# --- scanned against what the commit adds, not the whole clone -----------------------------
base_leaky="$tmp/seed-leaky"; mkdir -p "$base_leaky"; cp -R "$seed/." "$base_leaky/"; rm -rf "$base_leaky/.git"
echo "old note: $tok" >"$base_leaky/docs/notes.md"
(cd "$base_leaky" && git init -q -b main && git add -A && git -c user.name=s -c user.email=s@example.invalid commit -q -m "chore: seed")
origin_leaky="$tmp/origin-leaky.git"; git clone -q --bare "$base_leaky" "$origin_leaky"
s=$(mktemp -d "$tmp/sess.XXXXXX"); cp -R "$base_leaky/." "$s/"; rm -rf "$s/.git"; echo new >"$s/docs/b.md"
drive "$s" "$(stop_json "$good_msg")" --origin "$origin_leaky"
assert_eq "a base that already holds the prefix does not stop an unrelated commit" 0 "$rc"

s=$(mktemp -d "$tmp/sess.XXXXXX"); cp -R "$base_leaky/." "$s/"; rm -rf "$s/.git"; echo "again $tok" >>"$s/docs/notes.md"
drive "$s" "$(stop_json "$good_msg")" --origin "$origin_leaky"
assert_eq "adding the prefix to a file that already has it: exit 3" 3 "$rc"

if [ "$can_link" -eq 1 ]; then
  s=$(new_session); ln -s "$tok" "$s/docs/leak"
  drive "$s" "$(stop_json "$good_msg")"
  assert_eq "token as a symlink target: exit 3" 3 "$rc"
  assert_has "token as a symlink target: names the rule" "$out" "refused token"

  s=$(new_session); mkdir "$s/docs/x"; ln -s "$(printf 'x\n/../../../../etc/passwd')" "$s/docs/esc" 2>/dev/null || true
  if [ -L "$s/docs/esc" ]; then
    drive "$s" "$(stop_json "$good_msg")"
    assert_eq "newline in a symlink target: exit 3" 3 "$rc"
  fi

  s=$(new_session); ln -s ../.git/hooks "$s/docs/h"
  drive "$s" "$(stop_json "$good_msg")"
  assert_eq "symlink target naming .git: exit 3" 3 "$rc"
fi

s=$(new_session)
printf 'key=%s\n' "$tok" | iconv -f UTF-8 -t UTF-16LE >"$s/docs/enc.txt" 2>/dev/null || true
if [ -s "$s/docs/enc.txt" ]; then
  drive "$s" "$(stop_json "$good_msg")"
  assert_eq "token hidden by working-tree-encoding: exit 3" 3 "$rc"
  assert_has "token hidden by working-tree-encoding: names the token rule" "$out" "refused token"
else
  echo "SKIP - no iconv; encoding fixture not run" >&2
fi

s=$(new_session); mkdir -p "$s/.ai"; echo x >"$s/.ai/$tok"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "token in a human-only path name: exit 3" 3 "$rc"
assert_eq "refusal detail does not print the token or its secret part" "" "$(printf '%s' "$out" | grep -F "FAKEFAKE" || true)"

# --- .git spellings that fold onto the clone's .git ----------------------------------------
for alias in .GIT .Git "GIT~1" ".git." ".git "; do
  s=$(new_session)
  if mkdir "$s/sub" && mkdir "$s/sub/$alias" 2>/dev/null && [ -d "$s/sub/$alias" ] && [ ! -e "$s/sub/.git" ]; then
    echo x >"$s/sub/$alias/config"
    drive "$s" "$(stop_json "$good_msg")"
    assert_eq "name that folds onto .git ($alias): exit 3" 3 "$rc"
    assert_has "name that folds onto .git ($alias): names the rule" "$out" "refused tree-scan"
  else
    echo "SKIP - cannot create a directory named [$alias] here" >&2
  fi
done

# --- gitignored files are not committed ----------------------------------------------------
s=$(new_session); echo noise >"$s/run.log"; echo x >"$s/docs/d.md"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "gitignored file: exit 0" 0 "$rc"
assert_eq "gitignored file: not in the commit" "" "$(committed_files | grep '^run.log$' || true)"

# --- human-only entries are prefixes -------------------------------------------------------
s=$(new_session); echo x >"$s/docs/d.md"
drive "$s" "$(stop_json "$good_msg")" --human-only-path docs
assert_eq "entry with no slash covers what is under it: exit 3" 3 "$rc"
s=$(new_session); echo x >"$s/docs-other.md"
drive "$s" "$(stop_json "$good_msg")" --human-only-path docs
assert_eq "entry with no slash does not cover a longer sibling name" 0 "$rc"

# --- fixture rule: case, and deletions -----------------------------------------------------
s=$(new_session); mkdir -p "$s/Scripts-x"; mkdir -p "$s/plugins/p/BIN"; echo x >"$s/plugins/p/BIN/q.sh"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "fixture rule folds case: exit 3" 3 "$rc"

s=$(new_session); rm "$s/scripts/tool.sh" "$s/tests/t.test.sh"
drive "$s" "$(stop_json "$good_msg")"
assert_eq "deleting a script and its test together: exit 0" 0 "$rc"

# --- trailers, as git reads them -----------------------------------------------------------
trailer_case() { # desc message expected-body
  s=$(new_session); echo "$1" >"$s/docs/m.md"
  drive "$s" "$(stop_json "$2")"
  assert_eq "trailers: $1 exit" 0 "$rc"
  assert_eq "trailers: $1" "$3" "$("$real_git" -C "$wd" log -1 --format=%B | sed '$d')"
}
trailer_case "no space after the colon" "$(printf 'feat(x): add\n\nWhy.\n\nCo-authored-by:Evil <e@example.invalid>\n')" "$(printf 'feat(x): add\n\nWhy.')"
trailer_case "continuation line" "$(printf 'feat(x): add\n\nWhy.\n\nCo-authored-by: Evil <e@example.invalid>\n  more\n')" "$(printf 'feat(x): add\n\nWhy.')"
trailer_case "prose line that only looks like a trailer" "$(printf 'feat(x): add\n\nWhy it exists.\nNote: keep this line.\n')" "$(printf 'feat(x): add\n\nWhy it exists.\nNote: keep this line.')"

# --- round 2: divider, entry typos, one-line output, quoted paths --------------------------
trailer_case "after a --- divider" "$(printf 'feat(x): add\n\nWhy.\n\n---\n\nCo-authored-by: Evil <e@example.invalid>\n')" "$(printf 'feat(x): add\n\nWhy.\n\n---')"

s=$(new_session); echo "# edit" >>"$s/docs/a.md"
drive "$s" "$(stop_json "$good_msg")" --human-only-path ./docs//
assert_eq "entry written ./docs// still protects docs: exit 3" 3 "$rc"

for bad in /abs ../up a//b ./ . .ai/. a/./b " .ai" ".ai " 'docs\' "docs/*" "do?s" "d[o]cs"; do
  s=$(new_session); echo x >"$s/docs/d.md"
  drive "$s" "$(stop_json "$good_msg")" --human-only-path "$bad"
  assert_eq "malformed human-only entry [$bad]: exit 2" 2 "$rc"
done

if [ "$can_link" -eq 1 ]; then
  s=$(new_session); hostile_link="$s/docs/$(printf 'a\ncommitted deadbeef task-x')"
  ln -s /etc/passwd "$hostile_link" 2>/dev/null || true
  if [ -L "$hostile_link" ]; then
    drive "$s" "$(stop_json "$good_msg")"
    assert_eq "a hostile link name cannot add a stdout line" 1 "$(printf '%s\n' "$out" | wc -l)"
    assert_eq "a hostile link name still refuses" 3 "$rc"
  else
    echo "SKIP - cannot create a link with a newline in its name here" >&2
  fi
fi

s=$(new_session); echo x >"$s/docs/d.md"
drive "$s" "$(stop_json "$good_msg")" --token-prefix 'ab+c('
assert_eq "a token prefix with regex characters is a usage fault: exit 2" 2 "$rc"

trailer_case "co-author line inside a prose paragraph" "$(printf 'feat(x): add\n\nWhy it exists.\nCo-authored-by: Evil <e@example.invalid>\nMore prose.\n')" "$(printf 'feat(x): add\n\nWhy it exists.\nMore prose.')"
trailer_case "non-breaking space before the attribution" "$(printf 'feat(x): add\n\nWhy.\n\n\302\240Co-authored-by: Evil <e@example.invalid>\nMore prose.\n')" "$(printf 'feat(x): add\n\nWhy.\n\nMore prose.')"

s=$(new_session); echo x >"$s/docs/d.md"
STUB_GIT_FAIL=trailers drive "$s" "$(stop_json "$good_msg")"
assert_eq "git failing in the trailer probe refuses: exit 3" 3 "$rc"
assert_has "git failing in the trailer probe: names the rule" "$out" "refused message"

s=$(new_session); mkdir -p "$s/scripts"; qname="$(printf 'scripts/ev"il.sh')"
if echo x >"$s/$qname" 2>/dev/null && [ -f "$s/$qname" ]; then
  drive "$s" "$(stop_json "$good_msg")"
  assert_eq "a quoted-by-git script path still needs a fixture: exit 3" 3 "$rc"
fi

# --- usage and environment -----------------------------------------------------------------
s=$(new_session); echo x >"$s/docs/d.md"
rc=0
PATH="$stubs:$PATH" bash "$script" run --session-tree "$s" --session-id sess1 --origin "$origin" \
  --base main --workdir "$tmp/wd-usage" --branch task/x --stop-json "$(stop_json "$good_msg")" \
  --author-name a --author-email a@example.invalid >/dev/null 2>&1 || rc=$?
assert_eq "no --human-only-path: exit 2" 2 "$rc"

rc=0
PATH="$stubs:$PATH" bash "$script" run --session-tree "$s" --session-id sess1 --origin "$origin" \
  --base main --workdir "$tmp/wd-noprot" --branch task/x --stop-json "$(stop_json "$good_msg")" \
  --author-name a --author-email a@example.invalid --human-only-path .ai/ >/dev/null 2>&1 || rc=$?
assert_eq "no --protected-paths-file: exit 2" 2 "$rc"

mkdir -p "$tmp/wd-full"; echo x >"$tmp/wd-full/f"
rc=0
PATH="$stubs:$PATH" bash "$script" run --session-tree "$s" --session-id sess1 --origin "$origin" \
  --base main --workdir "$tmp/wd-full" --branch task/x --stop-json "$(stop_json "$good_msg")" \
  --author-name a --author-email a@example.invalid --human-only-path .ai/ --protected-paths-file "$prot" >/dev/null 2>&1 || rc=$?
assert_eq "non-empty workdir: exit 2" 2 "$rc"

rc=0
PATH="$stubs:$PATH" bash "$script" run --session-tree "$s" --session-id sess1 --origin "$origin" \
  --base main --workdir "$tmp/wd-br" --branch feat/x --stop-json "$(stop_json "$good_msg")" \
  --author-name a --author-email a@example.invalid --human-only-path .ai/ --protected-paths-file "$prot" >/dev/null 2>&1 || rc=$?
assert_eq "branch outside task/*: exit 2" 2 "$rc"

# --- gh never ran --------------------------------------------------------------------------
[ ! -e "$tmp/gh.log" ] && r=never || r=ran
assert_eq "gh was never called" never "$r"

if [ "$fail" -ne 0 ]; then
  echo "driver-core tests FAILED" >&2
  exit 1
fi
echo "driver-core tests passed"
