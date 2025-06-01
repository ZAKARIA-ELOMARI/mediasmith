#!/usr/bin/env bash
# logging.sh - Fournit des fonctions standardisées pour la journalisation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/config/config.cfg"

#######################################
# Récupérer un timestamp au format yyyy-mm-dd-hh-mm-ss
#######################################
get_timestamp() {
  date "+%Y-%m-%d-%H-%M-%S"
}

#######################################
# Initialise le système de journalisation
#######################################
init_logging() {
  local ts fallback_log="$PROJECT_ROOT/logs/history.log"

  # Créer le répertoire logs du projet s'il n'existe pas
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
  fi
  
  log_info "=== Démarrage nouvelle session ==="
}

#######################################
# Journalisation - niveau INFOS (pour la sortie standard)
#######################################
log_info() {
  local ts msg username
  ts=$(get_timestamp)
  username=$(whoami)
  # Format : yyyy-mm-dd-hh-mm-ss : username : INFOS : message
  msg="$ts : $username : INFOS : $*"
  echo "$msg"
  echo "$msg" >> "$LOG_FILE"
}

#######################################
# Journalisation - niveau WARN (mappé vers INFOS)
#######################################
log_warn() {
  local ts msg username
  ts=$(get_timestamp)
  username=$(whoami)

  msg="$ts : $username : INFOS : $*"
  echo "$msg"
  echo "$msg" >> "$LOG_FILE"
}

#######################################
# Journalisation - niveau ERROR (pour la sortie d'erreur)
#######################################
log_error() {
  local ts msg username
  ts=$(get_timestamp)
  username=$(whoami)
  msg="$ts : $username : ERROR : $*"
  echo "$msg" >&2
  echo "$msg" >> "$LOG_FILE"
}

#######################################
# Journalisation - niveau DEBUG (mappé vers INFOS)
#######################################
log_debug() {
  [[ "$LOG_LEVEL" != "DEBUG" ]] && return 0
  local ts msg username
  ts=$(get_timestamp)
  username=$(whoami)
  msg="$ts : $username : DEBUG : $*"
  echo "$msg" >&2
  echo "$msg" >> "$LOG_FILE"
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