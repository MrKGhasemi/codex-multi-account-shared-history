<#
.SYNOPSIS
  Installs PowerShell helper commands for running four Codex ChatGPT accounts.

.DESCRIPTION
  Adds codex1, codex2, codex3, codex4, codexui, and codexsharedstatus functions to your PowerShell profile.
  Each command runs Codex with a different CODEX_HOME, so auth.json stays separate per account.

  This script does NOT copy, sync, or commit auth.json.
#>

$ErrorActionPreference = "Stop"

$ProfilePath = $PROFILE
$ProfileDir = Split-Path $ProfilePath -Parent
New-Item -ItemType Directory -Force -Path $ProfileDir | Out-Null

if (Test-Path $ProfilePath) {
    Copy-Item $ProfilePath "$ProfilePath.bak-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
}

$CodexUiHome     = Join-Path $env:USERPROFILE ".codex"
$Codex1Home      = Join-Path $env:USERPROFILE ".codex-plus-1"
$Codex2Home      = Join-Path $env:USERPROFILE ".codex-plus-2"
$Codex3Home      = Join-Path $env:USERPROFILE ".codex-plus-3"
$Codex4Home      = Join-Path $env:USERPROFILE ".codex-plus-4"
$CodexSharedHome = Join-Path $env:USERPROFILE ".codex-shared-history"

foreach ($dir in @($CodexUiHome, $Codex1Home, $Codex2Home, $Codex3Home, $Codex4Home, $CodexSharedHome)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

# Force file-based credentials for the four CLI profiles so each gets its own auth.json.
# The desktop/UI profile is left untouched because the app may use its default credential mode.
foreach ($profileHome in @($Codex1Home, $Codex2Home, $Codex3Home, $Codex4Home)) {
    Set-Content -Path (Join-Path $profileHome "config.toml") -Value 'cli_auth_credentials_store = "file"' -Encoding UTF8
}

$Block = @'
# >>> Codex multi-account shared-history switcher >>>

$global:CodexUiHome     = Join-Path $env:USERPROFILE ".codex"
$global:Codex1Home      = Join-Path $env:USERPROFILE ".codex-plus-1"
$global:Codex2Home      = Join-Path $env:USERPROFILE ".codex-plus-2"
$global:Codex3Home      = Join-Path $env:USERPROFILE ".codex-plus-3"
$global:Codex4Home      = Join-Path $env:USERPROFILE ".codex-plus-4"
$global:CodexSharedHome = Join-Path $env:USERPROFILE ".codex-shared-history"

function Invoke-CodexWithHome {
    param(
        [Parameter(Mandatory=$true)]
        [string]$CodexHome,

        [Parameter(ValueFromRemainingArguments=$true)]
        [string[]]$CodexArgs
    )

    $oldCodexHome = $env:CODEX_HOME

    try {
        $env:CODEX_HOME = $CodexHome
        & codex @CodexArgs
    }
    finally {
        if ($null -eq $oldCodexHome) {
            Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue
        } else {
            $env:CODEX_HOME = $oldCodexHome
        }
    }
}

function codex1 {
    Invoke-CodexWithHome -CodexHome $global:Codex1Home @args
}

function codex2 {
    Invoke-CodexWithHome -CodexHome $global:Codex2Home @args
}

function codex3 {
    Invoke-CodexWithHome -CodexHome $global:Codex3Home @args
}

function codex4 {
    Invoke-CodexWithHome -CodexHome $global:Codex4Home @args
}

function codexui {
    Invoke-CodexWithHome -CodexHome $global:CodexUiHome @args
}

function codexsharedstatus {
    $homes = @(
        @{ Name = "UI";      Path = $global:CodexUiHome },
        @{ Name = "codex1";  Path = $global:Codex1Home },
        @{ Name = "codex2";  Path = $global:Codex2Home },
        @{ Name = "codex3";  Path = $global:Codex3Home },
        @{ Name = "codex4";  Path = $global:Codex4Home },
        @{ Name = "shared";  Path = $global:CodexSharedHome }
    )

    foreach ($h in $homes) {
        Write-Host ""
        Write-Host "[$($h.Name)] $($h.Path)"

        foreach ($child in @("auth.json", "config.toml", "history.jsonl", "sessions", "archived_sessions")) {
            $p = Join-Path $h.Path $child
            if (Test-Path $p) {
                $item = Get-Item -LiteralPath $p -Force
                $kind = if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { "link" } elseif ($item.PSIsContainer) { "dir" } else { "file" }
                $target = ""
                try {
                    if ($kind -eq "link" -and $item.Target) { $target = " -> $($item.Target)" }
                } catch {}
                Write-Host ("  {0,-18} {1}{2}" -f $child, $kind, $target)
            } else {
                Write-Host ("  {0,-18} missing" -f $child)
            }
        }
    }
}

# <<< Codex multi-account shared-history switcher <<<
'@

$Content = ""
if (Test-Path $ProfilePath) {
    $Content = Get-Content $ProfilePath -Raw
}

$Pattern = "(?s)# >>> Codex multi-account shared-history switcher >>>.*?# <<< Codex multi-account shared-history switcher <<<"
$Content = [regex]::Replace($Content, $Pattern, "").TrimEnd()

Set-Content -Path $ProfilePath -Value ($Content + "`r`n`r`n" + $Block + "`r`n") -Encoding UTF8

. $ProfilePath

Write-Host ""
Write-Host "Installed Codex profile switcher for four accounts."
Write-Host "PowerShell profile: $ProfilePath"
Write-Host ""
Write-Host "Next commands:"
Write-Host '  $env:CODEX_HOME="$env:USERPROFILE\.codex-plus-1"; codex login --device-auth'
Write-Host '  $env:CODEX_HOME="$env:USERPROFILE\.codex-plus-2"; codex login --device-auth'
Write-Host '  $env:CODEX_HOME="$env:USERPROFILE\.codex-plus-3"; codex login --device-auth'
Write-Host '  $env:CODEX_HOME="$env:USERPROFILE\.codex-plus-4"; codex login --device-auth'
Write-Host ""
Write-Host "Usage after login:"
Write-Host "  codex1 resume --all"
Write-Host "  codex2 resume --all"
Write-Host "  codex3 resume --all"
Write-Host "  codex4 resume --all"
Write-Host "  codexui resume --all"
Write-Host "  codexsharedstatus"
