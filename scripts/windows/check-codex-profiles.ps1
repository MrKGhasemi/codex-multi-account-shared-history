<#
.SYNOPSIS
  Prints Codex profile paths, auth/config/session status, and link targets on Windows.
#>

param(
    [int]$AccountCount = 0
)

$ErrorActionPreference = "Stop"

$CountFile = Join-Path (Join-Path $env:USERPROFILE ".codex-switcher") "account-count.txt"

if ($AccountCount -le 0 -and (Test-Path $CountFile)) {
    $saved = (Get-Content -LiteralPath $CountFile -Raw).Trim()
    $parsed = 0
    if ([int]::TryParse($saved, [ref]$parsed) -and $parsed -ge 1 -and $parsed -le 99) {
        $AccountCount = $parsed
    }
}
if ($AccountCount -le 0) { $AccountCount = 4 }
if ($AccountCount -gt 99) { throw "AccountCount must be between 1 and 99." }

$Homes = @(
    @{ Name = "UI"; Path = Join-Path $env:USERPROFILE ".codex" }
)
for ($i = 1; $i -le $AccountCount; $i++) {
    $Homes += @{ Name = "codex$i"; Path = Join-Path $env:USERPROFILE ".codex-plus-$i" }
}
$Homes += @{ Name = "shared"; Path = Join-Path $env:USERPROFILE ".codex-shared-history" }

Write-Host "Configured CLI accounts: $AccountCount"
Write-Host "Codex executable:"
try {
    Get-Command codex -ErrorAction Stop | Format-List Source,Version
} catch {
    Write-Host "  codex not found in PATH"
}

foreach ($h in $Homes) {
    Write-Host ""
    Write-Host "[$($h.Name)] $($h.Path)"
    foreach ($child in @("auth.json", "config.toml", "history.jsonl", "session_index.jsonl", "state_5.sqlite", "sessions", "archived_sessions")) {
        $p = Join-Path $h.Path $child
        if (Test-Path $p) {
            $item = Get-Item -LiteralPath $p -Force
            $kind = if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                "link"
            } elseif ($item.PSIsContainer) {
                "dir"
            } else {
                "file"
            }

            $target = ""
            try {
                if ($kind -eq "link" -and $item.Target) {
                    $target = " -> $($item.Target)"
                }
            } catch {}

            Write-Host ("  {0,-18} {1}{2}" -f $child, $kind, $target)
        } else {
            Write-Host ("  {0,-18} missing" -f $child)
        }
    }
}

function Test-CodexLoginForHome {
    param([Parameter(Mandatory=$true)][string]$ProfileHome)

    if (!(Get-Command codex -ErrorAction SilentlyContinue)) { return $false }
    $oldCodexHome = $env:CODEX_HOME
    $oldEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = "SilentlyContinue"
        $env:CODEX_HOME = $ProfileHome
        cmd.exe /c codex login status >$null 2>&1
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
    finally {
        $ErrorActionPreference = $oldEap
        if ($null -eq $oldCodexHome) {
            Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue
        } else {
            $env:CODEX_HOME = $oldCodexHome
        }
    }
}

Write-Host ""
Write-Host "Login status checks:"
for ($i = 1; $i -le $AccountCount; $i++) {
    $profileHome = Join-Path $env:USERPROFILE ".codex-plus-$i"
    $status = if (Test-CodexLoginForHome -ProfileHome $profileHome) { "logged in" } else { "not logged in / status unavailable" }
    Write-Host ("  codex{0,-3} {1}" -f $i, $status)
}
$uiStatus = if (Test-CodexLoginForHome -ProfileHome (Join-Path $env:USERPROFILE ".codex")) { "logged in" } else { "not logged in / status unavailable" }
Write-Host ("  codexui   $uiStatus")
