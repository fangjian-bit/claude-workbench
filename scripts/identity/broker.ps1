#Requires -Version 7.2
<#
.SYNOPSIS
  Host token broker: keeps each repo's dev token fresh (WB-D24, issue #392). Installed with the
  other host scripts by install-host-tools.ps1 and registered as a scheduled task by
  register-broker-task.ps1; it runs from $WowHome\bin, never from a checkout.

.DESCRIPTION
  Runs on the host, where the App keys live; no key is ever copied into a container.

  Dev tokens. For every repo named in $WowHome\broker.json ({"repos": ["name", ...]}) the broker
  keeps $WowHome\tokens\<repo>\dev-token current: the token on one line, its expires_at on the
  next, the format token-check.sh and the container's gh shim read. A token is minted when the
  file is missing, malformed, expired, or has 30 minutes or less left (-RefreshMinutes). Dev
  tokens live an hour, so that is a new token every ~30 minutes, and it is a property of the
  file, not of a timer: a token that expired while the machine slept is replaced on the first
  pass after wake or logon. The mint is scripts/identity/mint.sh with the "dev" entry of
  apps.json (client_id, installation_id, key = a bare PEM filename in $WowHome, unencrypted so
  it can run unattended, like review.pem) and the dev App's permissions only.

  Atomic write. mint.sh writes to $WowHome\staging\<repo>\, the broker checks the result is
  token-shaped and still live, then publishes it with [IO.File]::Move(src, dst, overwrite) on the
  same volume, so a reader sees the old token or the new one, never a partial file. A failed mint
  leaves the old token in place (it stays valid until it expires) and is retried after
  -RetrySeconds. Docker Desktop may hold a token file open and make the move fail with a sharing
  violation; that is logged and retried, not an error to chase.

  Reviewer tokens. The broker mints none: review-token.sh (the host review flow) calls
  wow-review-mint itself, and a reviewer token never reaches a dev container (WB-D24; reviewer and
  author are separate identities). There is deliberately no request channel for containers, so
  nothing under $WowHome is container-writable. The broker's only part is cleanup: every pass it
  deletes any $WowHome\review-tokens\<repo>\reviewer-token older than -ReviewTtlMinutes, for any
  repo, which covers a review session killed before it ran `review-token.sh discard`.

  Review sessions and logs (#634). The sweep also removes, under $WowHome\review-sessions\,
  each session directory whose name passes the repository-name rule, that is not a link or
  junction and holds none at any depth (one that does is left, and logged once per broker
  process), and whose session-token is older than -ReviewSessionMinutes (when that file is
  absent, the directory itself is). It assumes a live session re-mints session-token, and its
  run ends, well inside -ReviewSessionMinutes. In $WowHome\review-logs\, top level only, it
  removes regular, non-link files older than -ReviewLogDays. The logs may hold secrets, and the
  sweep is cleanup, not an exposure limit: a token expires on its own clock.

  One bad repo or one failed file operation is logged and retried; it never stops the others.

  One broker runs at a time (an exclusive lock on $WowHome\broker.lock). Tokens are never logged
  or printed; $WowHome\broker.log carries timestamps, repo names and mint.sh's error line.

.PARAMETER Once
  One pass over every repo, then exit: 0 all current, 1 a mint failed, 2 bad configuration.
  Without it the broker loops every -PollSeconds until stopped.

.PARAMETER ReviewSessionMinutes
  Age past which a review session directory under $WowHome\review-sessions is removed (default
  120), as -ReviewTtlMinutes is for reviewer tokens.

.PARAMETER ReviewLogDays
  Age in days past which a top-level file under $WowHome\review-logs is removed (default 7).

.PARAMETER Sh
  The POSIX shell that runs mint.sh (Git for Windows' sh.exe). Default: the first sh on PATH.
  openssl, curl and jq must be on the PATH this process has.

.PARAMETER ScriptsDir
  Where mint.sh lives. Default: this script's directory.

.PARAMETER WowHome
  The identity directory (default $env:WOW_HOME, else ~/.config/glunk-identity). A value in MSYS
  form (/c/Users/...), as review-token.sh needs, is converted with the shell's cygpath. One home
  holds one org's Apps (apps.json has one "dev" entry); a second org needs a second home, a second
  broker.json and a second task (-TaskName in register-broker-task.ps1).
#>
[CmdletBinding()]
param(
  [string]$WowHome = $(if ($env:WOW_HOME) { $env:WOW_HOME } else { Join-Path $HOME '.config/glunk-identity' }),
  [string]$Sh,
  [string]$ScriptsDir = $PSScriptRoot,
  [switch]$Once,
  [int]$RefreshMinutes = 30,
  [int]$PollSeconds = 5,
  [int]$RetrySeconds = 60,
  [int]$ReviewTtlMinutes = 10,
  [int]$ReviewSessionMinutes = 120,
  [int]$ReviewLogDays = 7
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$devPerms = 'contents=write,pull_requests=write,issues=write,checks=read,actions=read,statuses=read'
$bare = '^[A-Za-z0-9._-]+$'

function ToSh([string]$p) { $p.Replace('\', '/') } # dirname and [ -r ] in MSYS sh want forward slashes

function Write-Log([string]$msg) {
  $log = Join-Path $WowHome 'broker.log'
  try {
    if ((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -gt 1MB) {
      Move-Item -LiteralPath $log -Destination "$log.1" -Force
    }
    $line = '{0:yyyy-MM-ddTHH:mm:ssZ} {1}' -f [DateTime]::UtcNow, ($msg -replace '[\x00-\x1f]', ' ')
    Add-Content -LiteralPath $log -Value $line
  } catch { } # a log that cannot be written must not stop the broker
}

function Test-RepoName([string]$n) {
  $n -match '\A[A-Za-z0-9._-]+\z' -and $n -notmatch '\A[-.]' -and $n -notmatch '\.\z'
}

# Read-Token <file>: @{ Expires = [DateTimeOffset] } for a token-shaped file, else $null. The shape is
# token-check.sh's: the token, LF, the expires_at, LF -- no CR, no blank line, nothing else.
function Read-Token([string]$path) {
  try {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $text = [IO.File]::ReadAllText($path)
    if ($text -cnotmatch '\Aghs_[A-Za-z0-9._-]{36,}\n[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\n\z') { return $null }
    $exp = [DateTimeOffset]::MinValue
    $ok = [DateTimeOffset]::TryParseExact($text.Split("`n")[1], "yyyy-MM-dd'T'HH:mm:ss'Z'",
      [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$exp)
    if (-not $ok) { return $null }
    return @{ Expires = $exp }
  } catch { return $null }
}

# Get-AppField <role> <field>: a bare value from apps.json, or $null (same rule as wow-common.sh app_get).
function Get-AppField([string]$role, [string]$field) {
  $f = Join-Path $WowHome 'apps.json'
  if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { return $null }
  try { $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json } catch { return $null }
  $app = $j.PSObject.Properties[$role]
  if (-not $app) { return $null }
  $v = $app.Value.PSObject.Properties[$field]
  if (-not $v -or $null -eq $v.Value) { return $null }
  $s = "$($v.Value)".Trim()
  if ($s -notmatch $bare) { return $null }
  $s
}

# Invoke-Sh <args...>: run the POSIX shell, return @{ Code; Text } with output trimmed for the log.
function Invoke-Sh([string[]]$shArgs) {
  $env:WOW_HOME = ToSh $WowHome
  $out = & $script:ShPath @shArgs 2>&1
  $code = $LASTEXITCODE
  $text = (@($out) | ForEach-Object { "$_" }) -join ' '
  if ($text.Length -gt 300) { $text = $text.Substring(0, 300) }
  @{ Code = $code; Text = $text }
}

function Update-DevToken([string]$repo) {
  $dst = Join-Path $WowHome "tokens/$repo/dev-token"
  $cur = Read-Token $dst
  $now = [DateTimeOffset]::UtcNow
  if ($cur -and ($cur.Expires - $now).TotalMinutes -gt $RefreshMinutes) { return $true }

  $cid = Get-AppField 'dev' 'client_id'
  $iid = Get-AppField 'dev' 'installation_id'
  $keyName = Get-AppField 'dev' 'key'
  if (-not $cid -or -not $iid -or -not $keyName -or $keyName -match '^[-.]') {
    Write-Log "dev $repo`: dev client_id / installation_id / key missing or unusable in apps.json"
    return $false
  }
  $key = Join-Path $WowHome $keyName
  if (-not (Test-Path -LiteralPath $key -PathType Leaf)) {
    Write-Log "dev $repo`: dev key file $keyName not found"
    return $false
  }

  $stageDir = Join-Path $WowHome "staging/$repo"
  $null = New-Item -ItemType Directory -Force -Path $stageDir, (Split-Path $dst)
  $stage = Join-Path $stageDir 'dev-token'
  Remove-Item -LiteralPath $stage -Force -ErrorAction SilentlyContinue

  $r = Invoke-Sh @((ToSh (Join-Path $ScriptsDir 'mint.sh')),
    '--client-id', $cid, '--installation-id', $iid, '--key', (ToSh $key),
    '--repos', $repo, '--perms', $devPerms, '--out', (ToSh $stage))
  if ($r.Code -ne 0) {
    Remove-Item -LiteralPath $stage -Force -ErrorAction SilentlyContinue
    Write-Log "dev $repo`: mint failed (exit $($r.Code)): $($r.Text)"
    return $false
  }
  $new = Read-Token $stage
  if (-not $new -or ($new.Expires - [DateTimeOffset]::UtcNow).TotalMinutes -le 0) {
    Remove-Item -LiteralPath $stage -Force -ErrorAction SilentlyContinue
    Write-Log "dev $repo`: minted file is not a live token; keeping the old one"
    return $false
  }
  [IO.File]::Move($stage, $dst, $true)
  Write-Log "dev $repo`: token rotated, expires $($new.Expires.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
  $true
}


# Expire-ReviewTokens: delete every repo's reviewer-token file older than the TTL. Walks the directory,
# not broker.json, so a repo dropped from the config is still cleaned. Links are never followed.
function Expire-ReviewTokens {
  $root = Join-Path $WowHome 'review-tokens'
  if (-not (Test-Path -LiteralPath $root -PathType Container)) { return }
  foreach ($d in @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue)) {
    if ($d.LinkType -or -not (Test-RepoName $d.Name)) { continue }
    $f = Join-Path $d.FullName 'reviewer-token'
    $item = Get-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
    if ($item -and -not $item.PSIsContainer -and ([DateTime]::UtcNow - $item.LastWriteTimeUtc).TotalMinutes -gt $ReviewTtlMinutes) {
      try {
        Remove-Item -LiteralPath $f -Force
        Write-Log "review $($d.Name)`: reviewer token file expired and removed"
      } catch { Write-Log "review $($d.Name)`: $($_.Exception.Message)" }
    }
  }
}

# Test-HasLink <dir>: $true when the directory holds a link or junction at any depth. Never descends
# into a link. Throws when something cannot be listed, which the caller treats as "leave it".
function Test-HasLink([string]$dir) {
  foreach ($c in @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop)) {
    if ($c.LinkType) { return $true }
    if ($c.PSIsContainer -and (Test-HasLink $c.FullName)) { return $true }
  }
  $false
}

$script:LinkLogged = @{}

# Expire-ReviewSessions: remove review session directories whose session-token (or, with none, the
# directory) is older than -ReviewSessionMinutes, and review logs older than -ReviewLogDays. A session
# that is, or contains, a link or junction is left alone: Remove-Item must never be pointed through one.
function Expire-ReviewSessions {
  $root = Join-Path $WowHome 'review-sessions'
  if ((Test-Path -LiteralPath $root -PathType Container) -and -not (Get-Item -LiteralPath $root -Force).LinkType) {
    foreach ($d in @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue)) {
      if ($d.LinkType -or -not (Test-RepoName $d.Name)) { continue }
      try {
        if (Test-HasLink $d.FullName) {
          if (-not $script:LinkLogged[$d.Name]) {
            $script:LinkLogged[$d.Name] = $true
            Write-Log "review-session $($d.Name)`: holds a link or junction; left in place"
          }
          continue
        }
        $tok = Get-Item -LiteralPath (Join-Path $d.FullName 'session-token') -Force -ErrorAction SilentlyContinue
        $stamp = if ($tok -and -not $tok.PSIsContainer) { $tok.LastWriteTimeUtc } else { $d.LastWriteTimeUtc }
        if (([DateTime]::UtcNow - $stamp).TotalMinutes -gt $ReviewSessionMinutes) {
          Remove-Item -LiteralPath $d.FullName -Recurse -Force
          Write-Log "review-session $($d.Name)`: expired and removed"
        }
      } catch { Write-Log "review-session $($d.Name)`: $($_.Exception.Message)" }
    }
  }
  $logs = Join-Path $WowHome 'review-logs'
  if ((Test-Path -LiteralPath $logs -PathType Container) -and -not (Get-Item -LiteralPath $logs -Force).LinkType) {
    foreach ($f in @(Get-ChildItem -LiteralPath $logs -File -Force -ErrorAction SilentlyContinue)) {
      if ($f.LinkType) { continue }
      if (([DateTime]::UtcNow - $f.LastWriteTimeUtc).TotalDays -gt $ReviewLogDays) {
        try { Remove-Item -LiteralPath $f.FullName -Force } catch { Write-Log "review-log $($f.Name)`: $($_.Exception.Message)" }
      }
    }
  }
}

# Get-ManifestCommit: the commit install-host-tools.ps1 recorded for this install, for the log. Never trusted for anything.
function Get-ManifestCommit {
  $m = Join-Path $ScriptsDir 'MANIFEST'
  if (-not (Test-Path -LiteralPath $m -PathType Leaf)) { return 'none (not an installed copy)' }
  $l = Get-Content -LiteralPath $m | Where-Object { $_ -match '^commit ' } | Select-Object -First 1
  if ($l -match '^commit ([0-9a-f]{7,40})$') { $Matches[1] } else { 'unreadable' }
}

function Get-Repos {
  $f = Join-Path $WowHome 'broker.json'
  if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "no broker.json in $WowHome" }
  $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
  $repos = @($j.repos)
  if ($repos.Count -eq 0) { throw 'broker.json names no repos' }
  foreach ($r in $repos) {
    if ($r -isnot [string] -or -not (Test-RepoName $r)) { throw "broker.json: bad repository name '$r'" }
  }
  $repos
}

# --- start up ------------------------------------------------------------------------------
function Stop-Setup([string]$msg) {
  # Under the task there is no console, so a setup failure goes to the log as well.
  Write-Log "setup: $msg"
  Write-Error $msg -ErrorAction Continue
  exit 2
}
$script:ShPath = $Sh
if (-not $script:ShPath) {
  $found = Get-Command sh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($found) { $script:ShPath = $found.Source }
}
if ($script:ShPath -and $WowHome.StartsWith('/') -and (Test-Path -LiteralPath $script:ShPath -PathType Leaf)) {
  $conv = (& $script:ShPath -c 'cygpath -w "$1"' sh $WowHome 2>$null)
  if ($conv) { $WowHome = ("$conv").Trim() }
}
if (-not (Test-Path -LiteralPath $WowHome -PathType Container)) {
  Write-Error "WowHome $WowHome does not exist" -ErrorAction Continue
  exit 2
}
if (-not $script:ShPath -or -not (Test-Path -LiteralPath $script:ShPath -PathType Leaf)) {
  Stop-Setup 'no POSIX sh found: pass -Sh (Git for Windows sh.exe)'
}
if (-not (Test-Path -LiteralPath (Join-Path $ScriptsDir 'mint.sh') -PathType Leaf)) { Stop-Setup "mint.sh not found in $ScriptsDir" }

try {
  $lock = [IO.File]::Open((Join-Path $WowHome 'broker.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
} catch {
  Write-Log 'another broker holds broker.lock; exiting'
  Write-Error 'another broker holds broker.lock' -ErrorAction Continue
  exit $(if ($Once) { 1 } else { 0 }) # a second scheduled start is not a failure
}

$retryAt = @{}
$exit = 0
try {
  Write-Log "broker started, installed from commit $(Get-ManifestCommit)"
  while ($true) {
    $failed = $false
    try {
      $repos = Get-Repos
    } catch {
      if ($Once) { Write-Log "config: $($_.Exception.Message)"; Write-Error $_.Exception.Message -ErrorAction Continue; $exit = 2; break }
      if (-not $retryAt['*'] -or [DateTime]::UtcNow -ge $retryAt['*']) {
        Write-Log "config: $($_.Exception.Message)"
        $retryAt['*'] = [DateTime]::UtcNow.AddSeconds($RetrySeconds)
      }
      $repos = @()
    }
    foreach ($repo in $repos) {
      # Each step is its own try: a throw (a held file, a swapped directory) is logged, never fatal.
      if (-not ($retryAt[$repo] -and [DateTime]::UtcNow -lt $retryAt[$repo] -and -not $Once)) {
        # a failed dev mint waits out the retry gap
        try { $ok = Update-DevToken $repo } catch { Write-Log "dev $repo`: $($_.Exception.Message)"; $ok = $false }
        if (-not $ok) { $retryAt[$repo] = [DateTime]::UtcNow.AddSeconds($RetrySeconds); $failed = $true }
      }
    }
    try { Expire-ReviewTokens } catch { Write-Log "review: $($_.Exception.Message)" }
    try { Expire-ReviewSessions } catch { Write-Log "review-sessions: $($_.Exception.Message)" }
    if ($Once) { if ($failed) { $exit = 1 }; break }
    Start-Sleep -Seconds $PollSeconds
  }
} finally {
  $lock.Dispose()
}
exit $exit
