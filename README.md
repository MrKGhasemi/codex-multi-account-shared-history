# Codex Multi-Account Shared History Switcher

Use **any practical number of Codex CLI / ChatGPT logins on one machine** while keeping every login separate and sharing the same local Codex conversation history.

> This is a local helper project. It is not an official OpenAI product.

## What changed

The project is no longer hard-coded to four accounts.

On Windows, run:

```bat
setup-codex-accounts.bat
```

The batch file asks how many accounts you want (1-99), then:

1. creates `.codex-plus-1` through `.codex-plus-N`
2. configures each CLI profile to use its own file-backed `auth.json`
3. installs `codex1` through `codexN` PowerShell commands
4. merges existing local sessions into one shared store
5. connects every profile to that shared store
6. runs `codex login status` separately for each existing `CODEX_HOME` and preserves logged-in profiles
7. offers login only for newly added/unlogged profiles
8. prints a final status check

It does **not** create ChatGPT accounts for you. You must already have the accounts you want to sign in with.

## How it works

For `N` accounts:

```text
Account 1 -> ~/.codex-plus-1
Account 2 -> ~/.codex-plus-2
...
Account N -> ~/.codex-plus-N
UI/default -> ~/.codex
```

Authentication stays separate:

```text
~/.codex-plus-1/auth.json
~/.codex-plus-2/auth.json
...
~/.codex-plus-N/auth.json
~/.codex/auth.json
```

Only local conversation data is shared:

```text
sessions/
archived_sessions/
history.jsonl
```

The shared store is:

```text
~/.codex-shared-history
```

Every configured profile points at the same live session directories. On Windows, `sessions` and `archived_sessions` use directory junctions and `history.jsonl` uses a hardlink. On Linux, the project uses symbolic links.

Because the profiles point to the same files, **there is no periodic copy-sync process**. New and resumed local sessions are visible across the configured profiles immediately.

## Security model

New or unlogged CLI profiles are configured with:

```toml
cli_auth_credentials_store = "file"
```

That makes those Codex credentials live in the profile's own `CODEX_HOME/auth.json`. Existing file-backed profiles keep that behavior. If an already-existing profile is successfully logged in through a keyring/auto credential store, the installer preserves its current credential-store configuration rather than breaking that login. The scripts never intentionally copy, link, print, or commit `auth.json`.

Treat every `auth.json` like a password.

## Repository layout

```text
.
├── setup-codex-accounts.bat
├── README.md
├── COMMANDS.md
├── SECURITY.md
├── .gitignore
└── scripts
    ├── windows
    │   ├── install-codex-profiles.ps1
    │   ├── use-live-shared-history.ps1
    │   ├── check-codex-profiles.ps1
    │   ├── test-codex-login.ps1
    │   └── remove-old-copy-sync-block.ps1
    └── linux
        ├── install-codex-profiles.sh
        ├── use-live-shared-history.sh
        └── check-codex-profiles.sh
```

# Windows: easiest setup

## 1. Run the batch file

Double-click:

```text
setup-codex-accounts.bat
```

or from Command Prompt:

```bat
setup-codex-accounts.bat
```

Enter the number of accounts when prompted.

You can also provide the count directly:

```bat
setup-codex-accounts.bat 6
```

The batch file checks for Codex CLI. If it is missing and `npm` is available, it can install `@openai/codex` after asking permission.

## 2. Login

The batch file checks each profile with `codex login status` under that profile's own `CODEX_HOME`. A successful existing login is **left untouched**. It also conservatively preserves an existing `auth.json` rather than automatically overwriting/relogging it if the status check fails. The browser login flow is offered only for profiles that are confirmed to need login.

Example: if `codex1` through `codex4` are already logged in and you rerun the BAT with a total count of `5`, their existing authentication is preserved, only `.codex-plus-5` is added, all five profiles are connected to the shared history, and only `codex5` is offered for login. Existing file-backed logins keep their `auth.json`; an already-working keyring/auto-backed profile keeps its credential-store configuration instead of being forcibly switched and broken.

For account 1 it temporarily uses:

```text
CODEX_HOME=%USERPROFILE%\.codex-plus-1
```

For account 2:

```text
CODEX_HOME=%USERPROFILE%\.codex-plus-2
```

and so on.

If you skip login during setup, use PowerShell later:

```powershell
$env:CODEX_HOME="$env:USERPROFILE\.codex-plus-1"
codex login
```

Repeat with the desired account number.

For a headless machine, Codex also supports device-code login:

```powershell
$env:CODEX_HOME="$env:USERPROFILE\.codex-plus-1"
codex login --device-auth
```

Device-code login may need to be enabled for the ChatGPT account/workspace.

## 3. Use the profiles

Open a **new PowerShell window** after setup.

Examples when you configured 6 accounts:

```powershell
codex1
codex2
codex3
codex4
codex5
codex6
```

Generic form:

```powershell
codexaccount 6
```

Resume from the shared session list:

```powershell
codex1 resume --all
codex6 resume --all
codexui resume --all
```

Check everything:

```powershell
codexsharedstatus
```

or:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\check-codex-profiles.ps1
```

# Windows: manual / scripted setup

Install or change the account count:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\install-codex-profiles.ps1 -AccountCount 8
```

Enable shared live history without an interactive close-session pause:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\use-live-shared-history.ps1 -AccountCount 8 -Force
```

Share the session directories without linking `history.jsonl`:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\use-live-shared-history.ps1 -AccountCount 8 -NoHistoryLink
```

The selected count is saved at:

```text
%USERPROFILE%\.codex-switcher\account-count.txt
```

Later runs can omit `-AccountCount`; the scripts reuse the saved value.

## Changing the number of accounts

Re-run the batch file and enter the new count, or re-run the installer with another `-AccountCount`.

Increasing the count is additive: it creates only the missing profile homes/helper commands. Existing profile directories, existing `auth.json` files, and existing correct shared-history links are preserved.

By default, Windows setup also refuses to silently shrink below the saved/discovered highest profile number. This protects an existing `codex1`...`codexN` setup from being accidentally unmanaged. The low-level installer supports `-AllowDecrease` if you intentionally want a smaller managed helper set; even then it does **not** delete profile directories or `auth.json`.

# Linux / macOS-like shells

Install for a specific number of accounts:

```bash
bash ./scripts/linux/install-codex-profiles.sh 6
source "$HOME/.codex-switcher/codex-functions.sh"
```

Login:

```bash
CODEX_HOME="$HOME/.codex-plus-1" codex login
CODEX_HOME="$HOME/.codex-plus-2" codex login
# repeat through the configured count
```

Enable shared live history:

```bash
bash ./scripts/linux/use-live-shared-history.sh --accounts 6
```

Or, after the count has been saved by the installer:

```bash
bash ./scripts/linux/use-live-shared-history.sh
```

Check the setup:

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

# Concurrency warning

Do not modify the **same conversation** from two profiles at the same time.

All configured profiles share the same live local session files. Simultaneous writers can conflict. Exit or stop one Codex process before continuing the same conversation through another account.

# Backups and rollback

The shared-history scripts create a timestamped backup before replacing local session folders. The folder looks like:

```text
codex-backup-before-shared-links-YYYYMMDD-HHMMSS
```

To roll back:

1. close all Codex processes
2. remove the linked/junction `sessions`, `archived_sessions`, and linked `history.jsonl` entries from the profiles
3. restore the desired data from the timestamped backup
4. remove or reinstall the marked switcher block in your shell profile

Do **not** delete an `auth.json` unless you intentionally want to remove that profile's local login.

# Troubleshooting

## `codexN` is not recognized

Open a new PowerShell window after running the installer.

Or reload your profile:

```powershell
. $PROFILE
```

## PowerShell execution policy blocks a script

Use a one-run bypass:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\install-codex-profiles.ps1 -AccountCount 4
```

The provided `.bat` already uses a one-process execution-policy bypass for its helper scripts.

## Force mode / locked files

The BAT now calls the sharing script with `-Force` and does **not** stop at a “close Codex” pause. It also leaves already-correct junctions/hardlinks in place, so adding a new account normally touches only the new profile.

`-Force` means “attempt the update immediately”; it cannot override an exclusive Windows filesystem lock. If Windows specifically reports that a file is in use, close the process holding that file and rerun. On some managed Windows machines, junction/hardlink creation may also be restricted by policy.

## Login is going into the wrong profile

Check `CODEX_HOME` before running `codex login`:

```powershell
$env:CODEX_HOME
```

For account 3 it should be:

```text
%USERPROFILE%\.codex-plus-3
```

## Deleted conversations return

If you used an older copy/merge version of this project, remove the old marked block and reinstall:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\remove-old-copy-sync-block.ps1
```

Then re-run the live-history script.

# Notes

This project shares **local Codex history**, not remote ChatGPT web conversation history. It does not merge accounts, subscriptions, workspaces, entitlements, or credentials.
