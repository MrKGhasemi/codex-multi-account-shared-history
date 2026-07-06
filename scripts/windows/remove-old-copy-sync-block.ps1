<#
.SYNOPSIS
  Removes older copy/merge sync function blocks from the PowerShell profile and reinstalls the current switcher.

.DESCRIPTION
  Use this if deleted conversations keep coming back because an older Sync-CodexHistory function is still in your profile.
#>

$ErrorActionPreference = "Stop"
$ProfilePath = $PROFILE

if (Test-Path $ProfilePath) {
    Copy-Item $ProfilePath "$ProfilePath.bak-before-clean-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
    $content = Get-Content $ProfilePath -Raw
    $pattern = "(?s)# >>> Codex multi-account shared-history switcher >>>.*?# <<< Codex multi-account shared-history switcher <<<"
    $content = [regex]::Replace($content, $pattern, "").TrimEnd()
    Set-Content -Path $ProfilePath -Value ($content + "`r`n") -Encoding UTF8
}

& "$PSScriptRoot\install-codex-profiles.ps1"
