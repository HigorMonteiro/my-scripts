#!/usr/bin/env bash
# install_env.sh - Scripts de instalacao (Docker, Nginx, Python)

set -euo pipefail

echo "=== Instalacao do ambiente ==="

# Docker
install_docker() {
    echo "[*] Instalando Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "$USER"
    echo "[OK] Docker instalado."
}

# Nginx
install_nginx() {
    echo "[*] Instalando Nginx..."
    sudo apt-get update && sudo apt-get install -y nginx
    sudo systemctl enable nginx
    echo "[OK] Nginx instalado."
}

# Python
install_python() {
    echo "[*] Instalando Python e pip..."
    sudo apt-get update && sudo apt-get install -y python3 python3-pip python3-venv
    echo "[OK] Python instalado."
}

case "${1:-all}" in
    docker)  install_docker ;;
    nginx)   install_nginx ;;
    python)  install_python ;;
    all)
        install_docker
        install_nginx
        install_python
        ;;
    *)
        echo "Uso: $0 {docker|nginx|python|all}"
        exit 1
        ;;
esac

echo "=== Instalacao concluida ==="
