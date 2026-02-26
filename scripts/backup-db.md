# Scripts

## backup-db.sh

Backs up MySQL/MariaDB or PostgreSQL databases running in Docker (or Docker Swarm) containers.

### Install

```bash
curl -fsSL https://gitea.marvin.ar/lhome/HomelabScripts/raw/branch/main/scripts/backup-db.sh \
  -o /usr/local/bin/backup-db.sh && chmod +x /usr/local/bin/backup-db.sh
```

### Usage

```bash
backup-db.sh /path/to/backup.conf
```

### Config file

```ini
CONTAINER="my_db_container"   # Docker container or Swarm service name (required)
BACKUP_DIR="/var/backups/db"  # Default: /var/backups/<container>
RETENTION_DAYS=7              # Default: 7
```

Credentials are read automatically from the container's environment variables (`MYSQL_*`, `MARIADB_*`, or `POSTGRES_*`).

### Example (on host `gitea`)

```bash
ssh gitea
backup-db.sh /etc/backup/gitea-db.conf
```

Or via cron:

```
0 3 * * * /usr/local/bin/backup-db.sh /etc/backup/gitea-db.conf
```
