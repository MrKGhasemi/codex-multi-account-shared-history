<#
.SYNOPSIS
  Prints Codex profile paths, auth/config/session status, and junction targets on Windows.
#>

$Homes = @(
    @{ Name = "UI";      Path = Join-Path $env:USERPROFILE ".codex" },
    @{ Name = "codex1";  Path = Join-Path $env:USERPROFILE ".codex-plus-1" },
    @{ Name = "codex2";  Path = Join-Path $env:USERPROFILE ".codex-plus-2" },
    @{ Name = "codex3";  Path = Join-Path $env:USERPROFILE ".codex-plus-3" },
    @{ Name = "codex4";  Path = Join-Path $env:USERPROFILE ".codex-plus-4" },
    @{ Name = "shared";  Path = Join-Path $env:USERPROFILE ".codex-shared-history" }
)

Write-Host "Codex executable:"
try {
    Get-Command codex -ErrorAction Stop | Format-List Source,Version
} catch {
    Write-Host "  codex not found in PATH"
}

foreach ($h in $Homes) {
    Write-Host ""
    Write-Host "[$($h.Name)] $($h.Path)"

    foreach ($child in @("auth.json", "config.toml", "history.jsonl", "sessions", "archived_sessions")) {
        $p = Join-Path $h.Path $child
        if (Test-Path $p) {
            $item = Get-Item -LiteralPath $p -Force
            $kind = if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { "link" } elseif ($item.PSIsContainer) { "dir" } else { "file" }
            $target = ""
            try {
                if ($kind -eq "link" -and $item.Target) { $target = " -> $($item.Target)" }
            } catch {}
            Write-Host ("  {0,-18} {1}{2}" -f $child, $kind, $target)
        } else {
            Write-Host ("  {0,-18} missing" -f $child)
        }
    }
}

Write-Host ""
Write-Host "Login status checks:"
Write-Host "  codex1 login status"
Write-Host "  codex2 login status"
Write-Host "  codex3 login status"
Write-Host "  codex4 login status"
Write-Host "  codexui login status"
