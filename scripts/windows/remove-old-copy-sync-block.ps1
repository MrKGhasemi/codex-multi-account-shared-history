<#
.SYNOPSIS
  Removes an older marked Codex switcher block and reinstalls the current dynamic switcher.

.DESCRIPTION
  Use this if an older copy/merge synchronization function is still in your PowerShell profile.
  The saved account count is reused unless -AccountCount is provided.
#>

param(
    [int]$AccountCount = 0
)

$ErrorActionPreference = "Stop"
$ProfilePath = $PROFILE

if (Test-Path $ProfilePath) {
    Copy-Item $ProfilePath "$ProfilePath.bak-before-clean-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
    $content = Get-Content $ProfilePath -Raw
    $pattern = "(?s)# >>> Codex multi-account shared-history switcher >>>.*?# <<< Codex multi-account shared-history switcher <<<"
    $content = [regex]::Replace($content, $pattern, "").TrimEnd()
    Set-Content -Path $ProfilePath -Value ($content + "`r`n") -Encoding UTF8
}

if ($AccountCount -gt 0) {
    & "$PSScriptRoot\install-codex-profiles.ps1" -AccountCount $AccountCount
} else {
    & "$PSScriptRoot\install-codex-profiles.ps1"
}
