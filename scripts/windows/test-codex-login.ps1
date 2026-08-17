<#
.SYNOPSIS
  Checks whether one Codex account profile is already logged in.

.DESCRIPTION
  Runs `codex login status` with CODEX_HOME set to the selected .codex-plus-N
  profile. Exits 0 when Codex reports the profile is logged in, and non-zero
  otherwise. It does not print or modify credentials.
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateRange(1,99)]
    [int]$Account
)

$ErrorActionPreference = "SilentlyContinue"
$ProfileHome = Join-Path $env:USERPROFILE ".codex-plus-$Account"
$oldCodexHome = $env:CODEX_HOME
$exitCode = 1

try {
    $env:CODEX_HOME = $ProfileHome
    cmd.exe /c codex login status >$null 2>&1
    if ($LASTEXITCODE -eq 0) {
        $exitCode = 0
    }
}
catch {
    $exitCode = 1
}
finally {
    if ($null -eq $oldCodexHome) {
        Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue
    } else {
        $env:CODEX_HOME = $oldCodexHome
    }
}

exit $exitCode
