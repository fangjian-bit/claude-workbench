#Requires -Version 7.2
<#
.SYNOPSIS
  Shared helpers for the host launchers wow-driver.ps1 and (#762) wow-lane.ps1 (WB-D24, WB-D33,
  issue #728). Dot-sourced, never run.

.DESCRIPTION
  Functions only, with no top-level statements: a launcher dot-sources this file only after its own
  inline MANIFEST check, and nothing here runs before that check. Like the launchers it runs only
  from the installed copy in $WOW_HOME/bin (install-host-tools.ps1), never from a checkout.

  What is here: the argument checks and the canonical-path resolution; tool resolution; the two
  process runners (every external call goes through ProcessStartInfo.ArgumentList, one element per
  argument, never a joined string); the commit and model read from the Reference clone; the in-process
  git blob id; the strict record read and the atomic record write; the two container listings; the
  relay probe. The launcher sets $script:LaunchProg and $script:LaunchUsage before calling any of it.

  Honest limit. Everything above is an accident guard. If a container can write the Reference clone
  it can plant git config or hooks that run when git runs there; the control is a Reference clone no
  container opens. #762 relies on this file's id validation and may reuse the record to attach lanes.
#>

# Stop-Launch <message> [code]: one line on stderr, then exit. Anything outside printable ASCII
# becomes '?', so a file name from the clone cannot send escape sequences to the terminal.
function Stop-Launch([string]$Message, [int]$Code = 1) {
  $safe = [regex]::Replace($Message, '[^\x20-\x7E]', '?')
  [Console]::Error.WriteLine("$($script:LaunchProg): $safe")
  if ($Code -eq 2) { [Console]::Error.WriteLine($script:LaunchUsage) }
  exit $Code
}

function Stop-BadArgument([string]$Message) { Stop-Launch $Message 2 }

function Write-LaunchLine([string]$Text) { [Console]::Out.WriteLine($Text) }

function Test-Hex([string]$Value, [int]$Length) {
  $null -ne $Value -and $Value -cmatch "\A[0-9a-f]{$Length}\z"
}

function Test-RefName([string]$Value) {
  $null -ne $Value -and $Value -cmatch '\A[A-Za-z0-9._/-]+\z' -and $Value -notmatch '\A[-/]' -and
    $Value -notmatch '/\z' -and $Value -notmatch '\.\.' -and $Value -notmatch '//'
}

# --- canonical paths ---------------------------------------------------------------------------

function Test-ReparsePoint([string]$Path) {
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $null -ne $item.LinkTarget
}

# Get-FinalPath <path>: the on-disk path, links in the parents followed, every component in its
# on-disk casing. Windows asks the file system (GetFinalPathNameByHandle); elsewhere each component is
# looked up in its parent's listing and a link is followed with ResolveLinkTarget.
function Get-FinalPath([string]$Path) {
  if ($IsWindows) {
    if (-not ('WowLaunch.Native' -as [type])) {
      Add-Type -Namespace WowLaunch -Name Native -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode, SetLastError = true)]
public static extern System.IntPtr CreateFileW(string name, uint access, uint share, System.IntPtr sec, uint disp, uint flags, System.IntPtr tmpl);
[System.Runtime.InteropServices.DllImport("kernel32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode, SetLastError = true)]
public static extern uint GetFinalPathNameByHandleW(System.IntPtr h, System.Text.StringBuilder buf, uint len, uint flags);
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern bool CloseHandle(System.IntPtr h);
'@
    }
    # FILE_FLAG_BACKUP_SEMANTICS opens a directory; access 0, share read/write/delete, OPEN_EXISTING.
    $h = [WowLaunch.Native]::CreateFileW($Path, 0, 7, [IntPtr]::Zero, 3, 0x02000000, [IntPtr]::Zero)
    if ($h -eq [IntPtr](-1)) { throw "cannot open $Path" }
    try {
      $sb = [Text.StringBuilder]::new(4096)
      $n = [WowLaunch.Native]::GetFinalPathNameByHandleW($h, $sb, 4096, 0)
      if ($n -eq 0 -or $n -ge 4096) { throw "cannot resolve $Path" }
    } finally { $null = [WowLaunch.Native]::CloseHandle($h) }
    $final = $sb.ToString()
    if ($final.StartsWith('\\?\UNC\')) { throw "$Path is on a network share" }
    if ($final.StartsWith('\\?\')) { $final = $final.Substring(4) }
    return $final.TrimEnd('\')
  }
  $full = [IO.Path]::GetFullPath($Path)
  $root = [IO.Path]::GetPathRoot($full)
  $cur = $root
  foreach ($c in $full.Substring($root.Length).Split([char[]]@('/', '\'), [StringSplitOptions]::RemoveEmptyEntries)) {
    $real = $null
    foreach ($e in [IO.Directory]::EnumerateFileSystemEntries($cur)) {
      $n = [IO.Path]::GetFileName($e)
      if ($n -ceq $c) { $real = $n; break }
      if ($null -eq $real -and $n -ieq $c) { $real = $n }
    }
    if ($null -eq $real) { throw "$Path does not exist" }
    $next = Join-Path $cur $real
    $item = Get-Item -LiteralPath $next -Force
    if ($null -ne $item.LinkTarget) {
      $t = $item.ResolveLinkTarget($true)
      if ($null -eq $t) { throw "$next is a broken link" }
      $next = Get-FinalPath $t.FullName
    }
    $cur = $next
  }
  $cur
}

# Format-PathKey <path>: the form two paths are compared in (case-insensitive, one separator, none trailing).
function Format-PathKey([string]$Path) { $Path.Replace('/', '\').TrimEnd('\').ToLowerInvariant() }

function Test-PathInside([string]$Outer, [string]$Inner) {
  $o = Format-PathKey $Outer; $i = Format-PathKey $Inner
  $i -eq $o -or $i.StartsWith($o + '\')
}

# Resolve-LaunchDir <name> <path> [-Plain]: the argument checks shared by -Clone, -Reference and (with -Plain, which
# allows a link and skips the leaf and character rules) -WowHome; exit 2. Returns the final path.
function Resolve-LaunchDir([string]$Name, [string]$Path, [switch]$Plain) {
  if ([string]::IsNullOrEmpty($Path)) { Stop-BadArgument "$Name is required" }
  if (-not [IO.Path]::IsPathFullyQualified($Path)) { Stop-BadArgument "$Name must be an absolute path" }
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) { Stop-BadArgument "$Name is not an existing directory" }
  if (-not $Plain -and (Test-ReparsePoint $Path)) { Stop-BadArgument "$Name is a link or reparse point" }
  try { $final = Get-FinalPath $Path } catch { Stop-BadArgument "$Name cannot be resolved: $($_.Exception.Message)" }
  $given = $Path.TrimEnd('\', '/')
  if (-not $Plain) {
    # The leaf as given must be the leaf on disk, case included: the volume names derive from it.
    if ([IO.Path]::GetFileName($given) -cne [IO.Path]::GetFileName($final)) { Stop-BadArgument "$Name leaf differs from the on-disk name" }
    if ($final -cnotmatch '\A([A-Za-z]:)?[\\/A-Za-z0-9 ._-]+\z') {
      Stop-BadArgument "$Name path may hold only letters, digits, space, . _ - and separators (cmd.exe re-parses the rest)"
    }
    $leaf = [IO.Path]::GetFileName($final)
    if ($leaf -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9._-]*\z') { Stop-BadArgument "$Name leaf must match [A-Za-z0-9][A-Za-z0-9._-]*" }
  }
  $final
}

# --- tools and runners -------------------------------------------------------------------------

# Resolve-Tool <name>: one application on PATH (an alias or function of the same name cannot shadow it).
function Resolve-Tool([string]$Name) {
  $found = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $found) { Stop-Launch "$Name not found on PATH" }
  $found.Source
}

# Invoke-Tool: stdout as bytes, the exit code, and stderr text. Stderr goes to the console with
# -InheritStderr (progress for the human), else it is captured; both outputs are read as they arrive,
# so no pipe can fill and deadlock. Never refuses by itself: Get-ToolText does.
function Invoke-Tool([string]$Exe, [string[]]$Arguments, [byte[]]$Stdin, [switch]$InheritStderr) {
  $psi = [Diagnostics.ProcessStartInfo]::new($Exe)
  foreach ($x in $Arguments) { $psi.ArgumentList.Add($x) }
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = -not $InheritStderr
  $psi.RedirectStandardInput = $null -ne $Stdin
  $p = [Diagnostics.Process]::Start($psi)
  $outMs = [IO.MemoryStream]::new()
  $outTask = $p.StandardOutput.BaseStream.CopyToAsync($outMs)
  $errTask = if (-not $InheritStderr) { $p.StandardError.ReadToEndAsync() }
  if ($null -ne $Stdin) {
    try { $p.StandardInput.BaseStream.Write($Stdin, 0, $Stdin.Length) } catch [IO.IOException] { } finally { $p.StandardInput.Close() }
  }
  $p.WaitForExit()
  $outTask.Wait()
  [pscustomobject]@{ Code = $p.ExitCode; Out = $outMs.ToArray(); Err = $(if ($errTask) { $errTask.Result } else { '' }) }
}

# Get-ToolText: stdout as UTF-8 text, refusing on a nonzero exit (empty output from a failed call is never a result).
function Get-ToolText([string]$Exe, [string[]]$Arguments, [switch]$InheritStderr) {
  $r = Invoke-Tool $Exe $Arguments -InheritStderr:$InheritStderr
  if ($r.Code -ne 0) { $verb = @($Arguments | Where-Object { $_ -cmatch '\A[a-z][a-z-]*\z' })[0]
    Stop-Launch "$([IO.Path]::GetFileNameWithoutExtension($Exe)) $verb failed (exit $($r.Code))" }
  [Text.Encoding]::UTF8.GetString($r.Out)
}

# Invoke-Session: the interactive session. Inherits the console; its exit code is returned as is.
function Invoke-Session([string]$Exe, [string[]]$Arguments) {
  $psi = [Diagnostics.ProcessStartInfo]::new($Exe)
  foreach ($x in $Arguments) { $psi.ArgumentList.Add($x) }
  $psi.UseShellExecute = $false
  $p = [Diagnostics.Process]::Start($psi)
  $p.WaitForExit()
  $p.ExitCode
}

# --- the Reference clone: commit, model, .devcontainer tree --------------------------------------

# Get-ReferenceCommit: fetch <remote> <base> in the Reference, resolve refs/remotes/<remote>/<base> once.
function Get-ReferenceCommit([string]$Git, [string]$Reference, [string]$Remote, [string]$Base) {
  $null = Get-ToolText $Git @('-C', $Reference, 'fetch', '--quiet', $Remote, $Base)
  $c = (Get-ToolText $Git @('-C', $Reference, 'rev-parse', '--verify', "refs/remotes/$Remote/$Base^{commit}")).Trim()
  if (-not (Test-Hex $c 40)) { Stop-Launch "refs/remotes/$Remote/$Base did not resolve to a commit" }
  $c
}

# Get-RoleModel: models.<role> from .ai/project.yml at that commit, matched to the fixed set. The
# value returned is the script's own literal, never the text read.
function Get-RoleModel([string]$Git, [string]$Yq, [string]$Reference, [string]$Commit, [ValidateSet('architect', 'coder')][string]$Role) {
  $blob = Invoke-Tool $Git @('-C', $Reference, 'cat-file', 'blob', "$($Commit):.ai/project.yml")
  if ($blob.Code -ne 0) { Stop-Launch "cannot read .ai/project.yml at $Commit in the Reference clone" }
  $r = Invoke-Tool $Yq @('-r', ".models.$Role") -Stdin $blob.Out
  if ($r.Code -ne 0) { Stop-Launch "yq could not read models.$Role" }
  switch -CaseSensitive ([Text.Encoding]::UTF8.GetString($r.Out).Trim()) {
    'sonnet' { return 'sonnet' }
    'opus' { return 'opus' }
    'haiku' { return 'haiku' }
    'fable' { return 'fable' }
    default { Stop-Launch "models.$Role is not one of sonnet, opus, haiku, fable" }
  }
}

# Get-BlobId <file>: git's blob id, in-process: SHA-1 over "blob <len>", a NUL byte, then the bytes.
function Get-BlobId([string]$Path) {
  $len = ([IO.FileInfo]::new($Path)).Length
  $sha = [Security.Cryptography.SHA1]::Create()
  $fs = [IO.File]::OpenRead($Path)
  try {
    $head = [byte[]]([Text.Encoding]::ASCII.GetBytes("blob $len") + [byte]0)
    $null = $sha.TransformBlock($head, 0, $head.Length, $null, 0)
    $buf = [byte[]]::new(81920)
    while (($n = $fs.Read($buf, 0, $buf.Length)) -gt 0) { $null = $sha.TransformBlock($buf, 0, $n, $null, 0) }
    $null = $sha.TransformFinalBlock([byte[]]::new(0), 0, 0)
    ([BitConverter]::ToString($sha.Hash) -replace '-', '').ToLowerInvariant()
  } finally { $fs.Dispose(); $sha.Dispose() }
}

# Get-CommittedDevTree: relative path -> blob id of every file under .devcontainer/ at the commit.
function Get-CommittedDevTree([string]$Git, [string]$Reference, [string]$Commit) {
  $text = Get-ToolText $Git @('-C', $Reference, 'ls-tree', '-r', '-z', $Commit, '--', '.devcontainer')
  $tree = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal) # case-sensitive: Dockerfile and dockerfile stay two files
  foreach ($rec in $text.Split([char]0, [StringSplitOptions]::RemoveEmptyEntries)) {
    if ($rec -cnotmatch '\A(\d{6}) (blob|commit|tree) ([0-9a-f]{40})\t(.+)\z') { Stop-Launch 'unreadable git ls-tree record' }
    if ($Matches[1] -cne '100644' -and $Matches[1] -cne '100755') { Stop-Launch "$($Matches[4]) is not a regular file at $Commit" }
    $tree[$Matches[4]] = $Matches[3]
  }
  if ($tree.Count -eq 0) { Stop-Launch ".devcontainer/ has no files at $Commit" }
  $tree
}

# Get-DiskDevFiles: relative path -> full path of every file under <Clone>/.devcontainer. A reparse
# point anywhere, the directory itself included, refuses.
function Get-DiskDevFiles([string]$Clone) {
  $root = Join-Path $Clone '.devcontainer'
  if (-not (Test-Path -LiteralPath $root -PathType Container)) { Stop-Launch '.devcontainer/ is missing from the clone' }
  if (Test-ReparsePoint $root) { Stop-Launch '.devcontainer is a link or reparse point' }
  $files = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
  $stack = [Collections.Generic.Stack[string]]::new()
  $stack.Push($root)
  while ($stack.Count -gt 0) {
    $d = $stack.Pop()
    foreach ($e in [IO.Directory]::EnumerateFileSystemEntries($d)) {
      if ([IO.Path]::GetFileName($e) -cnotmatch '\A[A-Za-z0-9._-]+\z') { Stop-Launch "a file name under .devcontainer/ holds characters outside letters, digits, . _ -: $($e.Substring($Clone.Length))" }
      $rel = $e.Substring($Clone.Length).TrimStart('\', '/').Replace('\', '/')
      $attr = [IO.File]::GetAttributes($e)
      if ($attr -band [IO.FileAttributes]::ReparsePoint) { Stop-Launch "$rel is a link or reparse point" }
      if ($attr -band [IO.FileAttributes]::Directory) { $stack.Push($e) } else { $files[$rel] = $e }
    }
  }
  $files
}

# Test-DevTree: the clone's .devcontainer/ equals the commit's, file set and bytes. Refuses naming the first difference.
function Test-DevTree([string]$Git, [string]$Reference, [string]$Clone, [string]$Commit) {
  $want = Get-CommittedDevTree $Git $Reference $Commit
  $have = Get-DiskDevFiles $Clone
  foreach ($rel in ($want.Keys | Sort-Object -CaseSensitive)) {
    if (-not $have.ContainsKey($rel)) { Stop-Launch "$rel is missing from the clone but committed on the base" }
  }
  foreach ($rel in ($have.Keys | Sort-Object -CaseSensitive)) {
    if (-not $want.ContainsKey($rel)) { Stop-Launch "$rel is in the clone but not committed on the base" }
  }
  foreach ($rel in ($want.Keys | Sort-Object -CaseSensitive)) {
    if ((Get-BlobId $have[$rel]) -cne $want[$rel]) { Stop-Launch "$rel differs from the base" }
  }
}

# Get-DevTreeId: the id of the .devcontainer tree at a commit, or $null when git cannot read it.
function Get-DevTreeId([string]$Git, [string]$Reference, [string]$Commit) {
  $r = Invoke-Tool $Git @('-C', $Reference, 'rev-parse', '--verify', "$($Commit):.devcontainer")
  if ($r.Code -ne 0) { return $null }
  $id = [Text.Encoding]::UTF8.GetString($r.Out).Trim()
  if (Test-Hex $id 40) { $id } else { $null }
}

# --- the record --------------------------------------------------------------------------------

function Get-RecordPath([string]$WowHome, [string]$Leaf) { Join-Path (Join-Path $WowHome 'driver') "$Leaf.json" }

# Read-Record: $null when absent; refuses on anything but exactly {id, commit, clone} in their shapes.
function Read-Record([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or (Test-ReparsePoint $Path)) { Stop-Launch 'the driver record is not a regular file' }
  if (([IO.FileInfo]::new($Path)).Length -gt 4096) { Stop-Launch 'the driver record is larger than 4 KiB' }
  try { $o = [IO.File]::ReadAllText($Path) | ConvertFrom-Json -ErrorAction Stop } catch { Stop-Launch 'the driver record is not valid JSON' }
  if ($o -isnot [pscustomobject]) { Stop-Launch 'the driver record is not a JSON object' }
  $names = @($o.PSObject.Properties.Name | Sort-Object -CaseSensitive)
  if ($names.Count -ne 3 -or $names[0] -cne 'clone' -or $names[1] -cne 'commit' -or $names[2] -cne 'id') {
    Stop-Launch 'the driver record must hold exactly id, commit and clone'
  }
  foreach ($n in $names) { if ($o.$n -isnot [string]) { Stop-Launch "the driver record's $n is not a string" } }
  if (-not (Test-Hex $o.id 64)) { Stop-Launch "the driver record's id is not 64 lowercase hex digits" }
  if (-not (Test-Hex $o.commit 40)) { Stop-Launch "the driver record's commit is not 40 lowercase hex digits" }
  [pscustomobject]@{ id = $o.id; commit = $o.commit; clone = $o.clone }
}

# Write-Record: a temp file in the same directory, then a rename over the old record.
function Write-Record([string]$Path, [string]$Id, [string]$Commit, [string]$Clone) {
  if (-not (Test-Hex $Id 64) -or -not (Test-Hex $Commit 40)) { Stop-Launch 'refusing to record a malformed id or commit' }
  $dir = Split-Path -Parent $Path
  if (Test-Path -LiteralPath $dir) {
    if (-not (Test-Path -LiteralPath $dir -PathType Container) -or (Test-ReparsePoint $dir)) { Stop-Launch 'driver/ under WowHome is not a plain directory' }
  } else { $null = New-Item -ItemType Directory -Path $dir }
  $tmp = Join-Path $dir ".$([IO.Path]::GetFileName($Path)).$([guid]::NewGuid().ToString('N')).tmp"
  try {
    $json = [ordered]@{ id = $Id; commit = $Commit; clone = $Clone } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText($tmp, $json + "`n")
    [IO.File]::Move($tmp, $Path, $true)
  } finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } }
}

# --- containers --------------------------------------------------------------------------------

function ConvertFrom-PsLines([string]$Text, [bool]$WithLabel) {
  $lines = $Text -split "`n"
  if ($lines.Count -gt 0 -and $lines[-1] -eq '') { $lines = @($lines | Select-Object -First ($lines.Count - 1)) }
  $rx = if ($WithLabel) { '\A([0-9a-f]{64}) ([a-z]+) (.*)\z' } else { '\A([0-9a-f]{64}) ([a-z]+)\z' }
  foreach ($l in $lines) {
    $l = $l.TrimEnd("`r")
    if ($l -cnotmatch $rx) { Stop-Launch 'unreadable docker ps line' }
    [pscustomobject]@{ Id = $Matches[1]; State = $Matches[2]; Label = $(if ($WithLabel) { $Matches[3] } else { $null }) }
  }
}

# Get-LaunchContainers: every container (any state) on <leaf>-tmp, plus those whose
# devcontainer.local_folder label names the path: the union of two listings, by id. Label values are
# data, compared and never put on a command line.
function Get-LaunchContainers([string]$Docker, [string]$Path, [string]$Leaf) {
  $bq = [string][char]96
  $byVolume = ConvertFrom-PsLines (Get-ToolText $Docker @('ps', '-a', '--no-trunc', '--filter', "volume=${Leaf}-tmp", '--format', '{{.ID}} {{.State}}')) $false
  $fmt = '{{.ID}} {{.State}} {{.Label ' + $bq + 'devcontainer.local_folder' + $bq + '}}'
  $byLabel = ConvertFrom-PsLines (Get-ToolText $Docker @('ps', '-a', '--no-trunc', '--filter', 'label=devcontainer.local_folder', '--format', $fmt)) $true
  $set = [ordered]@{}
  foreach ($c in @($byVolume)) { $set[$c.Id] = $c }
  $want = Format-PathKey $Path
  foreach ($c in @($byLabel)) { if ((Format-PathKey $c.Label) -eq $want -and -not $set.Contains($c.Id)) { $set[$c.Id] = $c } }
  @($set.Values)
}

# Assert-KnownStates: any state but running, exited or created refuses, wherever it appears.
function Assert-KnownStates($Containers) {
  foreach ($c in @($Containers)) {
    if ($c.State -cne 'running' -and $c.State -cne 'exited' -and $c.State -cne 'created') {
      Stop-Launch "container $($c.Id) is $($c.State): stop it (docker stop $($c.Id)), then rerun"
    }
  }
}

# --- the relay probe (attach only) -------------------------------------------------------------

# An accident guard, not a boundary. ls and grep by absolute path: it runs as root, and ~/.local/bin on the writable home volume may lead PATH. No & | ^ % or " in the script: it may pass through cmd.exe on a stub.
function Get-RelayProbeScript {
  "/bin/ls -d /tmp/vscode-remote-containers-* 2>/dev/null; /bin/grep -l -a -s -e '[v]scode-remote-containers-server' -e '[v]scode-server' /proc/[0-9]*/cmdline 2>/dev/null; exit 0"
}

function Test-RelayProbe([string]$Docker, [string]$Id) {
  if (-not (Test-Hex $Id 64)) { Stop-Launch 'refusing to probe a malformed container id' }
  $r = Invoke-Tool $Docker @('exec', '-u', 'root', $Id, '/bin/sh', '-c', (Get-RelayProbeScript))
  if ($r.Code -ne 0 -or $r.Out.Length -ne 0) {
    Stop-Launch 'a VS Code attach may have reached this container: stop it (WB-D33), then rerun at start of day'
  }
}
