#Requires -Version 7.2
<#
.SYNOPSIS
  Start a coder lane, or a spec session, or list the spec sessions, in the claude-workbench dev container that the driver
  launcher recorded (WB-D24, WB-D33, issue #762, split from #728). Run it from pwsh 7.2+ on the host,
  from the installed copy in $WOW_HOME\bin (install-host-tools.ps1), never from a checkout. Use
  `pwsh -File`: from a pwsh prompt `-Spec 1,2` binds as `1 2` and is refused with exit 2.

.DESCRIPTION
  Three modes, exactly one per run:

    -Issue N -Hash HASH   Lane mode. Starts a coder lane in the worktree scripts/lanes/lane.sh prep N
                          made (/tmp/lanes/N in the container), on models.coder, with the lane's fixed
                          first message, which opens with the issue number. HASH is the prompt-sha256= value prep printed.
    -Spec N[,N...]        Spec mode. Makes a fresh detached worktree at the Reference's base commit
                          under /tmp/lanes (spec- and six characters of a-z0-9), starts a session there
                          on models.architect at --effort high, whose first message asks it to run
                          /way-of-working:spec-task for each issue in order and build nothing. When that
                          session exits the worktree is removed, after checking it is still the one made.
                          Beside the worktree the prep writes a record (/tmp/lanes/record- and the leaf:
                          the issue list, one space, the launch time in Unix seconds), removed with it. The
                          run refuses, before the container clone's fetch and before any worktree or record is made, when a spec session already
                          running in the container covers an issue in the list (or has no readable record).
    -SpecSweep            Sweep mode. Read-only: lists every spec worktree directory, spec record and
                          running spec-session process under /tmp/lanes, each with its issues and start
                          time. It kills, removes and edits nothing, and starts no session.
                          It refuses, listing nothing, when /tmp/lanes in the container is a link, not a
                          directory, or not owned by the container user.

  Order, lane and spec modes (-SpecSweep runs steps 1 to 5, skips steps 6 and 8, and its step 7 is the
  one non-interactive docker exec -u app of the sweep script, whose lines it prints):
    1. The MANIFEST check, inline, before the helper is dot-sourced (as wow-driver.ps1 does it).
    2. The arguments (exit 2, before any external call, except the sh run that converts an MSYS-form -WowHome).
    3. Installed from bin under the final -WowHome.
    4. git, docker and yq. No devcontainer: this launcher never runs it.
    5. Exactly one container for the clone, running; none for the Reference; the driver record names
       this clone and that container; the relay probe is clean. The record is never written here.
    6. The Reference's commit and the role's model.
    7. One non-interactive docker exec -u app of an in-container script (a lane probe, or the spec
       worktree prep, which runs its busy check right after its lanes-directory check and before the
       base fetch). Its single-word answer decides, or for the prep a busy line (busy, the leaf, a
       process id and the issues or unknown); anything else refuses.
    8. The interactive session, through Invoke-Session. In spec mode the session and the cleanup after
       it sit in a try whose finally runs the cleanup.

  The scripts for step 7 and for the spec cleanup are single-quoted one-liners returned by the four
  Get-*Script functions below. Nothing variable is spliced into one: the lanes directory and the repo
  directory (launcher literals), the issue number, hash, commit, base name, worktree leaf, spec issue list and launch seconds go in as
  positional arguments, each validated here first. None holds & | ^ % ! or a double quote, nor does any
  other docker argument (Resolve-Tool may resolve a docker.cmd, which runs through cmd.exe).

  Exit codes: 0 for -SpecSweep when it listed; 2 for a bad or missing argument (a usage line on stderr, before any external call, except the sh run
  that converts an MSYS-form -WowHome);
  1 for every refusal (a one-line reason on stderr) and for a spec worktree that was kept rather than
  removed; otherwise the session's own exit code.

  Honest limit. The spec record and the busy check are accident guards like the rest: a same-user
  process can write a record or run under the name claude. Two -Spec runs can both pass the check before
  either one's session has started. A session started before the record existed, or one whose worktree
  the post-session cleanup removed under it, has no record and reads as unknown, which refuses every
  -Spec run until it is stopped. The MANIFEST check catches running from a checkout by mistake, and is not a boundary.
  Every in-container check runs as app, the same user as every lane, so a same-user process can defeat
  them. GIT_NO_REPLACE_OBJECTS=1 keeps a refs/replace/<commit> in the shared /workspace/.git from
  swapping the pinned commit's tree, but loose-object tampering in that .git is not caught, worktree
  add runs that .git's hooks (a post-checkout hook), and ~/.local/bin leads the container's PATH, so a
  copy there can shadow git, sha256sum or mktemp for the scripts and for the lane's first call. The
  session's own git reads (git show, log, diff, and spec-fresh.sh's diff) still honor a planted replace
  ref. If the host docker exec client dies, the in-container claude can keep running, so the finally
  cleanup may run under a live session; the removal is not forced, so git refuses it on modified or
  untracked files, but a session that has changed nothing yet loses its working directory. These checks catch accidents.

.PARAMETER Clone
  As wow-driver.ps1: the clone the container opens.

.PARAMETER Reference
  As wow-driver.ps1: a different full clone that no container opens. It supplies the base commit and
  models.coder or models.architect.

.PARAMETER WowHome
  As wow-driver.ps1. Default: $env:WOW_HOME, else $HOME/.config/glunk-identity.

.PARAMETER Remote
  The remote in the Reference only (default origin). In the container the clone's remote is always the
  literal origin.

.PARAMETER Base
  Default main.

.PARAMETER Issue
  Lane mode: the task issue number, decimal digits with no leading zero, at most 9.

.PARAMETER Hash
  Lane mode: the prompt-sha256 that lane.sh prep printed, 64 lowercase hex digits.

.PARAMETER Spec
  Spec mode: one string, issue numbers split on commas; no empty part, no repeat, at most 10.

.PARAMETER SpecSweep
  Sweep mode: a switch, exclusive with -Issue, -Hash and -Spec. Lists the spec worktrees, records and
  running spec sessions under /tmp/lanes and changes nothing. Refuses, listing nothing, when /tmp/lanes
  is a link, not a directory, or not owned by the container user.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
  [string]$Clone,
  [string]$Reference,
  [string]$WowHome = $(if ($env:WOW_HOME) { $env:WOW_HOME } else { Join-Path $HOME '.config/glunk-identity' }),
  [string]$Remote = 'origin',
  [string]$Base = 'main',
  [string]$Issue,
  [string]$Hash,
  [string]$Spec,
  [switch]$SpecSweep
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The installed-copy guard: before the helper is dot-sourced, and before anything else runs.
$notInstalled = {
  [Console]::Error.WriteLine('wow-lane: run the installed copy in $WOW_HOME/bin (install-host-tools.ps1)')
  exit 1
}
try {
  $manifestPath = Join-Path $PSScriptRoot 'MANIFEST'
  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { & $notInstalled }
  $manifest = [IO.File]::ReadAllText($manifestPath).Split("`n") | ForEach-Object { $_.TrimEnd("`r") }
  if (@($manifest)[0] -cnotmatch '\Acommit [0-9a-f]{40}\z') { & $notInstalled }
  foreach ($name in 'wow-lane.ps1', 'wow-launch-common.ps1') {
    $own = Join-Path $PSScriptRoot $name
    $rows = @($manifest | Where-Object { $_ -cmatch '\A[0-9a-f]{64}  ' -and $_.Substring(66) -ceq $name })
    if ($rows.Count -ne 1 -or -not (Test-Path -LiteralPath $own -PathType Leaf)) { & $notInstalled }
    if ($rows[0].Substring(0, 64) -cne (Get-FileHash -LiteralPath $own -Algorithm SHA256).Hash.ToLowerInvariant()) { & $notInstalled }
  }
} catch { & $notInstalled }

$script:LaunchProg = 'wow-lane'
$script:LaunchUsage = 'usage: wow-lane.ps1 -Clone <path> -Reference <path> (-Issue <N> -Hash <sha256> | -Spec <N[,N...]> | -SpecSweep) [-WowHome <path>] [-Remote <name>] [-Base <name>]'
. (Join-Path $PSScriptRoot 'wow-launch-common.ps1')

# The in-container scripts. Each is one line in one single-quoted string, with no single quote, & | ^ % !
# or double quote inside; control flow is if and case (the cleanup, the prep and the sweep also have
# while loops, and the prep and sweep shell functions, and $(( )) arithmetic). Positionals only, and
# set -f first. stderr goes to /dev/null for the whole script, stdout of every command too, and only the
# final echo writes (a printf format would need a percent sign); the prep's one other write is its record
# file, and the sweep writes nothing but its echoes. Text read in the container (process names, working
# directories, directory names, record contents) is matched against its shape before it is used as a
# path or a pattern, and is never echoed unmatched.
# set -f does not stop a case pattern from matching: the unquoted values in the case words and patterns
# are safe only because the launcher validates each one (digits, lowercase hex, a plain ref name) first,
# or, for text read in the container, because the script matches its shape first (or uses it only as a case word).

# Positionals: lanes dir, issue, hash. Words: ok unsafe-dir no-worktree no-prompt hash-mismatch.
function Get-LaneProbeScript {
  'set -f; exec 2>/dev/null; L=$1; N=$2; H=$3; w=ok; if test -L $L; then w=unsafe-dir; fi; if test $w = ok; then if test -d $L; then :; else w=unsafe-dir; fi; fi; if test $w = ok; then if test -O $L; then :; else w=unsafe-dir; fi; fi; if test $w = ok; then if test -L $L/$N; then w=no-worktree; fi; fi; if test $w = ok; then if test -d $L/$N; then :; else w=no-worktree; fi; fi; if test $w = ok; then if test -L $L/$N/.git; then w=no-worktree; fi; fi; if test $w = ok; then if test -f $L/$N/.git; then :; else w=no-worktree; fi; fi; if test $w = ok; then if test -L $L/$N-prompt.md; then w=no-prompt; fi; fi; if test $w = ok; then if test -f $L/$N-prompt.md; then :; else w=no-prompt; fi; fi; if test $w = ok; then set -- $(sha256sum $L/$N-prompt.md); case $1 in $H) :;; *) w=hash-mismatch;; esac; fi; echo $w'
}

# Positionals: lanes dir, repo dir, base, commit, leaf, issue list, launch seconds. Words: ok unsafe-dir unreadable base-moved exists failed, or the line busy leaf pid issues-or-unknown.
function Get-SpecPrepScript {
  'set -f; exec 2>/dev/null; L=$1; R=$2; B=$3; C=$4; F=$5; Q=$6; S=$7; w=ok; bl=; bp=; bi=; hit=0; dg() { if test $# = 2; then :; else dok=0; return 0; fi; dv=$1; dok=1; while test ${#dv} -gt 0; do case $dv in [$2]*) dv=${dv#?};; *) dok=0; dv=;; esac; done; }; pf() { g=; q=$1; dg $q 0-9; if test $dok = 0; then return 0; fi; if test -O /proc/$q; then :; else return 0; fi; c=$(cat /proc/$q/comm); case $c in claude) :;; *) return 0;; esac; y=$(readlink /proc/$q/cwd); case $y in $L/spec-*) :;; *) return 0;; esac; set -- ${y#$L/}; if test $# -gt 2; then return 0; fi; if test $# = 2; then case $2 in \(deleted\)) :;; *) return 0;; esac; fi; case $1 in spec-[a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9]) g=$1;; esac; }; rd() { ri=unknown; rs=unknown; f=$L/record-$1; if test -L $f; then return 0; fi; if test -f $f; then :; else return 0; fi; n=0; a=; b=; while read -r k u; do n=$((n+1)); a=$k; b=$u; done <$f; if test $n = 1; then :; else return 0; fi; ok=1; if test ${#b} -lt 1; then ok=0; fi; if test ${#b} -gt 10; then ok=0; fi; dg $b 0-9; if test $dok = 0; then ok=0; fi; case $b in 0*) ok=0;; esac; if test ${#a} -lt 1; then ok=0; fi; if test ${#a} -gt 99; then ok=0; fi; dg $a 0-9,; if test $dok = 0; then ok=0; fi; case $a in ,*) ok=0;; *,) ok=0;; *,,*) ok=0;; 0*) ok=0;; *,0*) ok=0;; esac; if test $ok = 1; then IFS=,; set -- $a; unset IFS; if test $# -gt 10; then ok=0; fi; while test $# -gt 0; do if test ${#1} -gt 9; then ok=0; fi; shift; done; fi; if test $ok = 1; then ri=$a; rs=$b; fi; };  ht() { hit=0; if test $ri = unknown; then hit=1; return 0; fi; IFS=,; set -- $ri; unset IFS; while test $# -gt 0; do case ,$Q, in *,$1,*) hit=1;; esac; shift; done; }; if test -L $L; then w=unsafe-dir; elif test -e $L; then if test -d $L; then if test -O $L; then :; else w=unsafe-dir; fi; else w=unsafe-dir; fi; else if mkdir -m 700 $L >/dev/null; then :; else w=unsafe-dir; fi; fi; if test $w = ok; then set -- $(ls /proc); while test $# -gt 0; do if test $w = ok; then pf $1; if test ${#g} -gt 0; then rd $g; ht; if test $hit = 1; then w=busy; bl=$g; bp=$1; bi=$ri; fi; fi; fi; shift; done; fi; if test $w = ok; then if git -C $R fetch -q origin +refs/heads/$B:refs/remotes/origin/$B >/dev/null; then :; else w=unreadable; fi; fi; if test $w = ok; then x=$(git -C $R rev-parse --verify -q refs/remotes/origin/$B); case $x in $C) :;; ?*) w=base-moved;; *) w=unreadable;; esac; fi; if test $w = ok; then if test -e $L/record-$F; then w=exists; fi; if test -L $L/record-$F; then w=exists; fi; fi; if test $w = ok; then if mkdir -m 700 $L/$F >/dev/null; then :; else w=exists; fi; fi; if test $w = ok; then if git -C $R worktree add --detach $L/$F $C >/dev/null; then :; else w=failed; if git -C $R worktree remove --force $L/$F >/dev/null; then :; else rmdir $L/$F >/dev/null; fi; fi; fi; if test $w = ok; then if echo $Q $S >$L/record-$F; then :; else w=failed; rm -f $L/record-$F >/dev/null; if git -C $R worktree remove --force $L/$F >/dev/null; then :; else rmdir $L/$F >/dev/null; fi; fi; fi; if test $w = busy; then echo busy $bl $bp $bi; else echo $w; fi'
}

# Positionals: lanes dir, repo dir, leaf, commit. Words: removed kept.
function Get-SpecCleanupScript {
  'set -f; exec 2>/dev/null; L=$1; R=$2; F=$3; C=$4; v=ok; w=kept; n=0; h=0; d=0; i=0; t=; if test -L $L; then v=no; fi; if test $v = ok; then if test -d $L; then :; else v=no; fi; fi; if test $v = ok; then if test -O $L; then :; else v=no; fi; fi; if test $v = ok; then if test -L $L/$F; then v=no; fi; fi; if test $v = ok; then if test -d $L/$F; then :; else v=no; fi; fi; if test $v = ok; then if test -L $L/$F/.git; then v=no; fi; fi; if test $v = ok; then if test -f $L/$F/.git; then :; else v=no; fi; fi; if test $v = ok; then t=$(mktemp); case $t in /*) :;; *) v=no;; esac; fi; if test $v = ok; then if git -C $R worktree list --porcelain >$t; then :; else v=no; fi; fi; if test $v = ok; then while read -r k u; do case $k in worktree) i=0; case $u in $L/$F) n=$((n+1)); i=1;; esac;; HEAD) if test $i = 1; then case $u in $C) h=1;; esac; fi;; detached) if test $i = 1; then d=1; fi;; esac; done <$t; fi; if test $v = ok; then if test $n$h$d = 111; then if git -C $R worktree remove $L/$F >/dev/null; then w=removed; rm -f $L/record-$F >/dev/null; fi; fi; fi; case $t in /*) rm -f $t >/dev/null;; esac; echo $w'
}

# Positionals: lanes dir. Prints one line per running spec session and per leaf with no running session: leaf, process id or -, issues or unknown, seconds or unknown, yes or no (directory present); or the one word none; or the one word unsafe-dir when the lanes directory is a link, not a directory or not owned by the user (nothing else is printed then). A missing lanes directory is not refused.
function Get-SpecSweepScript {
  'set -f; exec 2>/dev/null; L=$1; seen=,; any=0; dg() { if test $# = 2; then :; else dok=0; return 0; fi; dv=$1; dok=1; while test ${#dv} -gt 0; do case $dv in [$2]*) dv=${dv#?};; *) dok=0; dv=;; esac; done; }; pf() { g=; q=$1; dg $q 0-9; if test $dok = 0; then return 0; fi; if test -O /proc/$q; then :; else return 0; fi; c=$(cat /proc/$q/comm); case $c in claude) :;; *) return 0;; esac; y=$(readlink /proc/$q/cwd); case $y in $L/spec-*) :;; *) return 0;; esac; set -- ${y#$L/}; if test $# -gt 2; then return 0; fi; if test $# = 2; then case $2 in \(deleted\)) :;; *) return 0;; esac; fi; case $1 in spec-[a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9]) g=$1;; esac; }; rd() { ri=unknown; rs=unknown; f=$L/record-$1; if test -L $f; then return 0; fi; if test -f $f; then :; else return 0; fi; n=0; a=; b=; while read -r k u; do n=$((n+1)); a=$k; b=$u; done <$f; if test $n = 1; then :; else return 0; fi; ok=1; if test ${#b} -lt 1; then ok=0; fi; if test ${#b} -gt 10; then ok=0; fi; dg $b 0-9; if test $dok = 0; then ok=0; fi; case $b in 0*) ok=0;; esac; if test ${#a} -lt 1; then ok=0; fi; if test ${#a} -gt 99; then ok=0; fi; dg $a 0-9,; if test $dok = 0; then ok=0; fi; case $a in ,*) ok=0;; *,) ok=0;; *,,*) ok=0;; 0*) ok=0;; *,0*) ok=0;; esac; if test $ok = 1; then IFS=,; set -- $a; unset IFS; if test $# -gt 10; then ok=0; fi; while test $# -gt 0; do if test ${#1} -gt 9; then ok=0; fi; shift; done; fi; if test $ok = 1; then ri=$a; rs=$b; fi; };  sp() { d=no; if test -d $L/$1; then d=yes; fi; }; w=ok; if test -L $L; then w=unsafe-dir; elif test -e $L; then if test -d $L; then if test -O $L; then :; else w=unsafe-dir; fi; else w=unsafe-dir; fi; fi; if test $w = ok; then set -- $(ls /proc); while test $# -gt 0; do pf $1; if test ${#g} -gt 0; then rd $g; sp $g; echo $g $1 $ri $rs $d; seen=$seen$g,; any=1; fi; shift; done; set -- $(ls $L); while test $# -gt 0; do h=; case $1 in spec-[a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9]) h=$1;; record-spec-[a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9][a-z0-9]) h=${1#record-};; esac; if test ${#h} -gt 0; then case $seen in *,$h,*) h=;; esac; fi; if test ${#h} -gt 0; then e=0; if test -d $L/$h; then e=1; fi; if test -e $L/record-$h; then e=1; fi; if test -L $L/record-$h; then e=1; fi; if test $e = 1; then rd $h; sp $h; echo $h - $ri $rs $d; seen=$seen$h,; any=1; fi; fi; shift; done; fi; if test $w = unsafe-dir; then echo unsafe-dir; elif test $any = 0; then echo none; fi'
}

# First-message templates: only @N@, @HASH@ and @LIST@ are filled, each from a validated value.
$script:LaneMessage = 'Lane for issue #@N@. In one Bash call, run: T=$(mktemp -d); cp /tmp/lanes/@N@-prompt.md $T/p.md; sha256sum $T/p.md; echo $T/p.md. Stop unless that call printed the hash @HASH@. If it did, read only that copy and follow it.'
$script:SpecMessage = 'Run /way-of-working:spec-task for each of these issues, one at a time, in this order: @LIST@. Build nothing, and start no build for any of them.'

$script:LanesDir = '/tmp/lanes'
$script:RepoDir = '/workspace'

function Test-IssueNumber([string]$Value) { $null -ne $Value -and $Value -cmatch '\A[1-9][0-9]{0,8}\z' }

# Assert-Plain: no argv element carries & | ^ % ! or a double quote (a docker.cmd runs through cmd.exe).
function Assert-Plain([string[]]$Arguments) {
  foreach ($a in $Arguments) { if ($a -cmatch '[&|^%!"]') { Stop-Launch 'refusing an argument with & | ^ % ! or a double quote' } }
}

# Invoke-ContainerExec: one non-interactive docker exec -u app of a script. Returns its stdout, or $null
# for a nonzero exit.
function Invoke-ContainerExec([string]$Docker, [string]$Id, [string]$Script, [string[]]$ScriptArgs) {
  $argv = @('exec', '-u', 'app', '-e', 'GIT_TERMINAL_PROMPT=0', '-e', 'GIT_NO_REPLACE_OBJECTS=1', $Id, '/bin/sh', '-c', $Script, 'sh') + $ScriptArgs
  Assert-Plain $argv
  $r = Invoke-Tool $Docker $argv
  if ($r.Code -ne 0) { return $null }
  [Text.Encoding]::UTF8.GetString($r.Out)
}

# Invoke-ContainerWord: Invoke-ContainerExec, read as one one-word line. Returns the word, or $null for a
# nonzero exit, any other output or more than one line.
function Invoke-ContainerWord([string]$Docker, [string]$Id, [string]$Script, [string[]]$ScriptArgs) {
  $text = Invoke-ContainerExec $Docker $Id $Script $ScriptArgs
  if ($null -eq $text -or -not ($text -cmatch '\A([a-z]+(-[a-z]+)*)\r?\n\z')) { return $null }
  $Matches[1]
}

# The shapes of what the spec scripts print (the same ones they check in the container).
$script:IssueListRx = '[1-9][0-9]{0,8}(?:,[1-9][0-9]{0,8}){0,9}'
$script:SpecLeafRx = 'spec-[a-z0-9]{6}'
$script:SecondsRx = '[1-9][0-9]{0,9}'

# Invoke-SpecPrep: the spec prep script's answer. A word as Invoke-ContainerWord reads it, or the exact
# line busy, a leaf, a process id and the issues or unknown (returned as that line without its newline);
# $null for anything else.
function Invoke-SpecPrep([string]$Docker, [string]$Id, [string[]]$ScriptArgs) {
  $text = Invoke-ContainerExec $Docker $Id (Get-SpecPrepScript) $ScriptArgs
  if ($null -eq $text) { return $null }
  if ($text -cmatch "\A(busy $($script:SpecLeafRx) [1-9][0-9]{0,9} (unknown|$($script:IssueListRx)))\r?\n\z") { return $Matches[1] }
  if (-not ($text -cmatch '\A([a-z]+(-[a-z]+)*)\r?\n\z')) { return $null }
  $Matches[1]
}

# Invoke-SpecSweep: the sweep script's lines, each a leaf, a process id or -, the issues or unknown, the
# record's seconds or unknown, and yes or no; or the one line none (returned as an empty array); or the one
# line unsafe-dir (returned as that string). $null for a nonzero exit or anything else.
function Invoke-SpecSweep([string]$Docker, [string]$Id, [string]$LanesDir) {
  $text = Invoke-ContainerExec $Docker $Id (Get-SpecSweepScript) @($LanesDir)
  if ($null -eq $text -or -not $text.EndsWith("`n")) { return $null }
  $lines = @($text.Substring(0, $text.Length - 1).Split("`n") | ForEach-Object { $_.TrimEnd("`r") })
  if ($lines.Count -eq 1 -and $lines[0] -ceq 'none') { return , @() }
  if ($lines.Count -eq 1 -and $lines[0] -ceq 'unsafe-dir') { return 'unsafe-dir' }
  $rx = "\A($($script:SpecLeafRx)) ([1-9][0-9]{0,9}|-) (unknown|$($script:IssueListRx)) ($($script:SecondsRx)|unknown) (yes|no)\z"
  $rows = @()
  foreach ($l in $lines) {
    if ($l -cnotmatch $rx) { return $null }
    $rows += , [pscustomobject]@{ Leaf = $Matches[1]; Pid = $Matches[2]; Issues = $Matches[3]; Seconds = $Matches[4]; Present = ($Matches[5] -ceq 'yes') }
  }
  , $rows
}

try {
  # --- arguments: exit 2, before any external call (the one exception: the sh run for an MSYS-form -WowHome) ---
  $cloneP = Resolve-LaunchDir '-Clone' $Clone
  $refP = Resolve-LaunchDir '-Reference' $Reference
  $gitDir = Join-Path $refP '.git'
  if (-not (Test-Path -LiteralPath $gitDir -PathType Container)) { Stop-BadArgument '-Reference needs a .git directory (not a file, so not a worktree)' }
  if (Test-ReparsePoint $gitDir) { Stop-BadArgument "-Reference's .git is a link or reparse point" }
  if ((Test-PathInside $cloneP $refP) -or (Test-PathInside $refP $cloneP)) { Stop-BadArgument '-Clone and -Reference may not be, or contain, one another' }
  $wowP = Resolve-LaunchDir '-WowHome' (ConvertFrom-MsysDrivePath '-WowHome' $WowHome) -Plain
  if ((Test-PathInside $cloneP $wowP) -or (Test-PathInside $wowP $cloneP)) { Stop-BadArgument '-Clone may not be, contain or sit inside -WowHome' }
  if (-not (Test-RefName $Remote)) { Stop-BadArgument '-Remote is not a plain ref name' }
  if (-not (Test-RefName $Base)) { Stop-BadArgument '-Base is not a plain ref name' }
  $leaf = [IO.Path]::GetFileName($cloneP)
  $refLeaf = [IO.Path]::GetFileName($refP)
  if ($leaf -ieq $refLeaf) { Stop-BadArgument '-Clone and -Reference may not share a folder name: they would share the <leaf>-tmp volume' }

  $hasIssue = $PSBoundParameters.ContainsKey('Issue')
  $hasHash = $PSBoundParameters.ContainsKey('Hash')
  $hasSpec = $PSBoundParameters.ContainsKey('Spec')
  $hasSweep = $SpecSweep.IsPresent
  if ($hasSweep -and ($hasIssue -or $hasHash -or $hasSpec)) { Stop-BadArgument '-SpecSweep cannot be combined with -Issue, -Hash or -Spec' }
  if ($hasSpec -and ($hasIssue -or $hasHash)) { Stop-BadArgument '-Spec cannot be combined with -Issue or -Hash' }
  if (-not $hasSweep -and -not $hasSpec -and -not $hasIssue -and -not $hasHash) { Stop-BadArgument 'give -Issue with -Hash, -Spec, or -SpecSweep' }
  if ($hasIssue -ne $hasHash) { Stop-BadArgument '-Issue and -Hash go together' }
  $specList = @()
  if ($hasSpec) {
    $specList = @($Spec.Split(','))
    if ($specList.Count -gt 10) { Stop-BadArgument '-Spec takes at most 10 issues' }
    foreach ($s in $specList) { if (-not (Test-IssueNumber $s)) { Stop-BadArgument '-Spec holds a part that is not an issue number (decimal digits, no leading zero, at most 9)' } }
    if (@($specList | Select-Object -Unique).Count -ne $specList.Count) { Stop-BadArgument '-Spec repeats an issue' }
  } elseif (-not $hasSweep) {
    if (-not (Test-IssueNumber $Issue)) { Stop-BadArgument '-Issue is not an issue number (decimal digits, no leading zero, at most 9)' }
    if (-not (Test-Hex $Hash 64)) { Stop-BadArgument '-Hash is not 64 lowercase hex digits' }
  }

  # --- installed from bin under the final WowHome -------------------------------------------------
  $binWant = Join-Path $wowP 'bin'
  if ((Format-PathKey (Get-FinalPath $PSScriptRoot)) -ne (Format-PathKey $binWant)) { & $notInstalled }

  $git = Resolve-Tool 'git'
  $docker = Resolve-Tool 'docker'
  $yq = Resolve-Tool 'yq'

  # --- the one running container, recorded by the driver launcher -------------------------------
  $mine = @(Get-LaunchContainers $docker $cloneP $leaf)
  Assert-KnownStates $mine
  if ($mine.Count -ne 1 -or $mine[0].State -cne 'running') {
    $ids = ($mine | ForEach-Object { "$($_.Id) ($($_.State))" }) -join ', '
    Stop-Launch "needs exactly one running container for this clone, found: $(if ($ids) { $ids } else { 'none' }). Start the day with wow-driver.ps1"
  }
  $id = $mine[0].Id
  $refBusy = @(Get-LaunchContainers $docker $refP $refLeaf)
  if ($refBusy.Count -gt 0) {
    Stop-Launch "the Reference clone is in use by container $($refBusy[0].Id): the Reference must be a clone no container opens"
  }
  $rec = Read-Record (Get-RecordPath $wowP $leaf)
  if ($null -eq $rec) { Stop-Launch 'no driver record for this clone: run wow-driver.ps1 first' }
  if ((Format-PathKey $rec.clone) -ne (Format-PathKey $cloneP)) { Stop-Launch 'the driver record names another clone: run wow-driver.ps1 first' }
  if ($rec.id -cne $id) { Stop-Launch "the running container $id is not the recorded one ($($rec.id)): run wow-driver.ps1 first" }
  Test-RelayProbe $docker $id

  # --- commit and model --------------------------------------------------------------------------
  $commit = $null
  $model = $null
  if (-not $hasSweep) {
    $commit = Get-ReferenceCommit $git $refP $Remote $Base
    $model = Get-RoleModel $git $yq $refP $commit $(if ($hasSpec) { 'architect' } else { 'coder' })
  }

  if ($hasSweep) {
    # --- sweep: read-only, no session -------------------------------------------------------------
    $rows = Invoke-SpecSweep $docker $id $script:LanesDir
    if ($rows -is [string] -and $rows -ceq 'unsafe-dir') { Stop-Launch "$($script:LanesDir) in the container is a link, not a directory, or not owned by the container user" }
    if ($null -eq $rows) { Stop-Launch 'the spec sweep in the container gave no usable answer' }
    if (@($rows).Count -eq 0) { Write-LaunchLine 'no spec sessions' }
    foreach ($r in @($rows)) {
      $where = "$($script:LanesDir)/$($r.Leaf)" + $(if ($r.Present) { '' } else { ' (gone)' })
      $proc = if ($r.Pid -ceq '-') { 'no process' } else { "process $($r.Pid)" }
      $started = if ($r.Seconds -ceq 'unknown') { 'unknown' } else { [DateTimeOffset]::FromUnixTimeSeconds([long]$r.Seconds).ToLocalTime().ToString('yyyy-MM-dd HH:mm:ss zzz', [Globalization.CultureInfo]::InvariantCulture) }
      Write-LaunchLine "$where; $proc; issues $($r.Issues); started $started"
    }
    $code = 0
  } elseif (-not $hasSpec) {
    # --- lane ----------------------------------------------------------------------------------
    $word = Invoke-ContainerWord $docker $id (Get-LaneProbeScript) @($script:LanesDir, $Issue, $Hash)
    switch -CaseSensitive ($word) {
      'ok' { }
      'unsafe-dir' { Stop-Launch "$($script:LanesDir) in the container is missing, a link, or not owned by the container user" }
      'no-worktree' { Stop-Launch "$($script:LanesDir)/$Issue is not a worktree: run lane.sh prep $Issue first" }
      'no-prompt' { Stop-Launch "$($script:LanesDir)/$Issue-prompt.md is not a regular file: run lane.sh prep $Issue first" }
      'hash-mismatch' { Stop-Launch 'the prompt file does not hash to -Hash: check the hash copied from prep, or re-run lane.sh prep' }
      default { Stop-Launch 'the lane probe in the container gave no usable answer' }
    }
    $message = $script:LaneMessage.Replace('@N@', $Issue).Replace('@HASH@', $Hash)
    $argv = @('exec', '-it', '-u', 'app', '-e', 'GIT_TERMINAL_PROMPT=0', '-w', "$($script:LanesDir)/$Issue", $id,
      '/usr/local/bin/claude', '--model', $model, $message)
    Assert-Plain $argv
    $code = Invoke-Session $docker $argv
  } else {
    # --- spec ----------------------------------------------------------------------------------
    $chars = 'abcdefghijklmnopqrstuvwxyz0123456789'
    $specLeaf = 'spec-' + (-join (1..6 | ForEach-Object { $chars[[Security.Cryptography.RandomNumberGenerator]::GetInt32($chars.Length)] }))
    $launched = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString([Globalization.CultureInfo]::InvariantCulture)
    if ($launched -cnotmatch "\A$($script:SecondsRx)\z") { Stop-Launch 'the launch time is not whole Unix seconds' }
    $word = Invoke-SpecPrep $docker $id @($script:LanesDir, $script:RepoDir, $Base, $commit, $specLeaf, ($specList -join ','), $launched)
    switch -CaseSensitive ($word) {
      { $_ -cmatch '\Abusy ' } {
        $b = $word.Split(' ')
        Stop-Launch "a spec session is already running in $($script:LanesDir)/$($b[1]) (process $($b[2]), issues $(if ($b[3] -ceq 'unknown') { 'unknown: no readable record' } else { $b[3] })): the maintainer stops that session before -Spec runs again"
      }
      'ok' { }
      'unsafe-dir' { Stop-Launch "$($script:LanesDir) in the container is a link, not a directory, not owned by the container user, or cannot be made" }
      'unreadable' { Stop-Launch "the container clone could not fetch or read origin/$Base" }
      'base-moved' { Stop-Launch "the container clone's origin/$Base is not $commit, the Reference's commit: fetch the Reference again, or wait for the container clone to catch up" }
      'exists' { Stop-Launch "$($script:LanesDir)/$specLeaf already exists: run again" }
      'failed' { Stop-Launch "git worktree add or the spec record write failed in the container; it was rolled back as far as it could be, so check $($script:LanesDir)/$specLeaf for a leftover directory" }
      default { Stop-Launch "the spec prep in the container gave no usable answer; $($script:LanesDir)/$specLeaf may have been made, check it by hand" }
    }
    $message = $script:SpecMessage.Replace('@LIST@', ($specList -join ', '))
    $dir = "$($script:LanesDir)/$specLeaf"
    $argv = @('exec', '-it', '-u', 'app', '-e', 'GIT_TERMINAL_PROMPT=0', '-w', $dir, $id,
      '/usr/local/bin/claude', '--model', $model, '--effort', 'high', $message)
    Assert-Plain $argv
    $code = 1
    $kept = $false
    try {
      $code = Invoke-Session $docker $argv
    } finally {
      $clean = $null
      try { $clean = Invoke-ContainerWord $docker $id (Get-SpecCleanupScript) @($script:LanesDir, $script:RepoDir, $specLeaf, $commit) } catch { $clean = $null }
      if ($clean -cne 'removed') {
        $kept = $true
        [Console]::Error.WriteLine("wow-lane: kept the spec worktree $dir in container $id (not removed: it may hold untracked files, such as .claude/settings.local.json, or it is no longer the detached worktree made at $commit)")
        [Console]::Error.WriteLine("wow-lane: inspect: docker exec -it -u app $id git -C $dir status")
        [Console]::Error.WriteLine("wow-lane: remove by hand once checked: docker exec -u app $id git -C $($script:RepoDir) worktree remove --force $dir")
        [Console]::Error.WriteLine("wow-lane: then remove its record: docker exec -u app $id rm $($script:LanesDir)/record-$specLeaf")
      }
    }
    if ($kept) { exit 1 }
  }
} catch {
  Stop-Launch $_.Exception.Message
}
exit $code
