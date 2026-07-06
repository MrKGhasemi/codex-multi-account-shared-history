# Security Policy

This repository is designed to avoid sharing authentication files.

## Sensitive files

Codex may store credentials in:

```text
auth.json
```

Common locations:

```text
~/.codex/auth.json
~/.codex-plus-1/auth.json
~/.codex-plus-2/auth.json
```

On Windows:

```text
%USERPROFILE%\.codex\auth.json
%USERPROFILE%\.codex-plus-1\auth.json
%USERPROFILE%\.codex-plus-2\auth.json
```

Treat these files like passwords. They may contain access tokens.

## What the scripts do not do

The scripts do not intentionally copy, link, sync, print, or commit `auth.json`.

The scripts only work with:

```text
sessions/
archived_sessions/
history.jsonl
config.toml
```

`config.toml` is used to tell Codex CLI to store each account's credentials inside that account's own `CODEX_HOME`.

## Before publishing your repo

Run:

```bash
git status --ignored
```

Make sure none of these appear as tracked files:

```text
auth.json
.codex/
.codex-plus-1/
.codex-plus-2/
.codex-shared-history/
*.backup
*.bak-*
```

## Device code safety

Device codes are temporary login secrets. Do not post them in public issues, screenshots, tickets, or chat.

## MFA

This setup does not disable MFA. Keep Google Authenticator or any MFA method enabled.
