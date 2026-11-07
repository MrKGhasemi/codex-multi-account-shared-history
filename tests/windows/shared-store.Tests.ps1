param([string]$Workspace = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent))
$ErrorActionPreference = 'Stop'
$root = Join-Path $Workspace ('.diagnostics\guard-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$env:USERPROFILE = $root
$env:LOCALAPPDATA = Join-Path $root 'AppData\Local'
$ui = Join-Path $root '.codex'
$cli = Join-Path $root '.codex-plus-1'
$shared = Join-Path $root '.codex-shared-history'
foreach ($p in @($ui,$cli,(Join-Path $shared 'sessions'),(Join-Path $shared 'archived_sessions'),(Join-Path $shared 'sqlite'),(Join-Path $ui 'thread-writer-locks'),(Join-Path $root '.codex-switcher'))) {
    New-Item -ItemType Directory -Path $p -Force | Out-Null
}
foreach ($homePath in @($ui,$cli)) {
    foreach ($child in @('sessions','archived_sessions')) {
        New-Item -ItemType Junction -Path (Join-Path $homePath $child) -Target (Join-Path $shared $child) | Out-Null
    }
}
New-Item -ItemType Junction -Path (Join-Path $cli 'thread-writer-locks') -Target (Join-Path $ui 'thread-writer-locks') | Out-Null
Set-Content -LiteralPath (Join-Path $ui 'config.toml') -Value ('sqlite_home = "' + (Join-Path $shared 'sqlite').Replace('\','\\') + '"')
Set-Content -LiteralPath (Join-Path $shared 'sqlite\state_5.sqlite') -Value ''
Set-Content -LiteralPath (Join-Path $cli 'auth.json') -Value 'test-auth-must-stay-isolated'
$authHash = (Get-FileHash -LiteralPath (Join-Path $cli 'auth.json')).Hash
$support = Join-Path $Workspace 'scripts\windows\shared-store.ps1'
Copy-Item -LiteralPath $support -Destination (Join-Path $root '.codex-switcher\shared-store.ps1')
. $support
function Expect-Blocked {
    param([scriptblock]$Action, [string]$Label)
    $blocked = $false
    try { & $Action } catch { $blocked = $true }
    if (!$blocked) { throw "Protection failed: $Label" }
    Write-Output "PASS: $Label"
}
Assert-CodexSharedStore -ProfileHome $cli -UiHome $ui -SharedHome $shared
Write-Output 'PASS: intact shared store is accepted'
Expect-Blocked { Assert-CodexSharedArguments @('-c','sqlite_home="elsewhere"') } 'SQLite override is blocked'
Expect-Blocked { Assert-CodexSharedArguments @('--remote=ws://localhost:12345') } 'remote server bypass is blocked'
$lockPath = Join-Path $cli 'thread-writer-locks'
$savedLockPath = Join-Path $cli 'saved-lock-junction'
if (!$lockPath.StartsWith($root + '\') -or !$savedLockPath.StartsWith($root + '\')) { throw 'Unexpected test move paths' }
Move-Item -LiteralPath $lockPath -Destination $savedLockPath
New-Item -ItemType Directory -Path $lockPath | Out-Null
Expect-Blocked { Assert-CodexSharedStore -ProfileHome $cli -UiHome $ui -SharedHome $shared } 'independent writer locks are blocked'
Move-Item -LiteralPath $lockPath -Destination (Join-Path $cli 'unshared-locks')
Move-Item -LiteralPath $savedLockPath -Destination $lockPath
$goodConfig = Get-Content -LiteralPath (Join-Path $ui 'config.toml') -Raw
Set-Content -LiteralPath (Join-Path $ui 'config.toml') -Value ('[tui]' + "`n" + $goodConfig)
Expect-Blocked { Assert-CodexSharedStore -ProfileHome $cli -UiHome $ui -SharedHome $shared } 'nested SQLite key is rejected'
Set-Content -LiteralPath (Join-Path $ui 'config.toml') -Value $goodConfig
New-Item -ItemType File -Path (Join-Path $ui '.desktop-created') | Out-Null
Expect-Blocked { Get-CodexSharedRuntime -UiHome $ui } 'desktop profiles cannot fall back to another CLI engine'
Move-Item -LiteralPath (Join-Path $ui '.desktop-created') -Destination (Join-Path $ui 'saved-desktop-marker')

# Exercise the real generated wrapper with a harmless capturing command.
$installerPath = Join-Path $Workspace 'scripts\windows\install-codex-profiles.ps1'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($installerPath,[ref]$tokens,[ref]$errors)
$assignment = $ast.Find({ param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$BlockTemplate' },$true)
$template = $assignment.Right.Expression.Value
if (!$template) { $template = $assignment.Right.Value }
if (!$template) { throw 'Unable to read generated wrapper template' }
$template = $template.Replace('__COUNT__','1').Replace('__FUNCTIONS__','')
. ([scriptblock]::Create($template))
function codex { $script:captured = @($args); $script:capturedHome = $env:CODEX_HOME }
$env:CODEX_HOME = 'original-environment'
Invoke-CodexWithHome -CodexHome $cli resume --all
if ($script:capturedHome -ne $cli -or $env:CODEX_HOME -ne 'original-environment') { throw 'Profile isolation/environment restoration failed' }
foreach ($flag in @('--no-daemon','--include-non-interactive','--all')) {
    if ($script:captured -notcontains $flag) { throw "Missing guard argument: $flag" }
}
$expectedOverride = 'sqlite_home="' + (Join-Path $shared 'sqlite').Replace('\','\\') + '"'
if ($script:captured -notcontains $expectedOverride) { throw 'Shared SQLite was not enforced at invocation' }
Expect-Blocked { Invoke-CodexWithHome -CodexHome $cli -c 'sqlite_home="elsewhere"' resume --all } 'wrapper rejects store override before starting Codex'
if ($env:CODEX_HOME -ne 'original-environment') { throw 'Failed invocation changed CODEX_HOME' }
Write-Output 'PASS: real wrapper enforces shared store, flags, and isolated account home'

$credentialFunction = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Set-FileCredentialStore' },$true)
. ([scriptblock]::Create($credentialFunction.Extent.Text))
Set-Content -LiteralPath (Join-Path $cli 'config.toml') -Value '[tui]'
Set-FileCredentialStore -ProfileHome $cli
if (!(Get-Content -LiteralPath (Join-Path $cli 'config.toml') -Raw).StartsWith('cli_auth_credentials_store = "file"')) { throw 'Credential key is not top level' }
if ((Get-FileHash -LiteralPath (Join-Path $cli 'auth.json')).Hash -ne $authHash) { throw 'Authentication was changed' }
Write-Output 'PASS: authentication stays untouched; credential config is top level'

$sharingAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $Workspace 'scripts\windows\use-live-shared-history.ps1'),[ref]$tokens,[ref]$errors)
foreach ($name in @('Test-AppendOnlyExtension','Invoke-RoboCopySafe')) {
    $functionAst = $sharingAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name },$true)
    . ([scriptblock]::Create($functionAst.Extent.Text))
}
$src = Join-Path $root 'merge-source'; $dst = Join-Path $root 'merge-target'
New-Item -ItemType Directory -Path $src,$dst | Out-Null
[IO.File]::WriteAllText((Join-Path $src 'chat.jsonl'),"first`nsecond`n")
[IO.File]::WriteAllText((Join-Path $dst 'chat.jsonl'),"first`n")
Invoke-RoboCopySafe -Source $src -Destination $dst
if ([IO.File]::ReadAllText((Join-Path $dst 'chat.jsonl')) -ne "first`nsecond`n") { throw 'Append-only extension was not preserved' }
[IO.File]::WriteAllText((Join-Path $src 'chat.jsonl'),"different`n")
Expect-Blocked { Invoke-RoboCopySafe -Source $src -Destination $dst } 'divergent transcripts cannot overwrite saved messages'
if ([IO.File]::ReadAllText((Join-Path $dst 'chat.jsonl')) -ne "first`nsecond`n") { throw 'Conflicting merge changed the destination' }
Write-Output 'PASS: setup preserves the longer append-only transcript'
