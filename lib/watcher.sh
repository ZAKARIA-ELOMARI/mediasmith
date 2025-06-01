#!/usr/bin/env bash
# watcher.sh - script de surveillance de fichiers

set -euo pipefail

#######################################
# Utilisation et valeurs par défaut
#######################################
WATCH_DIR=""
DAEMON=false

print_usage() {
    echo "Utilisation: $0 [--watch-dir DIR] [--daemon]"
    exit 1
}

#######################################
# Détermine le chemin du script et du projet
#######################################


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/config/config.cfg"
source "$PROJECT_ROOT/lib/logging.sh"
source "$PROJECT_ROOT/lib/utils.sh"
source "$PROJECT_ROOT/lib/backup.sh"
source "$PROJECT_ROOT/lib/conversion.sh"

WATCH_DIR="${WATCH_DIR:-}"

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

# si il y a un argument --daemon, relance le script en arrière-plan
if $DAEMON; then
    ARGS=()
    [[ -n "$WATCH_DIR" ]] && ARGS+=(--watch-dir "$WATCH_DIR")
    nohup "$0" "${ARGS[@]}" > nohup.out 2>&1 &
    echo "Surveillant en cours d'exécution en mode démon (PID $!)"
    exit 0
fi

init_logging > /dev/null 2>&1
export LOGGING_INITIALIZED=1

# s'assure que WATCH_DIR est défini
if [[ -z "$WATCH_DIR" ]]; then
    log_error "Aucun répertoire de surveillance spécifié. Utilisez --watch-dir DIR ou définissez WATCH_DIR dans config.cfg."
    exit 1
fi

log_info "Surveillance de $WATCH_DIR pour les nouveaux fichiers..."

WATCH_INTERVAL=10
TEMP_DIR="/tmp"
PENDING_FLAG="$TEMP_DIR/file_watcher_pending_$$"
TIMESTAMP_FILE="$TEMP_DIR/file_watcher_timestamp_$$"
DELETED_FILES="$TEMP_DIR/file_watcher_deleted_$$"

cleanup() {
    log_info "Nettoyage..."
    rm -f "$PENDING_FLAG" "$TIMESTAMP_FILE" "$DELETED_FILES"
    kill $IDLE_CHECK_PID 2>/dev/null
    exit
}
trap cleanup INT TERM

remove_from_backup_queue() {
    local file_to_remove="$1"
    local filename=$(basename "$file_to_remove")
    if [[ -f "$TO_BACKUP" ]]; then
        local temp_backup="$TO_BACKUP.tmp.$$"
        grep -v "^$(printf '%s\n' "$file_to_remove" | sed 's/[[\.*^$()+?|]/\\&/g')$" "$TO_BACKUP" > "$temp_backup" 2>/dev/null || true
        mv "$temp_backup" "$TO_BACKUP"
        log_info "Supprimé $filename de la file de sauvegarde"
    fi
}

process_changes() {
    log_info "Début du traitement des changements..."
    if [[ -f "$DELETED_FILES" ]]; then
        while IFS= read -r deleted_file; do
            if [[ -n "$deleted_file" ]]; then
                log_info "Traitement de la suppression: $(basename "$deleted_file")"
                remove_from_backup_queue "$deleted_file"
            fi
        done < "$DELETED_FILES"
        > "$DELETED_FILES"
    fi

    find "$WATCH_DIR" -type f | while read -r file; do
        filename=$(basename "$file")
        if ! grep -Fxq "$filename" "$CONVERTED_FILES_LOG"; then
            log_info "Conversion de $filename..."
            convert_main "$file"
            echo "$filename" >> "$CONVERTED_FILES_LOG"
            echo "$file" >> "$TO_BACKUP"
        else
            log_info "Déjà converti, ignoré: $filename"
        fi
    done

    backup_process
    log_info "Fin du traitement des changements."
}

process_when_idle() {
    while true; do
        sleep 1
        if [[ -f "$PENDING_FLAG" && -f "$TIMESTAMP_FILE" ]]; then
            last_event_time=$(<"$TIMESTAMP_FILE")
            now=$(date +%s)
            diff=$(( now - last_event_time ))
            log_debug "Vérification d'inactivité: ${diff}s depuis le dernier événement"
            if (( diff >= WATCH_INTERVAL )); then
                log_info "Seuil d'inactivité atteint — traitement..."
                process_changes
                rm -f "$PENDING_FLAG"
                log_debug "Drapeau en attente effacé"
            fi
        fi
    done
}

handle_file_event() {
    local file="$1" event="$2"
    case "$event" in
        *DELETE*|*MOVED_FROM*)
            log_info "Fichier supprimé/déplacé: $(basename "$file")"
            echo "$file" >> "$DELETED_FILES"
            ;;
        *CREATE*|*MODIFY*|*MOVED_TO*)
            log_info "Fichier créé/modifié/déplacé dans: $(basename "$file")"
            ;;
    esac
    date +%s > "$TIMESTAMP_FILE"
    touch "$PENDING_FLAG"
    log_debug "Drapeau en attente/horodatage défini"
}

# commence le processus de surveillance
process_when_idle &
IDLE_CHECK_PID=$!
log_debug "PID du surveillant d'inactivité: $IDLE_CHECK_PID"

# monitorer les événements de fichiers
if command -v inotifywait >/dev/null 2>&1; then
    log_info "Utilisation d'inotifywait"
    inotifywait -m -r -e create,move,modify,delete "$WATCH_DIR" --format '%w%f %e' |
    while read -r file event; do
        log_debug "Événement SF: $event sur $file"
        handle_file_event "$file" "$event"
    done
else
    log_info "Utilisation de fswatch"
    fswatch -0 -r "$WATCH_DIR" | while IFS= read -r -d "" file; do
        if [[ ! -e "$file" ]]; then
            log_debug "Événement SF: DELETE sur $file"
            handle_file_event "$file" "DELETE"
        else
            log_debug "Événement SF: MODIFY sur $file"
            handle_file_event "$file" "MODIFY"
        fi
    done
fi
