# Dot-sourced by register-broker-task.ps1 and install-host-tools.ps1 (issue #1016); defines functions, runs nothing.
# A stopped scheduled task ends conhost, which can leave the pwsh it started running. These find that pwsh by the
# `-File "..."` argument the task's own action carries, so they match what the task starts and nothing rebuilt from a home.

# Get-FileArgSpan <action arguments>: the first -File "..." span (the switch, the quoted path and both quotes), or $null.
function Get-FileArgSpan([string]$Arguments) {
  if (-not $Arguments) { return $null }
  $m = [regex]::Match($Arguments, '-File\s+"[^"]+"', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
  if ($m.Success) { $m.Value } else { $null }
}

# Test-FileArgMatch <command line> <span>: true only when both are non-empty and the line holds the span, case-insensitive.
# The span ends at its closing quote, so another home's broker, a bin.old copy or a longer path does not match.
function Test-FileArgMatch([string]$CommandLine, [string]$Span) {
  if (-not $CommandLine -or -not $Span) { return $false }
  $CommandLine.IndexOf($Span, [StringComparison]::OrdinalIgnoreCase) -ge 0
}

# Stop-FileArgProcess <span>: end every process (this one excepted) whose command line holds the span, then wait up to
# $TimeoutSeconds (30) for them to go; throws naming the ids of any that remain.
function Stop-FileArgProcess([string]$Span, [int]$TimeoutSeconds = 30) {
  $list = { @(Get-CimInstance -ClassName Win32_Process | Where-Object { $_.ProcessId -ne $PID -and (Test-FileArgMatch ([string]$_.CommandLine) $Span) }) }
  $found = @(& $list)
  foreach ($p in $found) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  while ($found.Count -gt 0) {
    Start-Sleep -Milliseconds 500
    $found = @(& $list)
    if ($found.Count -gt 0 -and [DateTime]::UtcNow -ge $deadline) {
      throw "still running after $TimeoutSeconds s: process id $(($found | ForEach-Object { $_.ProcessId }) -join ', ')"
    }
  }
}
