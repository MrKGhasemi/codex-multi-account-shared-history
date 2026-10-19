# Shared by setup and the installed PowerShell helpers. No authentication is read.
function Get-CodexSharedRuntime {
    param([string]$UiHome = (Join-Path $env:USERPROFILE '.codex'))
    $binRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
    $running = @(@(Get-Process -Name codex -ErrorAction SilentlyContinue) | ForEach-Object {
        try {
            if ($_.Path -and $_.Path.StartsWith($binRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { $_.Path }
        } catch {}
    } | Select-Object -Unique)
    if ($running.Count -gt 1) { throw 'Multiple desktop Codex engine versions are running. Restart the desktop before continuing a shared chat.' }
    if ($running.Count -eq 1) { return $running[0] }
    foreach ($directory in @(Get-ChildItem -LiteralPath $binRoot -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
        $path = Join-Path $directory.FullName 'codex.exe'
        if (Test-Path -LiteralPath $path) { return $path }
    }
    if (Test-Path -LiteralPath (Join-Path $UiHome '.desktop-created')) {
        throw 'The desktop Codex engine is unavailable. Shared chats cannot fall back to a different CLI engine.'
    }
    return 'codex'
}

function Test-CodexSharedDirectory {
    param([string]$Path, [string]$Target)
    if (!(Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $fullTarget = [IO.Path]::GetFullPath($Target).TrimEnd('\')
    if ([string]::Equals($fullPath, $fullTarget, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    $item = Get-Item -LiteralPath $Path -Force
    if (!(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or !$item.Target) { return $false }
    $actual = [string]@($item.Target)[0]
    if (![IO.Path]::IsPathRooted($actual)) { $actual = Join-Path $item.Parent.FullName $actual }
    return [string]::Equals([IO.Path]::GetFullPath($actual).TrimEnd('\'), $fullTarget, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-CodexSharedStore {
    param([string]$ProfileHome, [string]$UiHome, [string]$SharedHome)
    foreach ($child in @('sessions', 'archived_sessions')) {
        foreach ($homePath in @($UiHome, $ProfileHome) | Select-Object -Unique) {
            if (!(Test-CodexSharedDirectory -Path (Join-Path $homePath $child) -Target (Join-Path $SharedHome $child))) {
                throw "Shared $child link is missing or points elsewhere: $homePath. Codex was not started, to protect saved messages. Repair the shared links with setup."
            }
        }
    }
    $locks = Join-Path $UiHome 'thread-writer-locks'
    if (!(Test-CodexSharedDirectory -Path (Join-Path $ProfileHome 'thread-writer-locks') -Target $locks)) {
        throw 'The CLI writer locks are not shared with the desktop. Codex was not started, to prevent conflicting writes. Repair the shared links with setup.'
    }
    $configPath = Join-Path $UiHome 'config.toml'
    if (!(Test-Path -LiteralPath $configPath)) { throw 'Desktop shared SQLite configuration is missing. Codex was not started.' }
    $content = Get-Content -LiteralPath $configPath -Raw
    $topLevel = [regex]::Split($content, '(?m)^\s*\[')[0]
    $expected = 'sqlite_home = "' + (Join-Path $SharedHome 'sqlite').Replace('\', '\\') + '"'
    $lines = @([regex]::Matches($topLevel, '(?m)^\s*sqlite_home\s*=.*$'))
    if ($lines.Count -ne 1 -or $lines[0].Value.Trim() -ne $expected) {
        throw 'The desktop SQLite location has changed. Codex was not started, to avoid splitting chat history. Repair the shared configuration with setup.'
    }
    if (!(Test-Path -LiteralPath (Join-Path $SharedHome 'sqlite\state_5.sqlite'))) {
        throw 'The shared thread database is missing. Codex was not started, to avoid creating an empty replacement store.'
    }
}

function Assert-CodexSharedArguments {
    param([object[]]$Arguments)
    foreach ($argument in $Arguments) {
        $text = [string]$argument
        if ($text -match '^--remote(?:=|$)' -or $text -match '^(?:--config=|-c)?sqlite_home\s*=') {
            throw 'Shared-profile helpers cannot override sqlite_home or connect to another app server. Those options bypass shared storage protection.'
        }
    }
}

function Get-CodexSharedPython {
    $python = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.cache\codex-runtimes\*\dependencies\python\python.exe') -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    if ($python) { return $python }
    $command = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($command -and $command.Source -notmatch 'WindowsApps') { return $command.Source }
    throw 'Preserving existing SQLite history needs Python 3.11 or newer (the desktop bundled Python is supported).'
}
