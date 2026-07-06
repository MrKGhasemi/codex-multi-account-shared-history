# Codex Multi-Account Shared History Switcher

Use multiple ChatGPT Codex CLI on the same machine, while keeping logins separate and sharing the same local Codex conversation history.

This repo is designed for the exact problem where:

- you have two ChatGPT/Codex accounts;
- logging out of Codex can also disturb browser or app sessions;
- the Codex desktop app does not cleanly switch between accounts;
- the CLI can switch accounts with `CODEX_HOME`, but each profile normally has separate history;
- you want `codex1` and `codex2` to see and continue the same conversations;
- deleted conversations should stay deleted instead of coming back from another copied profile.

The solution is:

1. Use separate `CODEX_HOME` directories for authentication.
2. Keep each account's `auth.json` private and separate.
3. Share only conversation folders with filesystem links.
4. Use short commands: `codex1`, `codex2`, and `codexui`.

> Important: this project is a local helper setup. It is not an official OpenAI product.

---

## Why this is needed

ChatGPT web supports account switching, but Codex desktop account switching is not currently supported. OpenAI's account switching help page says account switching is available on ChatGPT web and is not yet supported in Codex desktop or native mobile apps.

Codex CLI, however, reads its local state from `CODEX_HOME`. OpenAI's Codex docs say `CODEX_HOME` defaults to `~/.codex` and stores local files like `config.toml`, `auth.json`, `history.jsonl`, logs, and caches.

OpenAI's auth docs also say Codex caches login details locally, either in `auth.json` under `CODEX_HOME` or in an OS credential store. If file-based credentials are used, `auth.json` must be treated like a password because it contains access tokens.

So the safe design is:

```text
Account 1 login  -> ~/.codex-plus-1/auth.json
Account 2 login  -> ~/.codex-plus-2/auth.json
UI app login     -> ~/.codex/auth.json
Shared history   -> ~/.codex-shared-history/sessions
```

The auth files stay separate. The conversations are shared.

---

## Mental model

Codex has two kinds of local data:

### 1. Identity / login data

These files must stay separate:

```text
~/.codex/auth.json
~/.codex-plus-1/auth.json
~/.codex-plus-2/auth.json
```

Never commit them. Never paste them into chat. Never share them.

### 2. Conversation data

These can be shared locally:

```text
sessions/
archived_sessions/
history.jsonl
```

This repo creates links so all profiles point at the same conversation store:

```text
~/.codex/sessions              -> ~/.codex-shared-history/sessions
~/.codex-plus-1/sessions       -> ~/.codex-shared-history/sessions
~/.codex-plus-2/sessions       -> ~/.codex-shared-history/sessions
```

On Windows, the links are directory Junctions. On Linux, they are symbolic links.

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

# Windows guide

## Windows prerequisites

Check that Codex CLI exists:

```powershell
codex --version
```

If PowerShell says `codex` is not recognized, install Codex CLI first. One common installation method is:

```powershell
npm install -g @openai/codex
```

Then close PowerShell, reopen it, and test again:

```powershell
codex --version
```

## Step 1: install the profile switcher

From the repo folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\install-codex-profiles.ps1
```

This creates these folders:

```text
C:\Users\<you>\.codex
C:\Users\<you>\.codex-plus-1
C:\Users\<you>\.codex-plus-2
C:\Users\<you>\.codex-shared-history
```

It also adds these PowerShell functions:

```powershell
codex1
codex2
codexui
codexsharedstatus
```

Reload your PowerShell profile:

```powershell
. $PROFILE
```

Or simply close PowerShell and open it again.

## Step 2: login to account 1

```powershell
$env:CODEX_HOME="$env:USERPROFILE\.codex-plus-1"
codex login --device-auth
```

Complete the browser/device-code login for account 1.

If you do not want device-code login, use:

```powershell
$env:CODEX_HOME="$env:USERPROFILE\.codex-plus-1"
codex login
```

## Step 3: login to account 2

```powershell
$env:CODEX_HOME="$env:USERPROFILE\.codex-plus-2"
codex login --device-auth
```

Complete the browser/device-code login for account 2.

## Step 4: check both accounts

```powershell
codex1 login status
codex2 login status
```

Expected result:

```text
Logged in using ChatGPT
```

## Step 5: enable live shared history

Close all Codex surfaces first:

- Codex CLI
- Codex Windows app
- VS Code / Cursor / Windsurf Codex extension, if open

Then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\use-live-shared-history.ps1
```

This backs up your existing session folders, merges existing sessions into the shared folder, and replaces the per-profile session folders with Junctions.

## Step 6: use it

Account 1:

```powershell
codex1 resume --all
```

Account 2:

```powershell
codex2 resume --all
```

Default/UI profile:

```powershell
codexui resume --all
```

Check folder status:

```powershell
codexsharedstatus
```

---

# Linux guide

The Linux setup is the same idea:

```text
~/.codex            = default/UI/IDE profile
~/.codex-plus-1     = account 1
~/.codex-plus-2     = account 2
~/.codex-shared-history = shared sessions
```

## Linux prerequisites

Check Codex CLI:

```bash
codex --version
```

If it is missing, install Codex CLI first, for example:

```bash
npm install -g @openai/codex
```

Then restart your shell or refresh PATH and test:

```bash
codex --version
```

## Step 1: install shell functions

From the repo folder:

```bash
bash ./scripts/linux/install-codex-profiles.sh
```

Load the functions now:

```bash
source "$HOME/.codex-switcher/codex-functions.sh"
```

## Step 2: login to account 1

```bash
CODEX_HOME="$HOME/.codex-plus-1" codex login --device-auth
```

## Step 3: login to account 2

```bash
CODEX_HOME="$HOME/.codex-plus-2" codex login --device-auth
```

## Step 4: check both accounts

```bash
codex1 login status
codex2 login status
```

## Step 5: enable live shared history

Close all Codex CLI/UI/IDE sessions first, then run:

```bash
bash ./scripts/linux/use-live-shared-history.sh
```

## Step 6: use it

```bash
codex1 resume --all
codex2 resume --all
codexui resume --all
codexsharedstatus
```

---

# Daily workflow

Use account 1:

```bash
codex1 resume --all
```

Exit Codex.

Use account 2:

```bash
codex2 resume --all
```

Exit Codex.

Use the default/UI profile:

```bash
codexui resume --all
```

The important rule is:

> Do not open the same conversation from `codex1` and `codex2` at the same time.

Because the profiles share the same live session files, two writers can conflict if they modify the same session simultaneously.

---

# Command reference

## Start a new Codex session with account 1

```bash
codex1
```

## Start a new Codex session with account 2

```bash
codex2
```

## Resume any conversation from account 1

```bash
codex1 resume --all
```

## Resume any conversation from account 2

```bash
codex2 resume --all
```

## Resume the last conversation

```bash
codex1 resume --last
codex2 resume --last
```

## Check login status

```bash
codex1 login status
codex2 login status
codexui login status
```

## Login again without logging out

```bash
CODEX_HOME="$HOME/.codex-plus-1" codex login --device-auth
CODEX_HOME="$HOME/.codex-plus-2" codex login --device-auth
```

Windows equivalent:

```powershell
$env:CODEX_HOME="$env:USERPROFILE\.codex-plus-1"; codex login --device-auth
$env:CODEX_HOME="$env:USERPROFILE\.codex-plus-2"; codex login --device-auth
```

## Delete a conversation

Inside Codex CLI, use `/delete` if available for the selected conversation, or use the CLI delete command with a session id/name:

```bash
codex delete <SESSION_ID_OR_NAME>
```

Because the session folder is shared live, deletion should apply to all profiles.

---

# Error handling

## Error: `codex : The term 'codex' is not recognized`

Meaning: Windows cannot find Codex CLI.

Fix:

```powershell
npm install -g @openai/codex
```

Then close PowerShell, open it again, and test:

```powershell
codex --version
```

## Error: `Enable device code authorization for Codex in ChatGPT Security Settings`

Meaning: the account has not enabled device-code login for Codex.

Fix:

1. Open ChatGPT in the browser profile for that account.
2. Go to Settings -> Security.
3. Enable device-code authorization for Codex.
4. Run login again:

```powershell
$env:CODEX_HOME="$env:USERPROFILE\.codex-plus-1"; codex login --device-auth
```

or for account 2:

```powershell
$env:CODEX_HOME="$env:USERPROFILE\.codex-plus-2"; codex login --device-auth
```

## Error: `Cannot overwrite variable Home because it is read-only or constant`

Meaning: an old PowerShell function used `$Home` as a parameter name. PowerShell treats `$HOME` and `$Home` as the same read-only variable.

Fix:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\remove-old-copy-sync-block.ps1
. $PROFILE
```

The current scripts use `$CodexHome`, not `$Home`.

## Error: `codex1 : The term 'codex1' is not recognized`

Meaning: your PowerShell profile has not been loaded or the installer did not run.

Fix:

```powershell
. $PROFILE
```

If that fails, run the installer again:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\install-codex-profiles.ps1
. $PROFILE
```

## Error: `running scripts is disabled on this system`

Meaning: PowerShell execution policy blocks scripts.

Use one-run bypass:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\install-codex-profiles.ps1
```

Or allow local scripts for your user:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

## Error: deleted conversations come back

Meaning: you are still using copy/merge sync, not live shared folders.

Fix:

1. Remove the old copy-sync block:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\remove-old-copy-sync-block.ps1
```

2. Close all Codex apps/terminals.
3. Convert to live shared folders:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\use-live-shared-history.ps1
```

4. Check that `sessions` is a link:

```powershell
codexsharedstatus
```

## Error: Windows cannot create a Junction

Possible causes:

- Codex is still open and locking files.
- The folder already exists and cannot be removed.
- PowerShell lacks permission.

Fix:

1. Close Codex CLI/UI/IDE.
2. Open PowerShell normally and run again.
3. If it still fails, try PowerShell as Administrator.

## Error: Linux `ln: failed to create symbolic link`

Possible causes:

- Codex is open.
- Existing folder could not be removed.
- Permission issue.

Fix:

```bash
bash ./scripts/linux/check-codex-profiles.sh
```

Close Codex, then run:

```bash
bash ./scripts/linux/use-live-shared-history.sh
```

## Error: `codex resume -all` does not work

Use two dashes:

```bash
codex1 resume --all
codex2 resume --all
```

Not:

```bash
codex1 resume -all
```

## Problem: UI app still does not switch accounts

That is expected. This repo switches CLI accounts. Codex desktop account switching is not currently supported. Use:

```bash
codex1 resume --all
codex2 resume --all
```

For the desktop app, pick one account or use separate OS users for full UI isolation.

---

# Undo / rollback

Both Windows and Linux scripts create a backup folder before replacing session folders.

Example backup name:

```text
codex-backup-before-shared-links-20260706-185900
```

To undo manually:

1. Close Codex CLI/UI/IDE.
2. Remove the `sessions` and `archived_sessions` links from each profile.
3. Copy the backup folders back into each profile.
4. Remove the functions from your PowerShell profile or shell rc file.

Windows profile path is usually:

```powershell
$PROFILE
```

Linux functions file is:

```bash
$HOME/.codex-switcher/codex-functions.sh
```

---

# Official docs used

- OpenAI Codex authentication: `https://developers.openai.com/codex/auth`
- OpenAI Codex advanced config and `CODEX_HOME`: `https://developers.openai.com/codex/config-advanced`
- OpenAI Codex CLI features and `resume --all`: `https://developers.openai.com/codex/cli/features`
- OpenAI Codex CLI reference: `https://developers.openai.com/codex/cli/reference`
- ChatGPT account switching support note: `https://help.openai.com/en/articles/20001068-use-multiple-accounts-with-account-switching`
