# Security Policy

This project separates authentication for each Codex CLI account and shares only local conversation/session data.

## Sensitive files

Codex credentials may be stored in:

```text
~/.codex/auth.json
~/.codex-plus-1/auth.json
~/.codex-plus-2/auth.json
...
~/.codex-plus-N/auth.json
```

Windows equivalents:

```text
%USERPROFILE%\.codex\auth.json
%USERPROFILE%\.codex-plus-1\auth.json
...
%USERPROFILE%\.codex-plus-N\auth.json
```

Treat every `auth.json` like a password. It may contain access tokens.

## Script boundaries

The scripts never intentionally copy, link, print, sync, or commit `auth.json`.

On Windows the sharing and recovery scripts operate on session files, command history, the session index, local SQLite history, writer locks, and relevant profile settings. Backups, logs, and diagnostic copies can contain private history. Local chats are deliberately visible across the configured profiles.

For new or unlogged Windows CLI profiles, and existing file-backed profiles, the installer uses:

```toml
cli_auth_credentials_store = "file"
```

Existing unrelated `config.toml` settings are preserved.

The usage dashboard binds only to `127.0.0.1`. It reads the account email and usage data through Codex, keeps dashboard results in memory, and does not read `auth.json` directly. Keep the dashboard local: it is not an authenticated web service and can show account emails to someone with access to that machine.

The desktop/UI profile is not forced to file-backed credential storage because the desktop app may use its normal credential mode.

## Account-count state

The selected profile count is stored in:

```text
~/.codex-switcher/account-count.txt
```

This file contains only a number. It does not contain credentials.

## Before publishing

Run:

```bash
git status --ignored
git diff --cached --name-only
```

Confirm that no credentials, chat data, private screenshots, local profile data, or `.diagnostics/` are included. Ignore rules do not remove already tracked files and do not apply to manual uploads or ZIP files.

Never post device codes, access tokens, `auth.json`, or screenshots containing credentials.

## Rerun / account expansion safety

Windows setup is additive by default. It invokes `codex login status` with each profile's `CODEX_HOME` to detect an existing login. The scripts do not parse or print credential contents, and existing `auth.json` files are not copied, linked, replaced, or deleted. An existing keyring/auto-backed profile also keeps its credential-store setting so setup does not invalidate a working login. Adding a higher account number keeps earlier account authentication intact.
