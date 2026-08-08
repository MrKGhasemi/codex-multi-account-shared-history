# Codex Four-Account Shared History Switcher

Use four ChatGPT/Codex CLI accounts on the same machine while keeping each login separate and sharing the same local Codex conversation history.

This setup provides these commands:

```text
codex1  -> account 1
codex2  -> account 2
codex3  -> account 3
codex4  -> account 4
codexui -> default/UI profile
```

All five profiles can see the same local sessions, but the four CLI accounts keep separate authentication files.

> Important: this is a local helper project. It is not an official OpenAI product.

---

## How it works

Each account receives its own `CODEX_HOME`:

```text
Account 1 -> ~/.codex-plus-1
Account 2 -> ~/.codex-plus-2
Account 3 -> ~/.codex-plus-3
Account 4 -> ~/.codex-plus-4
UI/default -> ~/.codex
```

Authentication remains separate:

```text
~/.codex-plus-1/auth.json
~/.codex-plus-2/auth.json
~/.codex-plus-3/auth.json
~/.codex-plus-4/auth.json
~/.codex/auth.json
```

Only conversation data is shared:

```text
sessions/
archived_sessions/
history.jsonl
```

The shared store is:

```text
~/.codex-shared-history
```

The scripts link every profile to it:

```text
~/.codex/sessions        -> ~/.codex-shared-history/sessions
~/.codex-plus-1/sessions -> ~/.codex-shared-history/sessions
~/.codex-plus-2/sessions -> ~/.codex-shared-history/sessions
~/.codex-plus-3/sessions -> ~/.codex-shared-history/sessions
~/.codex-plus-4/sessions -> ~/.codex-shared-history/sessions
```

On Windows, `sessions` and `archived_sessions` use directory Junctions. On Linux, they use symbolic links. Windows uses a hardlink for `history.jsonl`; Linux uses a symbolic link.

The scripts never intentionally copy or link `auth.json`.

---

## Repository layout

```text
.
├── README.md
├── COMMANDS.md
├── SECURITY.md
├── .gitignore
└── scripts
    ├── windows
    │   ├── install-codex-profiles.ps1
    │   ├── use-live-shared-history.ps1
    │   ├── check-codex-profiles.ps1
    │   └── remove-old-copy-sync-block.ps1
    └── linux
        ├── install-codex-profiles.sh
        ├── use-live-shared-history.sh
        └── check-codex-profiles.sh
```

---

# Windows setup

## 1. Verify Codex CLI

```powershell
codex --version
```

If needed:

```powershell
npm install -g @openai/codex
```

Close and reopen PowerShell after installation.

## 2. Install the profile commands

Run from the repository folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\install-codex-profiles.ps1
. $PROFILE
```

The installer creates:

```text
%USERPROFILE%\.codex
%USERPROFILE%\.codex-plus-1
%USERPROFILE%\.codex-plus-2
%USERPROFILE%\.codex-plus-3
%USERPROFILE%\.codex-plus-4
%USERPROFILE%\.codex-shared-history
```

It adds these PowerShell functions:

```text
codex1
codex2
codex3
codex4
codexui
codexsharedstatus
```

## 3. Log in to all four accounts

Account 1:

```powershell
$env:CODEX_HOME="$env:USERPROFILE\.codex-plus-1"
codex login --device-auth
```

Account 2:

```powershell
$env:CODEX_HOME="$env:USERPROFILE\.codex-plus-2"
codex login --device-auth
```

Account 3:

```powershell
$env:CODEX_HOME="$env:USERPROFILE\.codex-plus-3"
codex login --device-auth
```

Account 4:

```powershell
$env:CODEX_HOME="$env:USERPROFILE\.codex-plus-4"
codex login --device-auth
```

Check them:

```powershell
codex1 login status
codex2 login status
codex3 login status
codex4 login status
```

## 4. Enable shared live history

Close Codex CLI, the Codex desktop app, and any IDE extension using Codex. Then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\use-live-shared-history.ps1
```

This creates a timestamped backup, merges existing sessions from every profile, and creates shared links.

To share session folders without linking `history.jsonl`:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\use-live-shared-history.ps1 -NoHistoryLink
```

## 5. Use the accounts

```powershell
codex1 resume --all
codex2 resume --all
codex3 resume --all
codex4 resume --all
codexui resume --all
```

Check profile and link status:

```powershell
codexsharedstatus
```

Or run the standalone checker:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\check-codex-profiles.ps1
```

---

# Linux setup

## 1. Verify Codex CLI

```bash
codex --version
```

If needed:

```bash
npm install -g @openai/codex
```

## 2. Install the shell functions

Run from the repository folder:

```bash
bash ./scripts/linux/install-codex-profiles.sh
source "$HOME/.codex-switcher/codex-functions.sh"
```

The installer creates:

```text
~/.codex
~/.codex-plus-1
~/.codex-plus-2
~/.codex-plus-3
~/.codex-plus-4
~/.codex-shared-history
```

## 3. Log in to all four accounts

```bash
CODEX_HOME="$HOME/.codex-plus-1" codex login --device-auth
CODEX_HOME="$HOME/.codex-plus-2" codex login --device-auth
CODEX_HOME="$HOME/.codex-plus-3" codex login --device-auth
CODEX_HOME="$HOME/.codex-plus-4" codex login --device-auth
```

Check them:

```bash
codex1 login status
codex2 login status
codex3 login status
codex4 login status
```

## 4. Enable shared live history

Close all Codex CLI/UI/IDE processes, then run:

```bash
bash ./scripts/linux/use-live-shared-history.sh
```

To skip linking `history.jsonl`:

```bash
bash ./scripts/linux/use-live-shared-history.sh --no-history-link
```

## 5. Use the accounts

```bash
codex1 resume --all
codex2 resume --all
codex3 resume --all
codex4 resume --all
codexui resume --all
codexsharedstatus
```

Or run the standalone checker:

```bash
bash ./scripts/linux/check-codex-profiles.sh
```

---

# Daily commands

Start a new session:

```bash
codex1
codex2
codex3
codex4
```

Resume the last session:

```bash
codex1 resume --last
codex2 resume --last
codex3 resume --last
codex4 resume --last
```

Resume from the full session list:

```bash
codex1 resume --all
codex2 resume --all
codex3 resume --all
codex4 resume --all
```

Check login status:

```bash
codex1 login status
codex2 login status
codex3 login status
codex4 login status
codexui login status
```

---

# Concurrency warning

Do not open and modify the same conversation from multiple profiles at the same time.

Because `codex1`, `codex2`, `codex3`, `codex4`, and `codexui` share the same live session files, simultaneous writers can conflict. Exit one Codex process before continuing the same conversation through another account.

---

# Updating an older two- or three-account installation

The installers replace the old marked switcher block, so upgrading is straightforward.

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\install-codex-profiles.ps1
. $PROFILE
powershell -ExecutionPolicy Bypass -File .\scripts\windows\use-live-shared-history.ps1
```

Linux:

```bash
bash ./scripts/linux/install-codex-profiles.sh
source "$HOME/.codex-switcher/codex-functions.sh"
bash ./scripts/linux/use-live-shared-history.sh
```

Your existing profiles remain in place. The scripts add any missing `.codex-plus-3` and `.codex-plus-4` profiles, preserve separate authentication, merge existing sessions from all accounts, and connect every profile to the shared store.

---

# Troubleshooting

## `codex1`, `codex2`, `codex3`, or `codex4` is not recognized

Windows:

```powershell
. $PROFILE
```

If needed, reinstall:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\install-codex-profiles.ps1
. $PROFILE
```

Linux:

```bash
source "$HOME/.codex-switcher/codex-functions.sh"
```

## PowerShell says script execution is disabled

Use a one-run bypass:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\install-codex-profiles.ps1
```

## Deleted conversations return

An old copy/merge synchronization function may still be installed. On Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\remove-old-copy-sync-block.ps1
. $PROFILE
powershell -ExecutionPolicy Bypass -File .\scripts\windows\use-live-shared-history.ps1
```

## Links cannot be created

Close Codex CLI, desktop app, and IDE extensions. Then rerun the shared-history script. On Windows, Administrator PowerShell may be required if Junction creation is restricted.

## Inspect the setup

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\check-codex-profiles.ps1
```

Linux:

```bash
bash ./scripts/linux/check-codex-profiles.sh
```

---

# Rollback

The shared-history scripts create a backup before replacing profile session folders. The folder name resembles:

```text
codex-backup-before-shared-links-20260724-190000
```

To roll back:

1. Close every Codex process.
2. Remove the `sessions`, `archived_sessions`, and linked `history.jsonl` entries from each profile.
3. Restore the desired data from the timestamped backup.
4. Remove or reinstall the marked switcher block in your PowerShell profile or shell configuration.

Do not delete `auth.json` unless you intentionally want to remove that account’s local login.
