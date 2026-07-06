#!/usr/bin/env bash
set -euo pipefail

# Converts Codex UI/default, codex1, and codex2 profiles to use one shared live session store.
# This uses symlinks for sessions, archived_sessions, and history.jsonl.
# This script never links or copies auth.json.

NO_HISTORY_LINK=0
if [ "${1:-}" = "--no-history-link" ]; then
  NO_HISTORY_LINK=1
fi

CODEX_UI_HOME="$HOME/.codex"
CODEX1_HOME="$HOME/.codex-plus-1"
CODEX2_HOME="$HOME/.codex-plus-2"
CODEX_SHARED_HOME="$HOME/.codex-shared-history"
HOMES=("$CODEX_UI_HOME" "$CODEX1_HOME" "$CODEX2_HOME")
BACKUP_ROOT="$HOME/codex-backup-before-shared-links-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$CODEX_SHARED_HOME/sessions" "$CODEX_SHARED_HOME/archived_sessions" "$BACKUP_ROOT"

echo "Backup folder: $BACKUP_ROOT"
echo "Close Codex CLI/UI/IDE before running this script. If a file is locked, close Codex and run again."
echo ""

copy_dir_contents() {
  local src="$1"
  local dst="$2"
  [ -d "$src" ] || return 0
  mkdir -p "$dst"
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
echo "Done. codex1, codex2, and codexui now share live sessions."
echo "Auth remains separate because auth.json was not linked or copied."
echo ""
echo "Use:"
echo "  codex1 resume --all"
echo "  codex2 resume --all"
echo "  codexui resume --all"
echo "  codexsharedstatus"
