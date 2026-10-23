#!/bin/sh
# Fixture tests for scripts/identity/wow-driver.ps1, wow-lane.ps1 and wow-launch-common.ps1 (issues #728, #762).
#
# Stub docker and devcontainer record their argv in one calls.log and answer from canned files; a
# recording git wrapper logs its argv and runs the real git. A scratch Reference clone (local bare
# origin, .devcontainer/ and .ai/project.yml committed), a scratch Clone folder holding a copy of
# .devcontainer/, and a scratch WowHome with the three scripts and a MANIFEST in install-host-tools.ps1's
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
#   wow-lane        not installed, bad arguments, container and record refusals, the lane probe and the
#                   spec prep and cleanup scripts run for real (the stub docker runs a non-interactive
#                   `exec -u app ... /bin/sh -c <script> sh <args>` with the real /bin/sh against a scratch
#                   lanes directory and a scratch container clone), both happy paths, base-moved and kept
#                   worktrees, and the static shape of the three scripts and both message templates
#
#
# Concurrency (#937): the sections run at once, each in a subshell with its own scratch world
# (setup_world: its own tmp, stub directory, clones, WowHome and STUB_* exports), so no case reads state
# another section wrote. Each section's output goes to files that are replayed in section order; the
# suite fails if any section reports a FAIL through `check` or exits non-zero.
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

tmp_root="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp_root"' EXIT

# Native pwsh wants native paths; under MSYS that is cygpath -m, elsewhere the path as is.
wp() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }
norm() { printf '%s' "$1" | tr 'A-Z/\\' 'a-z//' | sed 's,/*$,,'; }

pwsh_abs=$(command -v pwsh)
real_git=$(command -v git)
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
STUB_MSYS=$msys; export STUB_MSYS

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

# setup_world <name>: a private scratch world for one section, set in the calling shell.
setup_world() {
  tmp="$tmp_root/$1"; mkdir "$tmp"
  stubdir="$tmp/stub" ; mkdir "$stubdir"
  home="$tmp/home" ; mkdir -p "$home/bin"
  STUB_DIR="$stubdir"; export STUB_DIR
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
        [ -z "${STUB_LANES:-}" ] || ls "$STUB_LANES" >"$d/lanes-at-exec" 2>/dev/null
        [ ! -e "$d/it.hook" ] || sh "$d/it.hook"
        exit "${STUB_SESSION_EXIT:-0}" ;;
      "exec -u app "*)
        # wow-lane.ps1's in-container step: run the script for real, with the container's two literal
        # directories swapped for the scratch ones. MSYS mkdir -m fails (cannot change permissions) under
        # its /tmp, so there the script runs with a plain mkdir; elsewhere it runs as sent.
        shift
        while [ "$1" != /bin/sh ]; do shift; done
        shift 2; script=$1; shift 2
        [ -z "${STUB_MSYS:-}" ] || script=$(printf '%s' "$script" | sed 's/mkdir -m 700/mkdir/g')
        n=$#
        while [ "$n" -gt 0 ]; do
          a=$1; shift
          case $a in /tmp/lanes) a=$STUB_LANES ;; /workspace) a=$STUB_REPO ;; esac
          set -- "$@" "$a"; n=$((n - 1))
        done
        exec /bin/sh -c "$script" sh "$@" ;;
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
# wow-lane's container clone (cloned from the same origin) and a second one whose origin/main is c1.
crepo="$tmp/crepo" crepo2="$tmp/crepo2" origin2="$tmp/origin2.git" lanes="$tmp/lanes"
$real_git clone -q "$(wp "$origin")" "$crepo"
$real_git init -q --bare -b main "$origin2"; $real_git -C "$seed" push -q "$(wp "$origin2")" "$c1:refs/heads/main"
$real_git clone -q "$(wp "$origin2")" "$crepo2"
# On MSYS git prints native paths, so the scripts must be handed the native form of the scratch directories.
STUB_LANES=$(wp "$lanes") STUB_REPO=$(wp "$crepo"); export STUB_LANES STUB_REPO
set_clone() { rm -rf "$clone"; mkdir -p "$clone"; cp -R "$seed/.devcontainer" "$clone/.devcontainer"; }
set_clone

mkdir -p "$tmp/other/bin"
install_to() { # install_to <bin dir>: the three scripts and a MANIFEST in install-host-tools.ps1's format
  b=$1
  cp "$root_dir/scripts/identity/wow-driver.ps1" "$root_dir/scripts/identity/wow-lane.ps1" "$root_dir/scripts/identity/wow-launch-common.ps1" "$b/"
  {
    echo "commit $c2"; echo "installed 2026-01-01T00:00:00Z"
    for f in wow-driver.ps1 wow-lane.ps1 wow-launch-common.ps1; do echo "$(sha256sum <"$b/$f" | cut -d' ' -f1)  $f"; done
  } >"$b/MANIFEST"
}
install_to "$home/bin"; install_to "$tmp/other/bin"
STUB_RECORD="$home/driver/wb-driver.json"; export STUB_RECORD
  # A file symlink for the cases that need one, and the clone paths the sections pass to the launchers.
  echo x >"$tmp/link-target"; ln -s "$tmp/link-target" "$tmp/probe-link" 2>/dev/null || :
C=$(wp "$clone"); R=$(wp "$ref"); H=$(wp "$home")
# The -Clone path as the launcher passes it on: Get-FinalPath's form, backslashes on Windows.
if [ -n "$msys" ]; then CF=$(printf '%s' "$C" | tr / '\\'); else CF=$C; fi
}

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
  rm -rf "$stubdir"/calls.log "$stubdir"/git.log "$stubdir"/n.* "$stubdir"/ps.* "$stubdir"/up.* "$stubdir"/probe.* "$stubdir"/record-at-exec "$stubdir"/it.* "$stubdir"/lanes-at-exec "$stubdir"/spec-* "$stubdir"/moved-wt
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

# Helpers more than one section uses.
no_dc_exec() { ! calls | grep -q '^devcontainer exec'; }
no_canary() { ! { calls; glog; } | grep -q CANARY; }
# --- wow-lane.ps1 ------------------------------------------------------------------------------------
run_lane() { run_with "$home/bin/wow-lane.ps1" -Clone "$(wp "$clone")" -Reference "$(wp "$ref")" -WowHome "$(wp "$home")" "$@"; }
LANE_CONTAINER_STAGE=
LHASH=$ID1   # any 64 lowercase hex digits are a valid -Hash
no_app_exec() { ! calls | grep -q ' -u app '; }
no_banned() { ! calls | grep -q '[&|^%"]'; }
it_line() { calls | grep ' -it '; }
app_execs() { calls | grep ' -u app ' | grep -v ' -it '; }
# app_execs_pinned <n>: exactly n non-interactive -u app execs, each carrying GIT_NO_REPLACE_OBJECTS=1
app_execs_pinned() { [ "$(app_execs | wc -l | tr -d ' ')" -eq "$1" ] && [ "$(app_execs | grep -c -e '-e GIT_NO_REPLACE_OBJECTS=1')" -eq "$1" ]; }
no_effort() { ! it_line | grep -q -e '--effort'; }
exec_shape() { non_ps | awk '{print $2, $3, $4}' | tr '\n' ,; }
# lane_setup: one running recorded container, a fresh scratch lanes directory with lane 5 prepared (a linked
# worktree of the container clone, and a prompt file), and the container clone's worktree list pruned.
lane_setup() {
  reset; echo "$ID1 running" >"$stubdir/ps.vol.1"; write_record "$ID1" "$c2" "$(json_clone)"
  rm -rf "$lanes" "$tmp/otherwt" "$stubdir/moved-wt"; $real_git -C "$crepo" worktree prune
  mkdir "$lanes"; chmod 700 "$lanes" # not mkdir -m: MSYS fails it under its /tmp
  printf '%s exited /elsewhere/CANARY-LABEL\n' "$ID3" >"$stubdir/ps.label"
  $real_git -C "$crepo" worktree add -q --detach "$lanes/5" "$c2"
  printf 'CANARY-PROMPT: do things\n' >"$lanes/5-prompt.md"
  PH=$(sha256sum <"$lanes/5-prompt.md" | cut -d' ' -f1)
  cp "$home/driver/wb-driver.json" "$tmp/rec-snap"
}
lane_refuses() { # lane_refuses <label>: exit 1, a reason, no interactive exec
  check "wow-lane refuses ($1): exit 1" test "$rc" -eq 1
  check "wow-lane refuses ($1): says why on stderr" test -s "$tmp/err"
  check "wow-lane refuses ($1): no -it exec" no_it
  [ -z "${LANE_CONTAINER_STAGE:-}" ] || check "wow-lane refuses ($1): no in-container script ran" no_app_exec
  check "wow-lane refuses ($1): the record is not written" sh -c "[ ! -e '$home/driver/wb-driver.json' ] || cmp -s '$tmp/rec-snap' '$home/driver/wb-driver.json'"
}


# --- section: not installed ---
sec_notinst() {
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

  :
}

# --- section: bad arguments ---
sec_badargs() {
# --- bad arguments -----------------------------------------------------------------------------
bad_arg() { # bad_arg <label> <args...>: exit 2, a usage line, no stub or git call
  l=$1; shift; reset
  run_with "$home/bin/wow-driver.ps1" "$@"
  check "bad argument: $l exits 2" test "$rc" -eq 2
  check "bad argument: $l prints usage" err_has 'usage: wow-driver.ps1'
  check "bad argument: $l makes no external call" none_called
}
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

  :
}

# --- section: start of day, the record and the .devcontainer/ mismatch ---
sec_start() {
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
if [ -L "$tmp/probe-link" ]; then
  mismatch 'a link under it' sh -c "rm '$clone/.devcontainer/sub/x.sh' && ln -s '$tmp/link-target' '$clone/.devcontainer/sub/x.sh'"
else skip "a file symlink cannot be made here; the link-under-it fixture did not run"; fi
dc_as_link() { mv "$clone/.devcontainer" "$tmp/dc-moved" && mklink_dir "$clone/.devcontainer" "$tmp/dc-moved"; }
if mklink_dir "$tmp/probe-dlink" "$tmp/refs"; then
  mismatch 'a link as the directory' dc_as_link
else skip "a directory link cannot be made here; the link-as-the-directory fixture did not run"; fi
rm -rf "$tmp/dc-moved"

  :
}

# --- section: refusals by label, after up, edit after up ---
sec_startb() {
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

  :
}

# --- section: attach ---
sec_attach() {
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

  :
}

# --- section: wow-lane: not installed and bad arguments ---
sec_lanea() {
# not installed
reset; rm -f "$tmp/rec-snap"
run_with "$root_dir/scripts/identity/wow-lane.ps1" -Clone "$(wp "$clone")" -Reference "$(wp "$ref")" -WowHome "$(wp "$home")" -Issue 5 -Hash "$LHASH"
check "wow-lane not installed: a checkout (no MANIFEST) exits 1" test "$rc" -eq 1
check "wow-lane not installed: ...naming the installed copy" err_has 'installed copy'
check "wow-lane not installed: ...before any stub or git call" none_called
for f in wow-lane.ps1 wow-launch-common.ps1; do
  reset; cp "$home/bin/$f" "$tmp/keep"; printf '# edit\n' >>"$home/bin/$f"
  run_lane -Issue 5 -Hash "$LHASH"
  check "wow-lane not installed: a wrong hash for $f exits 1 before any call" sh -c "test $rc -eq 1 && ! test -s '$stubdir/calls.log' && ! test -s '$stubdir/git.log'"
  cp "$tmp/keep" "$home/bin/$f"
done
reset; cp "$home/bin/MANIFEST" "$tmp/keep"; grep -v ' wow-lane.ps1$' "$tmp/keep" >"$home/bin/MANIFEST"
run_lane -Issue 5 -Hash "$LHASH"
check "wow-lane not installed: a missing wow-lane.ps1 row exits 1 before any call" sh -c "test $rc -eq 1 && ! test -s '$stubdir/calls.log' && ! test -s '$stubdir/git.log'"
cp "$tmp/keep" "$home/bin/MANIFEST"
reset; run_with "$tmp/other/bin/wow-lane.ps1" -Clone "$(wp "$clone")" -Reference "$(wp "$ref")" -WowHome "$(wp "$home")" -Issue 5 -Hash "$LHASH"
check "wow-lane not installed: a bin outside -WowHome exits 1" test "$rc" -eq 1
check "wow-lane not installed: ...before any stub or git call" none_called
reset; run_with "$home/bin/wow-lane.ps1" -Clone "$(wp "$clone")" -Reference "$(wp "$ref")" -WowHome "$(wp "$tmp/nothere")" -Issue 5 -Hash "$LHASH"
check "wow-lane: a bad -WowHome exits 2 before the installed-copy check" test "$rc" -eq 2

# bad arguments
bad_lane() { # bad_lane <label> <args...>: exit 2, a usage line, no stub or git call
  l=$1; shift; reset
  run_with "$home/bin/wow-lane.ps1" "$@"
  check "wow-lane bad argument: $l exits 2" test "$rc" -eq 2
  check "wow-lane bad argument: $l prints usage" err_has 'usage: wow-lane.ps1'
  check "wow-lane bad argument: $l makes no external call" none_called
}
bad_lane 'no mode' -Clone "$C" -Reference "$R" -WowHome "$H"
bad_lane 'both modes' -Clone "$C" -Reference "$R" -WowHome "$H" -Issue 5 -Hash "$LHASH" -Spec 7
bad_lane '-Hash alone' -Clone "$C" -Reference "$R" -WowHome "$H" -Hash "$LHASH"
bad_lane '-Issue alone' -Clone "$C" -Reference "$R" -WowHome "$H" -Issue 5
bad_lane '-Spec with -Hash' -Clone "$C" -Reference "$R" -WowHome "$H" -Spec 7 -Hash "$LHASH"
for v in 0 07 1a 1234567890 ' 5'; do
  bad_lane "-Issue '$v'" -Clone "$C" -Reference "$R" -WowHome "$H" -Issue "$v" -Hash "$LHASH"
done
for v in abc "$(echo "$ID1" | cut -c1-63)" "$(echo "$ID1" | tr a A)" "$(echo "$ID1" | tr a g)" "${ID1}a"; do
  bad_lane "-Hash '$v'" -Clone "$C" -Reference "$R" -WowHome "$H" -Issue 5 -Hash "$v"
done
for v in '' '1,,2' ',1' '1,' '1,1' '1,2,3,4,5,6,7,8,9,10,11' '1;2' '1 2' '0' '07,8'; do
  bad_lane "-Spec '$v'" -Clone "$C" -Reference "$R" -WowHome "$H" -Spec "$v"
done
bad_lane 'a missing -Clone' -Reference "$R" -WowHome "$H" -Issue 5 -Hash "$LHASH"
bad_lane 'a -Clone equal to -Reference' -Clone "$R" -Reference "$R" -WowHome "$H" -Spec 7
bad_lane 'a bad -Remote' -Clone "$C" -Reference "$R" -WowHome "$H" -Spec 7 -Remote 'a b'
bad_lane 'a bad -Base' -Clone "$C" -Reference "$R" -WowHome "$H" -Spec 7 -Base 'a"b'

  :
}

# --- section: wow-lane: container, record and probe refusals ---
sec_laneb() {
# container and record refusals: no interactive exec, no in-container script, no record written
LANE_CONTAINER_STAGE=1
lane_setup; : >"$stubdir/ps.vol.1"; run_lane -Issue 5 -Hash "$PH"
lane_refuses 'zero containers'; check "wow-lane refuses (zero containers): ...no in-container script ran" no_app_exec
check "wow-lane refuses (zero containers): ...pointing at the driver launcher" err_has 'wow-driver.ps1'
lane_setup; echo "$ID1 exited" >"$stubdir/ps.vol.1"; run_lane -Issue 5 -Hash "$PH"
lane_refuses 'one exited container'; check "wow-lane refuses (exited): ...no in-container script ran" no_app_exec
lane_setup; echo "$ID2 running" >>"$stubdir/ps.vol.1"; run_lane -Issue 5 -Hash "$PH"
lane_refuses 'two containers'; check "wow-lane refuses (two): ...naming both ids" sh -c "grep -q $ID1 '$tmp/err' && grep -q $ID2 '$tmp/err'"
lane_setup; echo "$ID1 paused" >"$stubdir/ps.vol.1"; run_lane -Issue 5 -Hash "$PH"
lane_refuses 'a paused container'
lane_setup; echo "$ID2 running" >"$stubdir/ps.vol.2"; run_lane -Issue 5 -Hash "$PH"
lane_refuses 'a container on the Reference'; check "wow-lane refuses (Reference): ...before the fetch" sh -c "! grep -q ' fetch ' '$stubdir/git.log'"
lane_setup; rm -f "$home/driver/wb-driver.json"; run_lane -Issue 5 -Hash "$PH"
lane_refuses 'a missing record'; check "wow-lane refuses (no record): ...none written" test ! -e "$home/driver/wb-driver.json"
lane_setup; write_record "$ID2" "$c2" "$(json_clone)"; cp "$home/driver/wb-driver.json" "$tmp/rec-snap"; run_lane -Issue 5 -Hash "$PH"
lane_refuses 'a record naming another container'
lane_setup; write_record "$ID1" "$c2" "$(wp "$tmp/clones/elsewhere" | sed 's,\\,\\\\,g')"; cp "$home/driver/wb-driver.json" "$tmp/rec-snap"; run_lane -Issue 5 -Hash "$PH"
lane_refuses 'a record naming another clone'
lane_setup; echo dirty >"$stubdir/probe.out"; run_lane -Issue 5 -Hash "$PH"
lane_refuses 'a dirty relay probe'; check "wow-lane refuses (probe): ...naming the VS Code attach" err_has 'VS Code'
check "wow-lane refuses (probe): ...no in-container script ran" no_app_exec

LANE_CONTAINER_STAGE=
# the lane probe, run for real against the scratch lanes directory
probe_refuses() { # probe_refuses <label> <reason text>
  lane_refuses "$1"; check "wow-lane refuses ($1): ...naming its reason" err_has "$2"
}
lane_setup; rm -rf "$lanes"; run_lane -Issue 5 -Hash "$PH"; probe_refuses 'the lanes directory missing' 'in the container is missing, a link'
lane_setup; mv "$lanes" "$tmp/lanes.real"
if mklink_dir "$lanes" "$tmp/lanes.real"; then
  run_lane -Issue 5 -Hash "$PH"; probe_refuses 'the lanes directory a link' 'in the container is missing, a link'
else skip "a directory link cannot be made here; the lanes-directory link fixture did not run"; fi
rm -rf "$lanes" "$tmp/lanes.real"; $real_git -C "$crepo" worktree prune
lane_setup; $real_git -C "$crepo" worktree remove --force "$lanes/5"; run_lane -Issue 5 -Hash "$PH"; probe_refuses 'the worktree missing' 'is not a worktree'
lane_setup; rm "$lanes/5/.git"; run_lane -Issue 5 -Hash "$PH"; probe_refuses 'the worktree with no .git file' 'is not a worktree'
lane_setup; rm -rf "$lanes/5/.git"; mkdir "$lanes/5/.git"; run_lane -Issue 5 -Hash "$PH"; probe_refuses 'the worktree .git a directory' 'is not a worktree'
lane_setup; rm -f "$lanes/5-prompt.md"; run_lane -Issue 5 -Hash "$PH"; probe_refuses 'the prompt missing' 'is not a regular file'
if [ -L "$tmp/probe-link" ]; then
  lane_setup; mv "$lanes/5-prompt.md" "$tmp/prompt-real"; ln -s "$tmp/prompt-real" "$lanes/5-prompt.md"
  run_lane -Issue 5 -Hash "$PH"; probe_refuses 'the prompt a link' 'is not a regular file'
  lane_setup; mv "$lanes/5" "$tmp/wt-real"; ln -s "$tmp/wt-real" "$lanes/5"
  run_lane -Issue 5 -Hash "$PH"; probe_refuses 'the worktree a link' 'is not a worktree'
  rm -rf "$lanes/5" "$tmp/wt-real"; $real_git -C "$crepo" worktree prune
else skip "a file symlink cannot be made here; the prompt-link and worktree-link fixtures did not run"; fi
lane_setup; run_lane -Issue 5 -Hash "$(echo "$PH" | tr 0-9a-f 1-9a-f0)"; probe_refuses 'a hash mismatch' 'does not hash'

  :
}

# --- section: wow-lane: happy paths, kept worktrees and static shape ---
sec_lanec() {
# lane happy path
lane_setup; run_lane -Issue 5 -Hash "$PH"
lane_msg="In one Bash call, run: T=\$(mktemp -d); cp /tmp/lanes/5-prompt.md \$T/p.md; sha256sum \$T/p.md; echo \$T/p.md. Stop unless that call printed the hash $PH. If it did, read only that copy and follow it."
check "wow-lane lane: exits with the session's code" test "$rc" -eq 7
check "wow-lane lane: the interactive argv is exactly the declared one" test "$(non_ps | tail -1)" = "docker exec -it -u app -e GIT_TERMINAL_PROMPT=0 -w /tmp/lanes/5 $ID1 /usr/local/bin/claude --model sonnet $lane_msg"
check "wow-lane lane: relay probe, in-container probe, then the session, and nothing else" test "$(exec_shape)" = "exec -u root,exec -u app,exec -it -u,"
check "wow-lane lane: the one in-container exec carries GIT_NO_REPLACE_OBJECTS=1" app_execs_pinned 1
check "wow-lane lane: no --effort" no_effort
check "wow-lane lane: no devcontainer call" no_dc
check "wow-lane lane: no argv holds & | ^ % or a double quote" no_banned
check "wow-lane lane: nothing from the prompt file or the listings reaches an argv" no_canary
check "wow-lane lane: the record is byte-identical afterwards" cmp -s "$tmp/rec-snap" "$home/driver/wb-driver.json"
check "wow-lane lane: no devcontainer exec" no_dc_exec

# spec happy path: a hook looks at the lanes directory while the session runs
spec_setup() { lane_setup; rm -rf "$lanes/5" "$lanes/5-prompt.md"; $real_git -C "$crepo" worktree prune; }
spec_left() { ls "$lanes" | grep -q '^spec-'; }
not_spec_left() { ! spec_left; }
cat >"$tmp/hook.ok" <<'HOOK'
for w in "$STUB_LANES"/spec-*; do
  git -C "$w" rev-parse HEAD >"$STUB_DIR/spec-head"
  git -C "$w" symbolic-ref -q HEAD >"$STUB_DIR/spec-symref" 2>/dev/null || echo detached >"$STUB_DIR/spec-symref"
  basename "$w" >"$STUB_DIR/spec-leaf"
done
HOOK
spec_setup; cp "$tmp/hook.ok" "$stubdir/it.hook"; run_lane -Spec 12,7,30
spec_line="docker exec -it -u app -e GIT_TERMINAL_PROMPT=0 -w /tmp/lanes/spec-[a-z0-9]{6} $ID1 /usr/local/bin/claude --model opus --effort high Run /way-of-working:spec-task for each of these issues, one at a time, in this order: 12, 7, 30. Build nothing, and start no build for any of them.\$"
check "wow-lane spec: exits with the session's code" test "$rc" -eq 7
spec_it_ok() { it_line | grep -E -q -e "^$spec_line"; }
spec_seen() { # the hook saw a detached worktree at the Reference's commit, under the leaf the argv names
  l=$(cat "$stubdir/spec-leaf" 2>/dev/null) || return 1
  [ "$(cat "$stubdir/spec-head")" = "$c2" ] && [ "$(cat "$stubdir/spec-symref")" = detached ] &&
    printf '%s\n' "$l" | grep -q -x -E 'spec-[a-z0-9]{6}' && grep -q -x "$l" "$stubdir/lanes-at-exec" &&
    it_line | grep -q -e "-w /tmp/lanes/$l "
}
check "wow-lane spec: the interactive argv is the declared one, issues in the given order" spec_it_ok
check "wow-lane spec: a detached worktree at the Reference's commit existed under the leaf the argv names" spec_seen
check "wow-lane spec: both non-interactive execs carry GIT_NO_REPLACE_OBJECTS=1" app_execs_pinned 2
check "wow-lane spec: the worktree is gone afterwards" not_spec_left
check "wow-lane spec: ...and no worktree of the container clone is left but its own" test "$($real_git -C "$crepo" worktree list | wc -l | tr -d ' ')" -eq 1
check "wow-lane spec: no argv holds & | ^ % or a double quote" no_banned
check "wow-lane spec: the record is byte-identical afterwards" cmp -s "$tmp/rec-snap" "$home/driver/wb-driver.json"
spec_setup; cp "$tmp/hook.ok" "$stubdir/it.hook"; run_lane -Spec 9
one_issue() { it_line | grep -q -e 'in this order: 9\. Build nothing'; }
check "wow-lane spec: a single issue is named alone" one_issue

# spec refusals
spec_setup; STUB_REPO=$(wp "$crepo2"); run_lane -Spec 7; STUB_REPO=$(wp "$crepo")
lane_refuses 'the container clone origin/main at another commit (base-moved)'
check "wow-lane refuses (base-moved): ...naming the base" err_has 'origin/main'
check "wow-lane refuses (base-moved): ...no worktree or leaf directory left" not_spec_left
check "wow-lane refuses (base-moved): ...no registered worktree" test "$($real_git -C "$crepo2" worktree list | wc -l | tr -d ' ')" -eq 1
# kept worktrees: exit 1, the path named, and the worktree is not forced away
kept_check() { # kept_check <label>
  check "wow-lane kept ($1): exits 1 although the session exited 7" test "$rc" -eq 1
  check "wow-lane kept ($1): the kept path is named" err_has '/tmp/lanes/spec-'
  check "wow-lane kept ($1): ...with the hand removal" err_has 'worktree remove --force'
}
spec_setup
printf '%s\n' 'for w in "$STUB_LANES"/spec-*; do echo x >"$w/untracked"; done' >"$stubdir/it.hook"
run_lane -Spec 7; kept_check 'an untracked file'
untracked_kept() { ls "$lanes"/spec-*/untracked >/dev/null 2>&1; }
check "wow-lane kept (untracked): the worktree and the file are still there" untracked_kept
spec_setup; $real_git -C "$crepo" worktree add -q --detach "$tmp/otherwt" "$c2"
if [ -L "$tmp/probe-link" ]; then
  printf '%s\n' 'for w in "$STUB_LANES"/spec-*; do mv "$w" "$STUB_DIR/moved-wt"; ln -s "$STUB_OTHER" "$w"; done' >"$stubdir/it.hook"
  STUB_OTHER=$tmp/otherwt; export STUB_OTHER; run_lane -Spec 7; kept_check 'the worktree replaced by a link'
  check "wow-lane kept (link): the other worktree is still present" test -f "$tmp/otherwt/.git"
  for w in "$lanes"/spec-*; do rm -f "$w"; done
else skip "a file symlink cannot be made here; the replaced-by-a-link fixture did not run"; fi
$real_git -C "$crepo" worktree remove --force "$tmp/otherwt" || true
spec_setup
printf '%s\n' "for w in \"\$STUB_LANES\"/spec-*; do git -C \"\$w\" checkout -q --detach $c1; done" >"$stubdir/it.hook"
run_lane -Spec 7; kept_check 'HEAD moved to another commit'
check "wow-lane kept (HEAD moved): the worktree is still there" spec_left
rm -rf "$lanes"; $real_git -C "$crepo" worktree prune

# static shape of the three scripts and both message templates
lane_fn() { sed -n "/^function $1 /,/^}/p" "$root_dir/scripts/identity/wow-lane.ps1"; }
lane_line() { lane_fn "$1" | sed -n 2p; }
clean_line() { # no & | ^ % or double quote, and no single quote between the outer pair
  ! printf '%s\n' "$1" | grep -q '[&|^%"]' && ! printf '%s\n' "$1" | sed "s/^  '//; s/'\$//" | grep -q "'"
}
one_quoted() { lane_line "$1" | grep -q "^  '.*'\$"; }
starts_set_f() { lane_line "$1" | grep -q "^  'set -f; "; }
for fn in Get-LaneProbeScript Get-SpecPrepScript Get-SpecCleanupScript; do
  check "static: $fn is a function of exactly one line" test "$(lane_fn $fn | wc -l | tr -d ' ')" -eq 3
  check "static: $fn returns one single-quoted string" one_quoted $fn
  check "static: $fn holds none of & | ^ % or a double quote, nor an inner single quote" clean_line "$(lane_line $fn)"
  check "static: $fn starts with set -f" starts_set_f $fn
done
tpl_line() { grep -E "^[\$]script:$1 = '" "$root_dir/scripts/identity/wow-lane.ps1" | sed "s/^[^']*'//; s/'\$//"; }
for tpl in LaneMessage SpecMessage; do
  check "static: the $tpl template exists" test -n "$(tpl_line $tpl)"
  check "static: the $tpl template holds none of & | ^ % or a double quote" clean_line "$(tpl_line $tpl)"
done

  :
}

# --- section: model, declared values and the helper ---
sec_misc() {
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
for f in wow-driver.ps1 wow-lane.ps1; do
  check "declared: $f's docker exec carries the same two literals" sh -c "grep -q \"'-u', 'app'\" '$root_dir/scripts/identity/$f' && grep -q \"'GIT_TERMINAL_PROMPT=0'\" '$root_dir/scripts/identity/$f'"
done

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

  :
}

# --- section: ConvertFrom-MsysDrivePath ---
sec_msys() {
# --- ConvertFrom-MsysDrivePath (#789, #842): the platform flag is passed, so these run on any host -------
# A stub sh in its own directory logs its arguments and answers from sh.out and sh.code. It is written directly,
# not with mkstub: on MSYS mkstub's .cmd shim runs `sh` by name, so a shim named sh would run itself. There the
# stub is an sh.cmd running the real sh (by its Windows path, taken before PATH changes) on sh.sh.
shdir="$tmp/shstub" ; mkdir "$shdir"
noshdir="$tmp/nosh" ; mkdir "$noshdir"
# The stub uses only shell builtins: pwsh runs it with a PATH that holds no dirname or cat.
cat >"$tmp/sh.body" <<'STUB'
d=${0%/*}; d=${d%\\*}
echo "argc $#" >>"$d/sh.log"
for a in "$@"; do echo "arg $a" >>"$d/sh.log"; done
if [ -r "$d/sh.out" ]; then while IFS= read -r l || [ -n "$l" ]; do printf '%s\n' "$l"; done <"$d/sh.out"; fi
c=0; if [ -r "$d/sh.code" ]; then read -r c <"$d/sh.code"; fi
exit "$c"
STUB
if [ -n "$msys" ]; then
  real_sh_win=$(cygpath -w "$(command -v sh)")
  cp "$tmp/sh.body" "$shdir/sh.sh"
  printf '@"%s" "%%~dp0sh.sh" %%*\r\n' "$real_sh_win" >"$shdir/sh.cmd"
else
  { echo '#!/bin/sh'; cat "$tmp/sh.body"; } >"$shdir/sh"; chmod +x "$shdir/sh"
fi
sh_reset() { rm -f "$shdir/sh.log" "$shdir/sh.out" "$shdir/sh.code"; }
# msys_conv <path> <is-windows> [<path-dir>]: output in $out, exit code in $rc. The path reaches pwsh through an
# environment variable behind one leading letter (Git Bash rewrites a /-leading value on its way to a native
# program), never inside the -Command string. <path-dir> is the whole PATH pwsh runs with (default: the stub sh's).
msys_conv() {
  rc=0; out=$(MSYS_CONV_PATH="v$1" PATH="${3:-$shdir}" "$pwsh_abs" -NoProfile -NonInteractive -Command "\$script:LaunchProg = 't'; \$script:LaunchUsage = 'u'; . '$(wp "$root_dir/scripts/identity/wow-launch-common.ps1")'; ConvertFrom-MsysDrivePath '-WowHome' \$env:MSYS_CONV_PATH.Substring(1) \$$2" 2>&1) || rc=$?
  out=$(printf '%s' "$out" | tr -d '\r')
}

# With the stub sh on PATH: the conversion is whatever cygpath -w through sh printed.
sh_reset; printf 'D:\\conv\\y\n' >"$shdir/sh.out"
msys_conv '/c/x/y' true
check "msys: an sh conversion returns exactly what the stub printed" test "$rc" -eq 0 -a "$out" = 'D:\conv\y'
check "msys: the stub saw the value" grep -qxF 'arg /c/x/y' "$shdir/sh.log"
check "msys: the stub saw -c" grep -qxF 'arg -c' "$shdir/sh.log"
check "msys: the stub saw sh as \$0" grep -qxF 'arg sh' "$shdir/sh.log"
if [ -z "$msys" ]; then
  check "msys: the stub saw the cygpath script" grep -qxF 'arg cygpath -w "$1"' "$shdir/sh.log"
  check "msys: the stub saw four arguments" grep -qxF 'argc 4' "$shdir/sh.log"
fi
sh_reset; printf 'D:\\mnt\\x\n' >"$shdir/sh.out"
msys_conv '/mnt/c/x' true
check "msys: a non-default prefix returns what the stub printed" test "$rc" -eq 0 -a "$out" = 'D:\mnt\x'
sh_reset; echo 3 >"$shdir/sh.code"
msys_conv '/c/x' true
check "msys: a nonzero sh exit exits 2" test "$rc" -eq 2
case "$out" in
  *'-WowHome'*'cygpath -w conversion through sh failed (exit 3)'*'give its Windows form'*) ok "msys: a nonzero sh exit names the argument, the cause and the fix" ;;
  *) bad "msys: a nonzero sh exit names the argument, the cause and the fix" ;;
esac
sh_reset
msys_conv '/c/x' true
check "msys: empty sh output exits 2" test "$rc" -eq 2
case "$out" in
  *'-WowHome'*'printed nothing'*'give its Windows form'*) ok "msys: empty sh output names the argument, the cause and the fix" ;;
  *) bad "msys: empty sh output names the argument, the cause and the fix" ;;
esac
for refused in '//server/share/x' '/c/a&b' '/c/a>b' "/c/it's"; do
  sh_reset
  msys_conv "$refused" true
  check "msys: $refused exits 2 without running sh" test "$rc" -eq 2
  check "msys: $refused leaves no stub call" test ! -e "$shdir/sh.log"
done
msys_conv "/c/it's" true
case "$out" in
  *'one of & | ^ %'*) ok "msys: a single-quote path reaches the function and names the refused characters" ;;
  *) bad "msys: a single-quote path reaches the function and names the refused characters" ;;
esac

# With no sh on PATH: the fixed drive-prefix conversion.
for pair in '/c|C:/' '/c/|C:/' '/C/|C:/' '/c/x/y|C:/x/y'; do
  msys_conv "${pair%%|*}" true "$noshdir"
  check "msys: no sh, ${pair%%|*} converts to ${pair#*|}" test "$rc" -eq 0 -a "$out" = "${pair#*|}"
done
for badp in /cc/x /tmp/x /1/x; do
  msys_conv "$badp" true "$noshdir"
  check "msys: no sh, $badp exits 2" test "$rc" -eq 2
  case "$out" in
    *'-WowHome is in MSYS form'*'no sh was found on PATH'*'give its Windows form'*) ok "msys: no sh, $badp names the argument, the cause and the fix" ;;
    *) bad "msys: no sh, $badp names the argument, the cause and the fix" ;;
  esac
done
msys_conv '//server/share/x' true "$noshdir"
check "msys: no sh, a // value exits 2" test "$rc" -eq 2
msys_conv 'C:/x/y' true
check "msys: a drive-form path is unchanged" test "$rc" -eq 0 -a "$out" = 'C:/x/y'
msys_conv 'x/y' true
check "msys: a relative path is unchanged" test "$rc" -eq 0 -a "$out" = 'x/y'
msys_conv '/c/x' false
check "msys: flag false leaves /c/x unchanged" test "$rc" -eq 0 -a "$out" = '/c/x'
for f in wow-driver.ps1 wow-lane.ps1; do
  check "msys: $f converts -WowHome before resolving it" grep -qF "Resolve-LaunchDir '-WowHome' (ConvertFrom-MsysDrivePath '-WowHome' \$WowHome) -Plain" "$root_dir/scripts/identity/$f"
done
  :
}

# Run every section at once; replay each one's output in order.
sections="notinst badargs start startb attach lanea laneb lanec misc msys"
pids=
# An interrupt stops the section subshells and removes the scratch tree (a signal skips the EXIT trap);
# a pwsh run already in flight ends on its own, as test-all.sh's header allows.
stop_sections() { kill $pids 2>/dev/null || :; rm -rf "$tmp_root" || :; exit "$1"; }
trap 'stop_sections 129' HUP; trap 'stop_sections 130' INT; trap 'stop_sections 143' TERM
for n in $sections; do
  ( setup_world "$n"; "sec_$n"; [ "$fail" -eq 0 ] ) >"$tmp_root/$n.out" 2>"$tmp_root/$n.err" &
  eval "pid_$n=$!"; pids="$pids $!"
done
all_ok=1
for n in $sections; do
  eval "p=\$pid_$n"; src=0; wait "$p" || src=$?
  cat "$tmp_root/$n.out"; cat "$tmp_root/$n.err" >&2
  [ "$src" -eq 0 ] || { echo "FAIL - section $n exited $src" >&2; all_ok=0; }
done

[ "$all_ok" -eq 1 ] || { echo "identity-launchers: FAILED" >&2; exit 1; }
echo "identity-launchers: all passed"
