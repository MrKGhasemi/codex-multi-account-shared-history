# Codex Multi-Account Shared History Switcher

Use **any practical number of Codex CLI / ChatGPT logins on one machine** while keeping every login separate and sharing the same local Codex conversation history.

> This is a local helper project. It is not an official OpenAI product.

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

It does **not** create ChatGPT accounts. You must already have the accounts you want to sign in with.

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
session_index.jsonl
sqlite/ (Windows)
thread-writer-locks/ (Windows, canonical directory in ~/.codex)
```

The shared store is:

```text
~/.codex-shared-history
```

On Windows, every configured profile points at the same live session directories, session index, and SQLite thread inventory. On Windows, `sessions` and `archived_sessions` use directory junctions, while `history.jsonl` and `session_index.jsonl` use hardlinks. The profiles share a configured `sqlite_home` under `.codex-shared-history\sqlite`. The Linux scripts currently share rollout directories and command history through symbolic links; the Windows SQLite and writer-lock changes described here are not implemented by those Linux scripts.

Because the profiles point to the same files, **there is no periodic copy-sync process**. New and resumed local sessions are written to shared storage; restart the other client to refresh its view.

Run `setup-codex-accounts.bat` once for the desired account count. After it finishes, the links and PowerShell helpers persist across restarts; normal UI/CLI changes are written to the same shared store automatically. You only need to run setup again when adding accounts, repairing links, or intentionally changing the configuration.

The Windows helpers check the UI and CLI storage links and UI SQLite configuration on every launch. If they have changed, the helper stops before starting Codex. Each launch explicitly selects the shared SQLite directory and the desktop engine, and rejects arguments that override that directory or select a remote app server. The installer adds these safeguards to both Windows PowerShell and PowerShell 7.

First-time setup preserves the existing UI thread database and paginated message history before native migration. Existing shared databases are kept. When merging two copies of a rollout, setup accepts an identical file or an append-only extension; it stops on divergent contents instead of overwriting either conversation. Original profile folders are retained in the setup backup.

The setup also places the session inventory in `.codex-shared-history\sqlite` through Codex's `sqlite_home` setting. This is required by current Codex releases: rollout files alone are insufficient for the resume picker. Close and reopen the desktop UI once after the first setup so it loads the shared SQLite state.

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

All configured profiles share the same live local session files. On Windows, the shared native writer locks refuse a second writer for an already-open chat. Exit or close that chat in one client before continuing it through another account. The Linux scripts do not yet install this writer coordination.

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

`-Force` skips the interactive pause; it cannot bypass writer safety. Setup holds the native coordination lock and refuses to merge or move a store with an active writer. Close the affected UI/CLI chats and rerun if setup reports an active writer. On some managed Windows machines, junction/hardlink creation may also be restricted by policy.

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

### Desktop projects are not CLI resume entries

The Codex desktop app and the Codex CLI write different session sources. Desktop sessions commonly have metadata such as `source: "vscode"` and `originator: "Codex Desktop"`. The default CLI resume picker can omit those sessions even when their files are present in the shared `sessions` directory. Use the current CLI's opt-in flag when checking the complete local store:

```powershell
codexui resume --all --include-non-interactive
```

The Windows resume helpers add `--include-non-interactive` and `--no-daemon`, and use the installed desktop engine when available. Local chats can be shared between separately authenticated profiles; matching accounts is not required for this local store. Account-owned remote resources remain separate.

### Saved messages disappear after restart

Sharing rollout folders and the picker database is insufficient if each profile has independent `thread-writer-locks`. Two clients can then write the same chat with duplicate or regressed rollout ordinals. Codex skips those records when projecting paginated history, so messages can exist on disk while disappearing from the visible chat.

The Windows setup now links every CLI's writer-lock directory to the desktop's existing lock directory. It also uses the desktop engine in the generated CLI helpers for storage format compatibility. Use one active writer per chat. Close that chat in the other client before continuing it; do not bypass a writer-lock error.

For existing damaged history, setup installs and queues a single recovery worker. It waits until all UI/CLI thread writers close, saves SQLite snapshots and original rollouts, restores missing older cached history, and rebuilds damaged threads through Codex's native migration in an isolated staging store before publishing the repair. It preserves chat IDs and does not change authentication. Close Codex and the CLI sessions once, allow recovery to finish, then reopen them. Setup uses the desktop bundled Python, or an installed Python 3.11 or newer.

Recovery status is recorded in `%USERPROFILE%\.codex-switcher\history-recovery.log`; errors are in `history-recovery-errors.log`. A successful run ends with `Recovery complete`. Backups are under `history-recovery-backup-*` alongside the log. Do not reopen a writer while recovery is in progress. No recurring copy or recovery job is installed.

### Switching the account in the desktop UI

Authentication stays separate from the shared local session files and databases. Switching accounts does not delete those shared local files. This setup does not transfer remote project ownership, subscriptions, or credentials between accounts.

## Regression checks (Windows)

Run the launch-guard tests in Windows PowerShell and PowerShell 7:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\windows\shared-store.Tests.ps1
pwsh -NoProfile -File .\tests\windows\shared-store.Tests.ps1
```

Run the native history tests with the same desktop engine and bundled Python used by setup:

```powershell
. .\scripts\windows\shared-store.ps1
$testPython = Get-CodexSharedPython
$testRuntime = Get-CodexSharedRuntime
& $testPython .\tests\windows\native-history.py --runtime $testRuntime
```

These use isolated fixtures under `.diagnostics`, without credentials or model requests. They check saved messages after reopening both clients, recovery of regressed ordinals, refusal of concurrent writers, writer handoff after closing, preservation of cached history, and safe first-time setup including older CLI rollouts.
