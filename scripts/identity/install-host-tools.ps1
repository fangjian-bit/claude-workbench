#Requires -Version 7.2
<#
.SYNOPSIS
  Install the host identity scripts into $WowHome\bin, and the review image's build context into
  $WowHome\bin\review, from committed code (WB-D24, issues #392, #634). The clean-tree check covers
  every source directory of both.

.DESCRIPTION
  The broker, mint.sh and the wow-* commands run on the host next to every App key. A dev
  container bind-mounts a checkout of this repo read-write, so code run by path from a checkout is
  code a container can edit. This copies the scripts out of git instead, into a directory no
  container mounts, and everything on the host runs from that copy. Re-running it is the upgrade.

  What it does, in order, stopping at the first failure:
    1. Finds the source checkout (-SourceRepo, default the one holding this script).
    2. Checks, changing nothing in $WowHome: no source directory in the table below
       (scripts/identity, .devcontainer, scripts/loop, plugins/way-of-working/bin) has an
       uncommitted change, and HEAD is an ancestor of refs/remotes/<Remote>/<Base> after a fetch (which does update that
       remote-tracking ref): reviewed, merged code, not a worktree or an unpushed branch. HEAD is
       resolved once, and that commit is what is exported and recorded. Every table entry must
       exist at that commit.
    3. Only then (and only past -WhatIf / -Confirm) disables the scheduled task named by -StopTask,
       if it exists, stops it and ends the processes running its -File path (stopping the task ends
       conhost, not the pwsh it started), waiting for them, so a refusal above never leaves the broker
       down. The task is enabled again after the swap, on failure too, if it was enabled before; a run
       killed between the disable and that re-enable leaves it disabled until the register script runs.
    4. Exports the files from that commit (git cat-file blob: the stored bytes, so no working-tree
       edit and no CRLF conversion) into $WowHome\bin.new, writes MANIFEST there (the commit, the
       install time, each file's sha256 and destination path relative to bin, so the human can
       compare the commit with GitHub), and
       swaps it in for $WowHome\bin. Besides the host scripts that is bin\review, the review image's
       build context (#634): the Dockerfile plus exactly the files it copies, flat. The old bin is kept as bin.old until the swap succeeds and is
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

  Put $WowHome/bin on Git Bash's PATH to run wow-admin, wow-review and wow-review-mint from the
  installed copy (wow-review finds wow-review-mint beside itself). Run on its own it does not stop a running
  broker unless -StopTask is given; a held file then fails the swap cleanly.

  The driver launcher is not a Git Bash command (Git Bash's HOME doubles the container mount path). Run
  it from pwsh 7.2+ on the host, as the installed copy under $env:WOW_HOME\bin, or under the default
  $HOME\.config\glunk-identity\bin when WOW_HOME is unset (docs/identity/DEV-CONTAINER.md, Opening it):
    pwsh -File $env:WOW_HOME\bin\wow-driver.ps1 -Clone <clone> -Reference <other clone>
  The lane and spec launcher, wow-lane.ps1, runs the same way, beside the driver's container (#762):
    pwsh -File $env:WOW_HOME\bin\wow-lane.ps1 -Clone <clone> -Reference <other clone> -Issue N -Hash HASH
    pwsh -File $env:WOW_HOME\bin\wow-lane.ps1 -Clone <clone> -Reference <other clone> -Spec N[,N...]
  With an MSYS-form WOW_HOME (/c/...) the $env:WOW_HOME script path in those commands does not resolve in
  pwsh, so give the installed copy's path in Windows form; the launchers convert their own default -WowHome.
  yq (mikefarah v4) must be on PowerShell's PATH too. It runs only from there: it checks the MANIFEST.

.PARAMETER SourceRepo
  The git checkout to install from. Default: the repository containing this script.

.PARAMETER StopTask
  A scheduled task to disable and stop just before the swap, with the processes running its -File path
  ended and waited for, then enabled again after it (register-broker-task.ps1 passes its own).
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

# Committed source path -> destination path under bin/, one pair per line. The leading comma is
# required: without it PowerShell flattens the lines inside @( ... ) into one list of bare strings
# instead of pairs. bin/review/ is the review image's build context: the Dockerfile plus exactly the
# files it copies (tests/review-image.test.sh holds the two lists equal).
$table = @(
  ,@('scripts/identity/broker.ps1', 'broker.ps1')
  ,@('scripts/identity/mint.sh', 'mint.sh')
  ,@('scripts/identity/wow-common.sh', 'wow-common.sh')
  ,@('scripts/identity/wow-review-mint', 'wow-review-mint')
  ,@('scripts/identity/wow-admin', 'wow-admin')
  ,@('scripts/identity/wow-review', 'wow-review')
  ,@('scripts/identity/wow-review-poll', 'wow-review-poll')
  ,@('scripts/identity/wow-driver.ps1', 'wow-driver.ps1')
  ,@('scripts/identity/wow-launch-common.ps1', 'wow-launch-common.ps1')
  ,@('scripts/identity/wow-lane.ps1', 'wow-lane.ps1')
  ,@('plugins/way-of-working/bin/review-gate-state.sh', 'review-gate-state.sh')
  ,@('plugins/way-of-working/bin/token-check.sh', 'token-check.sh')
  ,@('plugins/way-of-working/bin/gh-identity.sh', 'gh-identity.sh')
  ,@('scripts/identity/review/Dockerfile', 'review/Dockerfile')
  ,@('scripts/identity/review/entrypoint.sh', 'review/entrypoint.sh')
  ,@('scripts/identity/review/outbox-read', 'review/outbox-read')
  ,@('scripts/identity/review/managed-settings.json', 'review/managed-settings.json')
  ,@('.devcontainer/dev-token', 'review/dev-token')
  ,@('.devcontainer/gh', 'review/gh')
  ,@('plugins/way-of-working/bin/token-check.sh', 'review/token-check.sh')
  ,@('plugins/way-of-working/bin/gh-identity.sh', 'review/gh-identity.sh')
  ,@('scripts/loop/inject.py', 'review/inject.py')
  ,@('scripts/loop/proxy.py', 'review/proxy.py')
)
$srcDirs = @($table | ForEach-Object { $_[0].Substring(0, $_[0].LastIndexOf('/')) } | Select-Object -Unique)

# One git, resolved once, as an application: an alias or function named git in a profile cannot shadow it.
$found = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$gitExe = if ($found) { $found.Source }
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

if ($IsWindows -and $WowHome.StartsWith('/')) { throw "WowHome $WowHome is in MSYS form; pass -WowHome in Windows form, or run register-broker-task.ps1, which converts it" }
if (-not (Test-Path -LiteralPath $WowHome -PathType Container)) { throw "WowHome $WowHome does not exist" }
$WowHome = (Resolve-Path -LiteralPath $WowHome).ProviderPath.TrimEnd('\')
if (-not $SourceRepo) { $SourceRepo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$script:repo = $SourceRepo
$null = Invoke-Git @('rev-parse', '--git-dir')

# --- checks: nothing under $WowHome changes until they all pass -----------------------------
foreach ($d in $srcDirs) {
  if (Invoke-Git @('status', '--porcelain', '--', $d)) { throw "$d has uncommitted changes; commit and merge them first" }
}
$null = Invoke-Git @('fetch', '--quiet', $Remote, $Base)
$head = Invoke-Git @('rev-parse', '--verify', 'HEAD^{commit}')
$remoteRef = "refs/remotes/$Remote/$Base" # full name: a local branch or tag called origin/main must not win
try { $null = Invoke-Git @('merge-base', '--is-ancestor', $head, $remoteRef) }
catch { throw "HEAD ($($head.Substring(0, 12))) is not on $Remote/$Base; install from merged code" }
foreach ($e in $table) { $null = Invoke-Git @('cat-file', '-e', "$($head):$($e[0])") }

# --- install ----------------------------------------------------------------------------------
$bin = Join-Path $WowHome 'bin'
$new = Join-Path $WowHome 'bin.new'
$old = Join-Path $WowHome 'bin.old'
if ($PSCmdlet.ShouldProcess($bin, "Install $($table.Count) host files from commit $($head.Substring(0, 12))")) {
  # Disabled across the swap so the broker task's one-minute trigger cannot start the old broker between the stop and the swap.
  $taskWasEnabled = $false
  $stopSpan = $null
  if ($StopTask) {
    $stopFound = @(Get-ScheduledTask -TaskName $StopTask -ErrorAction SilentlyContinue)
    if ($stopFound.Count -gt 1) { throw "expected one task named $StopTask, found $($stopFound.Count)" }
    if ($stopFound.Count -eq 1) {
      $taskWasEnabled = [bool]$stopFound[0].Settings.Enabled
      . (Join-Path $PSScriptRoot 'task-process.ps1')
      $stopSpan = Get-FileArgSpan (@($stopFound[0].Actions)[0].Arguments)
      $null = Disable-ScheduledTask -TaskName $StopTask -Confirm:$false
    }
  }
  try {
    if ($StopTask) {
      Stop-ScheduledTask -TaskName $StopTask -ErrorAction SilentlyContinue
      if ($stopSpan) { Stop-FileArgProcess $stopSpan }
    }

    # A crash mid-swap leaves bin.old and no bin: that is the last good copy, so put it back first.
    if (-not (Test-Path -LiteralPath $bin) -and (Test-Path -LiteralPath $old)) { Move-Item -LiteralPath $old -Destination $bin }
    if (Test-Path -LiteralPath $new) { Remove-Item -LiteralPath $new -Recurse -Force }
    $null = New-Item -ItemType Directory -Path $new
    foreach ($e in $table) {
      $dst = Join-Path $new $e[1]
      $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst)
      Export-Blob "$($head):$($e[0])" $dst
    }

    $lines = @("commit $head", "installed $([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))")
    foreach ($e in $table) {
      $p = Join-Path $new $e[1]
      if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "$($e[1]) missing after export" }
      $lines += '{0}  {1}' -f (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant(), $e[1]
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
  } finally {
    # A failed enable must not replace the install's own error: warn loudly and let that error through.
    if ($taskWasEnabled) {
      try { $null = Enable-ScheduledTask -TaskName $StopTask -Confirm:$false }
      catch { Write-Warning "could not enable task $StopTask again ($($_.Exception.Message)); it stays disabled until the register script runs" }
    }
  }
}
