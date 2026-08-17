# Command reference

## Windows: one-file setup

Interactive:

```bat
setup-codex-accounts.bat
```

Pass the account count directly:

```bat
setup-codex-accounts.bat 6
```

## Windows: manual PowerShell

Configure six account profiles:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\install-codex-profiles.ps1 -AccountCount 6
```

Enable shared live local history:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\use-live-shared-history.ps1 -AccountCount 6 -Force
```

Check:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\check-codex-profiles.ps1
```

Login to a profile:

```powershell
$env:CODEX_HOME="$env:USERPROFILE\.codex-plus-1"
codex login
```

Headless/device-code login:

```powershell
$env:CODEX_HOME="$env:USERPROFILE\.codex-plus-1"
codex login --device-auth
```

After opening a new PowerShell window:

```powershell
codex1
codex2
codexaccount 2
codexui
codexsharedstatus
```

Resume shared sessions:

```powershell
codex1 resume --last
codex1 resume --all
codexui resume --all
```

Check auth:

```powershell
codex1 login status
codex2 login status
codexui login status
```

## Linux / macOS-like shells

Configure six accounts:

```bash
bash ./scripts/linux/install-codex-profiles.sh 6
source "$HOME/.codex-switcher/codex-functions.sh"
```

Login:

```bash
CODEX_HOME="$HOME/.codex-plus-1" codex login
```

Enable live sharing:

```bash
bash ./scripts/linux/use-live-shared-history.sh --accounts 6
```

Check:

```bash
bash ./scripts/linux/check-codex-profiles.sh
```

Use:

```bash
codex1
codex6
codexaccount 6
codexui
codexsharedstatus
```

Never commit or share any profile's `auth.json`.

## Add one more account without relogging existing accounts

If `codex1` through `codex4` already have `auth.json`, run:

```bat
setup-codex-accounts.bat 5
```

The setup preserves accounts 1-4, adds account 5, shares history across all five, and offers login only for account 5.
