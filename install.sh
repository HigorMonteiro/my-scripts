#!/usr/bin/env bash
# install.sh - Script mestre para linkar tudo no sistema

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/.local/bin"

echo "=== Instalando my-scripts ==="
echo "Origem: $SCRIPT_DIR"

# Criar diretorio de binarios se nao existir
mkdir -p "$BIN_DIR"

# Tornar scripts executaveis
chmod +x "$SCRIPT_DIR"/setup/*.sh
chmod +x "$SCRIPT_DIR"/monitoring/*.sh
chmod +x "$SCRIPT_DIR"/database/*.sh
chmod +x "$SCRIPT_DIR"/aliases/*.sh

# Criar symlinks em ~/.local/bin
ln -sf "$SCRIPT_DIR/setup/install_env.sh"       "$BIN_DIR/install-env"
ln -sf "$SCRIPT_DIR/monitoring/check_services.sh" "$BIN_DIR/check-services"
ln -sf "$SCRIPT_DIR/database/db_backup.sh"       "$BIN_DIR/db-backup"

echo "[OK] Symlinks criados em $BIN_DIR"

# Adicionar aliases ao shell
SHELL_RC=""
if [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then
    SHELL_RC="$HOME/.bashrc"
fi

if [ -n "$SHELL_RC" ]; then
    ALIAS_LINE="source \"$SCRIPT_DIR/aliases/custom_aliases.sh\""
    if ! grep -qF "$ALIAS_LINE" "$SHELL_RC"; then
        echo "" >> "$SHELL_RC"
        echo "# my-scripts aliases" >> "$SHELL_RC"
        echo "$ALIAS_LINE" >> "$SHELL_RC"
        echo "[OK] Aliases adicionados em $SHELL_RC"
    else
        echo "[OK] Aliases ja configurados em $SHELL_RC"
    fi
else
    echo "[!] Nenhum .bashrc ou .zshrc encontrado. Adicione manualmente:"
    echo "    source \"$SCRIPT_DIR/aliases/custom_aliases.sh\""
fi

# Verificar se ~/.local/bin esta no PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo ""
    echo "[!] Adicione ao seu PATH:"
    echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "=== Instalacao concluida ==="
echo "Comandos disponiveis: install-env, check-services, db-backup"
