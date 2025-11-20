#!/bin/bash
# Streamlined Backup Script v3.0 - No manifest, better progress
# Exit on error



# Function to send email report
send_email_report() {
    local email_address="$1"
    local log_file="$2"
    local backup_file="$3"
    local exit_code="$4"
    
    if [ -n "$email_address" ]; then
        # Determine if backup was successful
        # Rsync exit codes 0=success, 23=partial, 24=partial - both are acceptable
        if [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 23 ] || [ "$exit_code" -eq 24 ]; then
            local status="SUCCESS"
            local color="$GREEN"
        else
            local status="FAILED"
            local color="$RED"
        fi
        
        local subject="Backup $status - $(hostname) - $(date '+%Y-%m-%d %H:%M:%S')"
        local body="Backup $status on $(date)\n"
        body+="Exit code: $exit_code\n"
        body+="Backup file: $backup_file\n"
        body+="Log file: $log_file\n\n"
        body+="=== LAST 20 LINES OF LOG ===\n"
        body+="$(tail -20 "$log_file" 2>/dev/null || echo 'Log file not available')\n"
        
        echo -e "$body" | mail -s "$subject" "$email_address"
        
        if [ $? -eq 0 ]; then
            log_message "INFO" "Email report sent to $email_address - Status: $status"
        else
            log_message "ERROR" "Failed to send email to $email_address"
        fi
    fi
}


set -e

# Configuration (can be overridden by environment variables)
RETENTION_DAYS=${RETENTION_DAYS:-7}           # Keep backups for 7 days by default
COMPRESS_BACKUP=${COMPRESS_BACKUP:-true}     # Compress by default
VERIFY_BACKUP=${VERIFY_BACKUP:-true}         # Verify backup integrity
MAX_PARALLEL=${MAX_PARALLEL:-4}              # Parallel compression threads
BACKUP_TYPE=${BACKUP_TYPE:-"full"}           # full or incremental
EMAIL_REPORT=${EMAIL_REPORT:-""}             # Email address for reports

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to display colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to display available mount points
show_mount_points() {
    print_message "$GREEN" "\nAvailable mount points:"
    print_message "$GREEN" "======================"
    df -h | grep -E '^/dev/' | awk '{print NR". "$1" - "$6" ("$4" free)"}'
    echo ""
}

# Check if mount point was provided as argument
if [ -n "$1" ]; then
    MOUNT_POINT="$1"
else
    # Show available mount points
    show_mount_points
    
    # Prompt user to select
    echo "Enter mount point path (e.g., /Backup_Data or /mnt/vps_backup):"
    read -p "Mount point: " MOUNT_POINT
    
    # If empty, try default /dev/sdb1
    if [ -z "$MOUNT_POINT" ]; then
        MOUNT_POINT=$(findmnt -n -o TARGET /dev/sdb1 2>/dev/null)
        if [ -z "$MOUNT_POINT" ]; then
            print_message "$RED" "ERROR: No mount point specified and /dev/sdb1 is not mounted"
            exit 1
        fi
        print_message "$YELLOW" "Using default: $MOUNT_POINT"
    fi
fi

# Verify mount point exists and is mounted
if [ ! -d "$MOUNT_POINT" ]; then
    print_message "$RED" "ERROR: Mount point $MOUNT_POINT does not exist"
    exit 1
fi

if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    print_message "$YELLOW" "WARNING: $MOUNT_POINT may not be a mount point"
    read -p "Continue anyway? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        exit 1
    fi
fi

# Set up backup directories and files
BACKUP_DATE=$(date +%Y-%m-%d)
BACKUP_TIME=$(date +%H%M%S)
BACKUP_DIR="$MOUNT_POINT/backup-$BACKUP_DATE-$BACKUP_TIME"
LOG_DIR="$MOUNT_POINT/logs"
LOG_FILE="$LOG_DIR/backup-log-$BACKUP_DATE-$BACKUP_TIME.log"
INCREMENTAL_MARKER="$MOUNT_POINT/.last_backup_marker"

# Create log directory
mkdir -p "$LOG_DIR"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_message "$RED" "ERROR: Run as root: sudo $0"
   exit 1
fi

# Function to log messages
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Start backup process
log_message "INFO" "========================================="
log_message "INFO" "Streamlined Backup Script v3.0 Starting"
log_message "INFO" "========================================="
log_message "INFO" "Backup type: $BACKUP_TYPE"
log_message "INFO" "Compression: $COMPRESS_BACKUP"
log_message "INFO" "Retention: $RETENTION_DAYS days"

# Check available disk space
log_message "INFO" "Checking disk space..."
AVAILABLE_SPACE=$(df -BG "$MOUNT_POINT" | awk 'NR==2 {print $4}' | sed 's/G//')
REQUIRED_SPACE=$(du -s --block-size=G / --exclude={/proc,/sys,/dev,/tmp,/run,/mnt,/media,/lost+found,"$MOUNT_POINT"} 2>/dev/null | awk '{print $1}' | sed 's/G//')

log_message "INFO" "Available space: ${AVAILABLE_SPACE}GB"
log_message "INFO" "Estimated required space: ${REQUIRED_SPACE}GB"

# Add compression factor if enabled
if [ "$COMPRESS_BACKUP" = true ]; then
    REQUIRED_SPACE=$((REQUIRED_SPACE / 2))  # Assume 50% compression ratio
    log_message "INFO" "Adjusted for compression: ${REQUIRED_SPACE}GB"
fi

if [ "$AVAILABLE_SPACE" -lt "$((REQUIRED_SPACE + 10))" ]; then
    log_message "WARNING" "Low disk space! Consider cleaning old backups first."
    
    # Offer to clean old backups
    read -p "Clean backups older than $RETENTION_DAYS days? (yes/no): " clean_now
    if [ "$clean_now" = "yes" ]; then
        find "$MOUNT_POINT" -maxdepth 1 -name "backup-*" -type d -mtime +$RETENTION_DAYS -exec rm -rf {} \; 2>/dev/null || true
        log_message "INFO" "Old backups cleaned"
    fi
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"
log_message "INFO" "Backup directory: $BACKUP_DIR"

# Backup system information
log_message "INFO" "Collecting system information..."
{
    echo "Backup Date: $BACKUP_DATE $BACKUP_TIME"
    echo "Hostname: $(hostname)"
    echo "Kernel: $(uname -r)"
    echo "OS: $(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo "Uptime: $(uptime)"
    echo "Disk Usage:"
    df -h
} > "$BACKUP_DIR/system_info.txt"

# Backup package list
log_message "INFO" "Backing up package list..."
dpkg --get-selections > "$BACKUP_DIR/packages.txt"
apt list --installed > "$BACKUP_DIR/apt_packages.txt" 2>/dev/null || true
snap list > "$BACKUP_DIR/snap_packages.txt" 2>/dev/null || true

# Backup repository sources
log_message "INFO" "Backing up repository sources..."
cp -r /etc/apt/sources.list* "$BACKUP_DIR/" 2>/dev/null || true

# Backup important config files
log_message "INFO" "Backing up configuration files..."
mkdir -p "$BACKUP_DIR/configs"
for config in /etc/fstab /etc/hosts /etc/hostname /etc/network/interfaces /etc/crontab; do
    if [ -f "$config" ]; then
        cp "$config" "$BACKUP_DIR/configs/" 2>/dev/null || true
    fi
done

# Determine rsync options based on backup type
RSYNC_OPTS="-a --partial --info=progress2 --human-readable"
if [ "$BACKUP_TYPE" = "incremental" ] && [ -f "$INCREMENTAL_MARKER" ]; then
    RSYNC_OPTS="$RSYNC_OPTS --newer-than=$(cat $INCREMENTAL_MARKER)"
    log_message "INFO" "Performing incremental backup since $(cat $INCREMENTAL_MARKER)"
fi

# System backup
log_message "INFO" "Starting system backup (this may take a while)..."
START_TIME=$(date +%s)

# RSYNC WITH PROGRESS
rsync $RSYNC_OPTS \
    --exclude=/proc \
    --exclude=/sys \
    --exclude=/dev \
    --exclude=/tmp \
    --exclude=/run \
    --exclude=/mnt \
    --exclude=/media \
    --exclude=/lost+found \
    --exclude='*.cache' \
    --exclude='*.tmp' \
    --exclude='*.log' \
    --exclude='/var/log/*' \
    --exclude='/var/cache/*' \
    --exclude='/var/tmp/*' \
    --exclude=/swapfile \
    --exclude=/swap.img \
    --exclude="$MOUNT_POINT" \
    --exclude='/home/*/.cache' \
    --exclude='/home/*/.local/share/Trash' \
    --no-specials \
    --no-devices \
    --ignore-errors \
    / "$BACKUP_DIR/system/" 2>&1 | tee -a "$LOG_FILE"

RSYNC_EXIT=${PIPESTATUS[0]}
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Log rsync result
if [ $RSYNC_EXIT -eq 0 ]; then
    log_message "SUCCESS" "Backup completed successfully in $((DURATION/60)) minutes!"
elif [ $RSYNC_EXIT -eq 23 ] || [ $RSYNC_EXIT -eq 24 ]; then
    log_message "WARNING" "Backup completed with minor errors (exit code: $RSYNC_EXIT)"
else
    log_message "ERROR" "Backup failed with exit code $RSYNC_EXIT"
fi

# Calculate backup statistics
BACKUP_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
FILE_COUNT=$(find "$BACKUP_DIR" -type f | wc -l)

log_message "INFO" "Backup statistics: $BACKUP_SIZE, $FILE_COUNT files"

# Verification (quick check)
if [ "$VERIFY_BACKUP" = true ]; then
    log_message "INFO" "Performing quick verification..."
    VERIFY_ERRORS=0
    
    # Quick check of critical files
    for check_file in etc/hostname etc/passwd etc/fstab; do
        if [ ! -f "$BACKUP_DIR/system/$check_file" ] && [ -f "/$check_file" ]; then
            log_message "ERROR" "Verification failed: Missing $check_file"
            ((VERIFY_ERRORS++))
        fi
    done
    
    if [ $VERIFY_ERRORS -eq 0 ]; then
        log_message "SUCCESS" "Backup verification passed"
    else
        log_message "WARNING" "Backup verification found $VERIFY_ERRORS issues"
    fi
fi

# Compression with progress
if [ "$COMPRESS_BACKUP" = true ]; then
    log_message "INFO" "Starting compression with $MAX_PARALLEL threads..."
    COMPRESS_START=$(date +%s)
    
    if command -v pigz >/dev/null 2>&1; then
        # Use pigz for parallel compression with progress
        log_message "INFO" "Using pigz for parallel compression..."
        tar -cf - -C "$(dirname $BACKUP_DIR)" "$(basename $BACKUP_DIR)" | \
        pigz -p $MAX_PARALLEL | \
        pv -s $(du -sb "$BACKUP_DIR" | cut -f1) > "$BACKUP_DIR.tar.gz"
    else
        # Fallback to standard tar with verbose output
        log_message "INFO" "Using tar with verbose output..."
        tar czvf "$BACKUP_DIR.tar.gz" -C "$(dirname $BACKUP_DIR)" "$(basename $BACKUP_DIR)" 2>&1 | tee -a "$LOG_FILE"
    fi
    
    if [ $? -eq 0 ]; then
        COMPRESSED_SIZE=$(du -sh "$BACKUP_DIR.tar.gz" | cut -f1)
        COMPRESSION_RATIO=$(echo "scale=2; $(du -s "$BACKUP_DIR.tar.gz" | cut -f1) * 100 / $(du -s "$BACKUP_DIR" | cut -f1)" | bc)
        rm -rf "$BACKUP_DIR"
        log_message "SUCCESS" "Backup compressed to $COMPRESSED_SIZE (${COMPRESSION_RATIO}% of original)"
        BACKUP_FILE="$BACKUP_DIR.tar.gz"
    else
        log_message "ERROR" "Compression failed, keeping uncompressed backup"
        BACKUP_FILE="$BACKUP_DIR"
    fi
    
    COMPRESS_END=$(date +%s)
    log_message "INFO" "Compression took $((($COMPRESS_END - $COMPRESS_START)/60)) minutes"
else
    BACKUP_FILE="$BACKUP_DIR"
fi

# Update incremental marker
echo "$BACKUP_DATE $BACKUP_TIME" > "$INCREMENTAL_MARKER"

# Cleanup old backups
log_message "INFO" "Cleaning up old backups (older than $RETENTION_DAYS days)..."
find "$MOUNT_POINT" -maxdepth 1 \( -name "backup-*.tar.gz" -o -name "backup-*" -type d \) -mtime +$RETENTION_DAYS -delete 2>/dev/null || true

# Cleanup old logs (older than 30 days)
find "$LOG_DIR" -name "backup-log-*.log" -type f -mtime +30 -delete 2>/dev/null || true

# Show final disk space
log_message "INFO" "Final disk usage:"
df -h "$MOUNT_POINT" | tee -a "$LOG_FILE"

# Create simple restore instructions
cat > "$MOUNT_POINT/RESTORE_INSTRUCTIONS.txt" << EOF
RESTORE INSTRUCTIONS
===================
Generated: $BACKUP_DATE $BACKUP_TIME

To restore from this backup:

1. Full System Restore:
   # Extract backup (if compressed)
   tar xzf $BACKUP_FILE -C /
   
   # Or use rsync for uncompressed
   rsync -av $BACKUP_FILE/system/ /

2. Restore Package List:
   dpkg --set-selections < $BACKUP_FILE/packages.txt
   apt-get dselect-upgrade

LATEST BACKUP: $BACKUP_FILE
EOF

log_message "SUCCESS" "========================================="
log_message "SUCCESS" "Backup process completed successfully!"
log_message "SUCCESS" "Final backup: $BACKUP_FILE"
log_message "SUCCESS" "Total duration: $((DURATION/60)) minutes"
log_message "SUCCESS" "Log file: $LOG_FILE"
log_message "SUCCESS" "========================================="



# Send email report if email address is configured
send_email_report "$EMAIL_REPORT" "$LOG_FILE" "$BACKUP_FILE" "$RSYNC_EXIT"




# Exit with appropriate code
exit $RSYNC_EXIT
