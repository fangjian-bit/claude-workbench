#Requires -Version 7.2
<#
.SYNOPSIS
  Host token broker: keeps each repo's dev token fresh and serves reviewer-token requests
  (WB-D24, issue #392). Registered as a scheduled task by register-broker-task.ps1.

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
  -RetrySeconds.

  Reviewer-token requests. A container may write an empty file named `reviewer-token` into
  $WowHome\req\<repo>\ (the request directory is its one writable mount). The broker deletes it,
  then runs wow-review-mint <repo> from this directory. The request's content is never read, and
  the repo comes from the directory name, so the requester chooses nothing but "now": no --out,
  no repo, no permission. The token lands in $WowHome\review-tokens\<repo>\reviewer-token, a tree
  no dev container mounts. At most one reviewer mint per repo per -ReviewMinGapSeconds: a request
  inside the gap stays in place and is served when the gap ends. While -SandboxRoot (default
  $env:REVIEW_SANDBOX_ROOT, the root review-sandbox.sh builds under) holds anything, requests
  wait, the same refusal review-token.sh makes. The root is resolved by sh with the same default
  (${TMPDIR:-/tmp}/review-sandbox), so it is checked even when the variable is unset; -SandboxRoot
  overrides it. A root that cannot be listed counts as occupied. Like review-token.sh's own check,
  it is only as good as the root matching the one the review session builds under: the broker
  resolves it once, in the task's environment. The broker also
  deletes a reviewer-token file older than -ReviewTtlMinutes, so a requested token's file does
  not sit on the host. A request that is not a plain file is ignored, never followed or removed.
  Who consumes this path is open (WB-D24 forbids mounting review-tokens/ into a dev container);
  review-token.sh calls wow-review-mint directly and does not use it.

  One bad repo or one failed file operation is logged and retried; it never stops the others.

  One broker runs at a time (an exclusive lock on $WowHome\broker.lock). Tokens are never logged
  or printed; $WowHome\broker.log carries timestamps, repo names and mint.sh's error line.

.PARAMETER Once
  One pass over every repo, then exit: 0 all current, 1 a mint failed, 2 bad configuration.
  Without it the broker loops every -PollSeconds until stopped.

.PARAMETER Sh
  The POSIX shell that runs mint.sh and wow-review-mint (Git for Windows' sh.exe). Default: the
  first sh on PATH. openssl, curl and jq must be on the PATH this process has.

.PARAMETER ScriptsDir
  Where mint.sh and wow-review-mint live. Default: this script's directory.
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
  [int]$ReviewMinGapSeconds = 30,
  [int]$ReviewTtlMinutes = 10,
  [string]$SandboxRoot = $env:REVIEW_SANDBOX_ROOT
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

# Test-SandboxPresent: $true if anything is under the review-sandbox root. Fails closed: a root that
# cannot be listed, or is a link, counts as occupied (review-token.sh makes the same refusal).
function Test-SandboxPresent {
  if (-not (Test-Path -LiteralPath $script:SandboxWin)) { return $false }
  try {
    if ((Get-Item -LiteralPath $script:SandboxWin -Force).LinkType) { return $true }
    @(Get-ChildItem -LiteralPath $script:SandboxWin -Force -ErrorAction Stop).Count -gt 0
  } catch { $true }
}

# Serve-Request <repo>: consume a reviewer-token request file, then mint. $true unless the mint failed.
function Serve-Request([string]$repo) {
  $req = Join-Path $WowHome "req/$repo/reviewer-token"
  $item = Get-Item -LiteralPath $req -Force -ErrorAction SilentlyContinue
  if (-not $item -or $item.PSIsContainer -or $item.LinkType -or $item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $true }
  # A request that must wait is left in place (and not logged again until the gap has passed).
  $last = $script:lastReview[$repo]
  if ($last -and ([DateTime]::UtcNow - $last).TotalSeconds -lt $ReviewMinGapSeconds) { return $true }
  if (Test-SandboxPresent) {
    $script:lastReview[$repo] = [DateTime]::UtcNow
    Write-Log "review $repo`: a review sandbox exists under $($script:SandboxWin); request waits"
    return $true
  }
  $script:lastReview[$repo] = [DateTime]::UtcNow
  Remove-Item -LiteralPath $req -Force
  $r = Invoke-Sh @((ToSh (Join-Path $ScriptsDir 'wow-review-mint')), $repo)
  if ($r.Code -ne 0) {
    Write-Log "review $repo`: mint failed (exit $($r.Code)): $($r.Text)"
    return $false
  }
  Write-Log "review $repo`: reviewer token minted on request"
  $true
}

# Expire-ReviewToken <repo>: delete this host's copy of the reviewer token once it is older than the TTL.
function Expire-ReviewToken([string]$repo) {
  $f = Join-Path $WowHome "review-tokens/$repo/reviewer-token"
  $item = Get-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
  if ($item -and -not $item.PSIsContainer -and ([DateTime]::UtcNow - $item.LastWriteTimeUtc).TotalMinutes -gt $ReviewTtlMinutes) {
    Remove-Item -LiteralPath $f -Force
    Write-Log "review $repo`: reviewer token file expired and removed"
  }
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
if (-not (Test-Path -LiteralPath $WowHome -PathType Container)) {
  Write-Error "WowHome $WowHome does not exist" -ErrorAction Continue
  exit 2
}
$script:ShPath = if ($Sh) { $Sh } else { (Get-Command sh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source }
if (-not $script:ShPath -or -not (Test-Path -LiteralPath $script:ShPath -PathType Leaf)) {
  Stop-Setup 'no POSIX sh found: pass -Sh (Git for Windows sh.exe)'
}
foreach ($s in 'mint.sh', 'wow-review-mint') {
  if (-not (Test-Path -LiteralPath (Join-Path $ScriptsDir $s) -PathType Leaf)) { Stop-Setup "$s not found in $ScriptsDir" }
}

# The sandbox root, resolved by the same shell and rule review-sandbox.sh and review-token.sh use
# (REVIEW_SANDBOX_ROOT, else ${TMPDIR:-/tmp}/review-sandbox), then made a Windows path where cygpath
# exists. -SandboxRoot overrides the variable and may be in either form.
if ($SandboxRoot) { $env:REVIEW_SANDBOX_ROOT = $SandboxRoot }
$resolved = & $script:ShPath -c 'r=${REVIEW_SANDBOX_ROOT:-${TMPDIR:-/tmp}/review-sandbox}; cygpath -w "$r" 2>/dev/null || printf "%s" "$r"' 2>$null
$script:SandboxWin = ("$resolved").Trim()
if (-not $script:SandboxWin) { Stop-Setup 'cannot resolve the review sandbox root' }
if (-not [IO.Path]::IsPathFullyQualified($script:SandboxWin)) {
  Stop-Setup "the review sandbox root '$($script:SandboxWin)' is not a full Windows path (relative, or sh has no cygpath)"
}

try {
  $lock = [IO.File]::Open((Join-Path $WowHome 'broker.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
} catch {
  Write-Log 'another broker holds broker.lock; exiting'
  Write-Error 'another broker holds broker.lock' -ErrorAction Continue
  exit $(if ($Once) { 1 } else { 0 }) # a second scheduled start is not a failure
}

$script:lastReview = @{}
$retryAt = @{}
$exit = 0
try {
  Write-Log 'broker started'
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
        # a failed dev mint waits out the retry gap; a reviewer request is still served
        try { $ok = Update-DevToken $repo } catch { Write-Log "dev $repo`: $($_.Exception.Message)"; $ok = $false }
        if (-not $ok) { $retryAt[$repo] = [DateTime]::UtcNow.AddSeconds($RetrySeconds); $failed = $true }
      }
      try { if (-not (Serve-Request $repo)) { $failed = $true } }
      catch { Write-Log "review $repo`: $($_.Exception.Message)"; $failed = $true }
      try { Expire-ReviewToken $repo } catch { Write-Log "review $repo`: $($_.Exception.Message)" }
    }
    if ($Once) { if ($failed) { $exit = 1 }; break }
    Start-Sleep -Seconds $PollSeconds
  }
} finally {
  $lock.Dispose()
}
exit $exit
