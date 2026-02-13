# 05 — Storage & Backups (FitnaAI)

## Overview

Automated backup system for the `home/fitna` data directory.
Supports bare-metal (systemd timer), Docker container (cron), and optional remote sync.

---

## Architecture

```
Host (Proxmox / LXC)
├── /mnt/data/fitnaai/home/fitna    ← Live data
├── /mnt/data/backups/fitnaai/      ← Backup archives
│   ├── fitna-backup-20250213-020000.tar.gz
│   ├── fitna-backup-20250214-020000.tar.gz
│   └── ...
└── /opt/fitnaai/scripts/           ← Automation scripts
```

## Filename Convention

```
fitna-backup-YYYYMMDD-HHMMSS.tar.gz
```

- Date-stamped to the second to prevent collisions
- Backups older than 30 days are auto-deleted (configurable via `RETENTION_DAYS`)

## Backup Location

| Item | Path |
|------|------|
| Source data | `/mnt/data/fitnaai/home/fitna` |
| Backup archives | `/mnt/data/backups/fitnaai/` |
| Logs | `/opt/fitnaai/logs/backup-fitna.log` |

---

## Manual Backup

```bash
# From project root
./scripts/backup-fitna.sh

# Custom source/target
SOURCE_DIR=/path/to/data BACKUP_DIR=/path/to/backups ./scripts/backup-fitna.sh

# Shorter retention
RETENTION_DAYS=7 ./scripts/backup-fitna.sh
```

## Restore

```bash
# Restore latest backup
./scripts/restore-fitna.sh

# Restore specific backup
./scripts/restore-fitna.sh fitna-backup-20250213-020000.tar.gz

# Dry run (preview without changes)
DRY_RUN=1 ./scripts/restore-fitna.sh

# Restore to custom location
RESTORE_TARGET=/tmp/fitna-test ./scripts/restore-fitna.sh
```

A **safety snapshot** of the current state is always created before restoring.

---

## Automated Scheduling

### Option A: systemd timer (bare-metal / LXC)

```bash
sudo cp scripts/fitna-backup.service /etc/systemd/system/
sudo cp scripts/fitna-backup.timer   /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now fitna-backup.timer

# Verify
systemctl list-timers fitna-backup.timer
```

### Option B: Docker container (cron)

```bash
docker compose -f docker/stacks/fitna-backup.yml up -d

# Manual trigger inside container
docker exec fitna-backup bash /app/scripts/backup-fitna.sh

# View logs
docker compose -f docker/stacks/fitna-backup.yml logs -f
```

---

## Docker Volume Mounts

| Host Path | Container Path | Mode |
|-----------|---------------|------|
| `/mnt/data/fitnaai/home/fitna` | `/app/fitna` | `ro` (read-only) |
| `/mnt/data/backups/fitnaai` | `/backups` | `rw` |
| `./scripts` | `/app/scripts` | `ro` |
| Docker volume `backup-logs` | `/app/logs` | `rw` |

---

## Remote Sync (Optional)

If an external VPS or NAS is available:

```bash
# One-time sync
rsync -avz --progress \
  /mnt/data/backups/fitnaai/ \
  user@remote-host:/backups/fitnaai/

# With SSH key (non-interactive)
rsync -avz -e "ssh -i ~/.ssh/backup_key" \
  /mnt/data/backups/fitnaai/ \
  user@remote-host:/backups/fitnaai/ \
  >> logs/remote-sync.log 2>&1
```

Add to cron for automated off-site backup (run after the main backup):

```cron
30 2 * * * rsync -avz -e "ssh -i ~/.ssh/backup_key" /mnt/data/backups/fitnaai/ user@remote:/backups/fitnaai/ >> /opt/fitnaai/logs/remote-sync.log 2>&1
```

---

## Go/No-Go Checklist

| # | Check | Command |
|---|-------|---------|
| 1 | Source directory exists | `ls -la /mnt/data/fitnaai/home/fitna` |
| 2 | Backup directory writable | `touch /mnt/data/backups/fitnaai/.writetest && rm -f /mnt/data/backups/fitnaai/.writetest` |
| 3 | Scripts are executable | `ls -la scripts/backup-fitna.sh scripts/restore-fitna.sh` |
| 4 | Test backup succeeds | `./scripts/backup-fitna.sh` |
| 5 | Archive integrity OK | `tar -tzf /mnt/data/backups/fitnaai/fitna-backup-*.tar.gz > /dev/null` |
| 6 | Old backup cleanup works | `RETENTION_DAYS=0 ./scripts/backup-fitna.sh` (then check) |
| 7 | Restore dry-run works | `DRY_RUN=1 ./scripts/restore-fitna.sh` |
| 8 | Restore test succeeds | `RESTORE_TARGET=/tmp/fitna-test ./scripts/restore-fitna.sh && ls /tmp/fitna-test` |
| 9 | Container mounts verified | `docker exec fitna-backup ls -l /app/fitna` |
| 10 | Cron/timer active | `systemctl list-timers fitna-backup.timer` or `docker exec fitna-backup crontab -l` |
