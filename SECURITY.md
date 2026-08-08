# Security Policy

This repository separates authentication for four Codex CLI accounts and never intentionally shares authentication files.

## Sensitive files

Codex credentials may be stored in `auth.json` at these locations:

```text
~/.codex/auth.json
~/.codex-plus-1/auth.json
~/.codex-plus-2/auth.json
~/.codex-plus-3/auth.json
~/.codex-plus-4/auth.json
```

Windows equivalents:

```text
%USERPROFILE%\.codex\auth.json
%USERPROFILE%\.codex-plus-1\auth.json
%USERPROFILE%\.codex-plus-2\auth.json
%USERPROFILE%\.codex-plus-3\auth.json
%USERPROFILE%\.codex-plus-4\auth.json
```

Treat every `auth.json` like a password. It may contain access tokens.

## Script boundaries

The scripts do not intentionally copy, link, sync, print, or commit `auth.json`.

They work only with:

```text
sessions/
archived_sessions/
history.jsonl
config.toml
```

Each of the four CLI profile directories gets this configuration:

```toml
cli_auth_credentials_store = "file"
```

That keeps each login inside its own `CODEX_HOME`.

## Before publishing

Run:

```bash
git status --ignored
```

Confirm these are not tracked:

```text
auth.json
.codex/
.codex-plus-1/
.codex-plus-2/
.codex-plus-3/
.codex-plus-4/
.codex-shared-history/
*.backup
*.bak-*
```

Do not post device codes, access tokens, authentication files, or screenshots containing them.
