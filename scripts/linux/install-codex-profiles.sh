#!/usr/bin/env bash
set -euo pipefail

# Installs shell helper commands for multiple Codex ChatGPT accounts on Linux/macOS-like shells.
# It creates:
#   codex1  -> CODEX_HOME=$HOME/.codex-plus-1
#   codex2  -> CODEX_HOME=$HOME/.codex-plus-2
#   codexui -> CODEX_HOME=$HOME/.codex
#
# This script does NOT copy, sync, or commit auth.json.

CODEX_UI_HOME="$HOME/.codex"
CODEX1_HOME="$HOME/.codex-plus-1"
CODEX2_HOME="$HOME/.codex-plus-2"
CODEX_SHARED_HOME="$HOME/.codex-shared-history"
SWITCHER_DIR="$HOME/.codex-switcher"
FUNCTIONS_FILE="$SWITCHER_DIR/codex-functions.sh"

mkdir -p "$CODEX_UI_HOME" "$CODEX1_HOME" "$CODEX2_HOME" "$CODEX_SHARED_HOME" "$SWITCHER_DIR"
printf '%s\n' 'cli_auth_credentials_store = "file"' > "$CODEX1_HOME/config.toml"
printf '%s\n' 'cli_auth_credentials_store = "file"' > "$CODEX2_HOME/config.toml"

cat > "$FUNCTIONS_FILE" <<'EOF'
# >>> Codex multi-account shared-history switcher >>>

export CODEX_UI_HOME="$HOME/.codex"
export CODEX1_HOME="$HOME/.codex-plus-1"
export CODEX2_HOME="$HOME/.codex-plus-2"
export CODEX_SHARED_HOME="$HOME/.codex-shared-history"

_codex_with_home() {
  if [ "$#" -lt 1 ]; then
    echo "usage: _codex_with_home <CODEX_HOME> [codex args...]" >&2
    return 2
  fi

  local new_home="$1"
  shift

  local had_old=0
  local old_home=""
  if [ "${CODEX_HOME+x}" = x ]; then
    had_old=1
    old_home="$CODEX_HOME"
  fi

  export CODEX_HOME="$new_home"
  codex "$@"
  local status=$?

  if [ "$had_old" -eq 1 ]; then
    export CODEX_HOME="$old_home"
  else
    unset CODEX_HOME
  fi

  return "$status"
}

codex1() {
  _codex_with_home "$CODEX1_HOME" "$@"
}

codex2() {
  _codex_with_home "$CODEX2_HOME" "$@"
}

codexui() {
  _codex_with_home "$CODEX_UI_HOME" "$@"
}

codexsharedstatus() {
  command -v codex >/dev/null 2>&1 && echo "codex: $(command -v codex)" || echo "codex: not found"
  for entry in "UI:$CODEX_UI_HOME" "codex1:$CODEX1_HOME" "codex2:$CODEX2_HOME" "shared:$CODEX_SHARED_HOME"; do
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
}

# <<< Codex multi-account shared-history switcher <<<
EOF

chmod 700 "$SWITCHER_DIR"
chmod 600 "$FUNCTIONS_FILE"

SOURCE_LINE="[ -f \"$FUNCTIONS_FILE\" ] && . \"$FUNCTIONS_FILE\""

install_source_line() {
  local rc="$1"
  touch "$rc"
  if ! grep -Fq "$FUNCTIONS_FILE" "$rc"; then
    printf '\n# Codex multi-account shared-history switcher\n%s\n' "$SOURCE_LINE" >> "$rc"
    echo "Added source line to $rc"
  else
    echo "Source line already exists in $rc"
  fi
}

case "${SHELL:-}" in
  *zsh*) install_source_line "$HOME/.zshrc" ;;
  *) install_source_line "$HOME/.bashrc" ;;
esac

echo ""
echo "Installed Codex profile switcher."
echo "Functions file: $FUNCTIONS_FILE"
echo ""
echo "Load it now with:"
echo "  source \"$FUNCTIONS_FILE\""
echo ""
echo "Next commands:"
echo '  CODEX_HOME="$HOME/.codex-plus-1" codex login --device-auth'
echo '  CODEX_HOME="$HOME/.codex-plus-2" codex login --device-auth'
echo ""
echo "Usage after login:"
echo "  codex1 resume --all"
echo "  codex2 resume --all"
echo "  codexui resume --all"
echo "  codexsharedstatus"
