#!/usr/bin/env bash
# watcher.sh - Surveillance des répertoires

set -euo pipefail

#######################################
# Usage and defaults
#######################################
WATCH_DIR=""
DAEMON=false

print_usage() {
    echo "Usage: $0 [--watch-dir DIR] [--daemon]"
    exit 1
}

#######################################
# Détermine le chemin du script et du projet
#######################################

source "$PROJECT_ROOT/lib/logging.sh"
source "$PROJECT_ROOT/lib/utils.sh"
source "$PROJECT_ROOT/lib/backup.sh"
source "$PROJECT_ROOT/lib/conversion.sh"

# Respect config file unless overridden by CLI
WATCH_DIR="${WATCH_DIR:-}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --watch-dir|-w)
            [[ -z "${2:-}" ]] && print_usage
            WATCH_DIR="$2"
            shift 2
            ;;
        --daemon|-d)
            DAEMON=true
            shift
            ;;
        --help|-h)
            print_usage
            ;;
        *)
            print_usage
            ;;
    esac
done

# If running as daemon, relaunch in background
if $DAEMON; then
    ARGS=()
    [[ -n "$WATCH_DIR" ]] && ARGS+=(--watch-dir "$WATCH_DIR")
    nohup "$0" "${ARGS[@]}" > nohup.out 2>&1 &
    echo "Watcher running in daemon mode (PID $!)"
    exit 0
fi

init_logging > /dev/null 2>&1

# Ensure WATCH_DIR is set
if [[ -z "$WATCH_DIR" ]]; then
    log_error "No watch directory specified. Use --watch-dir DIR or define WATCH_DIR in config.cfg."
    exit 1
fi

log_info "Watching $WATCH_DIR for new files..."

WATCH_INTERVAL=10
TEMP_DIR="/tmp"
PENDING_FLAG="$TEMP_DIR/file_watcher_pending_$$"
TIMESTAMP_FILE="$TEMP_DIR/file_watcher_timestamp_$$"
DELETED_FILES="$TEMP_DIR/file_watcher_deleted_$$"

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
        local temp_backup="$TO_BACKUP.tmp.$$"
        grep -v "^$(printf '%s\n' "$file_to_remove" | sed 's/[[\.*^$()+?|]/\\&/g')$" "$TO_BACKUP" > "$temp_backup" 2>/dev/null || true
        mv "$temp_backup" "$TO_BACKUP"
        log_info "Removed $filename from backup queue"
    fi
}

process_changes() {
    log_info "Start processing changes..."
    if [[ -f "$DELETED_FILES" ]]; then
        while IFS= read -r deleted_file; do
            if [[ -n "$deleted_file" ]]; then
                log_info "Processing deletion: $(basename "$deleted_file")"
                remove_from_backup_queue "$deleted_file"
            fi
        done < "$DELETED_FILES"
        > "$DELETED_FILES"
    fi

    find "$WATCH_DIR" -type f | while read -r file; do
        filename=$(basename "$file")
        if ! grep -Fxq "$filename" "$CONVERTED_FILES_LOG"; then
            log_info "Converting $filename..."
            convert_main "$file"
            echo "$filename" >> "$CONVERTED_FILES_LOG"
            echo "$file" >> "$TO_BACKUP"
        else
            log_info "Already converted, skipping: $filename"
        fi
    done

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

handle_file_event() {
    local file="$1" event="$2"
    case "$event" in
        *DELETE*|*MOVED_FROM*)
            log_info "File deleted/moved: $(basename "$file")"
            echo "$file" >> "$DELETED_FILES"
            ;;
        *CREATE*|*MODIFY*|*MOVED_TO*)
            log_info "File created/modified/moved in: $(basename "$file")"
            ;;
    esac
    date +%s > "$TIMESTAMP_FILE"
    touch "$PENDING_FLAG"
    log_debug "Set pending flag/timestamp"
}

# Start idle watcher
process_when_idle &
IDLE_CHECK_PID=$!
log_debug "Idle watcher PID: $IDLE_CHECK_PID"

# Monitor filesystem
if command -v inotifywait >/dev/null 2>&1; then
    log_info "Using inotifywait"
    inotifywait -m -r -e create,move,modify,delete "$WATCH_DIR" --format '%w%f %e' |
    while read -r file event; do
        log_debug "FS event: $event on $file"
        handle_file_event "$file" "$event"
    done
else
    log_info "Using fswatch"
    fswatch -0 -r "$WATCH_DIR" | while IFS= read -r -d "" file; do
        if [[ ! -e "$file" ]]; then
            log_debug "FS event: DELETE on $file"
            handle_file_event "$file" "DELETE"
        else
            log_debug "FS event: MODIFY on $file"
            handle_file_event "$file" "MODIFY"
        fi
    done
fi
