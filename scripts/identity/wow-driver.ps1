#Requires -Version 7.2
<#
.SYNOPSIS
  Start the driver session in the claude-workbench dev container, after the checks that must come
  first (WB-D24, WB-D33, issue #728). Run it from pwsh 7.2+ on the host, from the installed copy in
  $WOW_HOME\bin (install-host-tools.ps1), never from a checkout.

.DESCRIPTION
  Two paths, chosen by the clone's containers: those on its <leaf>-tmp volume, plus those whose
  devcontainer.local_folder label names it (docker ps -a, every state).

  Start of day (no container, or one stopped container), in order:
    1. compares the clone's .devcontainer/ with the committed copy at <Remote>/<Base>, read from the
       Reference clone, a different clone: same files, same bytes, no link anywhere;
    2. recreates the container: devcontainer up --skip-post-attach --remove-existing-container;
    3. checks that exactly the container up reported is running;
    4. records its id, the commit compared against and the clone's path in
       <WowHome>\driver\<leaf>.json (never mounted into a container);
    5. enters it with docker exec, into /usr/local/bin/claude --model <models.architect> --effort medium
       in /workspace.

  Attach (the driver restarted while lanes run in the same container): when the one running container
  is the one the record names, runs the relay probe and enters it with docker exec. No compare, no up,
  no recreate, so the lanes are undisturbed. An attached container runs the configuration of the
  commit it was created from; the launcher prints that commit and warns when .devcontainer/ has changed
  since. It still fetches the Reference clone for the model, so an offline restart refuses.

  Anything else refuses and says what to run. docker exec reads no host copy of
  .devcontainer/devcontainer.json, which a running container can rewrite; devcontainer exec does
  (WB-D33). The docker exec literals are that file's remoteUser (app) and remoteEnv
  (GIT_TERMINAL_PROMPT=0); tests/identity-launchers.test.sh holds the two equal.

  Exit codes: 2 for a bad or missing argument (a usage line on stderr, before any external call);
  1 for every refusal (a one-line reason on stderr); otherwise the session's own exit code.
  PowerShell's own binding errors (an unknown parameter, a stray positional argument) exit 1 with
  PowerShell's message.

  Honest limit. The MANIFEST check below catches running from a checkout by mistake. It is not a
  boundary: whoever can write this script can write the MANIFEST. A container that can write the
  Reference clone can plant git config or hooks that run when this script runs git there, which is
  host code execution beside the App keys; the Reference must be a clone no container opens. git
  never runs in the Clone, whose .git a container can write.

.PARAMETER Clone
  The clone the container opens: an absolute existing directory, not a link, whose leaf is the
  Docker volume-name rule and whose path holds only letters, digits, space, . _ - and separators
  (devcontainer.cmd re-parses & | ^ % and " through cmd.exe).

.PARAMETER Reference
  A different full clone that no container opens (for example the one install-host-tools.ps1 installs
  from): its .git a directory, not a file. It supplies the committed .devcontainer/ and models.architect.

.PARAMETER WowHome
  Default: $env:WOW_HOME, else $HOME/.config/glunk-identity. The Clone may not contain it.

.PARAMETER Remote
  Default origin.

.PARAMETER Base
  Default main.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
  [string]$Clone,
  [string]$Reference,
  [string]$WowHome = $(if ($env:WOW_HOME) { $env:WOW_HOME } else { Join-Path $HOME '.config/glunk-identity' }),
  [string]$Remote = 'origin',
  [string]$Base = 'main'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The installed-copy guard: before the helper is dot-sourced, and before anything else runs.
$notInstalled = {
  [Console]::Error.WriteLine('wow-driver: run the installed copy in $WOW_HOME/bin (install-host-tools.ps1)')
  exit 1
}
try {
  $manifestPath = Join-Path $PSScriptRoot 'MANIFEST'
  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { & $notInstalled }
  $manifest = [IO.File]::ReadAllText($manifestPath).Split("`n") | ForEach-Object { $_.TrimEnd("`r") }
  if (@($manifest)[0] -cnotmatch '\Acommit [0-9a-f]{40}\z') { & $notInstalled }
  foreach ($name in 'wow-driver.ps1', 'wow-launch-common.ps1') {
    $own = Join-Path $PSScriptRoot $name
    $rows = @($manifest | Where-Object { $_ -cmatch '\A[0-9a-f]{64}  ' -and $_.Substring(66) -ceq $name })
    if ($rows.Count -ne 1 -or -not (Test-Path -LiteralPath $own -PathType Leaf)) { & $notInstalled }
    if ($rows[0].Substring(0, 64) -cne (Get-FileHash -LiteralPath $own -Algorithm SHA256).Hash.ToLowerInvariant()) { & $notInstalled }
  }
} catch { & $notInstalled }

$script:LaunchProg = 'wow-driver'
$script:LaunchUsage = 'usage: wow-driver.ps1 -Clone <path> -Reference <path> [-WowHome <path>] [-Remote <name>] [-Base <name>]'
. (Join-Path $PSScriptRoot 'wow-launch-common.ps1')

try {
  # --- arguments: exit 2, before any external call ---------------------------------------------
  $cloneP = Resolve-LaunchDir '-Clone' $Clone
  $refP = Resolve-LaunchDir '-Reference' $Reference
  $gitDir = Join-Path $refP '.git'
  if (-not (Test-Path -LiteralPath $gitDir -PathType Container)) { Stop-BadArgument '-Reference needs a .git directory (not a file, so not a worktree)' }
  if (Test-ReparsePoint $gitDir) { Stop-BadArgument "-Reference's .git is a link or reparse point" }
  if ((Test-PathInside $cloneP $refP) -or (Test-PathInside $refP $cloneP)) { Stop-BadArgument '-Clone and -Reference may not be, or contain, one another' }
  $wowP = Resolve-LaunchDir '-WowHome' $WowHome -Plain
  if ((Test-PathInside $cloneP $wowP) -or (Test-PathInside $wowP $cloneP)) { Stop-BadArgument '-Clone may not be, contain or sit inside -WowHome' }
  if (-not (Test-RefName $Remote)) { Stop-BadArgument '-Remote is not a plain ref name' }
  if (-not (Test-RefName $Base)) { Stop-BadArgument '-Base is not a plain ref name' }
  $leaf = [IO.Path]::GetFileName($cloneP)
  $refLeaf = [IO.Path]::GetFileName($refP)
  if ($leaf -ieq $refLeaf) { Stop-BadArgument '-Clone and -Reference may not share a folder name: they would share the <leaf>-tmp volume' }

  # --- installed from bin under the final WowHome -------------------------------------------------
  $binWant = Join-Path $wowP 'bin'
  if ((Format-PathKey (Get-FinalPath $PSScriptRoot)) -ne (Format-PathKey $binWant)) { & $notInstalled }

  $git = Resolve-Tool 'git'
  $docker = Resolve-Tool 'docker'
  $devcontainer = Resolve-Tool 'devcontainer'
  $yq = Resolve-Tool 'yq'

  # --- the Clone's containers: which path --------------------------------------------------------
  $mine = @(Get-LaunchContainers $docker $cloneP $leaf)
  Assert-KnownStates $mine
  $running = @($mine | Where-Object { $_.State -ceq 'running' })
  if ($mine.Count -eq 0 -or ($mine.Count -eq 1 -and $running.Count -eq 0)) { $mode = 'start' }
  elseif ($mine.Count -eq 1) { $mode = 'attach' }
  else {
    $ids = ($mine | ForEach-Object { "$($_.Id) ($($_.State))" }) -join ', '
    Stop-Launch "found $($mine.Count) containers for this clone: $ids. docker stop the running one, docker rm every leftover (such as one VS Code made), then rerun at start of day"
  }

  # --- the Reference: no container may open it, then commit and model -------------------------------
  $refBusy = @(Get-LaunchContainers $docker $refP $refLeaf)
  if ($refBusy.Count -gt 0) {
    Stop-Launch "the Reference clone is in use by container $($refBusy[0].Id): the Reference must be a clone no container opens"
  }
  $commit = Get-ReferenceCommit $git $refP $Remote $Base
  $model = Get-RoleModel $git $yq $refP $commit 'architect'
  $record = Get-RecordPath $wowP $leaf

  if ($mode -eq 'start') {
    # 1. compare
    Test-DevTree $git $refP $cloneP $commit
    # 2. recreate
    $up = Invoke-Tool $devcontainer @('up', '--skip-post-attach', '--remove-existing-container', '--workspace-folder', $cloneP) -InheritStderr
    if ($up.Code -ne 0) { Stop-Launch "devcontainer up failed (exit $($up.Code))" }
    $lines = @([Text.Encoding]::UTF8.GetString($up.Out).Split("`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($lines.Count -eq 0) { Stop-Launch 'devcontainer up printed no result' }
    $last = $lines[-1]
    try { $res = $last | ConvertFrom-Json -ErrorAction Stop } catch { Stop-Launch 'devcontainer up printed no JSON result' }
    if ($res -isnot [pscustomobject] -or -not $res.PSObject.Properties['outcome'] -or -not $res.PSObject.Properties['containerId']) {
      Stop-Launch 'devcontainer up result lacks outcome or containerId'
    }
    if ($res.outcome -isnot [string] -or $res.outcome -cne 'success') { Stop-Launch 'devcontainer up did not report success' }
    if ($res.containerId -isnot [string] -or -not (Test-Hex $res.containerId 64)) { Stop-Launch 'devcontainer up reported a malformed container id' }
    $id = $res.containerId
    # 3. exactly that container, running
    $after = @(Get-LaunchContainers $docker $cloneP $leaf)
    Assert-KnownStates $after
    if ($after.Count -ne 1 -or $after[0].Id -cne $id -or $after[0].State -cne 'running') {
      $ids = ($after | ForEach-Object { "$($_.Id) ($($_.State))" }) -join ', '
      Stop-Launch "after up, expected only $id running, found: $(if ($ids) { $ids } else { 'none' }). docker stop the new container ($id) and docker rm any other, then rerun"
    }
    # 4. record
    Write-Record $record $id $commit $cloneP
    Write-LaunchLine "started $id from $commit"
  } else {
    # attach
    $rec = Read-Record $record
    if ($null -eq $rec) { Stop-Launch "no driver record at $record for the running container: stop it (docker stop $($mine[0].Id)), then rerun at start of day" }
    if ((Format-PathKey $rec.clone) -ne (Format-PathKey $cloneP)) { Stop-Launch 'the driver record names another clone: no two checkouts may share a folder name' }
    $id = $mine[0].Id
    if ($rec.id -cne $id) { Stop-Launch "the running container $id is not the recorded one ($($rec.id)): stop it (docker stop $id), then rerun at start of day" }
    Test-RelayProbe $docker $id
    Write-LaunchLine "attaching to $id, created from $($rec.commit)"
    $then = Get-DevTreeId $git $refP $rec.commit
    $now = Get-DevTreeId $git $refP $commit
    if ($null -eq $now) { Stop-Launch ".devcontainer/ cannot be read at $commit in the Reference clone" }
    if ($null -eq $then) { Write-LaunchLine "the .devcontainer/ tree at $($rec.commit) is unknown to the Reference clone" }
    elseif ($then -cne $now) {
      Write-LaunchLine "$Base's .devcontainer/ has changed since: recreate the container at start of day once the lanes are done"
    }
  }

  $code = Invoke-Session $docker @('exec', '-it', '-u', 'app', '-e', 'GIT_TERMINAL_PROMPT=0', '-w', '/workspace', $id,
    '/usr/local/bin/claude', '--model', $model, '--effort', 'medium')
} catch {
  Stop-Launch $_.Exception.Message
}
exit $code
