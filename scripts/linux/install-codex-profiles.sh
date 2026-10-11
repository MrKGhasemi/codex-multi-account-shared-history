#!/usr/bin/env bash
set -euo pipefail

# Installs shell helper commands for any number of Codex ChatGPT accounts.
# Usage: ./install-codex-profiles.sh [account-count]
# If no count is supplied, the saved count is reused, or 4 is used initially.

SWITCHER_DIR="$HOME/.codex-switcher"
COUNT_FILE="$SWITCHER_DIR/account-count.txt"
FUNCTIONS_FILE="$SWITCHER_DIR/codex-functions.sh"
CODEX_UI_HOME="$HOME/.codex"
CODEX_SHARED_HOME="$HOME/.codex-shared-history"

requested="${1:-}"
if [[ -n "$requested" ]]; then
  [[ "$requested" =~ ^[1-9][0-9]*$ ]] || { echo "account count must be 1..99" >&2; exit 2; }
  (( requested <= 99 )) || { echo "account count must be 1..99" >&2; exit 2; }
  ACCOUNT_COUNT="$requested"
elif [[ -f "$COUNT_FILE" ]] && [[ "$(cat "$COUNT_FILE")" =~ ^[1-9][0-9]*$ ]]; then
  ACCOUNT_COUNT="$(cat "$COUNT_FILE")"
else
  ACCOUNT_COUNT=4
fi

mkdir -p "$CODEX_UI_HOME" "$CODEX_SHARED_HOME" "$SWITCHER_DIR"
printf '%s\n' "$ACCOUNT_COUNT" > "$COUNT_FILE"
chmod 700 "$SWITCHER_DIR"
chmod 600 "$COUNT_FILE"

set_file_credential_store() {
  local profile_home="$1"
  local config="$profile_home/config.toml"
  local required='cli_auth_credentials_store = "file"'
  mkdir -p "$profile_home"

  if [[ ! -f "$config" ]]; then
    printf '%s\n' "$required" > "$config"
    return
  fi

  if grep -Eq '^[[:space:]]*cli_auth_credentials_store[[:space:]]*=' "$config"; then
    awk -v line="$required" '
      /^[[:space:]]*cli_auth_credentials_store[[:space:]]*=/ { print line; next }
      { print }
    ' "$config" > "$config.tmp"
    mv "$config.tmp" "$config"
  else
    printf '\n%s\n' "$required" >> "$config"
  fi
}

for ((i=1; i<=ACCOUNT_COUNT; i++)); do
  set_file_credential_store "$HOME/.codex-plus-$i"
done

{
  cat <<EOF
# >>> Codex multi-account shared-history switcher >>>
export CODEX_ACCOUNT_COUNT="$ACCOUNT_COUNT"
export CODEX_UI_HOME="\$HOME/.codex"
export CODEX_SHARED_HOME="\$HOME/.codex-shared-history"

_codex_with_home() {
  if [ "\$#" -lt 1 ]; then
    echo "usage: _codex_with_home <CODEX_HOME> [codex args...]" >&2
    return 2
  fi

  local new_home="\$1"
  shift
  local had_old=0
  local old_home=""

  if [ "\${CODEX_HOME+x}" = x ]; then
    had_old=1
    old_home="\$CODEX_HOME"
  fi

  export CODEX_HOME="\$new_home"
  if [ "\${1:-}" = "resume" ]; then
    local has_non_interactive=0 arg
    for arg in "\$@"; do
      [ "\$arg" = "--include-non-interactive" ] && has_non_interactive=1
    done
    local has_no_daemon=0
    for arg in "\$@"; do
      [ "\$arg" = "--no-daemon" ] && has_no_daemon=1
    done
    if [ "\$has_non_interactive" -eq 0 ] && [ "\$has_no_daemon" -eq 0 ]; then
      codex --no-daemon resume --include-non-interactive "\${@:2}"
    elif [ "\$has_non_interactive" -eq 0 ]; then
      codex --no-daemon resume --include-non-interactive "\${@:2}"
    elif [ "\$has_no_daemon" -eq 0 ]; then
      codex --no-daemon resume "\${@:2}"
    else
      codex --no-daemon "\$@"
    fi
  else
    codex --no-daemon "\$@"
  fi
  local status=\$?

  if [ "\$had_old" -eq 1 ]; then
    export CODEX_HOME="\$old_home"
  else
    unset CODEX_HOME
  fi
  return "\$status"
}

codexaccount() {
  if [ "\$#" -lt 1 ]; then
    echo "usage: codexaccount <1..\$CODEX_ACCOUNT_COUNT> [codex args...]" >&2
    return 2
  fi
  local account="\$1"
  shift
  case "\$account" in
    ''|*[!0-9]*) echo "invalid account number" >&2; return 2 ;;
  esac
  if [ "\$account" -lt 1 ] || [ "\$account" -gt "\$CODEX_ACCOUNT_COUNT" ]; then
    echo "account must be between 1 and \$CODEX_ACCOUNT_COUNT" >&2
    return 2
  fi
  _codex_with_home "\$HOME/.codex-plus-\$account" "\$@"
}

EOF

  for ((i=1; i<=ACCOUNT_COUNT; i++)); do
    printf 'codex%d() { codexaccount %d "$@"; }\n' "$i" "$i"
  done

  cat <<'EOF'

codexui() {
  _codex_with_home "$CODEX_UI_HOME" "$@"
}

codexsharedstatus() {
  command -v codex >/dev/null 2>&1 && echo "codex: $(command -v codex)" || echo "codex: not found"
  echo "Configured CLI accounts: $CODEX_ACCOUNT_COUNT"

  local name path child p i
  for name in UI; do
    path="$CODEX_UI_HOME"
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

  for ((i=1; i<=CODEX_ACCOUNT_COUNT; i++)); do
    name="codex$i"
    path="$HOME/.codex-plus-$i"
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

  name="shared"
  path="$CODEX_SHARED_HOME"
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
# <<< Codex multi-account shared-history switcher <<<
EOF
} > "$FUNCTIONS_FILE"

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
echo "Installed Codex profile switcher for $ACCOUNT_COUNT account(s)."
echo "Functions file: $FUNCTIONS_FILE"
echo "Saved account count: $COUNT_FILE"
echo ""
echo "Load it now with:"
echo "  source \"$FUNCTIONS_FILE\""
echo ""
echo "Login commands:"
for ((i=1; i<=ACCOUNT_COUNT; i++)); do
  echo "  CODEX_HOME=\"\$HOME/.codex-plus-$i\" codex login"
done
