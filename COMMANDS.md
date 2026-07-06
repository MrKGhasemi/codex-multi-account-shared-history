# Copy-paste commands

This file is the short command-only version of the setup.

---

# Windows

## 1. Install Codex CLI if missing

```powershell
npm install -g @openai/codex
codex --version
```

## 2. Install the profile switcher

Run from the repo folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\install-codex-profiles.ps1
. $PROFILE
```

## 3. Login account 1

```powershell
$env:CODEX_HOME="$env:USERPROFILE\.codex-plus-1"
codex login --device-auth
```

## 4. Login account 2

```powershell
$env:CODEX_HOME="$env:USERPROFILE\.codex-plus-2"
codex login --device-auth
```

## 5. Check logins

```powershell
codex1 login status
codex2 login status
```

## 6. Enable shared live history

Close Codex CLI, Codex UI, and IDE extensions first.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\use-live-shared-history.ps1
```

## 7. Use account 1

```powershell
codex1 resume --all
```

## 8. Switch to account 2

Exit Codex first, then:

```powershell
codex2 resume --all
```

## 9. Use UI/default profile from CLI

```powershell
codexui resume --all
```

## 10. Check folder/link status

```powershell
codexsharedstatus
```

## 11. Fix old `$Home` error

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\remove-old-copy-sync-block.ps1
. $PROFILE
```

## 12. Fix script execution policy for one run

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\install-codex-profiles.ps1
```

---

# Linux

## 1. Install Codex CLI if missing

```bash
npm install -g @openai/codex
codex --version
```

## 2. Install shell functions

```bash
bash ./scripts/linux/install-codex-profiles.sh
source "$HOME/.codex-switcher/codex-functions.sh"
```

## 3. Login account 1

```bash
CODEX_HOME="$HOME/.codex-plus-1" codex login --device-auth
```

## 4. Login account 2

```bash
CODEX_HOME="$HOME/.codex-plus-2" codex login --device-auth
```

## 5. Check logins

```bash
codex1 login status
codex2 login status
```

## 6. Enable shared live history

Close Codex CLI/UI/IDE first.

```bash
bash ./scripts/linux/use-live-shared-history.sh
```

## 7. Use account 1

```bash
codex1 resume --all
```

## 8. Switch to account 2

Exit Codex first, then:

```bash
codex2 resume --all
```

## 9. Use default/UI profile from CLI

```bash
codexui resume --all
```

## 10. Check folder/link status

```bash
codexsharedstatus
```

---

# Common commands

## Resume last session

```bash
codex1 resume --last
codex2 resume --last
```

## Start new session

```bash
codex1
codex2
```

## Delete session by id/name

```bash
codex delete <SESSION_ID_OR_NAME>
```

## Check profile paths

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\check-codex-profiles.ps1
```

Linux:

```bash
bash ./scripts/linux/check-codex-profiles.sh
```

## Never run these unless you intentionally want to remove login credentials

```bash
codex logout
```

Do not delete or commit:

```text
auth.json
```
