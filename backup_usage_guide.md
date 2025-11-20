# Improved Backup Script Usage Guide

## New Features Added
- **Compression support** with parallel processing (pigz)
- **Incremental backups** option
- **Email reporting** for automated runs
- **Verification** of backup integrity
- **Configurable retention** period
- **Color-coded output** for better readability
- **System information** collection
- **Restore instructions** auto-generated

## Configuration Options

Set these before running or export as environment variables:

```bash
export RETENTION_DAYS=14          # Keep backups for 14 days
export COMPRESS_BACKUP=true       # Enable compression
export VERIFY_BACKUP=true         # Verify backup integrity
export MAX_PARALLEL=8             # Use 8 CPU threads for compression
export BACKUP_TYPE=incremental    # Or "full" for complete backup
export EMAIL_REPORT=admin@example.com  # Send report via email
```

## Usage Examples

### Basic Usage
```bash
# Interactive mode with defaults
sudo ./backup_improved.sh

# Direct backup to specific mount
sudo ./backup_improved.sh /Backup_Data
```

### Compressed Backup
```bash
# One-time compressed backup
sudo COMPRESS_BACKUP=true ./backup_improved.sh /Backup_Data

# Compressed with 8 threads
sudo COMPRESS_BACKUP=true MAX_PARALLEL=8 ./backup_improved.sh /mnt/backup
```

### Incremental Backup
```bash
# First run - full backup
sudo BACKUP_TYPE=full ./backup_improved.sh /Backup_Data

# Subsequent runs - incremental only
sudo BACKUP_TYPE=incremental ./backup_improved.sh /Backup_Data
```

### Automated Daily Backup (Crontab)
```bash
# Edit crontab
sudo crontab -e

# Daily compressed backup at 2 AM with 14-day retention
0 2 * * * COMPRESS_BACKUP=true RETENTION_DAYS=14 /path/to/backup_improved.sh /Backup_Data

# Weekly full backup on Sunday, daily incrementals
0 2 * * 0 BACKUP_TYPE=full /path/to/backup_improved.sh /Backup_Data
0 2 * * 1-6 BACKUP_TYPE=incremental /path/to/backup_improved.sh /Backup_Data
```

### Email Notifications
```bash
# Setup mail (if not configured)
sudo apt-get install mailutils

# Run with email report
sudo EMAIL_REPORT=admin@example.com ./backup_improved.sh /Backup_Data
```

## Quick Commands

```bash
# Make executable
chmod +x backup_improved.sh

# Check available space before backup
df -h /Backup_Data

# List recent backups
ls -lah /Backup_Data/backup-* | tail -5

# View latest log
tail -f /Backup_Data/logs/backup-log-*.log

# Manual cleanup (remove backups older than 30 days)
find /Backup_Data -name "backup-*" -mtime +30 -exec rm -rf {} \;

# Extract compressed backup
tar xzf /Backup_Data/backup-2025-11-07-143022.tar.gz -C /tmp/restore_test

# Test restore (dry run)
rsync -av --dry-run /Backup_Data/backup-2025-11-07-143022/system/ /
```

## Restoration Process

### Full System Restore
```bash
# From compressed backup
cd /
sudo tar xzf /Backup_Data/backup-2025-11-07-143022.tar.gz

# From uncompressed backup
sudo rsync -av /Backup_Data/backup-2025-11-07-143022/system/ /
```

### Selective Restore
```bash
# Restore specific directory
sudo rsync -av /Backup_Data/backup-*/system/etc/ /etc/

# Restore user home
sudo rsync -av /Backup_Data/backup-*/system/home/username/ /home/username/

# Restore packages
sudo dpkg --set-selections < /Backup_Data/backup-*/packages.txt
sudo apt-get dselect-upgrade
```

## Output Example
```
[2025-11-07 14:30:22] [INFO] =========================================
[2025-11-07 14:30:22] [INFO] Backup Script v2.0 Starting
[2025-11-07 14:30:22] [INFO] =========================================
[2025-11-07 14:30:22] [INFO] Backup type: full
[2025-11-07 14:30:22] [INFO] Compression: true
[2025-11-07 14:30:22] [INFO] Available space: 45GB
[2025-11-07 14:30:23] [INFO] Starting system backup...
         15.2G 100%   52.34MB/s    0:04:52
[2025-11-07 14:35:15] [SUCCESS] Backup completed successfully in 4 minutes!
[2025-11-07 14:35:16] [INFO] Compressing backup (using 4 threads)...
[2025-11-07 14:37:22] [SUCCESS] Backup compressed to 6.8G
[2025-11-07 14:37:23] [SUCCESS] Backup verification passed
[2025-11-07 14:37:23] [INFO] =========================================
[2025-11-07 14:37:23] [INFO] BACKUP SUMMARY
[2025-11-07 14:37:23] [INFO] Backup size: 6.8G
[2025-11-07 14:37:23] [INFO] Duration: 7 minutes 1 seconds
[2025-11-07 14:37:23] [INFO] Location: /Backup_Data/backup-2025-11-07-143022.tar.gz
```

## Performance Tips

1. **Use compression** for network drives or limited space
2. **Use incremental** for daily backups, full weekly
3. **Install pigz** for faster compression: `sudo apt-get install pigz`
4. **Exclude large unnecessary directories** by adding to rsync excludes
5. **Run during off-hours** to minimize system impact

## Troubleshooting

```bash
# Check if script has correct permissions
ls -l backup_improved.sh

# Test with small directory first
sudo BACKUP_TYPE=full ./backup_improved.sh /test_backup

# Check logs for errors
grep ERROR /Backup_Data/logs/backup-log-*.log

# Verify mount point is accessible
mountpoint /Backup_Data

# Check disk space
df -h /Backup_Data
```