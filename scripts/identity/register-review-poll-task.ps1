#Requires -Version 7.2
<#
.SYNOPSIS
  Install (or remove) the scheduled task that runs wow-review-poll (WB-D24, issue #626).

.DESCRIPTION
  Registers a per-user task, run as the current user with limited rights and an Interactive logon,
  that runs the installed wow-review-poll:
    - at logon,
    - every -IntervalMinutes (2 to 60, default 5),
  with "run as soon as possible after a missed start" on, no stop on battery, a second start
  ignored while one runs (a long review makes the next ticks no-ops), and an 8 hour run-time limit.
  The poller decides only whether to launch wow-review; see the header of wow-review-poll.

  Register it only after every item in docs/identity/REVIEW-LIVE-RUN.md has passed, and create
  $WowHome\review-poll.json ({"repos": ["owner/name", ...]}) at the same time. -Unregister stops and
  removes the task.

  Like register-broker-task.ps1, it installs the host scripts into $WowHome\bin with
  install-host-tools.ps1 (committed code on origin/main only) and registers the task against those
  copies, never a checkout. It stops its own task before the install and restarts it if the install
  fails. Run it from a PowerShell 7.2+ prompt on the host, from a clone no container opens. The sh
  it records is resolved now (or -Sh), because a task does not search the same PATH an interactive
  shell does; docker, gh, jq, yq and timeout must be on the user's PATH. The task runs pwsh through
  conhost.exe --headless, so no window opens on a tick. -WhatIf shows what would be registered.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$WowHome = $(if ($env:WOW_HOME) { $env:WOW_HOME } else { Join-Path $HOME '.config/glunk-identity' }),
  [string]$Sh,
  [string]$SourceRepo,
  [string]$TaskName = 'glunk-wow-review-poll',
  [ValidateRange(2, 60)][int]$IntervalMinutes = 5,
  [switch]$Unregister
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($TaskName -notmatch '^[A-Za-z0-9._-]+$') { throw "TaskName must be letters, digits, . _ -" }

if ($Unregister) {
  if ($PSCmdlet.ShouldProcess($TaskName, 'Unregister scheduled task')) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
  }
  return
}

if (-not $Sh) {
  $found = Get-Command sh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($found) { $Sh = $found.Source }
}
if (-not $Sh -or -not (Test-Path -LiteralPath $Sh -PathType Leaf)) { throw 'no POSIX sh found: pass -Sh (Git for Windows sh.exe)' }
if ($WowHome.StartsWith('/')) {
  $conv = (& $Sh -c 'cygpath -w "$1"' sh $WowHome 2>$null)
  if ($conv) { $WowHome = ("$conv").Trim() }
}
if (-not (Test-Path -LiteralPath $WowHome -PathType Container)) { throw "WowHome $WowHome does not exist; create it first" }
# Full paths, no trailing backslash.
$WowHome = (Resolve-Path -LiteralPath $WowHome).ProviderPath.TrimEnd('\')
$Sh = (Resolve-Path -LiteralPath $Sh).ProviderPath
if ($Sh -match '[\\/]usr[\\/]bin[\\/]sh\.exe$') { throw "$Sh is Git's usr\bin shell, which finds Windows' timeout, find and sort; pass -Sh with Git for Windows' bin\sh.exe" }
$poll = Join-Path $WowHome 'bin\wow-review-poll' # the installed copy; install-host-tools.ps1 puts it there
foreach ($p in $WowHome, $poll, $Sh) {
  if ($p -match '["`$'']') { throw "path '$p' has a character the task command line cannot carry" }
}
# A Store install lives in a version-named folder that an update deletes; its execution alias survives.
$pwsh = (Get-Process -Id $PID).Path
if ($pwsh -like '*\WindowsApps\Microsoft.PowerShell_*') {
  $alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe'
  if (Test-Path -LiteralPath $alias) { $pwsh = $alias } else { Write-Warning "pwsh is a Store install and its alias $alias is missing; the task will break on the next PowerShell update" }
}

$cmd = "`$env:WOW_HOME = '$($WowHome.Replace('\', '/'))'; & '$Sh' '$($poll.Replace('\', '/'))'"
$arg = "-NoProfile -NonInteractive -WindowStyle Hidden -Command `"$cmd`""
# pwsh.exe is a console program: started directly, Windows opens its console window before -WindowStyle Hidden can hide it.
# conhost --headless runs it with no window. The system directory is .NET's, never a PATH lookup.
$conhost = Join-Path ([Environment]::SystemDirectory) 'conhost.exe'
if (-not (Test-Path -LiteralPath $conhost -PathType Leaf)) { throw "conhost.exe not found at $conhost; the task cannot start headless" }
$conArg = "--headless `"$pwsh`" $arg"
$action = New-ScheduledTaskAction -Execute $conhost -Argument $conArg

$user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$logon = New-ScheduledTaskTrigger -AtLogOn -User $user
$every = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)

$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 8)
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited

# Install the committed scripts (its checks refuse a dirty or unmerged checkout, and only after they pass does it
# stop this task), then register against the installed copy. Under -WhatIf the checks run; nothing is stopped,
# installed or registered.
$install = @{ WowHome = $WowHome; StopTask = $TaskName }
if ($SourceRepo) { $install.SourceRepo = $SourceRepo }
try { & (Join-Path $PSScriptRoot 'install-host-tools.ps1') @install }
catch {
  # The install stops the task only once its checks pass; if it then fails, bring back the task that was running.
  Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  throw
}
if (-not $WhatIfPreference -and -not (Test-Path -LiteralPath $poll -PathType Leaf)) {
  throw "the installer did not leave $poll; not registering a task for a missing file"
}

if ($PSCmdlet.ShouldProcess($TaskName, "Register scheduled task running: $conhost $conArg")) {
  Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($logon, $every) `
    -Settings $settings -Principal $principal -Force | Out-Null
  Start-ScheduledTask -TaskName $TaskName
  "registered $TaskName (logon, every $IntervalMinutes min); poll log: $(Join-Path $WowHome 'review-poll.log')"
}
