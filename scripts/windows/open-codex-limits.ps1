<# Open one PowerShell tab per configured account, each showing Codex /status. #>
param(
    [ValidateRange(0,99)][int]$AccountCount = 0,
    [ValidateRange(0,99)][int]$Account = 0,
    [switch]$InTab,
    [switch]$PlanOnly,
    [switch]$Fork,
    [string]$DiagnosticLog
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'shared-store.ps1')
$ui = Join-Path $env:USERPROFILE '.codex'
$shared = Join-Path $env:USERPROFILE '.codex-shared-history'

if ($InTab) {
    if ($Account -lt 1) { throw 'A tab needs an account number.' }
    try {
        $homePath = Join-Path $env:USERPROFILE ".codex-plus-$Account"
        Assert-CodexSharedStore -ProfileHome $homePath -UiHome $ui -SharedHome $shared
        $runtime = Get-CodexSharedRuntime -UiHome $ui
        $python = Get-CodexSharedPython
        $sessionId = $null
        if ($Fork) {
            $selection = & $python (Join-Path $PSScriptRoot 'select-status-session.py') --database (Join-Path $shared 'sqlite\state_5.sqlite')
            if ($LASTEXITCODE -ne 0) { throw 'Could not read the shared chat inventory.' }
            $sessionId = ($selection | ConvertFrom-Json).sessionId
        }
        $env:CODEX_HOME = $homePath
        if ($env:TERM -eq 'dumb') { Remove-Item Env:TERM }
        $sqliteOverride = 'sqlite_home="' + (Join-Path $shared 'sqlite').Replace('\','\\') + '"'
        $cliArgs = @('--no-daemon', '--no-alt-screen', '-c', $sqliteOverride, '-s', 'read-only')
        # Never start a status viewer in an arbitrary chat's project. In
        # particular, a user's home may itself be a Git repository. Give this
        # viewer an empty repository and trust only that exact directory.
        $git = (Get-Command git.exe -ErrorAction Stop).Source
        $workspaceInfo = & $python (Join-Path $PSScriptRoot 'prepare-status-workspace.py') `
            --profile-home $homePath --workspace-root (Join-Path $env:LOCALAPPDATA 'CodexAccountStatus') --git $git
        if ($LASTEXITCODE -ne 0) { throw 'Could not prepare the isolated status workspace.' }
        $directory = ($workspaceInfo | ConvertFrom-Json).directory
        $cliArgs += @('-C', [string]$directory)
        if ($sessionId) {
            # Native fork avoids the occupied-writer picker and never resumes a
            # chat already open in another account. No model prompt is supplied.
            $cliArgs += @('fork', [string]$sessionId)
        }
        Clear-Host
        $Host.UI.RawUI.WindowTitle = "codex$Account - limits"
        Write-Host "codex$Account - waiting for the Codex composer, then running /status."
        Write-Host 'Using an isolated, empty status workspace. Complete login if this account requires it.'
        Add-Type -Path (Join-Path $PSScriptRoot 'status-console.cs')
        [CodexStatusConsole]::Start(300, $DiagnosticLog)
        try {
            & $runtime @cliArgs
        } finally {
            [CodexStatusConsole]::Stop()
        }
    } catch {
        Write-Host "codex${Account}: $($_.Exception.Message)" -ForegroundColor Red
    }
    # -NoExit keeps failures and the returned prompt visible in this tab.
    return
}

if ($AccountCount -eq 0) {
    $countFile = Join-Path $env:USERPROFILE '.codex-switcher\account-count.txt'
    if (!(Test-Path -LiteralPath $countFile)) { throw 'Run setup-codex-accounts.bat first; the saved account count is missing.' }
    $saved = (Get-Content -LiteralPath $countFile -Raw).Trim()
    if (![int]::TryParse($saved, [ref]$AccountCount) -or $AccountCount -lt 1 -or $AccountCount -gt 99) {
        throw 'The saved account count must be between 1 and 99.'
    }
}
if ($Account -gt $AccountCount) { throw 'The requested account exceeds the configured count.' }
$accounts = @(1..$AccountCount)
if ($Account -gt 0) { $accounts = @($Account) }
$shell = (Get-Command powershell.exe -ErrorAction Stop).Source
$self = $PSCommandPath
# One wt invocation with new-tab subcommands means one window, not N windows.
$terminalArgs = @('-w', 'new')
foreach ($number in $accounts) {
    $profileHome = Join-Path $env:USERPROFILE ".codex-plus-$number"
    Assert-CodexSharedStore -ProfileHome $profileHome -UiHome $ui -SharedHome $shared
    if ($terminalArgs.Count -gt 2) { $terminalArgs += ';' }
    $terminalArgs += @('new-tab', '--title', "codex$number - limits", '--suppressApplicationTitle',
        $shell, '-NoLogo', '-NoProfile', '-NoExit', '-ExecutionPolicy', 'Bypass',
        '-File', $self, '-InTab', '-Account', [string]$number)
    if ($DiagnosticLog) { $terminalArgs += @('-DiagnosticLog', ($DiagnosticLog + ".$number")) }
    if ($Fork) { $terminalArgs += '-Fork' }
}
if ($PlanOnly) {
    [pscustomobject]@{ Accounts = $accounts; Executable = 'wt.exe'; Arguments = $terminalArgs } | ConvertTo-Json -Depth 5
    return
}
$terminal = Get-Command wt.exe -ErrorAction Stop
& $terminal.Source @terminalArgs
if ($LASTEXITCODE -ne 0) { throw "Windows Terminal exited with code $LASTEXITCODE." }
Write-Host "Opened $($accounts.Count) account status tabs in one Windows Terminal window."
