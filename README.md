# Codex Multi-Account Shared History Switcher

Run multiple Codex CLI profiles on one machine with separate logins and a shared **local** chat history. On Windows, use the same local history from Codex Desktop and check every configured CLI account's usage in Terminal or a browser.

This is an unofficial local utility. It does not create accounts, pool quotas, or sync ChatGPT web chats and account-owned cloud resources.

## Windows quick start

Download or clone the **whole repository** and keep the BAT files alongside the `scripts/` directory. The BAT files are launchers and do not work on their own.

| Launcher | What it does |
| --- | --- |
| [setup-codex-accounts.bat](setup-codex-accounts.bat) | Configures 1–99 CLI profiles, preserves existing Windows logins, and connects local history. |
| [open-codex-limits.bat](open-codex-limits.bat) | Opens one PowerShell tab per configured CLI profile in a single Windows Terminal window and runs `/status`. |
| [open-codex-dashboard.bat](open-codex-dashboard.bat) | Opens one browser dashboard with usage limits for all configured CLI profiles. It does not open or fork chats. |

Use Windows PowerShell and a filesystem that supports junctions and hardlinks, such as NTFS. Setup checks for Codex on PATH; if it is missing, it can offer to install it with npm. The dashboard, status launcher, and Windows history migration use the bundled Codex Python when available, or an installed Python 3.11 or newer. The status tab launcher additionally needs **Windows Terminal and Git**. The dashboard needs a browser, but does not require Windows Terminal or Git.

### 1. Set up accounts and shared history

Close Codex Desktop and any CLI or IDE sessions using this history before the first setup. Double-click the setup BAT and enter the total number of CLI profiles, or pass the count:

```bat
setup-codex-accounts.bat 6
```

The installer creates or reuses `%USERPROFILE%\.codex-plus-1` through `.codex-plus-N`. New or unlogged CLI profiles use separate file-backed credentials; existing Windows profiles with working keyring logins keep their credential-store configuration. Setup checks each login and offers sign-in for profiles it detects as missing a login. You can add accounts by rerunning setup with a larger total; the Windows installer does not silently shrink an existing profile set.

After setup and any history recovery finish, reopen Codex Desktop and open a new PowerShell window. Helpers are installed for Windows PowerShell and PowerShell 7:

```powershell
codex1 resume --all      # use profile 1 and show saved sessions across directories
codexaccount 2           # open profile 2
codexui resume --all     # CLI using the default desktop profile
codexsharedstatus        # inspect shared storage links, not account usage
codex1 login status
codex1 login             # sign in later, if you skipped it during setup
```

Both usage launchers read the saved count from `%USERPROFILE%\.codex-switcher\account-count.txt`. They cover `codex1` through `codexN`; the separate desktop login is not included. See [COMMANDS.md](COMMANDS.md) for more options.

### 2. View native Codex status in tabs

```bat
open-codex-limits.bat
open-codex-limits.bat -Account 3
open-codex-limits.bat -PlanOnly
```

Each tab opens an empty interactive session by default and runs `/status` after the composer is ready. It sends no model prompt and does not resume or fork a saved chat. If you start chatting, Codex can save the session. To create a fork of a randomly selected saved chat instead, run `open-codex-limits.bat -Fork`; that mode can add a saved fork per account.

The launcher uses a read-only Codex session in an empty Git workspace under `%LOCALAPPDATA%\CodexAccountStatus`. It records trust for that dedicated workspace only and backs up the affected profile config. Complete any sign-in prompt yourself. If the installed TUI layout changes or the five-minute wait expires, type `/status` manually in the tab.

### 3. Monitor usage in one browser dashboard

```bat
open-codex-dashboard.bat
```

The dashboard opens at the `http://127.0.0.1:<port>/` address printed by the launcher. It reads account and usage data through each profile's Codex app-server, without sending model prompts. It checks automatically about once a minute, and **به‌روزرسانی الآن** triggers a manual refresh. Refreshes do not overlap.

- See each profile's signed-in ChatGPT email and plan when available.
- See remaining percentages for the usage windows Codex returns, such as five-hour and weekly limits, with live countdowns and exact reset times. Dates are Gregorian with English digits; times use the browser's local timezone.
- See the last successful check and whether values are stale or unavailable. A profile with a missing login or a failed read does not prevent other profiles from updating.
- Sort accounts by profile number, nearest five-hour reset, or nearest weekly reset. Accounts without an upcoming reset for the selected window appear last.
- See the available Codex reset credit count reported by the usage response. The dashboard refreshes it with the quotas, distinguishes zero from unavailable, and never redeems credits.
- Search by profile number, alias, or visible email. Filter for accounts ready to use, blocked, with available reset credits, or needing sign-in. Readiness comes from Codex's explicit usage response, not the quota percentage or countdown.
- Refresh just one profile with the button on its card or table row. Switch between cards and a compact table, name profiles with aliases, and hide emails on screen. Display preferences are saved in this browser; hiding emails does not remove them from the local API.
- Enable recovery alerts to see a message when a later Codex read confirms a blocked account is usable again. Browser notifications also require browser permission. Keep the dashboard page open to receive alerts.

Running the BAT again reopens the dashboard already listening on `127.0.0.1:47631`. If another service uses that port, the launcher reports the conflict. Stop an older dashboard version before starting this version.
- The responsive Persian interface uses a bundled [Vazirmatn font](scripts/windows/limits-dashboard/Vazirmatn-OFL.txt) and respects the system's reduced-motion preference.

Quota reset times do not indicate when a subscription ends. The dashboard is local, shows email addresses when available, and does not write a dashboard history file. Keep the launcher window open while monitoring. Press **Ctrl+C in that window** to stop the server; closing the browser tab alone does not stop it. If the browser does not open, visit the printed address manually.

## How local sharing works

On Windows the desktop profile (`%USERPROFILE%\.codex`) and CLI profiles share local session and archive directories, the session index, SQLite history, and native writer locks. Command history is shared by default. Storage lives under `%USERPROFILE%\.codex-shared-history`, with the canonical writer-lock directory in the desktop profile. The clients use the same files directly; no background copy-sync job is required.

Managed CLI helpers check the shared links and database settings before launch. They use the installed desktop engine when available and add the flags needed to include non-interactive sessions in the resume picker. A restart of the other client may be needed to refresh its view. Local sharing does not require the same login on every client. However, local transcripts are visible from the configured profiles, so do not use this setup to separate confidential chats between accounts.

Use **one active writer per chat**. If Codex reports an active writer, close the chat in the other client before continuing. Setup's `-Force` skips the interactive pause but does not override active-writer checks. If setup finds two divergent copies of a rollout at the same path, it stops rather than choosing one to overwrite.

Windows setup preserves the existing SQLite history where available. It stores replaced paths and migration reports under `%USERPROFILE%\codex-backup-before-shared-links-*`. With the desktop engine installed, the setup BAT can queue a one-time recovery for damaged local history. Close active writers, wait for `Recovery complete` in `%USERPROFILE%\.codex-switcher\history-recovery.log`, then reopen Codex. Check `history-recovery-errors.log` if it fails. Keep the setup and recovery backups private. For rollback, close Codex and use the matching backups for the paths and configuration you intend to restore; do not recursively delete through live links.

## Linux support

The [Linux scripts](scripts/linux/) provide Bash helpers and symlink the session and archive directories and, optionally, command history. They do not implement the Windows BAT launchers, shared SQLite inventory, coordinated writer locks, or recovery. The scripts use Linux utilities (including `readlink -f`); macOS compatibility is not claimed. Back up local history and close Codex clients before running the Linux sharing script. See [COMMANDS.md](COMMANDS.md) for the Bash commands.

## Before publishing to GitHub

Publish the source files: the three BAT launchers, `scripts/`, `tests/`, the documentation and `.gitignore`. Keep the font and its license together. Never upload real profile directories, `auth.json`, chat/session data, local SQLite files, recovery backups, or `.diagnostics/`. Screenshots and diagnostics can contain account emails and chat text.

When using Git, review `git status --short --ignored` and `git diff --cached --name-only` before committing. When uploading in a browser or making a ZIP, exclude private files manually: `.gitignore` only affects Git and does not remove files already tracked. See [SECURITY.md](SECURITY.md).

## Windows regression checks

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\windows\shared-store.Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\windows\status-console.Tests.ps1

. .\scripts\windows\shared-store.ps1
$python = Get-CodexSharedPython
$runtime = Get-CodexSharedRuntime
& $python .\tests\windows\status-session.Tests.py
& $python .\tests\windows\status-workspace.Tests.py
& $python .\tests\windows\native-history.py --runtime $runtime
```

The native history tests use isolated local fixtures, not your existing chats or credentials.
