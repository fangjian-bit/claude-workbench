#!/bin/sh
# Fixture tests for scripts/identity/wow-driver.ps1 and wow-launch-common.ps1 (issue #728).
#
# Stub docker and devcontainer record their argv in one calls.log and answer from canned files; a
# recording git wrapper logs its argv and runs the real git. A scratch Reference clone (local bare
# origin, .devcontainer/ and .ai/project.yml committed), a scratch Clone folder holding a copy of
# .devcontainer/, and a scratch WowHome with the two scripts and a MANIFEST in install-host-tools.ps1's
# format are laid out per case. The stub docker answers its Nth `ps` call of each kind (volume, label)
# from ps.<kind>.<N>, else ps.<kind>, else empty.
#
#   not installed   no MANIFEST (a checkout), a wrong hash for either file, a missing row, a bin outside
#                   -WowHome: exit 1 before any stub call; a -WowHome reached through a link passes
#   bad arguments   missing/related/linked/odd-leaf -Clone and -Reference, a .git file, a bad -Remote or
#                   -Base, a -Clone holding -WowHome, & or % in a parent: exit 2, no stub or git call
#   start of day    zero, exited or created container: up, re-list, record, docker exec -it, the exec's code
#   refusals        .devcontainer/ mismatch, label-only or Reference containers, bad up results, bad re-list
#   attach          record + running container + clean probe: no compare, no devcontainer, no git on the Clone
#   attach refuses  mismatched/missing/malformed record, another clone, dirty probe, two containers,
#                   restarting/paused, a failed docker ps, a missing tool
#   model, canary, edit after up, the declared values the docker exec literals copy
#
# Permitted toolset: POSIX sh, its standard utilities, pwsh, git, yq and jq (skipped, loudly, if any is absent).
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"

for t in pwsh git yq jq; do
  if ! command -v "$t" >/dev/null 2>&1; then
    echo "SKIP - $t not on PATH; identity-launchers fixtures not run" >&2
    exit 0
  fi
done

tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

# Native pwsh wants native paths; under MSYS that is cygpath -m, elsewhere the path as is.
wp() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }
norm() { printf '%s' "$1" | tr 'A-Z/\\' 'a-z//' | sed 's,/*$,,'; }

pwsh_abs=$(command -v pwsh)
real_git=$(command -v git)
stubdir="$tmp/stub" ; mkdir "$stubdir"
home="$tmp/home" ; mkdir -p "$home/bin"
STUB_DIR="$stubdir"; export STUB_DIR
STUB_SESSION_EXIT=7; export STUB_SESSION_EXIT
REAL_GIT=$real_git; export REAL_GIT

fail=0
ok() { echo "ok - $1"; }
bad() { echo "FAIL - $1" >&2; fail=1; }
check() { _cl=$1; shift; if "$@"; then ok "$_cl"; else bad "$_cl"; fi; }

ID1=$(printf '%064d' 0 | tr 0 a)
ID2=$(printf '%064d' 0 | tr 0 b)
ID3=$(printf '%064d' 0 | tr 0 c)

case "$(uname -s)" in MINGW*|MSYS*) msys=1 ;; *) msys= ;; esac

# --- stubs -------------------------------------------------------------------------------------
# On MSYS the stubs are .cmd shims that run the sh stubs: they take the same cmd.exe re-parse path as
# the real devcontainer.cmd, so the -Clone character set protects them too.
mkstub() { # mkstub <name> <body-file>
  if [ -n "$msys" ]; then
    cp "$2" "$stubdir/$1.sh"
    printf '@sh "%%~dp0%s.sh" %%*\r\n' "$1" >"$stubdir/$1.cmd"
  else cp "$2" "$stubdir/$1"; chmod +x "$stubdir/$1"; fi
}
# mklink_dir <link> <target>: a directory link, a junction on MSYS (no admin, and MSYS ln -s copies);
# non-zero where a real link cannot be made.
mklink_dir() {
  if [ -n "$msys" ]; then
    "$pwsh_abs" -NoProfile -NonInteractive -Command "New-Item -ItemType Junction -Path '$(wp "$1")' -Target '$(wp "$2")' | Out-Null" >/dev/null 2>&1 &&
      "$pwsh_abs" -NoProfile -NonInteractive -Command "if ((Get-Item -LiteralPath '$(wp "$1")' -Force).LinkType) { exit 0 } else { exit 1 }" >/dev/null 2>&1
  else ln -s "$2" "$1" 2>/dev/null && [ -L "$1" ]; fi
}
skip() { echo "SKIP - $1" >&2; }
cat >"$tmp/docker.body" <<'STUB'
#!/bin/sh
d=$STUB_DIR
echo "docker $*" >>"$d/calls.log"
case "$1" in
  ps)
    kind=vol
    for a in "$@"; do case "$a" in label=*) kind=label ;; esac; done
    n=$(( $(cat "$d/n.$kind" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$d/n.$kind"
    if [ -e "$d/ps.exit" ]; then exit "$(cat "$d/ps.exit")"; fi
    if [ -e "$d/ps.$kind.$n" ]; then cat "$d/ps.$kind.$n"
    elif [ -e "$d/ps.$kind" ]; then cat "$d/ps.$kind"; fi
    exit 0 ;;
  exec)
    case "$*" in
      *" -it "*)
        [ ! -e "$STUB_RECORD" ] || cp "$STUB_RECORD" "$d/record-at-exec"
        exit "${STUB_SESSION_EXIT:-0}" ;;
      *)
        [ ! -e "$d/probe.out" ] || cat "$d/probe.out"
        exit "$(cat "$d/probe.exit" 2>/dev/null || echo 0)" ;;
    esac ;;
esac
exit 0
STUB
cat >"$tmp/devcontainer.body" <<'STUB'
#!/bin/sh
d=$STUB_DIR
echo "devcontainer $*" >>"$d/calls.log"
echo "stub devcontainer: building CANARY-STDERR" >&2
[ ! -e "$d/up.hook" ] || sh "$d/up.hook"
if [ -e "$d/up.out" ]; then cat "$d/up.out"; else
  printf '{"outcome":"success","containerId":"%s","note":"CANARY-UP"}\n' "$UP_ID"; fi
exit "$(cat "$d/up.exit" 2>/dev/null || echo 0)"
STUB
cat >"$tmp/git.body" <<'STUB'
#!/bin/sh
echo "git $*" >>"$STUB_DIR/git.log"
exec "$REAL_GIT" "$@"
STUB
mkstub docker "$tmp/docker.body"
mkstub devcontainer "$tmp/devcontainer.body"
# On MSYS a .cmd git shim would lose the ^ of ^{commit} to cmd.exe, which the real git.exe never sees, so
# the launcher runs the real git and run_with projects git's own trace2 log into git.log instead.
[ -n "$msys" ] || mkstub git "$tmp/git.body"

# --- a scratch Reference clone, a Clone folder and the installed scripts -----------------------------
seed="$tmp/seed" origin="$tmp/origin.git" ref="$tmp/refs/wb-ref" clone="$tmp/clones/wb-driver"
mkdir -p "$tmp/refs" "$tmp/clones"
G="$real_git -c user.name=t -c user.email=t@t"
$real_git init -q -b main "$seed"; $real_git init -q --bare -b main "$origin"
mkdir -p "$seed/.devcontainer/sub" "$seed/.ai"
printf 'FROM scratch\n# CANARY-DEVC\n' >"$seed/.devcontainer/Dockerfile"
printf '{"remoteUser": "app"}\n' >"$seed/.devcontainer/devcontainer.json"
printf 'echo hi\n' >"$seed/.devcontainer/sub/x.sh"
printf 'models:\n  architect: opus\n  coder: sonnet\ncanary: CANARY-YML\n' >"$seed/.ai/project.yml"
$G -C "$seed" add -A; $G -C "$seed" commit -q -m one
c1=$($real_git -C "$seed" rev-parse HEAD)
printf 'FROM scratch\n# CANARY-DEVC\n# second\n' >"$seed/.devcontainer/Dockerfile"
$G -C "$seed" commit -q -am two
$real_git -C "$seed" remote add origin "$(wp "$origin")"; $real_git -C "$seed" push -q origin main
c2=$($real_git -C "$seed" rev-parse HEAD)
$real_git clone -q "$(wp "$origin")" "$ref"
set_clone() { rm -rf "$clone"; mkdir -p "$clone"; cp -R "$seed/.devcontainer" "$clone/.devcontainer"; }
set_clone

mkdir -p "$tmp/other/bin"
install_to() { # install_to <bin dir>: the two scripts and a MANIFEST in install-host-tools.ps1's format
  b=$1
  cp "$root_dir/scripts/identity/wow-driver.ps1" "$root_dir/scripts/identity/wow-launch-common.ps1" "$b/"
  {
    echo "commit $c2"; echo "installed 2026-01-01T00:00:00Z"
    for f in wow-driver.ps1 wow-launch-common.ps1; do echo "$(sha256sum <"$b/$f" | cut -d' ' -f1)  $f"; done
  } >"$b/MANIFEST"
}
install_to "$home/bin"; install_to "$tmp/other/bin"
STUB_RECORD="$home/driver/wb-driver.json"; export STUB_RECORD

# --- running the launcher ------------------------------------------------------------------------
PATH_BASE=$PATH
drv_path() { printf '%s' "$stubdir:$PATH_BASE"; }
# run_drv [args...]: the default arguments are overridden by later duplicates, so cases pass full sets with run_with.
run_with() { # run_with <script> <args...>
  s=$1; shift; rc=0
  rm -f "$tmp/git.trace"
  if [ -n "$msys" ]; then tr2=$(wp "$tmp/git.trace"); else tr2=; fi
  PATH=$(drv_path) UP_ID=$ID1 GIT_TRACE2_EVENT=$tr2 "$pwsh_abs" -NoProfile -NonInteractive -File "$(wp "$s")" "$@" >"$tmp/out" 2>"$tmp/err" || rc=$?
  # Top-level git processes only (a child's sid holds a /), as "git <argv>" like the stub's line.
  [ ! -e "$tmp/git.trace" ] || jq -r 'select(.event == "start" and (.sid | contains("/") | not)) | "git " + (.argv[1:] | join(" "))' \
    "$tmp/git.trace" | tr -d '\r' >>"$stubdir/git.log"
  [ -z "${LAUNCH_TEST_VERBOSE:-}" ] || echo "# rc=$rc: $(tail -n 1 "$tmp/err" | head -c 300)" >&2
}
run_drv() { run_with "$home/bin/wow-driver.ps1" -Clone "$(wp "$clone")" -Reference "$(wp "$ref")" -WowHome "$(wp "$home")" "$@"; }
reset() {
  rm -f "$stubdir"/calls.log "$stubdir"/git.log "$stubdir"/n.* "$stubdir"/ps.* "$stubdir"/up.* "$stubdir"/probe.* "$stubdir"/record-at-exec
  : >"$stubdir/calls.log"; : >"$stubdir/git.log"
  rm -rf "$home/driver"; set_clone
}
calls() { cat "$stubdir/calls.log" 2>/dev/null || true; }
glog() { cat "$stubdir/git.log" 2>/dev/null || true; }
none_called() { [ ! -s "$stubdir/calls.log" ] && [ ! -s "$stubdir/git.log" ]; }
no_it() { ! calls | grep -q ' -it '; }
no_dc() { ! calls | grep -q '^devcontainer '; }
err_has() { grep -q -- "$1" "$tmp/err"; }
out_has() { grep -q -- "$1" "$tmp/out"; }
write_record() { # write_record <id> <commit> <clone>
  mkdir -p "$home/driver"
  printf '{"id":"%s","commit":"%s","clone":"%s"}\n' "$1" "$2" "$3" | sed 's,\\,\\\\,g;' >"$home/driver/wb-driver.json"
}
json_clone() { printf '%s' "$(wp "$clone")" | sed 's,\\,\\\\,g'; }
rec_ok() { # the record holds exactly id, commit, clone
  f=$home/driver/wb-driver.json
  [ -f "$f" ] && jq -e --arg i "$ID1" --arg c "$c2" 'keys == ["clone","commit","id"] and .id == $i and .commit == $c' "$f" >/dev/null &&
    [ "$(norm "$(jq -r .clone "$f")")" = "$(norm "$(wp "$clone")")" ]
}
# The calls other than docker ps, in order.
non_ps() { calls | grep -v '^docker ps '; }
probe_guarded() { case "$probe_script" in *"-e '[v]scode-remote-containers-server' -e '[v]scode-server'"*) return 0 ;; esac; return 1; }
probe_script=$(sed -n 's/^  "\(\/bin\/ls -d .*\)"$/\1/p' "$root_dir/scripts/identity/wow-launch-common.ps1")
rec_ok_commit() { jq -e --arg c "$c2" '.commit == $c' "$home/driver/wb-driver.json" >/dev/null; }
exec_line="docker exec -it -u app -e GIT_TERMINAL_PROMPT=0 -w /workspace $ID1 /usr/local/bin/claude --model opus --effort medium"

running1() { reset; echo "$ID1 running" >"$stubdir/ps.vol.1"; }

# --- not installed -----------------------------------------------------------------------------
reset
run_with "$root_dir/scripts/identity/wow-driver.ps1" -Clone "$(wp "$clone")" -Reference "$(wp "$ref")" -WowHome "$(wp "$home")"
check "not installed: a checkout (no MANIFEST) exits 1" test "$rc" -eq 1
check "not installed: ...naming the installed copy" err_has 'installed copy'
check "not installed: ...before any stub call" none_called
for f in wow-driver.ps1 wow-launch-common.ps1; do
  reset; cp "$home/bin/$f" "$tmp/keep"; printf '# edit\n' >>"$home/bin/$f"
  run_drv
  check "not installed: a wrong hash for $f exits 1 before any call" sh -c "test $rc -eq 1 && ! test -s '$stubdir/calls.log' && ! test -s '$stubdir/git.log'"
  cp "$tmp/keep" "$home/bin/$f"
done
reset; cp "$home/bin/MANIFEST" "$tmp/keep"; grep -v ' wow-launch-common.ps1$' "$tmp/keep" >"$home/bin/MANIFEST"
run_drv
check "not installed: a missing MANIFEST row exits 1 before any call" sh -c "test $rc -eq 1 && ! test -s '$stubdir/calls.log'"
cp "$tmp/keep" "$home/bin/MANIFEST"
reset; run_with "$tmp/other/bin/wow-driver.ps1" -Clone "$(wp "$clone")" -Reference "$(wp "$ref")" -WowHome "$(wp "$home")"
check "not installed: a bin outside -WowHome exits 1" test "$rc" -eq 1
check "not installed: ...before any stub call" none_called
if mklink_dir "$tmp/homelink" "$home"; then
  reset; echo "$ID1 exited" >"$stubdir/ps.vol.1"; echo "$ID1 running" >"$stubdir/ps.vol.3"
  run_with "$home/bin/wow-driver.ps1" -Clone "$(wp "$clone")" -Reference "$(wp "$ref")" -WowHome "$(wp "$tmp/homelink")"
  check "not installed: a -WowHome reached through a link passes" test "$rc" -eq 7
  reset; run_with "$tmp/homelink/bin/wow-driver.ps1" -Clone "$(wp "$clone")" -Reference "$(wp "$ref")" -WowHome "$(wp "$home")"
  check "not installed: a script run through the link passes the bin check" test "$rc" -ne 1 -o -s "$stubdir/calls.log"
else skip "a directory link cannot be made here; the -WowHome link fixtures did not run"; fi

# --- bad arguments -----------------------------------------------------------------------------
bad_arg() { # bad_arg <label> <args...>: exit 2, a usage line, no stub or git call
  l=$1; shift; reset
  run_with "$home/bin/wow-driver.ps1" "$@"
  check "bad argument: $l exits 2" test "$rc" -eq 2
  check "bad argument: $l prints usage" err_has 'usage: wow-driver.ps1'
  check "bad argument: $l makes no external call" none_called
}
C=$(wp "$clone"); R=$(wp "$ref"); H=$(wp "$home")
# The -Clone path as the launcher passes it on: Get-FinalPath's form, backslashes on Windows.
if [ -n "$msys" ]; then CF=$(printf '%s' "$C" | tr / '\\'); else CF=$C; fi
bad_arg 'a missing -Clone' -Reference "$R" -WowHome "$H"
bad_arg 'a missing -Reference' -Clone "$C" -WowHome "$H"
bad_arg 'a relative -Clone' -Clone wb-driver -Reference "$R" -WowHome "$H"
bad_arg 'a -Clone equal to -Reference' -Clone "$R" -Reference "$R" -WowHome "$H"
mkdir -p "$ref/inner-clone"
bad_arg 'a -Clone inside -Reference' -Clone "$(wp "$ref/inner-clone")" -Reference "$R" -WowHome "$H"
bad_arg 'a -Clone containing -Reference' -Clone "$(wp "$tmp/refs")" -Reference "$R" -WowHome "$H"
mkdir -p "$clone/wowh"
bad_arg 'a -Clone containing -WowHome' -Clone "$C" -Reference "$R" -WowHome "$(wp "$clone/wowh")"
mkdir -p "$tmp/wh-parent/wb-inside"
bad_arg 'a -Clone inside -WowHome' -Clone "$(wp "$tmp/wh-parent/wb-inside")" -Reference "$R" -WowHome "$(wp "$tmp/wh-parent")"
bad_arg 'a missing -WowHome directory' -Clone "$C" -Reference "$R" -WowHome "$(wp "$tmp/nothere")"
mkdir -p "$tmp/clones/.hidden" "$tmp/clones/_under"
bad_arg 'a leaf starting with a dot' -Clone "$(wp "$tmp/clones/.hidden")" -Reference "$R" -WowHome "$H"
bad_arg 'a leaf starting with an underscore' -Clone "$(wp "$tmp/clones/_under")" -Reference "$R" -WowHome "$H"
if [ -d "$tmp/CLONES/wb-driver" ]; then
  bad_arg 'a leaf or parent whose casing differs on disk' -Clone "$(wp "$tmp/clones/WB-DRIVER")" -Reference "$R" -WowHome "$H"
fi
mkdir -p "$tmp/a&b/wb-amp" "$tmp/a%b/wb-pct"
bad_arg 'an & in a parent of -Clone' -Clone "$(wp "$tmp/a&b/wb-amp")" -Reference "$R" -WowHome "$H"
bad_arg 'a % in a parent of -Clone' -Clone "$(wp "$tmp/a%b/wb-pct")" -Reference "$R" -WowHome "$H"
if mklink_dir "$tmp/clones/wb-link" "$clone" && mklink_dir "$tmp/refs/wb-rlink" "$ref"; then
  bad_arg 'a link as -Clone' -Clone "$(wp "$tmp/clones/wb-link")" -Reference "$R" -WowHome "$H"
  bad_arg 'a link as -Reference' -Clone "$C" -Reference "$(wp "$tmp/refs/wb-rlink")" -WowHome "$H"
else skip "a directory link cannot be made here; the link-argument fixtures did not run"; fi
mkdir -p "$tmp/refs/wb-wt"; echo 'gitdir: /nowhere' >"$tmp/refs/wb-wt/.git"
bad_arg 'a -Reference whose .git is a file' -Clone "$C" -Reference "$(wp "$tmp/refs/wb-wt")" -WowHome "$H"
mkdir -p "$tmp/other-parent/wb-driver/.git"; bad_arg 'a -Reference sharing the clone leaf' -Clone "$C" -Reference "$(wp "$tmp/other-parent/wb-driver")" -WowHome "$H"
check "bad argument: the shared leaf is the stated reason" err_has 'share a folder name'
mkdir -p "$tmp/refs/wb-nogit"
bad_arg 'a -Reference with no .git' -Clone "$C" -Reference "$(wp "$tmp/refs/wb-nogit")" -WowHome "$H"
for v in '-x' 'a..b' '/x' 'x/' 'a//b' 'a b' 'a"b' 'a;b'; do
  bad_arg "a bad -Remote ($v)" -Clone "$C" -Reference "$R" -WowHome "$H" -Remote "$v"
  bad_arg "a bad -Base ($v)" -Clone "$C" -Reference "$R" -WowHome "$H" -Base "$v"
done

# --- start of day ------------------------------------------------------------------------------
start_ok() { # start_ok <label>: the sequence, the record, the exec, the exit code
  check "$1: exits with the session's code" test "$rc" -eq 7
  check "$1: devcontainer up, then the exec, and nothing else between" test "$(non_ps)" = "devcontainer up --skip-post-attach --remove-existing-container --workspace-folder $CF
$exec_line"
  check "$1: six ps calls, two of them after up" test "$(calls | grep -c '^docker ps ')" -eq 6
  check "$1: the last two ps calls follow up" test "$(calls | sed -n '/^devcontainer up/,$p' | grep -c '^docker ps ')" -eq 2
  check "$1: the record is exactly id, commit and clone" rec_ok
  check "$1: the record existed when the session started" test -f "$stubdir/record-at-exec"
  check "$1: no devcontainer exec" no_dc_exec
  check "$1: nothing from the clone, the listings or up reaches an argv" no_canary
}
no_dc_exec() { ! calls | grep -q '^devcontainer exec'; }
no_canary() { ! { calls; glog; } | grep -q CANARY; }
printf '%s exited /elsewhere/CANARY-LABEL\n' "$ID3" >"$stubdir/ps.label"
for st in none exited created; do
  reset
  printf '%s exited /elsewhere/CANARY-LABEL\n' "$ID3" >"$stubdir/ps.label"
  [ "$st" = none ] || { echo "$ID1 $st" >"$stubdir/ps.vol.1"; echo "$ID1 $st $(wp "$clone")" >"$stubdir/ps.label.1"; }
  echo "$ID1 running" >"$stubdir/ps.vol.3"
  run_drv
  start_ok "start of day ($st)"
  check "start of day ($st): the record line names the container and commit" out_has "started $ID1 from $c2"
done
check "start of day: git ran only in the Reference" sh -c "! grep -q 'wb-driver' '$stubdir/git.log'"

# the record is replaced, atomically, and driver/ is created when absent
reset; echo "$ID1 running" >"$stubdir/ps.vol.3"; write_record "$ID2" "$c1" "$(json_clone)"
run_drv
check "start of day: an old record is replaced" rec_ok
check "start of day: no temp file left" test "$(ls -A "$home/driver" | wc -l | tr -d ' ')" -eq 1

# .devcontainer/ mismatch: refuses naming the file, before any devcontainer call
mismatch() { # mismatch <label> <mutation command...>
  l=$1; shift; reset; "$@"
  run_drv
  check "mismatch ($l): exits 1" test "$rc" -eq 1
  check "mismatch ($l): names a .devcontainer/ file" err_has 'Dockerfile\|sub/x.sh\|extra.txt\|devcontainer'
  check "mismatch ($l): no devcontainer call" no_dc
  check "mismatch ($l): no -it exec" no_it
  check "mismatch ($l): no record" test ! -e "$home/driver/wb-driver.json"
}
mismatch 'a changed byte' sh -c "printf 'X' >>'$clone/.devcontainer/sub/x.sh'"
mismatch 'an extra file' sh -c "echo x >'$clone/.devcontainer/extra.txt'"
# A case-insensitive folder (NTFS) cannot hold both names: the cp would fail and the evil byte alone would refuse.
if [ -d "$tmp/CLONES" ]; then skip "a case-insensitive file system; the case-variant fixture did not run"
else mismatch 'a case variant of a committed file' sh -c "cp '$clone/.devcontainer/Dockerfile' '$clone/.devcontainer/dockerfile' && echo evil >>'$clone/.devcontainer/Dockerfile'"; fi
mismatch 'a near-duplicate name (soft hyphen)' sh -c "cp '$clone/.devcontainer/Dockerfile' \"$clone/.devcontainer/Docker\$(printf '\\302\\255')file\"; echo evil >>'$clone/.devcontainer/Dockerfile'"
mismatch 'a missing file' rm "$clone/.devcontainer/sub/x.sh"
mismatch 'a CRLF checkout' sh -c "sed 's/\$/\r/' '$seed/.devcontainer/sub/x.sh' >'$clone/.devcontainer/sub/x.sh'"
echo x >"$tmp/link-target"
if ln -s "$tmp/link-target" "$tmp/probe-link" 2>/dev/null && [ -L "$tmp/probe-link" ]; then
  mismatch 'a link under it' sh -c "rm '$clone/.devcontainer/sub/x.sh' && ln -s '$tmp/link-target' '$clone/.devcontainer/sub/x.sh'"
else skip "a file symlink cannot be made here; the link-under-it fixture did not run"; fi
dc_as_link() { mv "$clone/.devcontainer" "$tmp/dc-moved" && mklink_dir "$clone/.devcontainer" "$tmp/dc-moved"; }
if mklink_dir "$tmp/probe-dlink" "$tmp/refs"; then
  mismatch 'a link as the directory' dc_as_link
else skip "a directory link cannot be made here; the link-as-the-directory fixture did not run"; fi
rm -rf "$tmp/dc-moved"

# containers found only by label, or on the Reference
reset; echo "$ID1 running $(wp "$clone")" >"$stubdir/ps.label.1"
run_drv
check "label only: a running container found only by label refuses (exit 1)" test "$rc" -eq 1
check "label only: ...with no devcontainer call" no_dc
reset; echo "$ID2 running" >"$stubdir/ps.vol.2"
run_drv
check "Reference volume: a container on the Reference's volume refuses" test "$rc" -eq 1
check "Reference volume: ...before devcontainer and before the fetch" sh -c "! grep -q '^devcontainer' '$stubdir/calls.log' && ! grep -q ' fetch ' '$stubdir/git.log'"
reset; echo "$ID2 exited $(wp "$ref")" >"$stubdir/ps.label.2"
run_drv
check "Reference label: a container labelled with the Reference refuses" test "$rc" -eq 1
check "Reference label: ...before devcontainer and before the fetch" sh -c "! grep -q '^devcontainer' '$stubdir/calls.log' && ! grep -q ' fetch ' '$stubdir/git.log'"
# the same, on the attach path
reset; echo "$ID1 running" >"$stubdir/ps.vol.1"; echo "$ID2 running" >"$stubdir/ps.vol.2"; write_record "$ID1" "$c2" "$(json_clone)"
run_drv
check "Reference volume: attach refuses too, before the fetch" sh -c "test $rc -eq 1 && ! grep -q ' fetch ' '$stubdir/git.log' && ! grep -q ' -it ' '$stubdir/calls.log'"

# after up
after_up() { # after_up <label> <setup command...>: refuses, no -it exec, record unchanged or absent
  l=$1; shift; reset; echo "$ID1 running" >"$stubdir/ps.vol.3"; "$@"
  run_drv
  check "after up ($l): exits 1" test "$rc" -eq 1
  check "after up ($l): no -it exec" no_it
  if [ -e "$tmp/snap" ]; then check "after up ($l): the old record is byte-identical" cmp -s "$tmp/snap" "$home/driver/wb-driver.json"
  else check "after up ($l): no record" test ! -e "$home/driver/wb-driver.json"; fi
  rm -f "$tmp/snap"
}
keep_record() { write_record "$ID2" "$c1" "$(json_clone)"; cp "$home/driver/wb-driver.json" "$tmp/snap"; }
after_up 'no JSON result' sh -c "echo 'not json' >'$stubdir/up.out'"
after_up 'empty output' sh -c ": >'$stubdir/up.out'"
after_up 'a failed up' sh -c "echo 1 >'$stubdir/up.exit'"
after_up 'a non-success outcome' sh -c "printf '{\"outcome\":\"error\",\"containerId\":\"%s\"}\n' $ID1 >'$stubdir/up.out'"
after_up 'a short id' sh -c "printf '{\"outcome\":\"success\",\"containerId\":\"abc\"}\n' >'$stubdir/up.out'"
after_up 'no id' sh -c "printf '{\"outcome\":\"success\"}\n' >'$stubdir/up.out'"
after_up 'a re-list with another id' sh -c "echo '$ID2 running' >'$stubdir/ps.vol.3'"
after_up 'a re-list not running' sh -c "echo '$ID1 exited' >'$stubdir/ps.vol.3'"
after_up 'a re-list with nothing' sh -c ": >'$stubdir/ps.vol.3'"
# the old record is kept byte-identical when the run refuses
reset; echo bad >"$stubdir/up.out"; keep_record; run_drv
check "after up: an old record is byte-identical after a refusal" cmp -s "$tmp/snap" "$home/driver/wb-driver.json"; rm -f "$tmp/snap"
reset; echo "$ID1 running" >"$stubdir/ps.vol.3"; echo "$ID2 running $(wp "$clone")" >"$stubdir/ps.label.3"
run_drv
check "after up: a re-list with two containers (volume and label) refuses" test "$rc" -eq 1
check "after up: ...naming both ids" sh -c "grep -q $ID1 '$tmp/err' && grep -q $ID2 '$tmp/err'"
check "after up: ...with no record and no -it exec" sh -c "test ! -e '$home/driver/wb-driver.json' && ! grep -q ' -it ' '$stubdir/calls.log'"

# edit after up: a byte changed under .devcontainer/ by up changes nothing that reaches argv
reset; echo "$ID1 running" >"$stubdir/ps.vol.3"
printf '#!/bin/sh\necho CANARY-EDIT >>"%s/.devcontainer/Dockerfile"\n' "$clone" >"$stubdir/up.hook"
run_drv
check "edit after up: still only the validated exec" test "$rc" -eq 7 -a "$(non_ps | tail -1)" = "$exec_line"
check "edit after up: nothing from the file in any argv" no_canary

# --- attach ------------------------------------------------------------------------------------
reset; echo "$ID1 running" >"$stubdir/ps.vol.1"; write_record "$ID1" "$c2" "$(json_clone)"
run_drv
check "attach: exits with the session's code" test "$rc" -eq 7
check "attach: no devcontainer call" no_dc
check "attach: probe, then the exec, with the recorded id" test "$(non_ps)" = "docker exec -u root $ID1 /bin/sh -c $probe_script
$exec_line"
check "attach: the probe script has none of & | ^ % or a double quote" sh -c "! printf '%s' '$probe_script' | grep -q '[&|^%\"]'"
check "attach: the probe uses the [v] self-match guard on both patterns" probe_guarded
check "attach: prints the record's commit" out_has "attaching to $ID1, created from $c2"
check "attach: no warning for an unchanged .devcontainer/" sh -c "! grep -q 'has changed since' '$tmp/out'"
check "attach: no compare and no git argv names the Clone" sh -c "! grep -q 'wb-driver' '$stubdir/git.log' && ! grep -q 'ls-tree' '$stubdir/git.log'"
check "attach: no recreate" sh -c "! grep -q 'remove-existing' '$stubdir/calls.log'"
check "attach: the record is untouched" rec_ok_commit
running1; write_record "$ID1" "$c1" "$(json_clone)"
run_drv
check "attach: an older commit with another .devcontainer tree warns" out_has 'has changed since'
check "attach: ...and still execs" test "$rc" -eq 7
e=$(printf '%040d' 0 | tr 0 e)
running1; write_record "$ID1" "$e" "$(json_clone)"
run_drv
check "attach: a record commit the Reference lacks prints unknown" out_has 'unknown'
check "attach: ...still execs and passes the exit code through" test "$rc" -eq 7

attach_refuses() { # attach_refuses <label>: exit 1, no devcontainer, no -it
  check "attach refuses ($1): exit 1" test "$rc" -eq 1
  check "attach refuses ($1): no devcontainer call" no_dc
  check "attach refuses ($1): no -it exec" no_it
  check "attach refuses ($1): says why on stderr" test -s "$tmp/err"
}
running1; write_record "$ID2" "$c2" "$(json_clone)"; run_drv; attach_refuses 'a mismatched record'
running1; run_drv; attach_refuses 'a missing record'
running1; mkdir -p "$home/driver"; echo '{"id":"x"}' >"$home/driver/wb-driver.json"; run_drv; attach_refuses 'a missing field'
running1; mkdir -p "$home/driver"
printf '{"id":"%s","commit":"%s","clone":"%s","extra":"1"}\n' "$ID1" "$c2" "$(json_clone)" >"$home/driver/wb-driver.json"; run_drv; attach_refuses 'an extra field'
running1; mkdir -p "$home/driver"
printf '{"id":"abc","commit":"%s","clone":"%s"}\n' "$c2" "$(json_clone)" >"$home/driver/wb-driver.json"; run_drv; attach_refuses 'a short id'
running1; mkdir -p "$home/driver"
printf '{"id":"%s","commit":"%s","clone":"%s"}\n' "$(echo "$ID1" | tr a A)" "$c2" "$(json_clone)" >"$home/driver/wb-driver.json"; run_drv; attach_refuses 'an uppercase id'
running1; mkdir -p "$home/driver"
printf '{"id":"%s","commit":"%s","clone":"%s"}\n' "$ID1" "$(echo "$c2" | cut -c1-12)" "$(json_clone)" >"$home/driver/wb-driver.json"; run_drv; attach_refuses 'a short commit'
running1; mkdir -p "$home/driver"; echo 'not json' >"$home/driver/wb-driver.json"; run_drv; attach_refuses 'not JSON'
running1; mkdir -p "$home/driver"; echo '[1,2]' >"$home/driver/wb-driver.json"; run_drv; attach_refuses 'a JSON array'
running1; mkdir -p "$home/driver"
printf '{"id":1,"commit":"%s","clone":"%s"}\n' "$c2" "$(json_clone)" >"$home/driver/wb-driver.json"; run_drv; attach_refuses 'a non-string id'
running1; write_record "$ID1" "$c2" "$(wp "$tmp/clones/elsewhere" | sed 's,\\,\\\\,g')"; run_drv; attach_refuses "another clone's record"
running1; write_record "$ID1" "$c2" "$(json_clone)"; echo "dirty" >"$stubdir/probe.out"; run_drv; attach_refuses 'a probe that prints a line'
check "attach refuses: ...naming the VS Code attach" err_has 'VS Code'
running1; write_record "$ID1" "$c2" "$(json_clone)"; echo 1 >"$stubdir/probe.exit"; run_drv; attach_refuses 'a probe that exits 1'
running1; write_record "$ID1" "$c2" "$(json_clone)"; echo "$ID2 running" >>"$stubdir/ps.vol.1"; run_drv; attach_refuses 'two containers'
check "attach refuses (two containers): ...naming both ids" sh -c "grep -q $ID1 '$tmp/err' && grep -q $ID2 '$tmp/err'"
running1; write_record "$ID1" "$c2" "$(json_clone)"; echo "$ID2 exited" >>"$stubdir/ps.vol.1"; run_drv; attach_refuses 'a running and an exited container'
for st in restarting paused dead removing; do
  reset; echo "$ID1 $st" >"$stubdir/ps.vol.1"; write_record "$ID1" "$c2" "$(json_clone)"; run_drv; attach_refuses "state $st"
done
running1; write_record "$ID1" "$c2" "$(json_clone)"; echo 1 >"$stubdir/ps.exit"; run_drv; attach_refuses 'a failed docker ps with empty stdout'
reset; echo 1 >"$stubdir/ps.exit"; run_drv
check "failed ps (start of day): exit 1, never read as zero containers" test "$rc" -eq 1 -a "$(calls | grep -c '^devcontainer')" -eq 0
reset; printf 'garbage line\n' >"$stubdir/ps.vol.1"; run_drv
check "unreadable ps line: exit 1 with no devcontainer call" test "$rc" -eq 1 -a "$(calls | grep -c '^devcontainer')" -eq 0
reset; printf '%s running\n\n' "$ID1" >"$stubdir/ps.vol.1"; run_drv
check "blank ps line: exit 1 with no devcontainer call" test "$rc" -eq 1 -a "$(calls | grep -c '^devcontainer')" -eq 0

# missing tool: yq off PATH
nobin="$tmp/nobin"; mkdir "$nobin"
for t in sh cat cp env dirname uname rm mkdir sed grep tr; do p=$(command -v "$t") && ln -s "$p" "$nobin/$t"; done
# On MSYS git has no stub, so its own directory (no yq in it) stands in for the stub.
nopath="$stubdir:$nobin"; [ -z "$msys" ] || nopath="$nopath:$(dirname "$real_git")"
reset; echo "$ID1 running" >"$stubdir/ps.vol.1"; write_record "$ID1" "$c2" "$(json_clone)"
rc=0; PATH="$nopath" "$pwsh_abs" -NoProfile -NonInteractive -File "$(wp "$home/bin/wow-driver.ps1")" -Clone "$C" -Reference "$R" -WowHome "$H" >"$tmp/out" 2>"$tmp/err" || rc=$?
check "missing tool: yq off PATH exits 1" test "$rc" -eq 1
check "missing tool: ...naming yq" err_has 'yq not found'
check "missing tool: ...before any docker call" none_called

# --- model -------------------------------------------------------------------------------------
push_yml() { # push_yml <architect value>
  printf 'models:\n  architect: %s\n  coder: sonnet\ncanary: CANARY-YML\n' "$1" >"$seed/.ai/project.yml"
  $G -C "$seed" commit -q -am "model $1"; $real_git -C "$seed" push -q origin main
  c2=$($real_git -C "$seed" rev-parse HEAD)
}
push_yml gpt
reset; echo "$ID1 running" >"$stubdir/ps.vol.1"; write_record "$ID1" "$c2" "$(json_clone)"; run_drv
check "model: a value outside the four names refuses" test "$rc" -eq 1
check "model: ...with no -it exec" no_it
push_yml 'fable'
reset; echo "$ID1 running" >"$stubdir/ps.vol.1"; write_record "$ID1" "$c2" "$(json_clone)"; run_drv
check "model: a valid value reaches argv as the script's literal" test "$(non_ps | tail -1)" = "docker exec -it -u app -e GIT_TERMINAL_PROMPT=0 -w /workspace $ID1 /usr/local/bin/claude --model fable --effort medium"
push_yml 'opus; rm -rf'
reset; echo "$ID1 running" >"$stubdir/ps.vol.1"; write_record "$ID1" "$c2" "$(json_clone)"; run_drv
check "model: an injected value refuses and reaches no argv" test "$rc" -eq 1 -a "$(calls | grep -c 'rm -rf')" -eq 0
printf 'models:\n  coder: sonnet\n' >"$seed/.ai/project.yml"; $G -C "$seed" commit -q -am nomodel; $real_git -C "$seed" push -q origin main
reset; echo "$ID1 running" >"$stubdir/ps.vol.1"; write_record "$ID1" "$c2" "$(json_clone)"; run_drv
check "model: a missing models.architect refuses" test "$rc" -eq 1

# --- the declared values the docker exec literals copy ---------------------------------------------
dc="$root_dir/.devcontainer/devcontainer.json"
check "declared: devcontainer.json still carries remoteUser app" grep -q '"remoteUser": "app"' "$dc"
check "declared: ...and remoteEnv GIT_TERMINAL_PROMPT=0" grep -q '"remoteEnv": { "GIT_TERMINAL_PROMPT": "0" }' "$dc"
check "declared: the launcher's docker exec carries the same two literals" sh -c "grep -q \"'-u', 'app'\" '$root_dir/scripts/identity/wow-driver.ps1' && grep -q \"'GIT_TERMINAL_PROMPT=0'\" '$root_dir/scripts/identity/wow-driver.ps1'"

# --- the helper defines functions only -----------------------------------------------------------
rc=0; out=$("$pwsh_abs" -NoProfile -NonInteractive -Command "
  \$ast = [System.Management.Automation.Language.Parser]::ParseFile('$(wp "$root_dir/scripts/identity/wow-launch-common.ps1")', [ref]\$null, [ref]\$null)
  \$other = \$ast.EndBlock.Statements | Where-Object { \$_ -isnot [System.Management.Automation.Language.FunctionDefinitionAst] }
  if (\$ast.BeginBlock -or \$ast.ProcessBlock -or \$other) { 'top-level statement' } else { 'functions only' }" 2>&1) || rc=$?
check "helper: wow-launch-common.ps1 has functions only" test "$out" = 'functions only'
if mklink_dir "$tmp/clones-link" "$tmp/clones"; then
  out=$("$pwsh_abs" -NoProfile -NonInteractive -Command ". '$(wp "$root_dir/scripts/identity/wow-launch-common.ps1")'; Get-FinalPath '$(wp "$tmp/clones-link/wb-driver")'" 2>&1) || true
  check "helper: Get-FinalPath follows a link in a parent" test "$(norm "$out")" = "$(norm "$(wp "$clone")")"
else skip "a directory link cannot be made here; the Get-FinalPath link fixture did not run"; fi

[ "$fail" -eq 0 ] || { echo "identity-launchers: FAILED" >&2; exit 1; }
echo "identity-launchers: all passed"
