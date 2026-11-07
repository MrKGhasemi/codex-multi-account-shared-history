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

Open the local usage dashboard for all configured accounts:

```bat
open-codex-dashboard.bat
```

It shows email, plan, remaining quota, and reset countdowns when available. It refreshes about once a minute and offers a manual refresh button. Press Ctrl+C in the launcher window to stop monitoring.

Open a tab for every configured account with automatic `/status`:

```bat
open-codex-limits.bat
```

Open only account 3, or preview all tabs:

```bat
open-codex-limits.bat -Account 3
open-codex-limits.bat -PlanOnly
```

Each status tab starts an empty session by default. Pass `-Fork` to fork a random saved chat instead. The viewer uses an empty, helper-created Git workspace; only that workspace is registered as trusted, with a config backup. Git is required. Complete any login prompts in the corresponding tab; after a five-minute timeout, enter `/status` manually.

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

## Linux (Bash)

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

Close Codex clients and back up local history first. The Linux scripts share session folders and command history, without the Windows SQLite inventory and writer-lock safeguards.

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

The setup preserves the existing credential files, adds account 5, and connects the five profiles to shared history. It offers login for profiles it detects as missing a login.
