$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'shared-store.ps1')
$countFile = Join-Path $env:USERPROFILE '.codex-switcher\account-count.txt'
if (!(Test-Path -LiteralPath $countFile)) { throw 'Run setup-codex-accounts.bat first.' }
$count = 0
if (![int]::TryParse((Get-Content -LiteralPath $countFile -Raw).Trim(), [ref]$count) -or $count -lt 1 -or $count -gt 99) {
    throw 'Saved account count must be between 1 and 99.'
}
$runtime = Get-CodexSharedRuntime
if ($runtime -eq 'codex') { $runtime = (Get-Command codex.exe -ErrorAction Stop).Source }
$python = Get-CodexSharedPython
& $python -u (Join-Path $PSScriptRoot 'limits-dashboard.py') --runtime $runtime --home $env:USERPROFILE --count $count
exit $LASTEXITCODE
