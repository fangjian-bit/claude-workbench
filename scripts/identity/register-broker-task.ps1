#Requires -Version 7.2
<#
.SYNOPSIS
  Install (or remove) the scheduled task that runs broker.ps1 (WB-D24, issue #392).

.DESCRIPTION
  Registers a per-user task, run as the current user with limited rights (the broker needs only
  the user's own $WowHome, never elevation), that starts broker.ps1:
    - at logon,
    - on wake from sleep (Power-Troubleshooter event 1),
    - every 30 minutes, which restarts a broker that died; a running one is left alone,
  with "run as soon as possible after a missed start" on, no run-time limit, no stop on battery,
  and a second start ignored while one runs. The broker itself loops and refreshes a dev token
  whenever 30 minutes or less remain, so a missed or late start costs at most the gap until the
  next trigger. The task starts it once at registration too.

  The task does not run from a checkout. It installs the host scripts into $WowHome\bin with
  install-host-tools.ps1 (committed code on origin/main only, with a MANIFEST of the commit and
  hashes) and registers the task against those copies, so a container editing a bind-mounted
  checkout cannot change what runs beside the App keys. Re-run this to upgrade; it stops the
  task, reinstalls and restarts it. Run it from a clone no container opens.
  A $WOW_HOME in MSYS form (/c/Users/...), as the host shell scripts need, is converted with cygpath.

  Run it from a PowerShell 7.2+ prompt on the host, once. The sh it records is resolved now (or
  -Sh), because a task does not search the same PATH an interactive shell does; openssl, curl
  and jq must be on the user's PATH. -Unregister removes the task. -WhatIf shows what would be
  registered.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [string]$WowHome = $(if ($env:WOW_HOME) { $env:WOW_HOME } else { Join-Path $HOME '.config/glunk-identity' }),
  [string]$Sh,
  [string]$SourceRepo,
  [string]$TaskName = 'glunk-wow-broker',
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
if (-not (Test-Path -LiteralPath $WowHome -PathType Container)) { throw "WowHome $WowHome does not exist; create it and its apps.json and broker.json first" }
# Full paths, no trailing backslash (it would escape the closing quote on the task's command line).
$WowHome = (Resolve-Path -LiteralPath $WowHome).ProviderPath.TrimEnd('\')
$Sh = (Resolve-Path -LiteralPath $Sh).ProviderPath
$broker = Join-Path $WowHome 'bin\broker.ps1' # the installed copy; install-host-tools.ps1 puts it there
foreach ($p in $WowHome, $broker, $Sh) {
  if ($p -match '["`$]') { throw "path '$p' has a character the task command line cannot carry" }
}
# A Store install lives in a version-named folder that an update deletes; its execution alias survives.
$pwsh = (Get-Process -Id $PID).Path
if ($pwsh -like '*\WindowsApps\Microsoft.PowerShell_*') {
  $alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe'
  if (Test-Path -LiteralPath $alias) { $pwsh = $alias } else { Write-Warning "pwsh is a Store install and its alias $alias is missing; the task will break on the next PowerShell update" }
}

$arg = "-NoProfile -NonInteractive -WindowStyle Hidden -File `"$broker`" -WowHome `"$WowHome`" -Sh `"$Sh`""
$action = New-ScheduledTaskAction -Execute $pwsh -Argument $arg

$user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$logon = New-ScheduledTaskTrigger -AtLogOn -User $user
$every = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 30)
$wakeClass = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler
$wake = New-CimInstance -CimClass $wakeClass -ClientOnly
$wake.Enabled = $true
$wake.Subscription = '<QueryList><Query Id="0" Path="System"><Select Path="System">*[System[Provider[@Name=''Microsoft-Windows-Power-Troubleshooter''] and EventID=1]]</Select></Query></QueryList>'

$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) `
  -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited

# Install the committed scripts (its checks refuse a dirty or unmerged checkout, and only after they pass does it
# stop the running broker), then register against the installed copy. Under -WhatIf the checks run (and the fetch
# updates the source clone's origin ref); nothing is stopped, installed or registered.
$install = @{ WowHome = $WowHome; StopTask = $TaskName }
if ($SourceRepo) { $install.SourceRepo = $SourceRepo }
try { & (Join-Path $PSScriptRoot 'install-host-tools.ps1') @install }
catch {
  # The install stops the task only once its checks pass; if it then fails, bring back the broker that was running.
  Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  throw
}
if (-not $WhatIfPreference -and -not (Test-Path -LiteralPath $broker -PathType Leaf)) {
  throw "the installer did not leave $broker; not registering a task for a missing file"
}

if ($PSCmdlet.ShouldProcess($TaskName, "Register scheduled task running: $pwsh $arg")) {
  Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($logon, $wake, $every) `
    -Settings $settings -Principal $principal -Force | Out-Null
  Start-ScheduledTask -TaskName $TaskName
  "registered $TaskName (logon, wake, every 30 min); broker log: $(Join-Path $WowHome 'broker.log')"
}
