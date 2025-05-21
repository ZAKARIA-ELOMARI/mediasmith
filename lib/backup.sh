#!/usr/bin/env bash
# lib/backup.sh - fonctions de sauvegarde des fichiers originaux avec horodatage

set -euo pipefail

# --- Chargement des dépendances ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# utils.sh fournit ensure_dir() et timestamp()
# logging.sh fournit log_info() et log_error()
source "$SCRIPT_DIR/utils.sh"
source "$SCRIPT_DIR/logging.sh"

# Variables exportées après init_backup :
#   BACKUP_TS        = horodatage (YYYYMMDD-HHMMSS)
#   BACKUP_DIR_TS    = chemin complet vers le dossier de backup horodaté

# init_backup <backup_root>
#   Initialise une nouvelle session de sauvegarde :
#   - crée <backup_root>/<timestamp>/
#   - définit BACKUP_TS et BACKUP_DIR_TS
init_backup() {
  local backup_root="$1"
  if [ -z "$backup_root" ]; then
    log_error "init_backup: répertoire de backup non spécifié"
    exit 1
  fi

  BACKUP_TS="$(timestamp)"
  BACKUP_DIR_TS="$backup_root/$BACKUP_TS"
  ensure_dir "$BACKUP_DIR_TS"
  log_info "Sauvegarde initialisée : $BACKUP_DIR_TS"
}

# backup_file <file_path> <source_root>
#   Copie <file_path> dans BACKUP_DIR_TS en reproduisant l'arborescence relative
backup_file() {
  local src="$1"
  local src_root="$2"
  if [ -z "${BACKUP_DIR_TS-}" ]; then
    log_error "backup_file: vous devez appeler init_backup avant"
    exit 1
  fi
  if [ ! -f "$src" ]; then
    log_error "backup_file: fichier introuvable : $src"
    return 1
  fi
  # chemin relatif
  local rel="${src#$src_root/}"
  local dst_dir="$BACKUP_DIR_TS/$(dirname "$rel")"
  ensure_dir "$dst_dir"
  cp -p "$src" "$dst_dir/"
  log_info "Sauvegardé : $src -> $dst_dir/"
}

# backup_directory <dir_path> <source_root>
#   Parcourt récursivement et sauvegarde tous les fichiers réguliers
backup_directory() {
  local dir="$1"
  local src_root="$2"
  if [ ! -d "$dir" ]; then
    log_error "backup_directory: répertoire introuvable : $dir"
    return 1
  fi
  while IFS= read -r -d '' file; do
    backup_file "$file" "$src_root"
  done < <(find "$dir" -type f -print0)
}

# Exemple d'utilisation :
#   init_backup "/path/to/backup"
#   backup_file "/path/to/source/file.mp4" "/path/to/source"
#   backup_directory "/path/to/source/subdir" "/path/to/source"
