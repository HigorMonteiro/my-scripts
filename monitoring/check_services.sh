#!/usr/bin/env bash
# check_services.sh - Painel interativo de servicos com start/stop/enable
#
# Uso:
#   ./check_services.sh              # Modo interativo (tabela + menu)
#   ./check_services.sh list         # Apenas listar servicos
#   ./check_services.sh start nginx  # Iniciar servico
#   ./check_services.sh stop nginx   # Parar servico
#   ./check_services.sh enable nginx # Habilitar no boot
#   ./check_services.sh disable nginx

set -euo pipefail

# ╔══════════════════════════════════════════════════════════╗
# ║  CORES E SIMBOLOS                                       ║
# ╚══════════════════════════════════════════════════════════╝
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
WHITE="\033[1;37m"
DIM="\033[2m"
BOLD="\033[1m"
BG_GREEN="\033[42;30m"
BG_RED="\033[41;37m"
BG_YELLOW="\033[43;30m"
BG_CYAN="\033[46;30m"
RESET="\033[0m"

TICK="${GREEN}●${RESET}"
CROSS="${RED}●${RESET}"
WARN="${YELLOW}●${RESET}"

# ╔══════════════════════════════════════════════════════════╗
# ║  DETECTAR INIT SYSTEM                                   ║
# ╚══════════════════════════════════════════════════════════╝
detect_init() {
    if command -v systemctl &>/dev/null && pidof systemd &>/dev/null; then
        echo "systemd"
    elif command -v launchctl &>/dev/null; then
        echo "launchd"
    elif command -v rc-service &>/dev/null; then
        echo "openrc"
    elif [ -d /etc/init.d ]; then
        echo "sysvinit"
    else
        echo "unknown"
    fi
}

INIT_SYSTEM=$(detect_init)

# ╔══════════════════════════════════════════════════════════╗
# ║  FUNCOES UTILITARIAS                                    ║
# ╚══════════════════════════════════════════════════════════╝

get_ports() {
    local pid="$1"
    [ -z "$pid" ] || [ "$pid" = "-" ] && echo "-" && return

    local ports=""
    if command -v ss &>/dev/null; then
        ports=$(ss -tlnp 2>/dev/null | grep "pid=${pid}[,)]" | awk '{print $4}' | grep -oE '[0-9]+$' | sort -un | tr '\n' ',' | sed 's/,$//')
    elif command -v lsof &>/dev/null; then
        ports=$(lsof -iTCP -sTCP:LISTEN -nP 2>/dev/null | awk -v p="$pid" '$2 == p {print $9}' | grep -oE '[0-9]+$' | sort -un | tr '\n' ',' | sed 's/,$//')
    fi
    echo "${ports:-"-"}"
}

get_process_path() {
    local pid="$1"
    [ -z "$pid" ] || [ "$pid" = "-" ] && echo "-" && return

    local path=""
    if [ -f "/proc/$pid/exe" ]; then
        path=$(readlink -f "/proc/$pid/exe" 2>/dev/null || echo "")
    fi
    if [ -z "$path" ] && command -v lsof &>/dev/null; then
        path=$(lsof -p "$pid" -Fn 2>/dev/null | grep '^n/' | head -1 | cut -c2- || echo "")
    fi
    if [ -z "$path" ] && command -v ps &>/dev/null; then
        path=$(ps -p "$pid" -o comm= 2>/dev/null || echo "")
    fi
    echo "${path:-"-"}"
}

format_uptime() {
    local pid="$1"
    [ -z "$pid" ] || [ "$pid" = "-" ] && echo "-" && return

    local elapsed=""
    if command -v ps &>/dev/null; then
        elapsed=$(ps -p "$pid" -o etime= 2>/dev/null | xargs) || true
    fi
    [ -z "$elapsed" ] && echo "-" && return

    # etime formats: MM:SS, HH:MM:SS, D-HH:MM:SS
    local days=0 hours=0 mins=0 secs=0
    if [[ "$elapsed" == *-* ]]; then
        days="${elapsed%%-*}"
        elapsed="${elapsed##*-}"
    fi
    IFS=: read -ra parts <<< "$elapsed"
    case ${#parts[@]} in
        3) hours="${parts[0]}"; mins="${parts[1]}"; secs="${parts[2]}" ;;
        2) mins="${parts[0]}"; secs="${parts[1]}" ;;
        1) secs="${parts[0]}" ;;
    esac

    # Remover zeros a esquerda
    days=$((10#$days)); hours=$((10#$hours)); mins=$((10#$mins))

    local result=""
    [ "$days" -gt 0 ] && result="${days}d "
    [ "$hours" -gt 0 ] && result="${result}${hours}h "
    [ "$mins" -gt 0 ] && result="${result}${mins}min"
    [ -z "$result" ] && result="${secs}s"
    echo "$result"
}

truncate_str() {
    local str="$1" max="$2"
    if [ "${#str}" -gt "$max" ]; then
        echo "${str:0:$((max-2))}.."
    else
        echo "$str"
    fi
}

# ╔══════════════════════════════════════════════════════════╗
# ║  COLETAR SERVICOS                                       ║
# ╚══════════════════════════════════════════════════════════╝

declare -a SVC_NAMES=()
declare -a SVC_PIDS=()
declare -a SVC_PATHS=()
declare -a SVC_PORTS=()
declare -a SVC_STATUS=()
declare -a SVC_UPTIMES=()

collect_services() {
    local idx=0

    if [ "$INIT_SYSTEM" = "systemd" ]; then
        while IFS= read -r line; do
            local unit active pid ports path uptime
            unit=$(echo "$line" | awk '{print $1}' | sed 's/\.service//')
            active=$(echo "$line" | awk '{print $3}')

            pid=$(systemctl show "$unit" --property=MainPID 2>/dev/null | cut -d= -f2)
            [ "$pid" = "0" ] && pid="-"

            ports=$(get_ports "$pid")
            path=$(get_process_path "$pid")
            uptime=$(format_uptime "$pid")

            SVC_NAMES+=("$unit")
            SVC_PIDS+=("$pid")
            SVC_PATHS+=("$path")
            SVC_PORTS+=("$ports")
            SVC_UPTIMES+=("$uptime")

            if [ "$active" = "active" ]; then
                SVC_STATUS+=("running")
            elif [ "$active" = "failed" ]; then
                SVC_STATUS+=("failed")
            else
                SVC_STATUS+=("stopped")
            fi
            idx=$((idx + 1))
        done < <(systemctl list-units --type=service --all --no-pager --no-legend 2>/dev/null | sort)

    elif [ "$INIT_SYSTEM" = "launchd" ]; then
        while IFS= read -r line; do
            local label lpid exit_code ports path uptime
            lpid=$(echo "$line" | awk '{print $1}')
            exit_code=$(echo "$line" | awk '{print $2}')
            label=$(echo "$line" | awk '{print $3}')

            [[ "$label" == com.apple.* ]] && continue
            [[ "$label" == [0-9]* ]] && continue
            [ -z "$label" ] && continue

            local pid_val="-"
            [ "$lpid" != "-" ] && [ "$lpid" != "0" ] && pid_val="$lpid"

            ports=$(get_ports "$pid_val")
            path=$(get_process_path "$pid_val")
            uptime=$(format_uptime "$pid_val")

            SVC_NAMES+=("$label")
            SVC_PIDS+=("$pid_val")
            SVC_PATHS+=("$path")
            SVC_PORTS+=("$ports")
            SVC_UPTIMES+=("$uptime")

            if [ "$pid_val" != "-" ]; then
                SVC_STATUS+=("running")
            elif [ "$exit_code" != "0" ]; then
                SVC_STATUS+=("failed")
            else
                SVC_STATUS+=("stopped")
            fi
            idx=$((idx + 1))
        done < <(launchctl list 2>/dev/null | tail -n +2 | sort -t$'\t' -k3)

    elif [ "$INIT_SYSTEM" = "sysvinit" ] || [ "$INIT_SYSTEM" = "openrc" ]; then
        for script in /etc/init.d/*; do
            [ ! -x "$script" ] && continue
            local svc result pid ports path uptime
            svc=$(basename "$script")

            result=$("$script" status 2>/dev/null) && local is_active=true || local is_active=false
            pid=$(echo "$result" | grep -oE 'pid\s+[0-9]+' | awk '{print $2}' | head -1)
            [ -z "$pid" ] && pid="-"

            ports=$(get_ports "$pid")
            path=$(get_process_path "$pid")
            uptime=$(format_uptime "$pid")

            SVC_NAMES+=("$svc")
            SVC_PIDS+=("$pid")
            SVC_PATHS+=("$path")
            SVC_PORTS+=("$ports")
            SVC_UPTIMES+=("$uptime")

            if $is_active; then
                SVC_STATUS+=("running")
            else
                SVC_STATUS+=("stopped")
            fi
            idx=$((idx + 1))
        done
    fi
}

# ╔══════════════════════════════════════════════════════════╗
# ║  DESENHAR TABELA                                        ║
# ╚══════════════════════════════════════════════════════════╝

draw_table() {
    local filter="${1:-all}" # all, running, stopped

    local total=${#SVC_NAMES[@]}
    local count_running=0 count_stopped=0 count_failed=0

    for s in "${SVC_STATUS[@]}"; do
        case "$s" in
            running) count_running=$((count_running + 1)) ;;
            failed)  count_failed=$((count_failed + 1)) ;;
            *)       count_stopped=$((count_stopped + 1)) ;;
        esac
    done

    # Banner
    echo ""
    echo -e "  ${BOLD}${WHITE}╔══════════════════════════════════════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "  ${BOLD}${WHITE}║${RESET}  ${BOLD}${CYAN}SERVICES${RESET}                                                              $(date '+%d/%m/%Y %H:%M:%S')  ${BOLD}${WHITE}║${RESET}"
    echo -e "  ${BOLD}${WHITE}║${RESET}  ${DIM}Host: $(hostname) | Init: $INIT_SYSTEM${RESET}$(printf '%*s' $((54 - ${#HOSTNAME} - ${#INIT_SYSTEM})) '')${BOLD}${WHITE}║${RESET}"
    echo -e "  ${BOLD}${WHITE}╠══════════════════════════════════════════════════════════════════════════════════════════════════════╣${RESET}"

    # Stats bar
    echo -e "  ${BOLD}${WHITE}║${RESET}  ${BG_GREEN} ${count_running} RUNNING ${RESET}  ${BG_RED} ${count_failed} FAILED ${RESET}  ${BG_YELLOW} ${count_stopped} STOPPED ${RESET}  ${DIM}Total: ${total}${RESET}$(printf '%*s' $((50 - ${#total})) '')${BOLD}${WHITE}║${RESET}"
    echo -e "  ${BOLD}${WHITE}╠══════════════════════════════════════════════════════════════════════════════════════════════════════╣${RESET}"

    # Header
    printf "  ${BOLD}${WHITE}║${RESET}  ${BOLD}%-4s %-28s %-7s %-28s %-8s %-10s %-10s${RESET}${BOLD}${WHITE}║${RESET}\n" "#" "NAME" "PID" "PATH" "PORT" "STATUS" "UP TIME"
    echo -e "  ${BOLD}${WHITE}╠══════════════════════════════════════════════════════════════════════════════════════════════════════╣${RESET}"

    # Rows
    local visible=0
    for i in "${!SVC_NAMES[@]}"; do
        local st="${SVC_STATUS[$i]}"

        # Filtro
        if [ "$filter" = "running" ] && [ "$st" != "running" ]; then continue; fi
        if [ "$filter" = "stopped" ] && [ "$st" != "stopped" ] && [ "$st" != "failed" ]; then continue; fi

        visible=$((visible + 1))
        local num="$((i + 1))"
        local name=$(truncate_str "${SVC_NAMES[$i]}" 26)
        local pid="${SVC_PIDS[$i]}"
        local path=$(truncate_str "${SVC_PATHS[$i]}" 26)
        local port="${SVC_PORTS[$i]}"
        local uptime="${SVC_UPTIMES[$i]}"

        local status_col
        case "$st" in
            running) status_col="${TICK} ${GREEN}RUNNING${RESET}" ;;
            failed)  status_col="${CROSS} ${RED}FAILED${RESET} " ;;
            *)       status_col="${CROSS} ${RED}STOPPED${RESET}" ;;
        esac

        printf "  ${BOLD}${WHITE}║${RESET}  ${DIM}%-4s${RESET} %-28s %-7s %-28s %-8s %b  %-10s${BOLD}${WHITE}║${RESET}\n" \
            "$num" "$name" "$pid" "$path" "$port" "$status_col" "$uptime"
    done

    if [ "$visible" -eq 0 ]; then
        printf "  ${BOLD}${WHITE}║${RESET}  ${DIM}%-100s${RESET}${BOLD}${WHITE}║${RESET}\n" "Nenhum servico encontrado com o filtro: $filter"
    fi

    echo -e "  ${BOLD}${WHITE}╚══════════════════════════════════════════════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

# ╔══════════════════════════════════════════════════════════╗
# ║  ACOES: START / STOP / ENABLE / DISABLE                 ║
# ╚══════════════════════════════════════════════════════════╝

svc_action() {
    local action="$1" service="$2"

    echo ""
    case "$INIT_SYSTEM" in
        systemd)
            case "$action" in
                start)   echo -e "  ${CYAN}[*]${RESET} Iniciando ${BOLD}$service${RESET}..."; sudo systemctl start "$service" ;;
                stop)    echo -e "  ${CYAN}[*]${RESET} Parando ${BOLD}$service${RESET}..."; sudo systemctl stop "$service" ;;
                restart) echo -e "  ${CYAN}[*]${RESET} Reiniciando ${BOLD}$service${RESET}..."; sudo systemctl restart "$service" ;;
                enable)  echo -e "  ${CYAN}[*]${RESET} Habilitando ${BOLD}$service${RESET} no boot..."; sudo systemctl enable "$service" ;;
                disable) echo -e "  ${CYAN}[*]${RESET} Desabilitando ${BOLD}$service${RESET} do boot..."; sudo systemctl disable "$service" ;;
            esac
            ;;
        launchd)
            local plist=""
            for dir in ~/Library/LaunchAgents /Library/LaunchAgents /Library/LaunchDaemons /System/Library/LaunchDaemons; do
                if [ -f "$dir/$service.plist" ]; then
                    plist="$dir/$service.plist"
                    break
                fi
            done

            case "$action" in
                start)
                    echo -e "  ${CYAN}[*]${RESET} Iniciando ${BOLD}$service${RESET}..."
                    if [ -n "$plist" ]; then
                        launchctl load -w "$plist" 2>/dev/null || launchctl kickstart "gui/$(id -u)/$service" 2>/dev/null || brew services start "${service##*.}" 2>/dev/null
                    else
                        brew services start "${service##*.}" 2>/dev/null || echo -e "  ${RED}[!] Nao encontrado. Tente: brew services start <nome>${RESET}"
                    fi
                    ;;
                stop)
                    echo -e "  ${CYAN}[*]${RESET} Parando ${BOLD}$service${RESET}..."
                    if [ -n "$plist" ]; then
                        launchctl unload "$plist" 2>/dev/null || launchctl kill SIGTERM "gui/$(id -u)/$service" 2>/dev/null || brew services stop "${service##*.}" 2>/dev/null
                    else
                        brew services stop "${service##*.}" 2>/dev/null || echo -e "  ${RED}[!] Nao encontrado. Tente: brew services stop <nome>${RESET}"
                    fi
                    ;;
                restart)
                    echo -e "  ${CYAN}[*]${RESET} Reiniciando ${BOLD}$service${RESET}..."
                    brew services restart "${service##*.}" 2>/dev/null || { svc_action stop "$service"; sleep 1; svc_action start "$service"; }
                    ;;
                enable)
                    echo -e "  ${CYAN}[*]${RESET} Habilitando ${BOLD}$service${RESET} no boot..."
                    if [ -n "$plist" ]; then
                        launchctl load -w "$plist"
                    else
                        brew services start "${service##*.}" 2>/dev/null
                    fi
                    ;;
                disable)
                    echo -e "  ${CYAN}[*]${RESET} Desabilitando ${BOLD}$service${RESET} do boot..."
                    if [ -n "$plist" ]; then
                        launchctl unload -w "$plist"
                    else
                        brew services stop "${service##*.}" 2>/dev/null
                    fi
                    ;;
            esac
            ;;
        sysvinit|openrc)
            case "$action" in
                start)   echo -e "  ${CYAN}[*]${RESET} Iniciando ${BOLD}$service${RESET}..."; sudo /etc/init.d/"$service" start ;;
                stop)    echo -e "  ${CYAN}[*]${RESET} Parando ${BOLD}$service${RESET}..."; sudo /etc/init.d/"$service" stop ;;
                restart) echo -e "  ${CYAN}[*]${RESET} Reiniciando ${BOLD}$service${RESET}..."; sudo /etc/init.d/"$service" restart ;;
                enable)  echo -e "  ${CYAN}[*]${RESET} Habilitando ${BOLD}$service${RESET} no boot..."; sudo update-rc.d "$service" defaults 2>/dev/null || sudo chkconfig "$service" on 2>/dev/null ;;
                disable) echo -e "  ${CYAN}[*]${RESET} Desabilitando ${BOLD}$service${RESET} do boot..."; sudo update-rc.d "$service" disable 2>/dev/null || sudo chkconfig "$service" off 2>/dev/null ;;
            esac
            ;;
    esac

    if [ $? -eq 0 ]; then
        echo -e "  ${GREEN}[OK]${RESET} Acao '${action}' executada com sucesso em ${BOLD}$service${RESET}"
    else
        echo -e "  ${RED}[ERRO]${RESET} Falha ao executar '${action}' em ${BOLD}$service${RESET}"
    fi
    echo ""
}

# ╔══════════════════════════════════════════════════════════╗
# ║  MENU INTERATIVO                                        ║
# ╚══════════════════════════════════════════════════════════╝

interactive_menu() {
    while true; do
        # Limpar e recoletar dados
        SVC_NAMES=(); SVC_PIDS=(); SVC_PATHS=(); SVC_PORTS=(); SVC_STATUS=(); SVC_UPTIMES=()
        collect_services
        draw_table "all"

        echo -e "  ${BOLD}ACOES:${RESET}"
        echo -e "  ${CYAN}[1]${RESET} Iniciar servico       ${CYAN}[4]${RESET} Habilitar no boot"
        echo -e "  ${CYAN}[2]${RESET} Parar servico         ${CYAN}[5]${RESET} Desabilitar do boot"
        echo -e "  ${CYAN}[3]${RESET} Reiniciar servico     ${CYAN}[6]${RESET} Filtrar (running/stopped)"
        echo -e "  ${CYAN}[r]${RESET} Atualizar tabela      ${CYAN}[q]${RESET} Sair"
        echo ""
        read -rp "  Escolha uma opcao: " choice

        case "$choice" in
            1)
                read -rp "  Nome do servico para INICIAR: " svc_name
                [ -n "$svc_name" ] && svc_action start "$svc_name"
                read -rp "  Pressione ENTER para continuar..." _
                ;;
            2)
                read -rp "  Nome do servico para PARAR: " svc_name
                [ -n "$svc_name" ] && svc_action stop "$svc_name"
                read -rp "  Pressione ENTER para continuar..." _
                ;;
            3)
                read -rp "  Nome do servico para REINICIAR: " svc_name
                [ -n "$svc_name" ] && svc_action restart "$svc_name"
                read -rp "  Pressione ENTER para continuar..." _
                ;;
            4)
                read -rp "  Nome do servico para HABILITAR no boot: " svc_name
                [ -n "$svc_name" ] && svc_action enable "$svc_name"
                read -rp "  Pressione ENTER para continuar..." _
                ;;
            5)
                read -rp "  Nome do servico para DESABILITAR do boot: " svc_name
                [ -n "$svc_name" ] && svc_action disable "$svc_name"
                read -rp "  Pressione ENTER para continuar..." _
                ;;
            6)
                echo ""
                echo -e "  ${CYAN}[a]${RESET} Todos  ${CYAN}[r]${RESET} Running  ${CYAN}[s]${RESET} Stopped"
                read -rp "  Filtro: " f
                case "$f" in
                    r) draw_table "running" ;;
                    s) draw_table "stopped" ;;
                    *) draw_table "all" ;;
                esac
                read -rp "  Pressione ENTER para continuar..." _
                ;;
            r|R) continue ;;
            q|Q) echo -e "\n  ${DIM}Bye!${RESET}\n"; exit 0 ;;
            *)   echo -e "  ${RED}Opcao invalida.${RESET}"; sleep 1 ;;
        esac
    done
}

# ╔══════════════════════════════════════════════════════════╗
# ║  SCRIPT PARA HABILITAR NO BOOT (standalone)             ║
# ╚══════════════════════════════════════════════════════════╝

enable_on_boot() {
    local service="$1"
    svc_action enable "$service"
}

# ╔══════════════════════════════════════════════════════════╗
# ║  MAIN - CLI                                             ║
# ╚══════════════════════════════════════════════════════════╝

case "${1:-interactive}" in
    list)
        collect_services
        draw_table "${2:-all}"
        ;;
    start|stop|restart)
        [ -z "${2:-}" ] && echo -e "  ${RED}Uso: $0 $1 <servico>${RESET}" && exit 1
        svc_action "$1" "$2"
        ;;
    enable|disable)
        [ -z "${2:-}" ] && echo -e "  ${RED}Uso: $0 $1 <servico>${RESET}" && exit 1
        svc_action "$1" "$2"
        ;;
    interactive|"")
        interactive_menu
        ;;
    -h|--help|help)
        echo ""
        echo -e "  ${BOLD}${CYAN}check_services.sh${RESET} - Painel de servicos"
        echo ""
        echo -e "  ${BOLD}USO:${RESET}"
        echo "    ./check_services.sh                   Modo interativo"
        echo "    ./check_services.sh list              Listar todos os servicos"
        echo "    ./check_services.sh list running      Listar apenas ativos"
        echo "    ./check_services.sh list stopped      Listar apenas parados"
        echo "    ./check_services.sh start  <servico>  Iniciar servico"
        echo "    ./check_services.sh stop   <servico>  Parar servico"
        echo "    ./check_services.sh restart <servico> Reiniciar servico"
        echo "    ./check_services.sh enable <servico>  Habilitar no boot"
        echo "    ./check_services.sh disable <servico> Desabilitar do boot"
        echo ""
        ;;
    *)
        echo -e "  ${RED}Comando invalido: $1${RESET}"
        echo "  Use: $0 --help"
        exit 1
        ;;
esac
