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
    - shares thread writer locks with the desktop profile to prevent concurrent writers

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
. (Join-Path $PSScriptRoot 'shared-store.ps1')
$SetupCoordination = $null
trap {
    if ($SetupCoordination) { $SetupCoordination.Dispose() }
    throw $_
}

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
    # Timestamps cannot decide which conversation is complete. Preserve exact
    # matches or append-only extensions; refuse divergent files with the same ID.
    $sourceRoot = [IO.Path]::GetFullPath($Source).TrimEnd('\') + '\'
    foreach ($file in Get-ChildItem -LiteralPath $Source -File -Recurse -Force) {
        $relative = $file.FullName.Substring($sourceRoot.Length)
        $target = Join-Path $Destination $relative
        if (Test-Path -LiteralPath $target) {
            $other = Get-Item -LiteralPath $target
            $short = if ($file.Length -le $other.Length) { $file.FullName } else { $target }
            $long = if ($file.Length -le $other.Length) { $target } else { $file.FullName }
            if (!(Test-AppendOnlyExtension -ShortPath $short -LongPath $long)) {
                throw "Conflicting conversation files: '$($file.FullName)' and '$target'. Both originals were kept; setup will not overwrite either."
            }
            if ($file.Length -le $other.Length) { continue }
        }
        New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    }
}

function Test-AppendOnlyExtension {
    param([string]$ShortPath, [string]$LongPath)
    $shortStream = [IO.File]::OpenRead($ShortPath)
    $longStream = [IO.File]::OpenRead($LongPath)
    try {
        $bufferA = New-Object byte[] 65536
        $bufferB = New-Object byte[] 65536
        while (($countA = $shortStream.Read($bufferA, 0, $bufferA.Length)) -gt 0) {
            $countB = $longStream.Read($bufferB, 0, $countA)
            if ($countB -ne $countA) { return $false }
            # Compare chunks without converting private message data to output.
            if ([Convert]::ToBase64String($bufferA,0,$countA) -cne [Convert]::ToBase64String($bufferB,0,$countB)) { return $false }
        }
        return $true
    } finally { $shortStream.Dispose(); $longStream.Dispose() }
}

function Assert-NoActiveProfileWriter {
    param([string]$ProfileHome)
    $lockHome = Join-Path $ProfileHome 'thread-writer-locks'
    if (!(Test-Path -LiteralPath $lockHome)) { return }
    foreach ($file in Get-ChildItem -LiteralPath $lockHome -File -Force) {
        if ($file.Name -eq '.coordination.lock') { continue } # setup owns the canonical coordination lock
        $stream = $null
        try {
            $stream = [IO.File]::Open($file.FullName,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::ReadWrite)
            $stream.Lock(0,1)
            $stream.Unlock(0,1)
        } catch { throw "Close the UI/CLI writer using '$ProfileHome' before changing its shared store. -Force cannot bypass writer safety." }
        finally { if ($stream) { $stream.Dispose() } }
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

function Move-ProfileSessionPathToBackup {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (!(Test-Path $Path)) { return }

    $resolved = [IO.Path]::GetFullPath($Path)
    $allowed = @($Homes | ForEach-Object { Join-Path $_ 'sessions'; Join-Path $_ 'archived_sessions' })
    if ($allowed -notcontains $resolved) { throw "Unexpected session path: $resolved" }
    $parent = Join-Path $BackupRoot ('replaced-paths\' + [Guid]::NewGuid().ToString('N'))
    $destination = [IO.Path]::GetFullPath((Join-Path $parent (Split-Path $resolved -Leaf)))
    if (!$destination.StartsWith([IO.Path]::GetFullPath($BackupRoot) + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected session backup path' }
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Move-Item -LiteralPath $resolved -Destination $destination
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
    if ((Test-Path -LiteralPath $configPath) -and (Get-Content -LiteralPath $configPath -Raw).TrimEnd() -eq $content.TrimEnd()) { return }
    Set-Content -LiteralPath $configPath -Value $content -Encoding UTF8
}

function Initialize-SharedSqliteState {
    param([string]$ProfileHome, [string]$SqliteHome, [switch]$RefreshInventory)

    New-Item -ItemType Directory -Force -Path $SqliteHome | Out-Null
    if (!$RefreshInventory -and (Test-Path -LiteralPath (Join-Path $SqliteHome 'state_5.sqlite')) -and
        (Test-Path -LiteralPath (Join-Path $SqliteHome 'thread_history_1.sqlite'))) {
        Write-Host 'Existing shared SQLite history is preserved; no migration needed.'
        return
    }
    $runtime = Get-CodexSharedRuntime -UiHome $ProfileHome
    $python = Get-CodexSharedPython
    & $python (Join-Path $PSScriptRoot 'seed-shared-sqlite.py') --ui-home $ProfileHome --destination $SqliteHome
    if ($LASTEXITCODE -ne 0) { throw 'Could not preserve the existing desktop SQLite history.' }
    if ($RefreshInventory -and (Test-Path -LiteralPath (Join-Path $SqliteHome 'state_5.sqlite'))) {
        & $python (Join-Path $PSScriptRoot 'seed-shared-sqlite.py') --ui-home $ProfileHome --destination $SqliteHome --refresh-inventory
        if ($LASTEXITCODE -ne 0) { throw 'Could not prepare native discovery of existing CLI conversations.' }
    }

    $oldCodexHome = $env:CODEX_HOME
    try {
        # Native migrations acquire writer locks too. Use an isolated initializer
        # while setup holds the real UI coordination lock against new writers.
        $initializer = Join-Path $BackupRoot 'initializer'
        New-Item -ItemType Directory -Path $initializer -Force | Out-Null
        New-Item -ItemType Junction -Path (Join-Path $initializer 'sessions') -Target $SharedSessions | Out-Null
        New-Item -ItemType Junction -Path (Join-Path $initializer 'archived_sessions') -Target $SharedArchived | Out-Null
        $env:CODEX_HOME = $initializer
        $override = 'sqlite_home="' + $SqliteHome.Replace('\', '\\') + '"'
        $reportPath = Join-Path $BackupRoot 'initialize-report.json'
        $errorPath = Join-Path $BackupRoot 'initialize-errors.log'
        $previousEap = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & $runtime -c $override migrate-rollouts --apply --json 1> $reportPath 2> $errorPath
            $migrationExit = $LASTEXITCODE
        } finally { $ErrorActionPreference = $previousEap }
        if ($migrationExit -ne 0) {
            throw "Codex could not initialize shared SQLite history (exit code $migrationExit). Original files were kept. See $reportPath and $errorPath."
        }
        & $python (Join-Path $PSScriptRoot 'seed-shared-sqlite.py') --ui-home $ProfileHome --destination $SqliteHome --normalize-rollout-paths
        if ($LASTEXITCODE -ne 0) { throw 'Could not finalize shared rollout paths.' }
    } finally {
        if ($null -eq $oldCodexHome) { Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue }
        else { $env:CODEX_HOME = $oldCodexHome }
    }
}

function Connect-SharedThreadWriterLocks {
    param([string]$ProfileHome, [string]$LockHome, [string]$BackupHome)

    $path = Join-Path $ProfileHome "thread-writer-locks"
    if ([string]::Equals($path, $LockHome, [StringComparison]::OrdinalIgnoreCase)) { return }
    if (Test-LinkTargetsDirectory -Path $path -ExpectedTarget $LockHome) { return }
    if (Test-Path -LiteralPath $path) {
        # Moving a lock file still in use would break coordination with its owner.
        foreach ($file in Get-ChildItem -LiteralPath $path -File -Force) {
            try {
                $handle = [IO.File]::Open($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
                $handle.Dispose()
            } catch { throw "Close the CLI using '$ProfileHome' before linking its writer locks." }
        }
        $resolved = [IO.Path]::GetFullPath($path)
        $expected = [IO.Path]::GetFullPath((Join-Path $ProfileHome 'thread-writer-locks'))
        if ($resolved -ne $expected) { throw "Unexpected writer lock path: $resolved" }
        New-Item -ItemType Directory -Path $BackupHome -Force | Out-Null
        Move-Item -LiteralPath $resolved -Destination (Join-Path $BackupHome 'thread-writer-locks')
    }
    New-Item -ItemType Junction -Path $path -Target $LockHome | Out-Null
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
$SharedWriterLocks = Join-Path $CodexUiHome "thread-writer-locks"
New-Item -ItemType Directory -Path $SharedWriterLocks -Force | Out-Null

New-Item -ItemType Directory -Force -Path $SharedSessions | Out-Null
New-Item -ItemType Directory -Force -Path $SharedArchived | Out-Null
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null

# Block new UI/shared-profile writers across the whole migration. Existing
# writers are checked again below after this lock has been acquired.
$coordinationPath = Join-Path $SharedWriterLocks '.coordination.lock'
try {
    $SetupCoordination = [IO.File]::Open($coordinationPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::ReadWrite)
    $SetupCoordination.Lock(0,1)
} catch {
    if ($SetupCoordination) { $SetupCoordination.Dispose(); $SetupCoordination = $null }
    throw 'Another client is coordinating shared history. Wait for it to finish before setup.'
}

# Establish safety before copying a rollout, changing a database location, or
# invoking a native migration. Already-configured profiles need no relinking.
$requiresOfflineMerge = $false
$expectedSqlite = 'sqlite_home = "' + $SharedSqliteHome.Replace('\','\\') + '"'
foreach ($h in $Homes) {
    $configPath = Join-Path $h 'config.toml'
    $config = if (Test-Path -LiteralPath $configPath) { Get-Content -LiteralPath $configPath -Raw } else { '' }
    $top = [regex]::Split([string]$config, '(?m)^\s*\[')[0]
    $configMatches = [regex]::Matches($top, '(?m)^\s*sqlite_home\s*=.*$')
    $changesHome = ($configMatches.Count -ne 1 -or $configMatches[0].Value.Trim() -ne $expectedSqlite)
    foreach ($child in @('sessions','archived_sessions')) {
        $path = Join-Path $h $child
        if (!(Test-LinkTargetsDirectory -Path $path -ExpectedTarget (Join-Path $CodexSharedHome $child))) {
            $changesHome = $true
            if ((Test-Path -LiteralPath $path) -and @(Get-ChildItem -LiteralPath $path -File -Recurse -Force).Count -gt 0) { $requiresOfflineMerge = $true }
        }
    }
    if ($changesHome) { Assert-NoActiveProfileWriter -ProfileHome $h }
}
if ($requiresOfflineMerge -or !(Test-Path -LiteralPath (Join-Path $SharedSqliteHome 'state_5.sqlite'))) {
    foreach ($h in $Homes) { Assert-NoActiveProfileWriter -ProfileHome $h }
}
foreach ($h in $Homes) {
    New-Item -ItemType Directory -Path $h -Force | Out-Null
    Connect-SharedThreadWriterLocks -ProfileHome $h -LockHome $SharedWriterLocks -BackupHome (Join-Path $BackupRoot (Split-Path $h -Leaf))
}

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
Initialize-SharedSqliteState -ProfileHome $CodexUiHome -SqliteHome $SharedSqliteHome -RefreshInventory:$requiresOfflineMerge
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
        Move-ProfileSessionPathToBackup -Path $sessions
        New-Item -ItemType Junction -Path $sessions -Target $SharedSessions | Out-Null
        Write-Host "Linked sessions: $h"
    }

    if (!(Test-LinkTargetsDirectory -Path $archived -ExpectedTarget $SharedArchived)) {
        Move-ProfileSessionPathToBackup -Path $archived
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

    Connect-SharedThreadWriterLocks -ProfileHome $h -LockHome $SharedWriterLocks -BackupHome (Join-Path $BackupRoot (Split-Path $h -Leaf))
}

$SetupCoordination.Dispose()
$SetupCoordination = $null

Write-Host ""
Write-Host "Done. codex1..codex$AccountCount and codexui now share live local sessions/history."
Write-Host "Existing auth.json files were not removed, copied, linked, or replaced."
Write-Host "Already-correct links were kept in place; newly added profiles were attached to the shared store."
Write-Host "No periodic copy-sync job is needed: the profiles point at the same session store."
Write-Host "Writer locks are shared too. Use one active writer per chat; close that chat in the other client before continuing it."
Write-Host ""
Write-Host "Use a new PowerShell window, then:"
Write-Host "  codex1 resume --all"
if ($AccountCount -gt 1) {
    Write-Host "  ... through codex$AccountCount resume --all"
}
Write-Host "  codexui resume --all"
Write-Host "  (profile helpers automatically include non-interactive desktop sessions)"
Write-Host "  codexsharedstatus"
