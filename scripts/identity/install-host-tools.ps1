#Requires -Version 7.2
<#
.SYNOPSIS
  Install the host identity scripts into $WowHome\bin, from committed code (WB-D24, issue #392).

.DESCRIPTION
  The broker, mint.sh and the wow-* commands run on the host next to every App key. A dev
  container bind-mounts a checkout of this repo read-write, so code run by path from a checkout is
  code a container can edit. This copies the scripts out of git instead, into a directory no
  container mounts, and everything on the host runs from that copy. Re-running it is the upgrade.

  What it does, in order, stopping at the first failure:
    1. Finds the source checkout (-SourceRepo, default the one holding this script).
    2. Checks, changing nothing in $WowHome: scripts/identity has no uncommitted change, and HEAD
       is an ancestor of refs/remotes/<Remote>/<Base> after a fetch (which does update that
       remote-tracking ref): reviewed, merged code, not a worktree or an unpushed branch. HEAD is
       resolved once, and that commit is what is exported and recorded.
    3. Only then (and only past -WhatIf / -Confirm) stops the scheduled task named by -StopTask,
       if given, so a refusal above never leaves the broker down.
    4. Exports the files from that commit (git cat-file blob: the stored bytes, so no working-tree
       edit and no CRLF conversion) into $WowHome\bin.new, writes MANIFEST there (the commit, the
       install time, each file's sha256, so the human can compare the commit with GitHub), and
       swaps it in for $WowHome\bin. The old bin is kept as bin.old until the swap succeeds and is
       put back if it fails; a leftover bin.old with no bin is restored on the next run.
    5. Creates $WowHome\tokens\<repo> for each repo in broker.json (a container mount whose source
       is missing fails to start). A bad broker.json is a warning here, not a failed install.

  Honest limit. The checks in step 2 catch accidents (an unreviewed worktree, a checkout about to
  be deleted). They do not narrow the hostile case. If a container can write the source clone, it
  can plant .git config or hooks that run on the host when this script runs git (core.fsmonitor on
  `status`, core.sshCommand on `fetch`), and it can edit this very script, which runs from that
  clone's working tree. That is host code execution beside the App keys, before any check. The
  control is to run this from a clone no container opens; #393's container must open a different
  clone or a volume. "Ancestor of main" also accepts an older merged commit (a downgrade).

  Put $WowHome/bin on Git Bash's PATH to run wow-admin and wow-review-mint (review-token.sh finds
  wow-review-mint there) from the installed copy. Run on its own it does not stop a running
  broker unless -StopTask is given; a held file then fails the swap cleanly.

.PARAMETER SourceRepo
  The git checkout to install from. Default: the repository containing this script.

.PARAMETER StopTask
  A scheduled task to stop just before the swap (register-broker-task.ps1 passes its own).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$WowHome = $(if ($env:WOW_HOME) { $env:WOW_HOME } else { Join-Path $HOME '.config/glunk-identity' }),
  [string]$SourceRepo,
  [string]$Remote = 'origin',
  [string]$Base = 'main',
  [string]$StopTask
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$files = 'broker.ps1', 'mint.sh', 'wow-common.sh', 'wow-review-mint', 'wow-admin'
$srcDir = 'scripts/identity'

# One git, resolved once, as an application: an alias or function named git in a profile cannot shadow it.
$gitExe = (Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $gitExe) { throw 'git not found on PATH' }

# Invoke-Git <args...>: stdout as text (trailing newline trimmed); stderr is kept apart, used only in the error.
function Invoke-Git([string[]]$a) {
  $psi = [Diagnostics.ProcessStartInfo]::new($gitExe)
  foreach ($x in @('-C', $script:repo) + $a) { $psi.ArgumentList.Add($x) }
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $p = [Diagnostics.Process]::Start($psi)
  $errTask = $p.StandardError.ReadToEndAsync()
  $out = $p.StandardOutput.ReadToEnd()
  $p.WaitForExit()
  if ($p.ExitCode -ne 0) { throw "git $($a -join ' ') failed: $($errTask.Result.Trim())" }
  $out.TrimEnd("`r", "`n")
}

# Export-Blob <rev:path> <dest>: the committed bytes, exactly as stored (no filters, no text conversion).
function Export-Blob([string]$spec, [string]$dest) {
  $psi = [Diagnostics.ProcessStartInfo]::new($gitExe)
  foreach ($x in '-C', $script:repo, 'cat-file', 'blob', $spec) { $psi.ArgumentList.Add($x) }
  $psi.RedirectStandardOutput = $true
  $psi.UseShellExecute = $false
  $p = [Diagnostics.Process]::Start($psi)
  $fs = [IO.File]::Create($dest)
  try { $p.StandardOutput.BaseStream.CopyTo($fs) } finally { $fs.Dispose() }
  $p.WaitForExit()
  if ($p.ExitCode -ne 0) { throw "git cat-file blob $spec failed" }
}

if (-not (Test-Path -LiteralPath $WowHome -PathType Container)) { throw "WowHome $WowHome does not exist" }
$WowHome = (Resolve-Path -LiteralPath $WowHome).ProviderPath.TrimEnd('\')
if (-not $SourceRepo) { $SourceRepo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$script:repo = $SourceRepo
$null = Invoke-Git @('rev-parse', '--git-dir')

# --- checks: nothing under $WowHome changes until they all pass -----------------------------
if (Invoke-Git @('status', '--porcelain', '--', $srcDir)) { throw "$srcDir has uncommitted changes; commit and merge them first" }
$null = Invoke-Git @('fetch', '--quiet', $Remote, $Base)
$head = Invoke-Git @('rev-parse', '--verify', 'HEAD^{commit}')
$remoteRef = "refs/remotes/$Remote/$Base" # full name: a local branch or tag called origin/main must not win
try { $null = Invoke-Git @('merge-base', '--is-ancestor', $head, $remoteRef) }
catch { throw "HEAD ($($head.Substring(0, 12))) is not on $Remote/$Base; install from merged code" }
foreach ($f in $files) { $null = Invoke-Git @('cat-file', '-e', "$($head):$srcDir/$f") }

# --- install ----------------------------------------------------------------------------------
$bin = Join-Path $WowHome 'bin'
$new = Join-Path $WowHome 'bin.new'
$old = Join-Path $WowHome 'bin.old'
if ($PSCmdlet.ShouldProcess($bin, "Install $($files.Count) host scripts from commit $($head.Substring(0, 12))")) {
  if ($StopTask) { Stop-ScheduledTask -TaskName $StopTask -ErrorAction SilentlyContinue }

  # A crash mid-swap leaves bin.old and no bin: that is the last good copy, so put it back first.
  if (-not (Test-Path -LiteralPath $bin) -and (Test-Path -LiteralPath $old)) { Move-Item -LiteralPath $old -Destination $bin }
  if (Test-Path -LiteralPath $new) { Remove-Item -LiteralPath $new -Recurse -Force }
  $null = New-Item -ItemType Directory -Path $new
  foreach ($f in $files) { Export-Blob "$($head):$srcDir/$f" (Join-Path $new $f) }

  $lines = @("commit $head", "installed $([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))")
  foreach ($f in $files) {
    $p = Join-Path $new $f
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "$f missing after export" }
    $lines += '{0}  {1}' -f (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant(), $f
  }
  [IO.File]::WriteAllText((Join-Path $new 'MANIFEST'), (($lines -join "`n") + "`n"))

  if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Recurse -Force } # a stale backup, bin is intact
  $hadBin = Test-Path -LiteralPath $bin
  try {
    if ($hadBin) { Move-Item -LiteralPath $bin -Destination $old }
    Move-Item -LiteralPath $new -Destination $bin
  } catch {
    if ($hadBin -and -not (Test-Path -LiteralPath $bin) -and (Test-Path -LiteralPath $old)) { Move-Item -LiteralPath $old -Destination $bin }
    throw
  }
  if (Test-Path -LiteralPath $old) {
    try { Remove-Item -LiteralPath $old -Recurse -Force } catch { Write-Warning "could not remove $old ($($_.Exception.Message)); the next run will" }
  }

  $cfg = Join-Path $WowHome 'broker.json'
  if (Test-Path -LiteralPath $cfg -PathType Leaf) {
    try {
      foreach ($r in @((Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json).repos)) {
        if ($r -is [string] -and $r -match '\A[A-Za-z0-9._-]+\z' -and $r -notmatch '\A[-.]' -and $r -notmatch '\.\z') {
          $null = New-Item -ItemType Directory -Force -Path (Join-Path $WowHome "tokens/$r")
        }
      }
    } catch { Write-Warning "broker.json unreadable ($($_.Exception.Message)); tokens/<repo> not created" }
  }
  "installed commit $head into $bin"
}
