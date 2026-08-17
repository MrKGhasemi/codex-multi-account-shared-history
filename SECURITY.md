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

They operate on:

```text
sessions/
archived_sessions/
history.jsonl
config.toml
```

For each CLI profile, the installer ensures this setting exists:

```toml
cli_auth_credentials_store = "file"
```

Existing unrelated `config.toml` settings are preserved.

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
```

Confirm that no credential or local profile data is tracked.

Never post device codes, access tokens, `auth.json`, or screenshots containing credentials.

## Rerun / account expansion safety

Windows setup is additive by default. It invokes `codex login status` with each profile's `CODEX_HOME` to detect an existing login. The scripts do not parse or print credential contents, and existing `auth.json` files are not copied, linked, replaced, or deleted. An existing keyring/auto-backed profile also keeps its credential-store setting so setup does not invalidate a working login. Adding a higher account number keeps earlier account authentication intact.
