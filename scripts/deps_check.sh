#!/usr/bin/env bash
# deps_check.sh - Vérifie et installe automatiquement les dépendances pour convertisseur_multimedia

set -euo pipefail

log_info()  { echo "[INFO]  $*"; }
log_error() { echo "[ERROR] $*" >&2; }
log_warn()  { echo "[WARN]  $*" >&2; }

# Détecter le système d'exploitation
OS="$(uname -s)"
case "$OS" in
  Linux*)  PLATFORM="linux" ;;
  Darwin*) PLATFORM="macos" ;;
  *)       PLATFORM="unknown" ;;
esac

log_info "Plateforme détectée : $PLATFORM"

# Vérifier si on est root ou non (seulement pour Linux)
if [ "$PLATFORM" = "linux" ]; then
  if [ "$EUID" -eq 0 ]; then
    SUDO=""
  else
    SUDO="sudo"
  fi
else
  SUDO=""
fi

# Détecter le gestionnaire de paquets selon la plateforme
if [ "$PLATFORM" = "linux" ]; then
  if command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt-get"
    INSTALL_CMD="install -y"
    DEPS=(ffmpeg inotify-tools imagemagick)
    OPTIONAL_DEPS=(rclone)
  elif command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER="dnf"
    INSTALL_CMD="install -y"
    DEPS=(ffmpeg inotify-tools ImageMagick)
    OPTIONAL_DEPS=(rclone)
  elif command -v yum >/dev/null 2>&1; then
    PKG_MANAGER="yum"
    INSTALL_CMD="install -y"
    DEPS=(ffmpeg inotify-tools ImageMagick)
    OPTIONAL_DEPS=(rclone)
  else
    log_error "Aucun gestionnaire de paquets Linux supporté (apt-get, dnf ou yum requis)."
    exit 1
  fi
elif [ "$PLATFORM" = "macos" ]; then
  # Gestionnaires de paquets macOS
  if command -v brew >/dev/null 2>&1; then
    PKG_MANAGER="brew"
    INSTALL_CMD="install"
    DEPS=(ffmpeg fswatch imagemagick)
    OPTIONAL_DEPS=(rclone)
  elif command -v nix-env >/dev/null 2>&1; then
    PKG_MANAGER="nix-env"
    INSTALL_CMD="-iA"
    
    DEPS=(nixpkgs.ffmpeg nixpkgs.fswatch nixpkgs.imagemagick)
    OPTIONAL_DEPS=(nixpkgs.rclone)
    log_warn "Nix détecté. Considérez ajouter ces paquets à votre configuration nix-darwin avec flakes :"
    log_warn "  ffmpeg, fswatch, imagemagick, rclone (optionnel)"
  else
    log_error "Aucun gestionnaire de paquets macOS supporté (homebrew ou nix requis)."
    exit 1
  fi
else
  log_error "Système d'exploitation non supporté : $OS"
  exit 1
fi

log_info "Gestionnaire détecté : $PKG_MANAGER"

# Fonction pour installer un paquet
install_package() {
  local pkg="$1"
  local is_optional="${2:-false}"
  
  case "$PKG_MANAGER" in
    "nix-env")
      if [ "$is_optional" = "true" ]; then
        log_info "Installation optionnelle de '$pkg' (nix-env)..."
        if ! nix-env $INSTALL_CMD "$pkg"; then
          log_warn "Impossible d'installer '$pkg' (optionnel) avec nix-env"
          return 1
        fi
      else
        log_info "Installation de '$pkg' (nix-env)..."
        nix-env $INSTALL_CMD "$pkg"
      fi
      ;;
    *)
      if [ "$is_optional" = "true" ]; then
        log_info "Installation optionnelle de '$pkg'..."
        if ! $SUDO $PKG_MANAGER $INSTALL_CMD "$pkg"; then
          log_warn "Impossible d'installer '$pkg' (optionnel)"
          return 1
        fi
      else
        log_info "Installation de '$pkg'..."
        $SUDO $PKG_MANAGER $INSTALL_CMD "$pkg"
      fi
      ;;
  esac
  
  log_info "'$pkg' installé."
  return 0
}

# Fonction pour vérifier si un paquet est installé
is_package_installed() {
  local pkg="$1"
  local check_cmd
  
  # Déterminer la commande à vérifier selon le paquet
  case "$pkg" in
    imagemagick|ImageMagick|nixpkgs.imagemagick) check_cmd="convert" ;;
    inotify-tools) check_cmd="inotifywait" ;;
    fswatch) check_cmd="fswatch" ;;
    rclone|nixpkgs.rclone) check_cmd="rclone" ;;
    ffmpeg|nixpkgs.ffmpeg) check_cmd="ffmpeg" ;;
    nixpkgs.fswatch) check_cmd="fswatch" ;;
    *) check_cmd="$(basename "$pkg")" ;;
  esac
  
  command -v "$check_cmd" >/dev/null 2>&1
}

# Installation des dépendances obligatoires
log_info "=== Installation des dépendances obligatoires ==="
for pkg in "${DEPS[@]}"; do
  if ! is_package_installed "$pkg"; then
    install_package "$pkg" false
  else
    log_info "'$pkg' est déjà présent."
  fi
done

# Installation des dépendances optionnelles
log_info "=== Installation des dépendances optionnelles ==="
for pkg in "${OPTIONAL_DEPS[@]}"; do
  if ! is_package_installed "$pkg"; then
    log_info "Tentative d'installation de '$pkg' (optionnel)..."
    if ! install_package "$pkg" true; then
      log_warn "'$pkg' n'a pas pu être installé (optionnel) - continuant sans ce paquet"
    fi
  else
    log_info "'$pkg' (optionnel) est déjà présent."
  fi
done

if [ "$PKG_MANAGER" = "nix-env" ]; then
  log_info ""
  log_info "=== Recommandation pour nix-darwin avec flakes ==="
  log_info "Ajoutez ces paquets à votre configuration nix-darwin :"
  log_info "  environment.systemPackages = with pkgs; ["
  log_info "    ffmpeg"
  log_info "    fswatch"
  log_info "    imagemagick"
  log_info "    rclone  # optionnel"
  log_info "  ];"
  log_info ""
  log_info "Puis exécutez : darwin-rebuild switch --flake ."
fi

log_info "=== Vérification terminée ==="
log_info "Toutes les dépendances obligatoires sont prêtes."