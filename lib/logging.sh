#!/usr/bin/env bash
# lib/logging.sh - Module de journalisation pour convertisseur multimédia
# Fournit des fonctions standardisées pour la journalisation


# LOG_DIR=${LOG_DIR:-"/var/log/convertisseur_multimedia"}
# LOG_FILE="${LOG_DIR}/history.log"
# LOG_LEVEL=${LOG_LEVEL:-"INFO"}  # Niveaux: DEBUG, INFO, WARN, ERROR
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/config/config.cfg"
#######################################
# Récupérer un timestamp portable
#######################################
get_timestamp() {
  # Sur macOS et Linux, date supporte "+%Y-%m-%d %H:%M:%S"
  date "+%Y-%m-%d %H:%M:%S"
}

#######################################
# Initialise le système de journalisation
#######################################
init_logging() {
  local ts fallback_log="$PROJECT_ROOT/logs/history.log"

  # Créer le répertoire logs du projet si nécessaire
  if [ ! -d "$PROJECT_ROOT/logs" ]; then
    mkdir -p "$PROJECT_ROOT/logs" 2>/dev/null || {
      echo "Erreur : impossible de créer le répertoire logs du projet : $PROJECT_ROOT/logs"
      exit 1
    }
  fi

  # Créer LOG_DIR si nécessaire
  if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR" 2>/dev/null || {
      echo "Erreur : impossible de créer $LOG_DIR. Utilisation du fichier de secours : $fallback_log"
      LOG_FILE="$fallback_log"
    }
  fi

  # Vérifier les permissions d'écriture
  if [ ! -w "$LOG_DIR" ]; then
    echo "Avertissement : pas de permission d'écriture dans $LOG_DIR. Utilisation du fichier de secours : $fallback_log"
    LOG_FILE="$fallback_log"
  fi

  # Créer le fichier de log si nécessaire
  if [ ! -f "$LOG_FILE" ]; then
    # Ensure the directory exists for the log file
    local log_dir="$(dirname "$LOG_FILE")"
    if [ ! -d "$log_dir" ]; then
      mkdir -p "$log_dir" 2>/dev/null || {
        echo "Erreur : impossible de créer le répertoire pour le fichier de log : $log_dir"
        exit 1
      }
    fi
    
    touch "$LOG_FILE" 2>/dev/null || {
      echo "Erreur : impossible de créer le fichier $LOG_FILE"
      exit 1
    }
    ts=$(get_timestamp)
    echo "[SYSTEM] $ts — Initialisation du fichier de logs" >> "$LOG_FILE"
  fi

  # Journaliser le démarrage
  log_info "=== Démarrage nouvelle session ==="
}

#######################################
# Journalisation - niveau INFO
#######################################
log_info() {
  local ts
  local message
  ts=$(get_timestamp)
  message="[INFO] $ts — $*"
  echo "$message" >&2
  echo "$message" >> "$LOG_FILE"
}

#######################################
# Journalisation - niveau WARN
#######################################
log_warn() {
  local ts
  ts=$(get_timestamp)
  local message="[WARN] $ts — $*"
  echo "$message" >&2
  echo "$message" >> "$LOG_FILE"
}

#######################################
# Journalisation - niveau ERROR
#######################################
log_error() {
  local ts
  local message
  ts=$(get_timestamp)
  message="[ERROR] $ts — $*"
  echo "$message" >&2
  echo "$message" >> "$LOG_FILE"
}

#######################################
# Journalisation - niveau DEBUG
#######################################
log_debug() {
  # Ne rien faire si le niveau de log est supérieur à DEBUG
  [[ "$LOG_LEVEL" != "DEBUG" ]] && return 0
  
  local ts
  ts=$(get_timestamp)
  local message="[DEBUG] $ts — $*"
  echo "$message" >&2
  echo "$message" >> "$LOG_FILE"
}

#######################################
# Fonction pour purger les anciens logs
#######################################
purge_old_logs() {
  local days=${1:-30}
  
  if [ -d "$LOG_DIR" ]; then
    log_info "Purge des logs plus anciens que $days jours"
    find "$LOG_DIR" -name "*.log" -type f -mtime +$days -delete
  fi
}

# Export des fonctions
export -f get_timestamp
export -f log_info
export -f log_warn
export -f log_error
export -f log_debug