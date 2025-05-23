#!/usr/bin/env bash

set -euo pipefail

#######################################
# Détermine le chemin du script et du projet
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Chargement du module de journalisation et config
source "$PROJECT_ROOT/config/config.cfg"
source "$PROJECT_ROOT/lib/logging.sh"
source "$PROJECT_ROOT/lib/utils.sh"

init_logging > /dev/null 2>&1

ensure_dir "$BACKUP_DIR"
touch "$TO_BACKUP"
touch "$BACKED_UP"

# === BACKUP PROCESS ===
backup_process() {
    TODAY_DIR="$BACKUP_DIR/$(date +%F)"
    ensure_dir "$TODAY_DIR"
    while IFS= read -r FILE; do
        [ ! -f "$FILE" ] && continue  # skip if file no longer exists

        # Skip if already backed up
        if grep -Fxq "$FILE" "$BACKED_UP"; then
            continue
        fi

        TYPE=$(get_type "$FILE")

        if [ "$TYPE" = "unknown" ]; then
            log_info "Unknown file type: $FILE"
            continue
        fi

        BASENAME=$(basename "$FILE")
        ensure_dir "$TODAY_DIR/$TYPE"
        cp "$FILE" "$TODAY_DIR/$TYPE"
        log_info "Backed up $FILE to $TODAY_DIR/$TYPE"

        echo "$FILE" >> "$BACKED_UP"
    done < "$TO_BACKUP"
    TIMESTAMP=$(date +%T)
    if command -v rclone &> /dev/null; then
        log_info "Backing up $BACKUP_DIR to remote $REMOTE_DIR/"
        rclone mkdir "$REMOTE_DIR/$TODAY"
        rclone copy "$BACKUP_DIR"/*/ "$REMOTE_DIR/$TODAY/$TIMESTAMP"
        log_info "Backed up $BACKUP_DIR to remote $REMOTE_DIR/"
    fi
    > "$TO_BACKUP"
}

backup_process