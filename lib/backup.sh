#!/usr/bin/env bash
# backup.sh - script de sauvegarde de fichiers

set -euo pipefail

# Chargement du module de journalisation
source "$PROJECT_ROOT/lib/logging.sh"
source "$PROJECT_ROOT/lib/utils.sh"

# initialiser la journalisation si ce n'est pas déjà fait
if [[ -z "${LOGGING_INITIALIZED:-}" ]]; then
    init_logging > /dev/null 2>&1
    export LOGGING_INITIALIZED=1
fi

ensure_dir "$BACKUP_DIR"
touch "$TO_BACKUP"
touch "$BACKED_UP"

# === PROCESSUS DE SAUVEGARDE ===
backup_process() {
    TODAY_DIR="$BACKUP_DIR/$(date +%F)"
    ensure_dir "$TODAY_DIR"
    TIMESTAMP=$(date +"%Y-%m-%d_%H:%M:%S")
    while IFS= read -r FILE; do
        [ ! -f "$FILE" ] && continue
        if grep -Fxq "$FILE" "$BACKED_UP"; then
            log_info "Déjà sauvegardé, ignorer: $FILE"
            continue
        fi

        TYPE=$(get_type "$FILE")
        
        if [ "$TYPE" = "unknown" ]; then
            log_info "Type de fichier inconnu: $FILE"
            continue
        fi

        ensure_dir "$TODAY_DIR/$TYPE"
        cp "$FILE" "$TODAY_DIR/$TYPE" && log_info "Sauvegardé $FILE vers $TODAY_DIR/$TYPE"

        if command -v rclone &> /dev/null && [ -e "$FILE" ]; then
            log_info "Sauvegarde: $FILE → ${REMOTE_DIR}/$TODAY/$TIMESTAMP/$TYPE/"
            rclone copy "$FILE" "${REMOTE_DIR}/$TODAY/$TIMESTAMP/$TYPE/" && log_info "Sauvegardé"
        else
            log_info "Le fichier n'existe plus: $FILE"
        fi


        echo "$FILE" >> "$BACKED_UP"
    done < "$TO_BACKUP"
    > "$TO_BACKUP"
}

backup_process