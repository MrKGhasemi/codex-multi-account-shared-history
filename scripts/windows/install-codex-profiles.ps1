<#
.SYNOPSIS
  Installs PowerShell helper commands for any number of Codex ChatGPT accounts.

.DESCRIPTION
  Creates .codex-plus-N profile homes, keeps authentication separate per profile,
  stores the selected account count, and writes codex1..codexN helper functions
  into the current user's PowerShell profile.

  Normal runs are additive: existing profile directories and auth.json files are
  never removed, and a lower requested count will not silently unmanage existing
  higher-numbered profiles. Use -AllowDecrease only when you intentionally want
  the generated helper set/count to become smaller. Even then auth.json is not deleted.

.PARAMETER AccountCount
  Total number of separate CLI account profiles to configure.

.PARAMETER AllowDecrease
  Allow the managed account count to be reduced below the saved/discovered count.
  Profile directories and auth.json files are still not deleted.
#>

param(
    [int]$AccountCount = 0,
    [switch]$AllowDecrease
)

$ErrorActionPreference = "Stop"

$SwitcherDir = Join-Path $env:USERPROFILE ".codex-switcher"
$CountFile = Join-Path $SwitcherDir "account-count.txt"

function Get-SavedAccountCount {
    if (!(Test-Path $CountFile)) { return 0 }
    $saved = (Get-Content -LiteralPath $CountFile -Raw).Trim()
    $parsed = 0
    if ([int]::TryParse($saved, [ref]$parsed) -and $parsed -ge 1 -and $parsed -le 99) {
        return $parsed
    }
    return 0
}

function Get-HighestExistingProfileNumber {
    $max = 0
    Get-ChildItem -LiteralPath $env:USERPROFILE -Directory -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            if ($_.Name -match '^\.codex-plus-(\d+)$') {
                $n = [int]$Matches[1]
                if ($n -ge 1 -and $n -le 99 -and $n -gt $max) { $max = $n }
            }
        }
    return $max
}

function Resolve-AccountCount {
    param([int]$Requested, [switch]$CanDecrease)

    if ($Requested -gt 99 -or $Requested -lt 0) {
        throw "AccountCount must be between 1 and 99."
    }

    $saved = Get-SavedAccountCount
    $existing = Get-HighestExistingProfileNumber

    if ($Requested -le 0) {
        $resolved = [Math]::Max($saved, $existing)
        if ($resolved -le 0) { $resolved = 4 }
        return $resolved
    }

    if ($CanDecrease) { return $Requested }

    $resolved = [Math]::Max($Requested, [Math]::Max($saved, $existing))
    if ($resolved -ne $Requested) {
        Write-Host "Requested $Requested account(s), but existing configuration reaches account $resolved."
        Write-Host "Additive mode is preserving the existing higher-numbered profile(s)."
    }
    return $resolved
}

function Test-CodexProfileLoggedIn {
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

function Set-FileCredentialStore {
    param([Parameter(Mandatory=$true)][string]$ProfileHome)

    New-Item -ItemType Directory -Force -Path $ProfileHome | Out-Null
    $configPath = Join-Path $ProfileHome "config.toml"
    $requiredLine = 'cli_auth_credentials_store = "file"'

    if (!(Test-Path $configPath)) {
        Set-Content -LiteralPath $configPath -Value $requiredLine -Encoding UTF8
        return
    }

    $content = Get-Content -LiteralPath $configPath -Raw
    if ($null -eq $content) { $content = "" }
    $pattern = '(?m)^\s*cli_auth_credentials_store\s*=.*$'
    if ([regex]::IsMatch($content, $pattern)) {
        $content = [regex]::Replace($content, $pattern, $requiredLine)
    } else {
        $content = $content.TrimEnd() + "`r`n" + $requiredLine + "`r`n"
    }
    Set-Content -LiteralPath $configPath -Value $content -Encoding UTF8
}

$AccountCount = Resolve-AccountCount -Requested $AccountCount -CanDecrease:$AllowDecrease

New-Item -ItemType Directory -Force -Path $SwitcherDir | Out-Null
Set-Content -LiteralPath $CountFile -Value $AccountCount -Encoding ASCII

$ProfilePath = $PROFILE
$ProfileDir = Split-Path $ProfilePath -Parent
New-Item -ItemType Directory -Force -Path $ProfileDir | Out-Null

if (Test-Path $ProfilePath) {
    Copy-Item $ProfilePath "$ProfilePath.bak-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
}

$CodexUiHome = Join-Path $env:USERPROFILE ".codex"
$CodexSharedHome = Join-Path $env:USERPROFILE ".codex-shared-history"

New-Item -ItemType Directory -Force -Path $CodexUiHome | Out-Null
New-Item -ItemType Directory -Force -Path $CodexSharedHome | Out-Null

$ExistingLoginAccounts = @()
$MissingLoginAccounts = @()
$KeyringLoginAccounts = @()
for ($i = 1; $i -le $AccountCount; $i++) {
    $profileHome = Join-Path $env:USERPROFILE ".codex-plus-$i"
    $authPath = Join-Path $profileHome "auth.json"
    $profileExisted = Test-Path -LiteralPath $profileHome
    $hadAuthFile = Test-Path -LiteralPath $authPath
    $wasLoggedIn = $false

    # Check an already-existing profile before changing its credential-store setting.
    # This preserves profiles whose credentials live in Windows Credential Manager.
    if ($profileExisted) {
        if ($hadAuthFile) {
            $wasLoggedIn = $true
        } else {
            $wasLoggedIn = Test-CodexProfileLoggedIn -ProfileHome $profileHome
        }
    }

    if ($hadAuthFile) {
        # Existing file-backed login: keep auth.json untouched and make sure Codex
        # continues reading credentials from this profile's CODEX_HOME/auth.json.
        Set-FileCredentialStore -ProfileHome $profileHome
    } elseif ($wasLoggedIn) {
        # Existing keyring/auto-backed login: preserve its current config so changing
        # credential-store mode does not make an already-working login disappear.
        New-Item -ItemType Directory -Force -Path $profileHome | Out-Null
        $KeyringLoginAccounts += $i
    } else {
        # New/unlogged profile: file storage keeps this account isolated by CODEX_HOME.
        Set-FileCredentialStore -ProfileHome $profileHome
    }

    if ($wasLoggedIn -or $hadAuthFile) {
        $ExistingLoginAccounts += $i
    } else {
        $MissingLoginAccounts += $i
    }
}

$FunctionDefinitions = ""
for ($i = 1; $i -le $AccountCount; $i++) {
    $FunctionDefinitions += ("function codex{0} {{`r`n    Invoke-CodexAccount -Account {0} @args`r`n}}`r`n`r`n" -f $i)
}

$BlockTemplate = @'
# >>> Codex multi-account shared-history switcher >>>
$global:CodexAccountCount = __COUNT__
$global:CodexUiHome = Join-Path $env:USERPROFILE ".codex"
$global:CodexSharedHome = Join-Path $env:USERPROFILE ".codex-shared-history"

function Invoke-CodexWithHome {
    param(
        [Parameter(Mandatory=$true)]
        [string]$CodexHome,

        [Parameter(ValueFromRemainingArguments=$true)]
        [object[]]$CodexArgs
    )

    $oldCodexHome = $env:CODEX_HOME
    try {
        $env:CODEX_HOME = $CodexHome
        $effectiveArgs = @($CodexArgs)
        # Include desktop-created sessions in the normal shared-store picker.
        if ($effectiveArgs.Count -gt 0 -and [string]$effectiveArgs[0] -eq "resume") {
            $resumeExtras = @()
            if ($effectiveArgs -notcontains "--include-non-interactive") {
                $resumeExtras += "--include-non-interactive"
            }
            if ($effectiveArgs -notcontains "--no-daemon") {
                $resumeExtras += "--no-daemon"
            }
            if ($resumeExtras.Count -gt 0) {
                if ($effectiveArgs.Count -eq 1) {
                    $effectiveArgs = @("resume") + $resumeExtras
                } else {
                    $effectiveArgs = @("resume") + $resumeExtras + @($effectiveArgs[1..($effectiveArgs.Count - 1)])
                }
            }
        }
        if ($effectiveArgs -notcontains "--no-daemon") {
            $effectiveArgs = @("--no-daemon") + $effectiveArgs
        }
        & codex @effectiveArgs
    }
    finally {
        if ($null -eq $oldCodexHome) {
            Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue
        } else {
            $env:CODEX_HOME = $oldCodexHome
        }
    }
}

function Invoke-CodexAccount {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [int]$Account,

        [Parameter(ValueFromRemainingArguments=$true)]
        [object[]]$CodexArgs
    )

    if ($Account -lt 1 -or $Account -gt $global:CodexAccountCount) {
        throw "Account must be between 1 and $global:CodexAccountCount."
    }

    $accountHome = Join-Path $env:USERPROFILE ".codex-plus-$Account"
    Invoke-CodexWithHome -CodexHome $accountHome @CodexArgs
}

function codexaccount {
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [int]$Account,

        [Parameter(ValueFromRemainingArguments=$true)]
        [object[]]$CodexArgs
    )
    Invoke-CodexAccount -Account $Account @CodexArgs
}

__FUNCTIONS__
function codexui {
    Invoke-CodexWithHome -CodexHome $global:CodexUiHome @args
}

function codexsharedstatus {
    $homes = @(
        @{ Name = "UI"; Path = $global:CodexUiHome }
    )

    for ($i = 1; $i -le $global:CodexAccountCount; $i++) {
        $homes += @{ Name = "codex$i"; Path = Join-Path $env:USERPROFILE ".codex-plus-$i" }
    }

    $homes += @{ Name = "shared"; Path = $global:CodexSharedHome }

    Write-Host "Configured CLI accounts: $global:CodexAccountCount"
    foreach ($h in $homes) {
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
}
# <<< Codex multi-account shared-history switcher <<<
'@

$Block = $BlockTemplate.Replace("__COUNT__", [string]$AccountCount).Replace("__FUNCTIONS__", $FunctionDefinitions.TrimEnd())

$Content = ""
if (Test-Path $ProfilePath) {
    $Content = Get-Content $ProfilePath -Raw
}

$Pattern = "(?s)# >>> Codex multi-account shared-history switcher >>>.*?# <<< Codex multi-account shared-history switcher <<<"
$Content = [regex]::Replace($Content, $Pattern, "").TrimEnd()

Set-Content -Path $ProfilePath -Value ($Content + "`r`n`r`n" + $Block + "`r`n") -Encoding UTF8

Write-Host ""
Write-Host "Installed Codex profile switcher for $AccountCount account(s)."
Write-Host "PowerShell profile: $ProfilePath"
Write-Host "Saved account count: $CountFile"
Write-Host ""
Write-Host "Authentication preservation:"
if ($ExistingLoginAccounts.Count -gt 0) {
    Write-Host ("  Existing logged-in profiles preserved: " + (($ExistingLoginAccounts | ForEach-Object { "codex$_" }) -join ", "))
}
if ($KeyringLoginAccounts.Count -gt 0) {
    Write-Host ("  Existing credential-store setting kept for: " + (($KeyringLoginAccounts | ForEach-Object { "codex$_" }) -join ", "))
}
if ($MissingLoginAccounts.Count -gt 0) {
    Write-Host ("  Login still needed for: " + (($MissingLoginAccounts | ForEach-Object { "codex$_" }) -join ", "))
} else {
    Write-Host "  All configured profiles are already logged in. No login is required by setup."
}
Write-Host ""
Write-Host "After opening a new PowerShell window:"
Write-Host "  codex1 resume --all"
if ($AccountCount -gt 1) {
    Write-Host "  ... through codex$AccountCount resume --all"
}
Write-Host "  codexaccount <number> resume --all"
Write-Host "  codexui resume --all --include-non-interactive"
Write-Host "  codexsharedstatus"
