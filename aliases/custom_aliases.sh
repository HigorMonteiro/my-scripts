#!/usr/bin/env bash
# custom_aliases.sh - Atalhos para .bashrc / .zshrc
# Adicione ao seu shell: source ~/my-scripts/aliases/custom_aliases.sh

# --- Navegacao ---
alias ..="cd .."
alias ...="cd ../.."
alias ll="ls -lah"

# --- Git ---
alias gs="git status"
alias ga="git add"
alias gc="git commit"
alias gp="git push"
alias gl="git log --oneline --graph --decorate -15"

# --- Docker ---
alias dps="docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
alias dcu="docker compose up -d"
alias dcd="docker compose down"
alias dlogs="docker compose logs -f"

# --- Django ---
alias pm="python manage.py"
alias pmr="python manage.py runserver"
alias pmm="python manage.py migrate"
alias pmmm="python manage.py makemigrations"

# --- Sistema ---
alias ports="sudo lsof -i -P -n | grep LISTEN"
alias myip="curl -s ifconfig.me"
