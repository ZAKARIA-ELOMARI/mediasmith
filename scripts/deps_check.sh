#!/usr/bin/env bash
# deps_check.sh - Vérifie et installe automatiquement les dépendances pour convertisseur_multimedia

set -euo pipefail

# Fonctions de log
log_info()  { echo "[INFO]  $*"; }
log_error() { echo "[ERROR] $*" >&2; }

# Vérifier si on est root ou non
if [ "$EUID" -eq 0 ]; then
  SUDO=""
else
  SUDO="sudo"
fi

# Détecter le gestionnaire de paquets et la commande d'installation
if command -v apt-get >/dev/null 2>&1; then
  PKG_MANAGER="apt-get"
  INSTALL_CMD="install -y"
  DEPS=(ffmpeg inotify-tools imagemagick)
elif command -v dnf >/dev/null 2>&1; then
  PKG_MANAGER="dnf"
  INSTALL_CMD="install -y"
  DEPS=(ffmpeg inotify-tools ImageMagick)
elif command -v yum >/dev/null 2>&1; then
  PKG_MANAGER="yum"
  INSTALL_CMD="install -y"
  DEPS=(ffmpeg inotify-tools ImageMagick)
else
  log_error "Aucun gestionnaire de paquets supporté (apt-get, dnf ou yum requis)."
  exit 1
fi

log_info "Gestionnaire détecté : $PKG_MANAGER"

# Boucle d'installation
for pkg in "${DEPS[@]}"; do
  # Déterminer la commande à vérifier
  case "$pkg" in
    imagemagick|ImageMagick) CHECK_CMD="convert" ;;
    inotify-tools)           CHECK_CMD="inotifywait" ;;
    *)                        CHECK_CMD="$pkg" ;;
  esac

  if ! command -v "$CHECK_CMD" >/dev/null 2>&1; then
    log_info "Installation de '$pkg'..."
    $SUDO $PKG_MANAGER $INSTALL_CMD "$pkg"
    log_info "'$pkg' installé."
  else
    log_info "'$pkg' est déjà présent."
  fi
done

log_info "Toutes les dépendances sont prêtes."
