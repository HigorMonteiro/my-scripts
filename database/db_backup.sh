#!/usr/bin/env bash
# db_backup.sh - Backup do banco Postgres/Django

set -euo pipefail

DB_NAME="${DB_NAME:-mydb}"
DB_USER="${DB_USER:-postgres}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/backups/db}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/${DB_NAME}_${TIMESTAMP}.sql.gz"
RETENTION_DAYS=7

mkdir -p "$BACKUP_DIR"

echo "=== Backup do banco $DB_NAME ==="
echo "Data: $(date)"

pg_dump -U "$DB_USER" "$DB_NAME" | gzip > "$BACKUP_FILE"
echo "[OK] Backup salvo em: $BACKUP_FILE"

# Limpar backups antigos
echo "[*] Removendo backups com mais de $RETENTION_DAYS dias..."
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +"$RETENTION_DAYS" -delete

echo "=== Backup concluido ==="
