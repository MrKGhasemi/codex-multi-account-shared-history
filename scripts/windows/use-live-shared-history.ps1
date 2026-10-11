<#
.SYNOPSIS
  Connects the Codex UI/default profile and any number of CLI account profiles
  to one shared live local session store.

.DESCRIPTION
  For every configured profile, this script:
    - merges existing sessions and archived sessions into .codex-shared-history
    - merges unique history.jsonl and session_index.jsonl lines
    - rebuilds one shared SQLite thread inventory from the shared rollouts
    - configures every profile to use the shared sqlite_home
    - creates directory junctions for sessions and archived_sessions when needed
    - creates hardlinks for history.jsonl and session_index.jsonl when needed

  Authentication is never copied or linked.

  Existing correct junctions/hardlinks are left in place. This makes rerunning the
  script additive and avoids unnecessarily touching already-configured profiles.

.PARAMETER AccountCount
  Number of CLI profiles. If omitted, the saved/discovered count is used.

.PARAMETER NoHistoryLink
  Share session folders but do not create/recreate history.jsonl hardlinks.

.PARAMETER Force
  Do not pause or require Codex processes to be closed before attempting the update.
  This is the mode used by setup-codex-accounts.bat. Windows can still reject an
  operation if another process has an exclusive OS-level lock on a file being changed.
#>

param(
    [int]$AccountCount = 0,
    [switch]$NoHistoryLink,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
try { $global:PSNativeCommandUseErrorActionPreference = $false } catch {}

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
    param([int]$Requested)
    if ($Requested -gt 99 -or $Requested -lt 0) {
        throw "AccountCount must be between 1 and 99."
    }
    $saved = Get-SavedAccountCount
    $existing = Get-HighestExistingProfileNumber
    if ($Requested -gt 0) {
        return [Math]::Max($Requested, [Math]::Max($saved, $existing))
    }
    $resolved = [Math]::Max($saved, $existing)
    if ($resolved -le 0) { $resolved = 4 }
    return $resolved
}

function Invoke-RoboCopySafe {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Destination
    )

    if (!(Test-Path $Source)) { return }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    robocopy $Source $Destination /E /XO /FFT /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
    $code = $LASTEXITCODE
    if ($code -gt 7) {
        throw "robocopy failed with exit code $code while copying '$Source' to '$Destination'"
    }
}

function Test-LinkTargetsDirectory {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$ExpectedTarget
    )

    if (!(Test-Path $Path)) { return $false }

    $item = Get-Item -LiteralPath $Path -Force
    $isReparse = (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
    if (!$isReparse -or !$item.PSIsContainer -or !$item.Target) { return $false }

    $target = @($item.Target)[0]
    if (![System.IO.Path]::IsPathRooted($target)) {
        $target = Join-Path $item.Parent.FullName $target
    }

    $actual = [System.IO.Path]::GetFullPath($target).TrimEnd('\')
    $expected = [System.IO.Path]::GetFullPath($ExpectedTarget).TrimEnd('\')
    return [string]::Equals($actual, $expected, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-HardLinkTargetsFile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$ExpectedTarget
    )

    if (!(Test-Path -LiteralPath $Path) -or !(Test-Path -LiteralPath $ExpectedTarget)) { return $false }

    $pathFull = [System.IO.Path]::GetFullPath($Path)
    $expectedFull = [System.IO.Path]::GetFullPath($ExpectedTarget)
    if ([string]::Equals($pathFull, $expectedFull, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }

    # PowerShell exposes hardlink targets on many Windows versions.
    try {
        $item = Get-Item -LiteralPath $Path -Force
        if ($item.LinkType -eq "HardLink" -and $item.Target) {
            foreach ($target in @($item.Target)) {
                $candidate = [string]$target
                if (![System.IO.Path]::IsPathRooted($candidate)) {
                    $candidate = Join-Path $item.Directory.FullName $candidate
                }
                if ([string]::Equals([System.IO.Path]::GetFullPath($candidate), $expectedFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                    return $true
                }
            }
        }
    } catch {}

    # Fallback for Windows PowerShell versions where Target is not populated for hardlinks.
    try {
        $driveRoot = [System.IO.Path]::GetPathRoot($pathFull).TrimEnd('\')
        $links = @(& fsutil.exe hardlink list $pathFull 2>$null)
        if ($LASTEXITCODE -eq 0) {
            foreach ($link in $links) {
                $candidate = ([string]$link).Trim()
                if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
                if ($candidate.StartsWith('\')) {
                    $candidate = $driveRoot + $candidate
                }
                try { $candidate = [System.IO.Path]::GetFullPath($candidate) } catch { continue }
                if ([string]::Equals($candidate, $expectedFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                    return $true
                }
            }
        }
    } catch {}

    return $false
}

function Remove-PathWithoutFollowingJunction {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (!(Test-Path $Path)) { return }

    $item = Get-Item -LiteralPath $Path -Force
    $isReparse = (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)

    if ($isReparse -and $item.PSIsContainer) {
        cmd /c rmdir "$Path" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Could not remove junction '$Path'." }
    } else {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

function Merge-JsonlUnique {
    param(
        [string[]]$Sources,
        [string]$Destination
    )

    $destDir = Split-Path $Destination -Parent
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null

    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $out = [System.Collections.Generic.List[string]]::new()

    foreach ($file in $Sources) {
        if (Test-Path $file) {
            foreach ($line in [System.IO.File]::ReadLines($file)) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                if ($seen.Add($line)) { $out.Add($line) }
            }
        }
    }

    [System.IO.File]::WriteAllLines($Destination, $out)
}

function Set-SharedSqliteHomeConfig {
    param([string]$ProfileHome, [string]$SqliteHome)

    $configPath = Join-Path $ProfileHome "config.toml"
    $escaped = $SqliteHome.Replace('\', '\\')
    $line = 'sqlite_home = "' + $escaped + '"'
    $content = if (Test-Path $configPath) { Get-Content -LiteralPath $configPath -Raw } else { "" }
    if ($null -eq $content) { $content = "" }
    # sqlite_home is a top-level TOML key. Remove any previous copy (including
    # an older incorrectly nested copy) and prepend the new key before tables.
    $pattern = '(?m)^\s*sqlite_home\s*=.*(?:\r?\n|$)'
    $content = [regex]::Replace($content, $pattern, "")
    $content = $line + "`r`n" + $content.TrimStart()
    Set-Content -LiteralPath $configPath -Value $content -Encoding UTF8
}

function Initialize-SharedSqliteState {
    param([string]$ProfileHome, [string]$SqliteHome)

    New-Item -ItemType Directory -Force -Path $SqliteHome | Out-Null
    if (!(Get-Command codex -ErrorAction SilentlyContinue)) {
        throw "Codex CLI is required to initialize the shared SQLite session index."
    }

    $oldCodexHome = $env:CODEX_HOME
    try {
        $env:CODEX_HOME = $ProfileHome
        $override = 'sqlite_home="' + $SqliteHome.Replace('\', '\\') + '"'
        & codex -c $override migrate-rollouts --apply --json *> $null
        if ($LASTEXITCODE -ne 0) {
            throw "Codex could not initialize the shared SQLite session index (exit code $LASTEXITCODE)."
        }
    } finally {
        if ($null -eq $oldCodexHome) { Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue }
        else { $env:CODEX_HOME = $oldCodexHome }
    }
}

$AccountCount = Resolve-AccountCount -Requested $AccountCount
$CodexUiHome = Join-Path $env:USERPROFILE ".codex"
$CodexSharedHome = Join-Path $env:USERPROFILE ".codex-shared-history"

$Homes = @($CodexUiHome)
for ($i = 1; $i -le $AccountCount; $i++) {
    $Homes += Join-Path $env:USERPROFILE ".codex-plus-$i"
}

$BackupRoot = Join-Path $env:USERPROFILE ("codex-backup-before-shared-links-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
$SharedSessions = Join-Path $CodexSharedHome "sessions"
$SharedArchived = Join-Path $CodexSharedHome "archived_sessions"
$SharedHistory = Join-Path $CodexSharedHome "history.jsonl"
$SharedSessionIndex = Join-Path $CodexSharedHome "session_index.jsonl"
$SharedSqliteHome = Join-Path $CodexSharedHome "sqlite"

New-Item -ItemType Directory -Force -Path $SharedSessions | Out-Null
New-Item -ItemType Directory -Force -Path $SharedArchived | Out-Null
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null

Write-Host "Configured CLI accounts: $AccountCount"
Write-Host "Backup folder: $BackupRoot"
if ($Force) {
    Write-Host "Force mode enabled: continuing without a close-session prompt."
} else {
    Write-Host "No interactive process check is performed. Close Codex only if Windows reports a locked file."
}
Write-Host "Existing correct shared links will be preserved instead of recreated."
Write-Host ""

$HistorySources = @()
$DistinctHistoryFound = $false
if (Test-Path $SharedHistory) {
    $HistorySources += $SharedHistory
}

# The resume picker also uses session_index.jsonl. Share it alongside the
# rollout folders so every profile discovers the same sessions.
$IndexSources = @()
$DistinctIndexFound = $false
if (Test-Path $SharedSessionIndex) {
    $IndexSources += $SharedSessionIndex
}

foreach ($h in $Homes) {
    New-Item -ItemType Directory -Force -Path $h | Out-Null

    $name = Split-Path $h -Leaf
    $backupHome = Join-Path $BackupRoot $name
    New-Item -ItemType Directory -Force -Path $backupHome | Out-Null

    $sessions = Join-Path $h "sessions"
    $archived = Join-Path $h "archived_sessions"
    $history = Join-Path $h "history.jsonl"
    $sessionIndex = Join-Path $h "session_index.jsonl"

    if (Test-Path $sessions) {
        if (!(Test-LinkTargetsDirectory -Path $sessions -ExpectedTarget $SharedSessions)) {
            Copy-Item $sessions $backupHome -Recurse -Force -ErrorAction SilentlyContinue
            Invoke-RoboCopySafe -Source $sessions -Destination $SharedSessions
        }
    }

    if (Test-Path $archived) {
        if (!(Test-LinkTargetsDirectory -Path $archived -ExpectedTarget $SharedArchived)) {
            Copy-Item $archived $backupHome -Recurse -Force -ErrorAction SilentlyContinue
            Invoke-RoboCopySafe -Source $archived -Destination $SharedArchived
        }
    }

    if (Test-Path $history) {
        $alreadyShared = (Test-Path $SharedHistory) -and (Test-HardLinkTargetsFile -Path $history -ExpectedTarget $SharedHistory)
        if (!$alreadyShared) {
            Copy-Item $history $backupHome -Force -ErrorAction SilentlyContinue
            $HistorySources += $history
            $DistinctHistoryFound = $true
        }
    }

    if (Test-Path $sessionIndex) {
        $alreadySharedIndex = (Test-Path $SharedSessionIndex) -and (Test-HardLinkTargetsFile -Path $sessionIndex -ExpectedTarget $SharedSessionIndex)
        if (!$alreadySharedIndex) {
            Copy-Item $sessionIndex $backupHome -Force -ErrorAction SilentlyContinue
            $IndexSources += $sessionIndex
            $DistinctIndexFound = $true
        }
    }
}

if (!(Test-Path $SharedHistory)) {
    if ($HistorySources.Count -gt 0) {
        Merge-JsonlUnique -Sources $HistorySources -Destination $SharedHistory
    } else {
        New-Item -ItemType File -Force -Path $SharedHistory | Out-Null
    }
} elseif ($DistinctHistoryFound) {
    # Merge only when a profile has history that is not already the shared hardlink.
    # A normal rerun/add-account operation therefore does not rewrite the existing
    # shared history file or disturb already-configured profiles.
    Merge-JsonlUnique -Sources $HistorySources -Destination $SharedHistory
} else {
    Write-Host "Existing history.jsonl is already shared; no history rewrite needed."
}

if (!(Test-Path $SharedSessionIndex)) {
    if ($IndexSources.Count -gt 0) {
        Merge-JsonlUnique -Sources $IndexSources -Destination $SharedSessionIndex
    } else {
        New-Item -ItemType File -Force -Path $SharedSessionIndex | Out-Null
    }
} elseif ($DistinctIndexFound) {
    Merge-JsonlUnique -Sources $IndexSources -Destination $SharedSessionIndex
} else {
    Write-Host "Existing session_index.jsonl is already shared; no index rewrite needed."
}

# The current picker reads the SQLite thread inventory in addition to the
# rollout files. Build that inventory from the shared rollouts, then point
# every profile at the same sqlite_home so UI and CLI discover the same rows.
Initialize-SharedSqliteState -ProfileHome $CodexUiHome -SqliteHome $SharedSqliteHome
foreach ($h in $Homes) {
    Set-SharedSqliteHomeConfig -ProfileHome $h -SqliteHome $SharedSqliteHome
}
Write-Host "Shared SQLite session state: $SharedSqliteHome"

foreach ($h in $Homes) {
    New-Item -ItemType Directory -Force -Path $h | Out-Null

    $sessions = Join-Path $h "sessions"
    $archived = Join-Path $h "archived_sessions"
    $history = Join-Path $h "history.jsonl"
    $sessionIndex = Join-Path $h "session_index.jsonl"

    if (!(Test-LinkTargetsDirectory -Path $sessions -ExpectedTarget $SharedSessions)) {
        Remove-PathWithoutFollowingJunction -Path $sessions
        New-Item -ItemType Junction -Path $sessions -Target $SharedSessions | Out-Null
        Write-Host "Linked sessions: $h"
    }

    if (!(Test-LinkTargetsDirectory -Path $archived -ExpectedTarget $SharedArchived)) {
        Remove-PathWithoutFollowingJunction -Path $archived
        New-Item -ItemType Junction -Path $archived -Target $SharedArchived | Out-Null
        Write-Host "Linked archived_sessions: $h"
    }

    if (!$NoHistoryLink -and !(Test-HardLinkTargetsFile -Path $history -ExpectedTarget $SharedHistory)) {
        if (Test-Path $history) {
            Remove-Item -LiteralPath $history -Force
        }
        New-Item -ItemType HardLink -Path $history -Target $SharedHistory | Out-Null
        Write-Host "Linked history.jsonl: $h"
    }

    if (!(Test-HardLinkTargetsFile -Path $sessionIndex -ExpectedTarget $SharedSessionIndex)) {
        if (Test-Path $sessionIndex) {
            Remove-Item -LiteralPath $sessionIndex -Force
        }
        New-Item -ItemType HardLink -Path $sessionIndex -Target $SharedSessionIndex | Out-Null
        Write-Host "Linked session_index.jsonl: $h"
    }
}

Write-Host ""
Write-Host "Done. codex1..codex$AccountCount and codexui now share live local sessions/history."
Write-Host "Existing auth.json files were not removed, copied, linked, or replaced."
Write-Host "Already-correct links were kept in place; newly added profiles were attached to the shared store."
Write-Host "No periodic copy-sync job is needed: the profiles point at the same session store."
Write-Host ""
Write-Host "Use a new PowerShell window, then:"
Write-Host "  codex1 resume --all"
if ($AccountCount -gt 1) {
    Write-Host "  ... through codex$AccountCount resume --all"
}
Write-Host "  codexui resume --all"
Write-Host "  (profile helpers automatically include non-interactive desktop sessions)"
Write-Host "  codexsharedstatus"
