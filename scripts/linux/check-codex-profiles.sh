#!/usr/bin/env bash
set -euo pipefail

CODEX_UI_HOME="$HOME/.codex"
CODEX1_HOME="$HOME/.codex-plus-1"
CODEX2_HOME="$HOME/.codex-plus-2"
CODEX3_HOME="$HOME/.codex-plus-3"
CODEX4_HOME="$HOME/.codex-plus-4"
CODEX_SHARED_HOME="$HOME/.codex-shared-history"

if command -v codex >/dev/null 2>&1; then
  echo "codex: $(command -v codex)"
  codex --version || true
else
  echo "codex: not found in PATH"
fi

for entry in \
  "UI:$CODEX_UI_HOME" \
  "codex1:$CODEX1_HOME" \
  "codex2:$CODEX2_HOME" \
  "codex3:$CODEX3_HOME" \
  "codex4:$CODEX4_HOME" \
  "shared:$CODEX_SHARED_HOME"; do
  name="${entry%%:*}"
  path="${entry#*:}"
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
done

echo ""
echo "Login status checks:"
echo "  codex1 login status"
echo "  codex2 login status"
echo "  codex3 login status"
echo "  codex4 login status"
echo "  codexui login status"
