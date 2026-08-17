#!/usr/bin/env bash
set -euo pipefail

# Connects UI/default plus N Codex CLI profiles to a shared live local session store.
# Usage: ./use-live-shared-history.sh [--accounts N] [--no-history-link]
# Authentication files are never copied or linked.

NO_HISTORY_LINK=0
ACCOUNT_COUNT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --accounts)
      shift
      [[ $# -gt 0 ]] || { echo "--accounts requires a number" >&2; exit 2; }
      ACCOUNT_COUNT="$1"
      ;;
    --no-history-link)
      NO_HISTORY_LINK=1
      ;;
    *)
      echo "usage: $0 [--accounts N] [--no-history-link]" >&2
      exit 2
      ;;
  esac
  shift
done

COUNT_FILE="$HOME/.codex-switcher/account-count.txt"
if [[ -z "$ACCOUNT_COUNT" ]]; then
  if [[ -f "$COUNT_FILE" ]] && [[ "$(cat "$COUNT_FILE")" =~ ^[1-9][0-9]*$ ]]; then
    ACCOUNT_COUNT="$(cat "$COUNT_FILE")"
  else
    ACCOUNT_COUNT=4
  fi
fi
[[ "$ACCOUNT_COUNT" =~ ^[1-9][0-9]*$ ]] || { echo "account count must be 1..99" >&2; exit 2; }
(( ACCOUNT_COUNT <= 99 )) || { echo "account count must be 1..99" >&2; exit 2; }

CODEX_UI_HOME="$HOME/.codex"
CODEX_SHARED_HOME="$HOME/.codex-shared-history"
HOMES=("$CODEX_UI_HOME")
for ((i=1; i<=ACCOUNT_COUNT; i++)); do
  HOMES+=("$HOME/.codex-plus-$i")
done

BACKUP_ROOT="$HOME/codex-backup-before-shared-links-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$CODEX_SHARED_HOME/sessions" "$CODEX_SHARED_HOME/archived_sessions" "$BACKUP_ROOT"

echo "Configured CLI accounts: $ACCOUNT_COUNT"
echo "Backup folder: $BACKUP_ROOT"
echo "Close Codex CLI/UI/IDE before running this script."
echo ""

copy_dir_contents() {
  local src="$1"
  local dst="$2"
  [ -d "$src" ] || return 0
  mkdir -p "$dst"

  if [ "$(readlink -f "$src")" = "$(readlink -f "$dst")" ]; then
    return 0
  fi

  if command -v rsync >/dev/null 2>&1; then
    rsync -a --ignore-existing "$src/" "$dst/"
  else
    cp -a -n "$src/." "$dst/" 2>/dev/null || cp -a "$src/." "$dst/"
  fi
}

history_sources=()
[ -f "$CODEX_SHARED_HOME/history.jsonl" ] && history_sources+=("$CODEX_SHARED_HOME/history.jsonl")

for h in "${HOMES[@]}"; do
  mkdir -p "$h"
  name="$(basename "$h")"
  backup_home="$BACKUP_ROOT/$name"
  mkdir -p "$backup_home"

  if [ -e "$h/sessions" ] || [ -L "$h/sessions" ]; then
    cp -a "$h/sessions" "$backup_home/" 2>/dev/null || true
    [ -d "$h/sessions" ] && copy_dir_contents "$h/sessions" "$CODEX_SHARED_HOME/sessions"
  fi

  if [ -e "$h/archived_sessions" ] || [ -L "$h/archived_sessions" ]; then
    cp -a "$h/archived_sessions" "$backup_home/" 2>/dev/null || true
    [ -d "$h/archived_sessions" ] && copy_dir_contents "$h/archived_sessions" "$CODEX_SHARED_HOME/archived_sessions"
  fi

  if [ -f "$h/history.jsonl" ]; then
    cp -a "$h/history.jsonl" "$backup_home/" 2>/dev/null || true
    history_sources+=("$h/history.jsonl")
  fi
done

if [ "${#history_sources[@]}" -gt 0 ]; then
  cat "${history_sources[@]}" 2>/dev/null | awk 'NF && !seen[$0]++' > "$CODEX_SHARED_HOME/history.jsonl.tmp"
  mv "$CODEX_SHARED_HOME/history.jsonl.tmp" "$CODEX_SHARED_HOME/history.jsonl"
else
  : > "$CODEX_SHARED_HOME/history.jsonl"
fi

for h in "${HOMES[@]}"; do
  mkdir -p "$h"
  rm -rf "$h/sessions" "$h/archived_sessions"
  ln -s "$CODEX_SHARED_HOME/sessions" "$h/sessions"
  ln -s "$CODEX_SHARED_HOME/archived_sessions" "$h/archived_sessions"

  if [ "$NO_HISTORY_LINK" -eq 0 ]; then
    rm -f "$h/history.jsonl"
    ln -s "$CODEX_SHARED_HOME/history.jsonl" "$h/history.jsonl"
  fi
done

echo ""
echo "Done. codex1..codex$ACCOUNT_COUNT and codexui now share live local sessions."
echo "Auth remains separate because auth.json was not linked or copied."
echo "No periodic copy-sync job is needed."
