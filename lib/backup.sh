#!/usr/bin/env bash

set -euo pipefail

# Chargement du module de journalisation
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
    TIMESTAMP=$(date +"%Y-%m-%d_%H:%M:%S")
    while IFS= read -r FILE; do
        [ ! -f "$FILE" ] && continue  # skip if file no longer exists

        # Skip if already backed up
        if grep -Fxq "$FILE" "$BACKED_UP"; then
            log_info "Already backed up, skipping: $FILE"
            continue
        fi

        TYPE=$(get_type "$FILE")
        
        if [ "$TYPE" = "unknown" ]; then
            log_info "Unknown file type: $FILE"
            continue
        fi

        ensure_dir "$TODAY_DIR/$TYPE"
        cp "$FILE" "$TODAY_DIR/$TYPE" && log_info "Backed up $FILE to $TODAY_DIR/$TYPE"

        if command -v rclone &> /dev/null && [ -e "$FILE" ]; then
            log_info "Backing up: $FILE → ${REMOTE_DIR}/$TODAY/$TIMESTAMP/$TYPE/"
            rclone copy "$FILE" "${REMOTE_DIR}/$TODAY/$TIMESTAMP/$TYPE/" && log_info "Backed up"
        else
            log_info "File no longer exists: $FILE"
        fi


        echo "$FILE" >> "$BACKED_UP"
    done < "$TO_BACKUP"
    > "$TO_BACKUP"
}

backup_process