<#
.SYNOPSIS
  Converts Codex UI, codex1, and codex2 profiles to use one shared live session store.

.DESCRIPTION
  Creates junctions:
    %USERPROFILE%\.codex\sessions              -> %USERPROFILE%\.codex-shared-history\sessions
    %USERPROFILE%\.codex-plus-1\sessions       -> %USERPROFILE%\.codex-shared-history\sessions
    %USERPROFILE%\.codex-plus-2\sessions       -> %USERPROFILE%\.codex-shared-history\sessions

  Same for archived_sessions.
  Creates a hardlink for history.jsonl unless -NoHistoryLink is passed.

  This script never links or copies auth.json.

.PARAMETER NoHistoryLink
  Do not hardlink history.jsonl. Conversation resume works from sessions even without history.jsonl.
#>

param(
    [switch]$NoHistoryLink
)

$ErrorActionPreference = "Stop"
try { $global:PSNativeCommandUseErrorActionPreference = $false } catch {}

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

function Remove-PathWithoutFollowingJunction {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (!(Test-Path $Path)) { return }

    $item = Get-Item -LiteralPath $Path -Force
    $isReparse = (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)

    if ($isReparse -and $item.PSIsContainer) {
        cmd /c rmdir "$Path" | Out-Null
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

$CodexUiHome     = Join-Path $env:USERPROFILE ".codex"
$Codex1Home      = Join-Path $env:USERPROFILE ".codex-plus-1"
$Codex2Home      = Join-Path $env:USERPROFILE ".codex-plus-2"
$CodexSharedHome = Join-Path $env:USERPROFILE ".codex-shared-history"
$Homes           = @($CodexUiHome, $Codex1Home, $Codex2Home)

$BackupRoot = Join-Path $env:USERPROFILE ("codex-backup-before-shared-links-" + (Get-Date -Format "yyyyMMdd-HHmmss"))

New-Item -ItemType Directory -Force -Path $CodexSharedHome | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $CodexSharedHome "sessions") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $CodexSharedHome "archived_sessions") | Out-Null
New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null

Write-Host "Backup folder: $BackupRoot"
Write-Host "Close Codex CLI/UI/IDE before running this script. If a file is locked, close Codex and run again."
Write-Host ""

$HistorySources = @()
$SharedHistory = Join-Path $CodexSharedHome "history.jsonl"
if (Test-Path $SharedHistory) { $HistorySources += $SharedHistory }

foreach ($h in $Homes) {
    New-Item -ItemType Directory -Force -Path $h | Out-Null

    $name = Split-Path $h -Leaf
    $backupHome = Join-Path $BackupRoot $name
    New-Item -ItemType Directory -Force -Path $backupHome | Out-Null

    $sessions = Join-Path $h "sessions"
    $archived = Join-Path $h "archived_sessions"
    $history  = Join-Path $h "history.jsonl"

    if (Test-Path $sessions) {
        Copy-Item $sessions $backupHome -Recurse -Force -ErrorAction SilentlyContinue
        Invoke-RoboCopySafe -Source $sessions -Destination (Join-Path $CodexSharedHome "sessions")
    }

    if (Test-Path $archived) {
        Copy-Item $archived $backupHome -Recurse -Force -ErrorAction SilentlyContinue
        Invoke-RoboCopySafe -Source $archived -Destination (Join-Path $CodexSharedHome "archived_sessions")
    }

    if (Test-Path $history) {
        Copy-Item $history $backupHome -Force -ErrorAction SilentlyContinue
        $HistorySources += $history
    }
}

if ($HistorySources.Count -gt 0) {
    Merge-JsonlUnique -Sources $HistorySources -Destination $SharedHistory
} elseif (!(Test-Path $SharedHistory)) {
    New-Item -ItemType File -Force -Path $SharedHistory | Out-Null
}

foreach ($h in $Homes) {
    New-Item -ItemType Directory -Force -Path $h | Out-Null

    $sessions = Join-Path $h "sessions"
    $archived = Join-Path $h "archived_sessions"
    $history  = Join-Path $h "history.jsonl"

    Remove-PathWithoutFollowingJunction -Path $sessions
    Remove-PathWithoutFollowingJunction -Path $archived

    New-Item -ItemType Junction -Path $sessions -Target (Join-Path $CodexSharedHome "sessions") | Out-Null
    New-Item -ItemType Junction -Path $archived -Target (Join-Path $CodexSharedHome "archived_sessions") | Out-Null

    if (!$NoHistoryLink) {
        if (Test-Path $history) { Remove-Item -LiteralPath $history -Force }
        New-Item -ItemType HardLink -Path $history -Target $SharedHistory | Out-Null
    }
}

Write-Host ""
Write-Host "Done. codex1, codex2, and codexui now share live sessions."
Write-Host "Auth remains separate because auth.json was not linked or copied."
Write-Host ""
Write-Host "Use:"
Write-Host "  codex1 resume --all"
Write-Host "  codex2 resume --all"
Write-Host "  codexui resume --all"
Write-Host "  codexsharedstatus"
