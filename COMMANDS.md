# Copy-paste commands for four Codex accounts

## Windows

Install Codex CLI if missing:

```powershell
npm install -g @openai/codex
codex --version
```

Install or upgrade the switcher:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\install-codex-profiles.ps1
. $PROFILE
```

Log in:

```powershell
$env:CODEX_HOME="$env:USERPROFILE\.codex-plus-1"; codex login --device-auth
$env:CODEX_HOME="$env:USERPROFILE\.codex-plus-2"; codex login --device-auth
$env:CODEX_HOME="$env:USERPROFILE\.codex-plus-3"; codex login --device-auth
$env:CODEX_HOME="$env:USERPROFILE\.codex-plus-4"; codex login --device-auth
```

Check logins:

```powershell
codex1 login status
codex2 login status
codex3 login status
codex4 login status
```

Enable shared live history:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\use-live-shared-history.ps1
```

Use profiles:

```powershell
codex1 resume --all
codex2 resume --all
codex3 resume --all
codex4 resume --all
codexui resume --all
```

Inspect links:

```powershell
codexsharedstatus
powershell -ExecutionPolicy Bypass -File .\scripts\windows\check-codex-profiles.ps1
```

Remove an old copy-sync block:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\remove-old-copy-sync-block.ps1
. $PROFILE
```

---

## Linux

Install Codex CLI if missing:

```bash
npm install -g @openai/codex
codex --version
```

Install or upgrade the switcher:

```bash
bash ./scripts/linux/install-codex-profiles.sh
source "$HOME/.codex-switcher/codex-functions.sh"
```

Log in:

```bash
CODEX_HOME="$HOME/.codex-plus-1" codex login --device-auth
CODEX_HOME="$HOME/.codex-plus-2" codex login --device-auth
CODEX_HOME="$HOME/.codex-plus-3" codex login --device-auth
CODEX_HOME="$HOME/.codex-plus-4" codex login --device-auth
```

Check logins:

```bash
codex1 login status
codex2 login status
codex3 login status
codex4 login status
```

Enable shared live history:

```bash
bash ./scripts/linux/use-live-shared-history.sh
```

Use profiles:

```bash
codex1 resume --all
codex2 resume --all
codex3 resume --all
codex4 resume --all
codexui resume --all
```

Inspect links:

```bash
codexsharedstatus
bash ./scripts/linux/check-codex-profiles.sh
```

---

## Common commands

Start new sessions:

```bash
codex1
codex2
codex3
codex4
```

Resume last sessions:

```bash
codex1 resume --last
codex2 resume --last
codex3 resume --last
codex4 resume --last
```

Never delete or commit any profile’s `auth.json` unless you intentionally want to remove credentials.
