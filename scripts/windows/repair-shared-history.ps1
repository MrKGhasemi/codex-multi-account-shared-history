<# Launches a single history recovery, waiting for existing UI/CLI writers. #>
param([switch]$Background)
$ErrorActionPreference = 'Stop'
$worker = Join-Path $PSScriptRoot 'repair-shared-history.py'
$switcher = Join-Path $env:USERPROFILE '.codex-switcher'
New-Item -ItemType Directory -Path $switcher -Force | Out-Null
$existing = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^python' -and $_.CommandLine -and $_.CommandLine.Contains($worker) }
if ($existing) { Write-Host 'History recovery is already waiting/running.'; exit 0 }
$python = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.cache\codex-runtimes\*\dependencies\python\python.exe') -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
if (!$python) {
    $command = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($command -and $command.Source -notmatch 'WindowsApps') { $python = $command.Source }
}
if (!$python) { throw 'History recovery needs Python 3 (the Codex desktop bundled Python is supported).' }
$binRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
$runtime = $null
foreach ($process in @(Get-Process codex -ErrorAction SilentlyContinue)) {
    try {
        if ($process.Path -and $process.Path.StartsWith($binRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            $runtime = $process.Path; break
        }
    } catch {}
}
if (!$runtime) {
    $runtime = Get-ChildItem -Path (Join-Path $binRoot '*\codex.exe') -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (!$runtime) { throw 'History recovery needs the installed Codex desktop engine.' }
$backup = Join-Path $switcher ('history-recovery-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$output = Join-Path $switcher 'history-recovery.log'
$errors = Join-Path $switcher 'history-recovery-errors.log'
if ($Background) {
    $arguments = @('-u', ('"' + $worker + '"'), '--runtime', ('"' + $runtime + '"'),
        '--backup', ('"' + $backup + '"'), '--wait')
    $process = Start-Process -FilePath $python -ArgumentList $arguments -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $output -RedirectStandardError $errors
    Write-Host "History recovery queued (PID $($process.Id)). Close the UI and CLI writers once, then let recovery finish before reopening."
    Write-Host "Recovery log: $output"
} else {
    & $python -u $worker --runtime $runtime --backup $backup --wait
    if ($LASTEXITCODE -ne 0) { throw "History recovery failed: exit code $LASTEXITCODE" }
}
