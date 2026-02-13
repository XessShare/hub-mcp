# Scripts — Operator Quick Reference

## Backup

```bash
# Run backup (defaults: ~/home/fitna → /mnt/data/backups/fitnaai/)
./scripts/backup-fitna.sh

# Custom paths
SOURCE_DIR=/custom/data BACKUP_DIR=/custom/backups ./scripts/backup-fitna.sh

# Change retention to 7 days
RETENTION_DAYS=7 ./scripts/backup-fitna.sh
```

## Restore

```bash
# Restore latest backup (creates safety snapshot first)
./scripts/restore-fitna.sh

# Restore specific archive
./scripts/restore-fitna.sh fitna-backup-20250213-020000.tar.gz

# Preview without modifying anything
DRY_RUN=1 ./scripts/restore-fitna.sh

# Restore to alternate location
RESTORE_TARGET=/tmp/test-restore ./scripts/restore-fitna.sh
```

## Docker

```bash
# Start backup container
docker compose -f docker/stacks/fitna-backup.yml up -d

# Trigger backup manually
docker exec fitna-backup bash /app/scripts/backup-fitna.sh

# Check mount
docker exec fitna-backup ls -l /app/fitna

# View logs
docker compose -f docker/stacks/fitna-backup.yml logs -f
```

## systemd Timer

```bash
# Install
sudo cp scripts/fitna-backup.service /etc/systemd/system/
sudo cp scripts/fitna-backup.timer   /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now fitna-backup.timer

# Check schedule
systemctl list-timers fitna-backup.timer

# Run manually
sudo systemctl start fitna-backup.service

# View logs
journalctl -u fitna-backup.service --since today
```

## Logs

| Log file | Purpose |
|----------|---------|
| `logs/backup-fitna.log` | Backup operations |
| `logs/restore-fitna.log` | Restore operations |
| `logs/remote-sync.log` | Remote rsync (if configured) |
