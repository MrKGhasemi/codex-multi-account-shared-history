#!/usr/bin/env bash
set -euo pipefail

# Usage: ./check-codex-profiles.sh [account-count]

COUNT_FILE="$HOME/.codex-switcher/account-count.txt"
ACCOUNT_COUNT="${1:-}"

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

if command -v codex >/dev/null 2>&1; then
  echo "codex: $(command -v codex)"
  codex --version || true
else
  echo "codex: not found in PATH"
fi

echo "Configured CLI accounts: $ACCOUNT_COUNT"

show_home() {
  local name="$1"
  local path="$2"
  local child p

  echo ""
  echo "[$name] $path"
  for child in auth.json config.toml history.jsonl sessions archived_sessions; do
    p="$path/$child"
    if [ -L "$p" ]; then
      echo "  $(printf '%-18s' "$child") link -> $(readlink "$p")"
    elif [ -d "$p" ]; then
      echo "  $(printf '%-18s' "$child") dir"
    elif [ -f "$p" ]; then
      echo "  $(printf '%-18s' "$child") file"
    else
      echo "  $(printf '%-18s' "$child") missing"
    fi
  done
}

show_home "UI" "$CODEX_UI_HOME"
for ((i=1; i<=ACCOUNT_COUNT; i++)); do
  show_home "codex$i" "$HOME/.codex-plus-$i"
done
show_home "shared" "$CODEX_SHARED_HOME"

echo ""
echo "Login status checks:"
for ((i=1; i<=ACCOUNT_COUNT; i++)); do
  echo "  codex$i login status"
done
echo "  codexui login status"
