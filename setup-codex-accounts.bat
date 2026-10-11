@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

title Codex Multi-Account Shared History Setup

echo ============================================================
echo   Codex Multi-Account Shared History - Windows Setup
echo ============================================================
echo.
echo This creates separate local Codex login profiles while all
echo profiles share the same local conversation/session history.
echo It does NOT create ChatGPT accounts and never shares auth.json.
echo Existing profile logins are preserved and are NOT logged in again.
echo.

if not "%~1"=="" (
    set "ACCOUNT_COUNT=%~1"
) else (
    set /p "ACCOUNT_COUNT=How many TOTAL Codex/ChatGPT accounts do you want to configure? "
)

where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo ERROR: Windows PowerShell was not found.
    goto :failed
)

if not defined ACCOUNT_COUNT goto :invalid_count
for /f "usebackq delims=" %%N in (`powershell.exe -NoLogo -NoProfile -Command "$n=0; if([int]::TryParse($env:ACCOUNT_COUNT,[ref]$n) -and $n -ge 1 -and $n -le 99){$n}else{exit 2}"`) do set "ACCOUNT_COUNT=%%N"
if errorlevel 1 goto :invalid_count
if not defined ACCOUNT_COUNT goto :invalid_count

where codex >nul 2>&1
if errorlevel 1 (
    echo Codex CLI was not found in PATH.
    where npm >nul 2>&1
    if errorlevel 1 (
        echo Install Node.js/npm and Codex CLI first, then run this file again.
        echo Command: npm install -g @openai/codex
        goto :failed
    )

    choice /C YN /N /M "Install @openai/codex globally with npm now? [Y/N]: "
    if errorlevel 2 goto :failed

    call npm install -g @openai/codex
    if errorlevel 1 (
        echo ERROR: Codex CLI installation failed.
        goto :failed
    )
)

echo.
echo [1/3] Creating/updating Codex profile homes...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\install-codex-profiles.ps1" -AccountCount %ACCOUNT_COUNT%
if errorlevel 1 goto :failed

rem The PowerShell installer is additive by default. It may keep a larger
rem previously configured count rather than silently dropping old profiles.
for /f "usebackq delims=" %%N in (`powershell.exe -NoLogo -NoProfile -Command "$p=Join-Path (Join-Path $env:USERPROFILE '.codex-switcher') 'account-count.txt'; if(Test-Path $p){(Get-Content -LiteralPath $p -Raw).Trim()}"`) do set "ACCOUNT_COUNT=%%N"

echo.
echo [2/3] Merging history and creating/updating shared live links...
echo Force mode: no close-session pause. Existing correct links are left in place.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\use-live-shared-history.ps1" -AccountCount %ACCOUNT_COUNT% -Force
if errorlevel 1 goto :failed

echo.
echo [3/3] Login setup
echo Checking each existing profile with: codex login status
echo Logged-in profiles are preserved and are NOT logged in again.
set "MISSING_ACCOUNTS="
set /a MISSING_COUNT=0
for /L %%I in (1,1,%ACCOUNT_COUNT%) do (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\test-codex-login.ps1" -Account %%I
    if !errorlevel! EQU 0 (
        echo   codex%%I: already logged in - keeping existing authentication
    ) else if exist "%USERPROFILE%\.codex-plus-%%I\auth.json" (
        rem Conservative fallback: never overwrite/remove an existing auth.json even
        rem if login status fails because of a transient CLI/configuration problem.
        echo   codex%%I: auth.json exists - preserving it; no automatic relogin
    ) else (
        echo   codex%%I: not logged in - login needed
        set "MISSING_ACCOUNTS=!MISSING_ACCOUNTS! %%I"
        set /a MISSING_COUNT+=1
    )
)

if !MISSING_COUNT! EQU 0 goto :skip_login

echo.
choice /C YN /N /M "Log in only the !MISSING_COUNT! missing profile(s) now? [Y/N]: "
if errorlevel 2 goto :skip_login

for %%I in (!MISSING_ACCOUNTS!) do (
    echo.
    echo ------------------------------------------------------------
    echo Login for NEW/UNLOGGED account %%I
    echo CODEX_HOME=%USERPROFILE%\.codex-plus-%%I
    echo ------------------------------------------------------------
    set "CODEX_HOME=%USERPROFILE%\.codex-plus-%%I"
    call codex login
    if errorlevel 1 (
        echo WARNING: Login for account %%I did not finish successfully.
        echo You can retry later with:
        echo   set CODEX_HOME=%USERPROFILE%\.codex-plus-%%I
        echo   codex login
    )
)
set "CODEX_HOME="

:skip_login
echo.
echo Checking the final setup...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\check-codex-profiles.ps1" -AccountCount %ACCOUNT_COUNT%

echo.
echo ============================================================
echo Setup complete.
echo.
echo Open a NEW PowerShell window to use:
echo   codex1
if %ACCOUNT_COUNT% GTR 1 echo   ... through codex%ACCOUNT_COUNT%
echo   codexaccount ^<number^>
echo   codexui
echo   codexsharedstatus
echo.
echo Existing authentication was kept. Only profiles confirmed missing login were offered login.
echo All configured profiles share the same live local session/history store.
echo The SQLite thread index is shared too, so the UI and CLI use the same picker data.
echo This is a one-time setup for the configured profiles. New session changes
echo are shared automatically after restarting the other client; do not rerun
echo this file for normal UI/CLI use.
echo The UI and a CLI profile must use the same account to show the same chats.
echo Resume helpers automatically include desktop-created sessions for every profile:
echo   codex1 resume --all
if %ACCOUNT_COUNT% GTR 1 echo   ... through codex%ACCOUNT_COUNT% resume --all
echo   codexui resume --all
echo ============================================================
echo.
pause
exit /b 0

:invalid_count
echo.
echo ERROR: Enter a whole number from 1 to 99.
echo.
pause
exit /b 2

:failed
echo.
echo Setup did not complete. Review the message above and run this
echo batch file again after fixing the reported issue.
echo.
pause
exit /b 1
