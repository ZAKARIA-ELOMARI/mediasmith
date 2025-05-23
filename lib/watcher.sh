#!/usr/bin/env bash
# watcher.sh - Surveillance des répertoires

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
source "$PROJECT_ROOT/lib/backup.sh"
source "$PROJECT_ROOT/lib/conversion.sh"

init_logging > /dev/null 2>&1

WATCH_INTERVAL=10
TEMP_DIR="/tmp"
PENDING_FLAG="$TEMP_DIR/file_watcher_pending_$$"
TIMESTAMP_FILE="$TEMP_DIR/file_watcher_timestamp_$$"
DELETED_FILES="$TEMP_DIR/file_watcher_deleted_$$"

log_info "Watching $WATCH_DIR for new files..."

cleanup() {
    log_info "Cleaning up..."
    rm -f "$PENDING_FLAG" "$TIMESTAMP_FILE" "$DELETED_FILES"
    kill $IDLE_CHECK_PID 2>/dev/null
    exit
}
trap cleanup INT TERM

# Function to remove file from backup queue
remove_from_backup_queue() {
    local file_to_remove="$1"
    local filename=$(basename "$file_to_remove")
    
    if [[ -f "$TO_BACKUP" ]]; then
        # Create temp file without the deleted file
        local temp_backup="$TO_BACKUP.tmp.$$"
        grep -v "^$(printf '%s\n' "$file_to_remove" | sed 's/[[\.*^$()+?{|]/\\&/g')$" "$TO_BACKUP" > "$temp_backup" 2>/dev/null || true
        mv "$temp_backup" "$TO_BACKUP"
        log_info "Removed $filename from backup queue"
    fi
}

process_changes() {
    log_info "Start processing changes..."
    
    # Process deleted files first
    if [[ -f "$DELETED_FILES" ]]; then
        while IFS= read -r deleted_file; do
            if [[ -n "$deleted_file" ]]; then
                log_info "Processing deletion: $(basename "$deleted_file")"
                remove_from_backup_queue "$deleted_file"
            fi
        done < "$DELETED_FILES"
        > "$DELETED_FILES"  # Clear the deleted files list
    fi
    
    # Process new/modified files
    find "$WATCH_DIR" -type f | while read -r file; do
        filename=$(basename "$file")

        # Check if file has already been converted
        if ! grep -Fxq "$filename" "$CONVERTED_FILES_LOG"; then
            log_info "Converting $filename..."
            convert_main "$file"
            echo "$filename" >> "$CONVERTED_FILES_LOG"

            # Queue file for backup
            echo "$file" >> "$TO_BACKUP"
        else
            log_debug "Already converted: $filename"
        fi
    done

    # Delegate backup work to backup_process
    backup_process

    log_info "End processing changes."
}

process_when_idle() {
    while true; do
        sleep 1
        if [[ -f "$PENDING_FLAG" && -f "$TIMESTAMP_FILE" ]]; then
            last_event_time=$(<"$TIMESTAMP_FILE")
            now=$(date +%s)
            diff=$(( now - last_event_time ))
            log_debug "Idle check: ${diff}s since last event"

            if (( diff >= WATCH_INTERVAL )); then
                log_info "Idle threshold reached — processing..."
                process_changes
                rm -f "$PENDING_FLAG"
                log_debug "Cleared pending flag"
            fi
        fi
    done
}

# Function to handle file events
handle_file_event() {
    local file="$1"
    local event="$2"
    
    case "$event" in
        *DELETE*|*MOVED_FROM*)
            log_info "File deleted/moved: $(basename "$file")"
            echo "$file" >> "$DELETED_FILES"
            ;;
        *CREATE*|*MODIFY*|*MOVED_TO*)
            log_info "File created/modified/moved in: $(basename "$file")"
            ;;
    esac
    
    # Update timestamp and set pending flag for any event
    date +%s > "$TIMESTAMP_FILE"
    touch "$PENDING_FLAG"
    log_debug "Set pending flag/timestamp"
}

# launch the idle watcher
process_when_idle &
IDLE_CHECK_PID=$!
log_debug "Idle watcher PID: $IDLE_CHECK_PID"

# monitor filesystem
if command -v inotifywait >/dev/null 2>&1; then
    log_info "Using inotifywait"
    inotifywait -m -r -e create,move,modify,delete "$WATCH_DIR" --format '%w%f %e' |
    while read -r file event; do
        log_info "FS event: $event on $file"
        handle_file_event "$file" "$event"
    done
else
    log_info "Using fswatch"
    while IFS= read -r -d "" event; do
        # Extract filename from fswatch event
        file="$event"
        log_info "FS event: $file"
        
        # Check if file still exists to determine if it was deleted
        if [[ ! -e "$file" ]]; then
            handle_file_event "$file" "DELETE"
        else
            handle_file_event "$file" "MODIFY"
        fi
    done < <(fswatch -0 -r "$WATCH_DIR")
fi