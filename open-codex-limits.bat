@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\open-codex-limits.ps1" %*
if errorlevel 1 (
    echo.
    echo Could not open the account status tabs. See the error above.
    pause
    exit /b 1
)
