#!/bin/bash
# backup-db.sh — MySQL/MariaDB & PostgreSQL Docker container backup
#
# Uso:    backup-db.sh <path/to/backup.conf>
# Origen: https://gitea.marvin.ar/lhome/HomelabScripts/raw/branch/main/scripts/backup-db.sh
# Actualizar:
#   curl -fsSL https://gitea.marvin.ar/lhome/HomelabScripts/raw/branch/main/scripts/backup-db.sh \
#     -o /usr/local/bin/backup-db.sh && chmod +x /usr/local/bin/backup-db.sh
#
# backup.conf (mínimo):
#   CONTAINER="zabbix_db"
#
# backup.conf (completo):
#   CONTAINER="zabbix_db"
#   RETENTION_DAYS=7
#   BACKUP_DIR="/var/backups/zabbix_db"   # opcional, por defecto /var/backups/<container>

set -euo pipefail

CONFIG="${1:?Uso: $0 <path/to/backup.conf>}"
# shellcheck source=/dev/null
source "$CONFIG"

: "${CONTAINER:?backup.conf debe definir CONTAINER}"
: "${RETENTION_DAYS:=7}"
: "${BACKUP_DIR:=/var/backups/${CONTAINER}}"

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/${CONTAINER}_${DATE}.sql.gz"

# --- Extraer env var del container ---
_env() {
    docker inspect "$CONTAINER" \
        --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
        | grep "^${1}=" | cut -d= -f2- || true
}

# --- Auto-detectar motor: MySQL/MariaDB → PostgreSQL ---
DB_USER=$(_env MYSQL_USER)
DB_PASS=$(_env MYSQL_PASSWORD)
DB_NAME=$(_env MYSQL_DATABASE)

if [ -z "$DB_USER" ]; then DB_USER=$(_env MARIADB_USER);    fi
if [ -z "$DB_PASS" ]; then DB_PASS=$(_env MARIADB_PASSWORD); fi
if [ -z "$DB_NAME" ]; then DB_NAME=$(_env MARIADB_DATABASE); fi

if [ -n "$DB_USER" ] && [ -n "$DB_NAME" ]; then
    ENGINE="mysql"
else
    DB_USER=$(_env POSTGRES_USER)
    DB_PASS=$(_env POSTGRES_PASSWORD)
    DB_NAME=$(_env POSTGRES_DB)
    if [ -n "$DB_USER" ] && [ -n "$DB_NAME" ]; then
        ENGINE="postgres"
    else
        echo "ERROR: motor no detectado en container '${CONTAINER}'" >&2
        exit 1
    fi
fi

# --- Backup ---
mkdir -p "$BACKUP_DIR"
echo "[$(date '+%F %T')] Iniciando backup de '${DB_NAME}' (${ENGINE}) desde '${CONTAINER}'"

case "$ENGINE" in
    mysql)
        docker exec "$CONTAINER" mysqldump \
            -u"$DB_USER" -p"$DB_PASS" \
            --single-transaction --routines --triggers \
            "$DB_NAME" 2>/dev/null \
            | gzip > "$BACKUP_FILE"
        ;;
    postgres)
        docker exec -e PGPASSWORD="$DB_PASS" "$CONTAINER" pg_dump \
            -U "$DB_USER" -d "$DB_NAME" --no-password \
            | gzip > "$BACKUP_FILE"
        ;;
esac

SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
echo "[$(date '+%F %T')] OK — ${BACKUP_FILE} (${SIZE})"

# --- Retención ---
DELETED=$(find "$BACKUP_DIR" -name "*.sql.gz" -mtime +"$RETENTION_DAYS" -print -delete | wc -l)
if [ "$DELETED" -gt 0 ]; then
    echo "[$(date '+%F %T')] Eliminados ${DELETED} backup(s) con más de ${RETENTION_DAYS} días"
fi

exit 0
