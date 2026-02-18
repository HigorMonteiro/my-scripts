#!/usr/bin/env bash
# check_services.sh - Monitoramento de servicos

set -euo pipefail

SERVICES=("nginx" "docker" "postgresql")

check_service() {
    local service="$1"
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        echo "[OK]    $service esta rodando"
    else
        echo "[FALHA] $service esta parado"
    fi
}

echo "=== Verificacao de servicos ==="
echo "Data: $(date)"
echo "---"

for svc in "${SERVICES[@]}"; do
    check_service "$svc"
done

echo "---"
echo "=== Verificacao concluida ==="
