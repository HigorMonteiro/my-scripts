#!/usr/bin/env bash
# check_services.sh - Lista todos os servicos do servidor com status e porta

set -euo pipefail

# Cores
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
BOLD="\033[1m"
RESET="\033[0m"

SEPARATOR="────────────────────────────────────────────────────────────────────────"

# Detectar init system
detect_init() {
    if command -v systemctl &>/dev/null && pidof systemd &>/dev/null; then
        echo "systemd"
    elif command -v rc-service &>/dev/null; then
        echo "openrc"
    elif [ -d /etc/init.d ]; then
        echo "sysvinit"
    elif command -v launchctl &>/dev/null; then
        echo "launchd"
    else
        echo "unknown"
    fi
}

# Buscar porta(s) de um processo pelo PID
get_ports() {
    local pid="$1"
    local ports=""

    if [ -z "$pid" ] || [ "$pid" = "-" ]; then
        echo "-"
        return
    fi

    if command -v ss &>/dev/null; then
        ports=$(ss -tlnp 2>/dev/null | grep "pid=$pid[,)]" | awk '{print $4}' | grep -oE '[0-9]+$' | sort -un | tr '\n' ',' | sed 's/,$//')
    elif command -v lsof &>/dev/null; then
        ports=$(lsof -iTCP -sTCP:LISTEN -nP 2>/dev/null | awk -v p="$pid" '$2 == p {print $9}' | grep -oE '[0-9]+$' | sort -un | tr '\n' ',' | sed 's/,$//')
    elif command -v netstat &>/dev/null; then
        ports=$(netstat -tlnp 2>/dev/null | grep "$pid/" | awk '{print $4}' | grep -oE '[0-9]+$' | sort -un | tr '\n' ',' | sed 's/,$//')
    fi

    if [ -z "$ports" ]; then
        echo "-"
    else
        echo "$ports"
    fi
}

# Header
echo ""
echo -e "${BOLD}${CYAN}  MONITORAMENTO DE SERVICOS${RESET}"
echo -e "  $(date '+%d/%m/%Y %H:%M:%S') | Host: $(hostname)"
echo -e "  ${SEPARATOR}"

INIT_SYSTEM=$(detect_init)

# Contadores
total=0
running=0
stopped=0

# Formato da tabela
header_fmt="  ${BOLD}%-35s %-12s %-15s %-10s${RESET}\n"
row_fmt="  %-35s %-12s %-15s %-10s\n"

echo ""
printf "$header_fmt" "SERVICO" "STATUS" "PORTA(S)" "PID"
echo -e "  ${SEPARATOR}"

# ── SYSTEMD ──────────────────────────────────────────
if [ "$INIT_SYSTEM" = "systemd" ]; then
    while IFS= read -r line; do
        unit=$(echo "$line" | awk '{print $1}' | sed 's/\.service//')
        active=$(echo "$line" | awk '{print $3}')
        sub=$(echo "$line" | awk '{print $4}')

        pid=$(systemctl show "$unit" --property=MainPID 2>/dev/null | cut -d= -f2)
        [ "$pid" = "0" ] && pid="-"

        ports=$(get_ports "$pid")

        total=$((total + 1))

        if [ "$active" = "active" ]; then
            status="${GREEN}active${RESET}"
            running=$((running + 1))
        elif [ "$active" = "failed" ]; then
            status="${RED}failed${RESET}"
            stopped=$((stopped + 1))
        else
            status="${YELLOW}$active${RESET}"
            stopped=$((stopped + 1))
        fi

        printf "  %-35s %-23b %-15s %-10s\n" "$unit" "$status" "$ports" "$pid"

    done < <(systemctl list-units --type=service --all --no-pager --no-legend 2>/dev/null | sort)

# ── LAUNCHD (macOS) ──────────────────────────────────
elif [ "$INIT_SYSTEM" = "launchd" ]; then
    while IFS= read -r line; do
        pid=$(echo "$line" | awk '{print $1}')
        exit_code=$(echo "$line" | awk '{print $2}')
        label=$(echo "$line" | awk '{print $3}')

        # Ignorar servicos internos do Apple muito verbosos
        [[ "$label" == com.apple.* ]] && continue
        [[ "$label" == [0-9]* ]] && continue
        [ -z "$label" ] && continue

        ports="-"
        if [ "$pid" != "-" ] && [ "$pid" != "0" ]; then
            ports=$(get_ports "$pid")
        fi

        total=$((total + 1))

        if [ "$pid" != "-" ] && [ "$pid" != "0" ]; then
            status="${GREEN}active${RESET}"
            running=$((running + 1))
        elif [ "$exit_code" != "0" ]; then
            status="${RED}failed${RESET}"
            stopped=$((stopped + 1))
        else
            status="${YELLOW}inactive${RESET}"
            stopped=$((stopped + 1))
        fi

        printf "  %-35s %-23b %-15s %-10s\n" "$label" "$status" "$ports" "$pid"

    done < <(launchctl list 2>/dev/null | tail -n +2 | sort -t$'\t' -k3)

# ── SYSVINIT / OPENRC ───────────────────────────────
elif [ "$INIT_SYSTEM" = "sysvinit" ] || [ "$INIT_SYSTEM" = "openrc" ]; then
    for script in /etc/init.d/*; do
        [ ! -x "$script" ] && continue
        svc=$(basename "$script")

        result=$("$script" status 2>/dev/null) && svc_active=true || svc_active=false

        pid=$(echo "$result" | grep -oE 'pid\s+[0-9]+' | awk '{print $2}' | head -1)
        [ -z "$pid" ] && pid="-"

        ports=$(get_ports "$pid")

        total=$((total + 1))

        if $svc_active; then
            status="${GREEN}active${RESET}"
            running=$((running + 1))
        else
            status="${RED}stopped${RESET}"
            stopped=$((stopped + 1))
        fi

        printf "  %-35s %-23b %-15s %-10s\n" "$svc" "$status" "$ports" "$pid"
    done

# ── DESCONHECIDO ─────────────────────────────────────
else
    echo -e "  ${RED}Init system nao suportado.${RESET}"
    echo "  Suportados: systemd, launchd (macOS), sysvinit, openrc"
    exit 1
fi

# ── PORTAS EM ESCUTA (complementar) ─────────────────
echo ""
echo -e "  ${SEPARATOR}"
echo -e "  ${BOLD}${CYAN}PORTAS EM ESCUTA${RESET}"
echo -e "  ${SEPARATOR}"
echo ""

port_header_fmt="  ${BOLD}%-10s %-20s %-15s %-10s${RESET}\n"
printf "$port_header_fmt" "PORTA" "PROCESSO" "PROTOCOLO" "PID"
echo -e "  ${SEPARATOR}"

if command -v ss &>/dev/null; then
    ss -tlnp 2>/dev/null | tail -n +2 | while IFS= read -r line; do
        port=$(echo "$line" | awk '{print $4}' | grep -oE '[0-9]+$')
        proto="tcp"
        proc_info=$(echo "$line" | grep -oP 'users:\(\("\K[^"]+' || echo "-")
        pid_info=$(echo "$line" | grep -oP 'pid=\K[0-9]+' || echo "-")
        printf "  %-10s %-20s %-15s %-10s\n" "$port" "$proc_info" "$proto" "$pid_info"
    done
elif command -v lsof &>/dev/null; then
    lsof -iTCP -sTCP:LISTEN -nP 2>/dev/null | tail -n +2 | awk '!seen[$2]++ {printf "  %-10s %-20s %-15s %-10s\n", $9, $1, "tcp", $2}' | sort -t: -k2 -n
fi

# ── RESUMO ───────────────────────────────────────────
echo ""
echo -e "  ${SEPARATOR}"
echo -e "  ${BOLD}RESUMO${RESET}"
echo -e "  Total: ${BOLD}$total${RESET} | ${GREEN}Ativos: $running${RESET} | ${RED}Inativos: $stopped${RESET}"
echo -e "  ${SEPARATOR}"
echo ""
