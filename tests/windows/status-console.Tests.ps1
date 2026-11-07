$ErrorActionPreference = 'Stop'
Add-Type -Path (Join-Path $PSScriptRoot '../../scripts/windows/status-console.cs')
$warningFooter = 'Ask Codex to do anything GPT-6.1-Sol medium Fast 1 warning f2 to view'
if (![CodexStatusConsole]::IsReady($warningFooter)) { throw 'Warning footer hides ready composer' }
if (![CodexStatusConsole]::IsReady('Ask Codex to do anything ? for shortcuts')) { throw 'Normal composer rejected' }
foreach ($screen in @('Trust this folder? Trust and continue',
    'Forking session... Ask Codex to do anything',
    'Resuming session... Ask Codex to do anything')) {
    if ([CodexStatusConsole]::IsReady($screen)) { throw "Input could be sent before startup completes: $screen" }
}
if ([CodexStatusConsole]::IsStatusVisible('Ask Codex to do anything')) { throw 'Composer mistaken for status output' }
if (![CodexStatusConsole]::IsStatusVisible('Account: example Session: sample 5h limit: 80% left')) { throw 'Status panel rejected' }
'PASS: warning footer; trust and loading dialogs; confirmed status output'
