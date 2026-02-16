# Backup Runbook — User Data from Omarchy SSD to pve-ryzen 2TB HDD

> **Status:** Active
> **Last updated:** 2026-02-16
> **Scope:** Backup of user-created files from `/mnt/omarchy/@home/fitna/` on pve (192.168.16.2) to the 2TB HDD on pve-ryzen (192.168.17.1)

---

## Architecture

```
pve (192.168.16.2)                     pve-ryzen (192.168.17.1)
┌──────────────────────┐               ┌──────────────────────┐
│ Omarchy M.2 SSD      │   rsync/SSH   │ 2TB HDD              │
│ /mnt/omarchy/@home/  │ ───────────>  │ /mnt/hdd/            │
│   fitna/             │               │   fitna-backup/      │
│                      │               │                      │
│ ~497 GB user data    │               │ 2TB capacity         │
│ (466 GB Desktop!)    │               │                      │
└──────────────────────┘               └──────────────────────┘
```

---

## Data Inventory (as of 2026-02-08)

### Priority 1 — Critical (Code, Secrets, Config)

| Path | Size | Type | Notes |
|------|------|------|-------|
| `FItnaai/` | 119 MB | Python project | Main project! Has .git |
| `.secrets/` | 92 B dir | Env files | `clawd-bot/development.env`, `fitnaai/development.env` |
| `.ssh/` | 270 B dir | SSH keys | Ed25519 keys |
| `.gnupg/` | 116 B dir | GPG keys | Encryption keys |
| `.git-credentials` | 70 B | GitHub token | **COMPROMISED — REVOKE IMMEDIATELY** |
| `.claude.json` | 30 KB | Claude config | Active config |
| `content-pipeline/` | 138 MB | Pipeline project | Has code |

### Priority 2 — Important (Documents, Projects)

| Path | Size | Type |
|------|------|------|
| `homelab/` | 12 GB | Homelab configs |
| `J-Jeco/` | 7.6 GB | Project data |
| `Documents/` | 1.6 GB | Personal docs |
| `Business/` | 140 KB | Business docs |
| `2026 Coding/` | 2.8 MB | Coding projects |
| `mcpServers/` | 176 KB | MCP server configs |
| `coderabbit-docs/` | 104 MB | CodeRabbit docs |

### Priority 3 — Media (Large, but user-created)

| Path | Size | Type |
|------|------|------|
| **`Desktop/`** | **466 GB** | **UNKNOWN — Must be checked!** |
| `Videos/` | 4.5 GB | User videos |
| `Pictures/` | 1.3 GB | User images |
| `Downloads/` | 3.9 GB | Downloads |

### Excluded (Regeneratable/System)

| Path | Reason |
|------|--------|
| `.venv/` | Python virtualenv — regeneratable |
| `node_modules/` | npm — regeneratable |
| `__pycache__/` | Python bytecode |
| `.cache/` | System caches |
| `.ollama/models/` | Re-downloadable AI models |
| `.mozilla/` | Browser profile |
| `*.iso`, `*.qcow2` | VM images — use vzdump instead |

---

## Prerequisites

### 1. SSH Key-Based Access

```bash
# On pve (192.168.16.2):
ssh-keygen -t ed25519 -C "pve-backup" -f /root/.ssh/id_backup -N ""
ssh-copy-id -i /root/.ssh/id_backup root@192.168.17.1
ssh root@192.168.17.1 "echo OK"
```

### 2. Mount Omarchy SSD (if not already mounted)

```bash
# On pve:
mount /mnt/omarchy   # or: systemctl start mnt-omarchy.mount
ls /mnt/omarchy/@home/fitna/   # verify
```

### 3. Mount 2TB HDD on pve-ryzen

```bash
# On pve-ryzen (192.168.17.1):
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT   # find the 2TB disk
# Example: /dev/sdb1  1.8T  part

# Mount it (if not mounted):
mkdir -p /mnt/hdd
mount /dev/sdb1 /mnt/hdd

# Make persistent (add to /etc/fstab):
echo "UUID=$(blkid -s UUID -o value /dev/sdb1) /mnt/hdd ext4 defaults,noatime 0 2" >> /etc/fstab
```

---

## Execution

### First Run: Check Desktop (466 GB)

Before the first full backup, check what's in Desktop:

```bash
# On pve:
ls -la /mnt/omarchy/@home/fitna/Desktop/ | head -40
du -sh /mnt/omarchy/@home/fitna/Desktop/*/ 2>/dev/null | sort -rh | head -20
file /mnt/omarchy/@home/fitna/Desktop/*.iso 2>/dev/null   # check for ISOs
```

### Dry Run (recommended first!)

```bash
# On pve:
bash proxmox/backup/backup-user-data.sh --dry-run
```

This shows what WOULD be transferred without actually copying anything.

### Full Backup (with Desktop)

```bash
bash proxmox/backup/backup-user-data.sh
```

**Estimated time:** 466+ GB over Gigabit LAN = ~60-90 minutes for first run.
Subsequent runs are incremental (only changed files).

### Quick Backup (without Desktop)

```bash
bash proxmox/backup/backup-user-data.sh --skip-desktop
```

**Estimated time:** ~30 GB = ~5-10 minutes.

### Code-Only Backup (skip all media)

```bash
bash proxmox/backup/backup-user-data.sh --skip-desktop --skip-media
```

**Estimated time:** ~15 GB = ~3-5 minutes.

### Manual HDD Path Override

If auto-detection fails:

```bash
BACKUP_HDD_MOUNT=/mnt/hdd bash proxmox/backup/backup-user-data.sh
```

---

## Verification

After backup completes:

```bash
# 1. Check backup size
ssh root@192.168.17.1 "du -sh /mnt/hdd/fitna-backup/"

# 2. Check backup contents
ssh root@192.168.17.1 "du -sh /mnt/hdd/fitna-backup/*/ | sort -rh | head -20"

# 3. Verify critical files exist
ssh root@192.168.17.1 "ls -la /mnt/hdd/fitna-backup/FItnaai/pyproject.toml"
ssh root@192.168.17.1 "ls -la /mnt/hdd/fitna-backup/.secrets/"
ssh root@192.168.17.1 "ls -la /mnt/hdd/fitna-backup/.ssh/"

# 4. Check manifest
ssh root@192.168.17.1 "cat /mnt/hdd/fitna-backup/BACKUP_MANIFEST.txt"

# 5. Test restore of one critical file
rsync root@192.168.17.1:/mnt/hdd/fitna-backup/FItnaai/pyproject.toml /tmp/restore-test-pyproject.toml
diff /mnt/omarchy/@home/fitna/FItnaai/pyproject.toml /tmp/restore-test-pyproject.toml
```

---

## Restore Procedure

### Full Restore

```bash
# On pve (192.168.16.2):
rsync -avz --progress \
    root@192.168.17.1:/mnt/hdd/fitna-backup/ \
    /mnt/omarchy/@home/fitna/
```

### Selective Restore (single project)

```bash
rsync -avz --progress \
    root@192.168.17.1:/mnt/hdd/fitna-backup/FItnaai/ \
    /mnt/omarchy/@home/fitna/FItnaai/
```

### Restore secrets only

```bash
rsync -avz \
    root@192.168.17.1:/mnt/hdd/fitna-backup/.secrets/ \
    /mnt/omarchy/@home/fitna/.secrets/

rsync -avz \
    root@192.168.17.1:/mnt/hdd/fitna-backup/.ssh/ \
    /mnt/omarchy/@home/fitna/.ssh/
```

---

## Automation (Optional)

### Systemd Timer for Daily Backup

Create `/etc/systemd/system/fitna-backup.service`:

```ini
[Unit]
Description=FitnaAI User Data Backup to pve-ryzen
After=network-online.target mnt-omarchy.mount
Requires=mnt-omarchy.mount

[Service]
Type=oneshot
ExecStart=/root/hub-mcp/proxmox/backup/backup-user-data.sh --skip-desktop
StandardOutput=journal
StandardError=journal
```

Create `/etc/systemd/system/fitna-backup.timer`:

```ini
[Unit]
Description=Daily FitnaAI backup at 03:00

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

Enable:

```bash
systemctl daemon-reload
systemctl enable --now fitna-backup.timer
systemctl list-timers | grep fitna
```

---

## Security Notes

1. **GitHub Token COMPROMISED**: `.git-credentials` contains an active token (`gho_Gp1z...`). Revoke at GitHub → Settings → Developer Settings → Personal Access Tokens **IMMEDIATELY**.

2. **Backup contains secrets**: `.secrets/`, `.ssh/`, `.gnupg/` are in the backup. Ensure:
   - 2TB HDD permissions: `chmod 700 /mnt/hdd/fitna-backup`
   - No shared access to the backup partition
   - Consider LUKS encryption for the 2TB HDD long-term

3. **Bash history**: `.bash_history` (109 KB) may contain sensitive commands. Review before sharing.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `Cannot SSH to root@192.168.17.1` | Run `ssh-copy-id root@192.168.17.1` from pve |
| `2TB HDD not found` | SSH to pve-ryzen, run `lsblk`, mount the HDD, set `BACKUP_HDD_MOUNT` |
| `Less than 50 GB free` | Clean up old data on 2TB HDD or add another disk |
| `Source not found` | Mount Omarchy SSD: `systemctl start mnt-omarchy.mount` |
| `rsync: connection unexpectedly closed` | Check network, increase SSH timeout, check disk space |
| `Permission denied` | Run as root on pve, check SSH key auth |
