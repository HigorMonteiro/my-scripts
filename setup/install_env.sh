#!/usr/bin/env bash
# install_env.sh - Scripts de instalacao (Docker, Nginx, Python)
# Suporte: Linux (apt/yum/dnf) e macOS (brew)

set -euo pipefail

# Cores
GREEN="\033[0;32m"
RED="\033[0;31m"
CYAN="\033[0;36m"
BOLD="\033[1m"
DIM="\033[2m"
RESET="\033[0m"

# Detectar OS e package manager
OS="$(uname -s)"
PKG=""

detect_pkg_manager() {
    if [ "$OS" = "Darwin" ]; then
        if command -v brew &>/dev/null; then
            PKG="brew"
        else
            echo -e "  ${RED}[!] Homebrew nao encontrado.${RESET}"
            echo -e "  ${DIM}Instale com: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"${RESET}"
            exit 1
        fi
    elif command -v apt-get &>/dev/null; then
        PKG="apt"
    elif command -v dnf &>/dev/null; then
        PKG="dnf"
    elif command -v yum &>/dev/null; then
        PKG="yum"
    else
        echo -e "  ${RED}[!] Gerenciador de pacotes nao suportado.${RESET}"
        exit 1
    fi
}

info()    { echo -e "  ${CYAN}[*]${RESET} $1"; }
success() { echo -e "  ${GREEN}[OK]${RESET} $1"; }
fail()    { echo -e "  ${RED}[!]${RESET} $1"; }

already_installed() {
    if command -v "$1" &>/dev/null; then
        success "$1 ja esta instalado ($(command -v "$1"))"
        return 0
    fi
    return 1
}

# ── Docker ───────────────────────────────────────────
install_docker() {
    already_installed docker && return

    info "Instalando Docker..."
    case "$PKG" in
        brew)
            brew install --cask docker
            success "Docker Desktop instalado. Abra o app para finalizar o setup."
            ;;
        apt)
            curl -fsSL https://get.docker.com | sh
            sudo usermod -aG docker "$USER"
            sudo systemctl enable docker
            success "Docker instalado e habilitado no boot."
            ;;
        dnf|yum)
            sudo $PKG install -y dnf-plugins-core 2>/dev/null || true
            sudo $PKG config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 2>/dev/null || true
            sudo $PKG install -y docker-ce docker-ce-cli containerd.io
            sudo systemctl start docker && sudo systemctl enable docker
            sudo usermod -aG docker "$USER"
            success "Docker instalado e habilitado no boot."
            ;;
    esac
}

# ── Nginx ────────────────────────────────────────────
install_nginx() {
    already_installed nginx && return

    info "Instalando Nginx..."
    case "$PKG" in
        brew)
            brew install nginx
            success "Nginx instalado."
            echo -e "  ${DIM}Iniciar: brew services start nginx${RESET}"
            echo -e "  ${DIM}Config:  $(brew --prefix)/etc/nginx/nginx.conf${RESET}"
            ;;
        apt)
            sudo apt-get update && sudo apt-get install -y nginx
            sudo systemctl enable nginx
            success "Nginx instalado e habilitado no boot."
            ;;
        dnf|yum)
            sudo $PKG install -y nginx
            sudo systemctl start nginx && sudo systemctl enable nginx
            success "Nginx instalado e habilitado no boot."
            ;;
    esac
}

# ── Python ───────────────────────────────────────────
install_python() {
    already_installed python3 && return

    info "Instalando Python..."
    case "$PKG" in
        brew)
            brew install python
            success "Python instalado."
            echo -e "  ${DIM}Versao: $(python3 --version 2>/dev/null)${RESET}"
            ;;
        apt)
            sudo apt-get update && sudo apt-get install -y python3 python3-pip python3-venv
            success "Python instalado."
            ;;
        dnf|yum)
            sudo $PKG install -y python3 python3-pip
            success "Python instalado."
            ;;
    esac
}

# ── Node.js ──────────────────────────────────────────
install_node() {
    already_installed node && return

    info "Instalando Node.js..."
    case "$PKG" in
        brew)
            brew install node
            success "Node.js instalado."
            ;;
        apt)
            curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
            sudo apt-get install -y nodejs
            success "Node.js instalado."
            ;;
        dnf|yum)
            curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash -
            sudo $PKG install -y nodejs
            success "Node.js instalado."
            ;;
    esac
}

# ── Redis ────────────────────────────────────────────
install_redis() {
    already_installed redis-server || already_installed redis-cli && return

    info "Instalando Redis..."
    case "$PKG" in
        brew)
            brew install redis
            success "Redis instalado."
            echo -e "  ${DIM}Iniciar: brew services start redis${RESET}"
            ;;
        apt)
            sudo apt-get update && sudo apt-get install -y redis-server
            sudo systemctl enable redis-server
            success "Redis instalado e habilitado no boot."
            ;;
        dnf|yum)
            sudo $PKG install -y redis
            sudo systemctl start redis && sudo systemctl enable redis
            success "Redis instalado e habilitado no boot."
            ;;
    esac
}

# ── PostgreSQL ───────────────────────────────────────
install_postgres() {
    already_installed psql && return

    info "Instalando PostgreSQL..."
    case "$PKG" in
        brew)
            brew install postgresql@17
            success "PostgreSQL instalado."
            echo -e "  ${DIM}Iniciar: brew services start postgresql@17${RESET}"
            ;;
        apt)
            sudo apt-get update && sudo apt-get install -y postgresql postgresql-contrib
            sudo systemctl enable postgresql
            success "PostgreSQL instalado e habilitado no boot."
            ;;
        dnf|yum)
            sudo $PKG install -y postgresql-server postgresql
            sudo postgresql-setup --initdb 2>/dev/null || true
            sudo systemctl start postgresql && sudo systemctl enable postgresql
            success "PostgreSQL instalado e habilitado no boot."
            ;;
    esac
}

# ── Main ─────────────────────────────────────────────
detect_pkg_manager

echo ""
echo -e "  ${BOLD}${CYAN}INSTALL ENV${RESET}"
echo -e "  ${DIM}OS: $OS | Package Manager: $PKG${RESET}"
echo -e "  ────────────────────────────────────────"
echo ""

case "${1:-all}" in
    docker)   install_docker ;;
    nginx)    install_nginx ;;
    python)   install_python ;;
    node)     install_node ;;
    redis)    install_redis ;;
    postgres) install_postgres ;;
    all)
        install_docker
        install_nginx
        install_python
        install_node
        install_redis
        install_postgres
        ;;
    -h|--help|help)
        echo -e "  ${BOLD}USO:${RESET}"
        echo "    ./install_env.sh              Instalar tudo"
        echo "    ./install_env.sh docker       Apenas Docker"
        echo "    ./install_env.sh nginx        Apenas Nginx"
        echo "    ./install_env.sh python       Apenas Python"
        echo "    ./install_env.sh node         Apenas Node.js"
        echo "    ./install_env.sh redis        Apenas Redis"
        echo "    ./install_env.sh postgres     Apenas PostgreSQL"
        echo ""
        ;;
    *)
        fail "Opcao invalida: $1"
        echo "  Uso: $0 {docker|nginx|python|node|redis|postgres|all}"
        exit 1
        ;;
esac

echo ""
echo -e "  ────────────────────────────────────────"
echo -e "  ${GREEN}${BOLD}Instalacao concluida!${RESET}"
echo ""
