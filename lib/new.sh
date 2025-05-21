#!/usr/bin/env bash
# convertisseur_multimedia.sh - Conversion audio, vidéo et images

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

#######################################
# ext_lower <filename> : renvoie l'extension en minuscules (sans le point)
#######################################
ext_lower() {
  local filename="$1"
  echo "${filename##*.}" | tr '[:upper:]' '[:lower:]'
}

#######################################
# SHOW PROGRESS - AVEC POURCENTAGE
#######################################
show_progress() {
  local cmd=("$@")
  local width=30
  local temp_file
  temp_file=$(mktemp)
  local pipe_file
  pipe_file=$(mktemp -u)
  local is_ffmpeg=0
  local duration_seconds=0
  local source_file=""
  
  # Détecter si c'est une commande ffmpeg et si oui, récupérer le fichier source
  if [[ "${cmd[0]}" == "ffmpeg" ]]; then
    is_ffmpeg=1
    # Rechercher le fichier d'entrée dans la commande
    for ((i=0; i<${#cmd[@]}; i++)); do
      if [[ "${cmd[$i]}" == "-i" && $((i+1)) -lt ${#cmd[@]} ]]; then
        source_file="${cmd[$i+1]}"
        break
      fi
    done
    
    # Si on a un fichier source, essayer d'obtenir sa durée
    if [[ -n "$source_file" && -f "$source_file" ]]; then
      # Obtenir la durée en secondes
      duration_seconds=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$source_file" 2>/dev/null)
      duration_seconds=${duration_seconds%.*} # Enlever la partie décimale
      # Si la durée est vide ou 0, utiliser une valeur par défaut
      if [[ -z "$duration_seconds" || "$duration_seconds" == "0" ]]; then
        duration_seconds=0
      fi
    fi
  fi
  
  # Créer un named pipe pour suivre le processus
  mkfifo "$pipe_file"
  
  # Préparer la commande modifiée pour ffmpeg si nécessaire
  if [[ $is_ffmpeg -eq 1 ]]; then
    # Créer une nouvelle commande avec les paramètres de progression
    local new_cmd=()
    new_cmd+=("ffmpeg")
    new_cmd+=("-nostdin")
    new_cmd+=("-progress")
    new_cmd+=("/dev/stdout")
    new_cmd+=("-stats")
    
    # Ajouter le reste des arguments originaux (sans le ffmpeg)
    local skip_first=1
    for arg in "${cmd[@]}"; do
      if [[ $skip_first -eq 1 ]]; then
        skip_first=0
        continue
      fi
      new_cmd+=("$arg")
    done
    
    # Remplacer la commande originale
    cmd=("${new_cmd[@]}")
  fi
  
  # Exécuter la commande avec toute sa sortie redirigée vers notre pipe et fichier temporaire
  { "${cmd[@]}" > "$pipe_file" 2>"$temp_file"; echo $? > "$temp_file.status"; } &
  local main_pid=$!
  
  # Lire depuis le pipe dans un background pour traiter la sortie
  {
    local current_time=0
    local percent=0
    
    while IFS= read -r line; do
      if [[ $is_ffmpeg -eq 1 && $duration_seconds -gt 0 ]]; then
        # Extraire le temps actuel de la sortie de ffmpeg
        if [[ "$line" == "out_time_ms="* ]]; then
          # Convertir millisecondes en secondes
          current_time=$(echo "${line#*=}" | awk '{printf "%.0f", $1/1000000}')
          # Calculer le pourcentage
          if [[ $duration_seconds -gt 0 ]]; then
            percent=$(( (current_time * 100) / duration_seconds ))
            # S'assurer que le pourcentage ne dépasse pas 100
            if [[ $percent -gt 100 ]]; then
              percent=100
            fi
            echo "PROGRESS:$percent" > "$temp_file.progress"
          fi
        fi
      fi
    done < "$pipe_file" > /dev/null
  } &
  local reader_pid=$!
  
  # Afficher la barre de progression initiale
  echo -n "Conversion en cours :   0% ["
  for ((i = 0; i < width; i++)); do echo -n " "; done
  echo -n "]"

  local i=0
  local last_percent=0
  
  # Boucle tant que le processus principal est en cours
  while kill -0 "$main_pid" 2>/dev/null; do
    # Récupérer le pourcentage s'il est disponible
    if [[ -f "$temp_file.progress" ]]; then
      local progress_line=$(cat "$temp_file.progress")
      if [[ "$progress_line" == PROGRESS:* ]]; then
        last_percent=${progress_line#PROGRESS:}
      fi
    elif [[ $is_ffmpeg -eq 0 ]]; then
      # Pour les commandes non-ffmpeg, utiliser une animation simple
      last_percent=$(( (i * 5) % 100 ))
    fi
    
    # Calculer combien de caractères de la barre remplir
    local filled_width=$(( (last_percent * width) / 100 ))
    if [[ $filled_width -gt $width ]]; then
      filled_width=$width
    fi
    
    # Afficher la barre avec pourcentage
    printf "\rConversion en cours : %3d%% [" "$last_percent"
    for ((j = 0; j < width; j++)); do
      if ((j < filled_width)); then echo -n "#"; else echo -n " "; fi
    done
    echo -n "]"
    
    sleep 0.1
    ((i++))
  done

  # Attendre explicitement la fin du processus principal
  wait "$main_pid"
  
  # Essayer de tuer proprement le processus de lecture
  kill "$reader_pid" 2>/dev/null || true
  wait "$reader_pid" 2>/dev/null || true
  
  # Récupérer le statut réel
  local status=1
  if [[ -f "$temp_file.status" ]]; then
    status=$(cat "$temp_file.status")
  fi

  # Afficher les éventuelles erreurs
  if [ "$status" -ne 0 ]; then
    log_error "Échec de la conversion (code: $status)"
    cat "$temp_file" >&2
  fi

  # Afficher une barre complète à 100%
  printf "\rConversion terminée : 100%% ["
  for ((j = 0; j < width; j++)); do echo -n "#"; done
  echo "]"

  # Nettoyer les fichiers temporaires
  rm -f "$temp_file" "$temp_file.status" "$temp_file.progress" "$pipe_file"
  return "$status"
}

#######################################
# convert_file <source_file> <out_ext> [<out_dir>]
#   Convertit un fichier audio, vidéo ou image
#######################################
convert_file() {
  local src="$1"
  # local out_ext="${2#.}"
  # local out_dir = "${$2:-$OUT_DIR}"
  local out_dir="$OUT_DIR"
  local base name ext_in out_path cmd

  # Vérifier que le fichier source existe
  if [[ ! -f "$src" ]]; then
    log_error "Le fichier source n'existe pas : $src"
    return 1
  fi

  base="$(basename "$src")"
  name="${base%.*}"
  ext_in="$(ext_lower "$src")"

  case "$ext_in" in
    mp3|wav|flac|aac|ogg)
      out_ext="$audio_ext"
      ;;      
    mp4|mkv|avi|mov|flv|wmv)
      out_ext="$video_ext"
      ;;      
    png|jpg|jpeg|gif|bmp|tiff|webp)
      out_ext="$image_ext"
      ;;      
    *)
      log_error "Type non supporté : .$ext_in (fichier $src)"
      return 1
      ;;
  esac


  ensure_dir "$out_dir"
  out_path="$out_dir/${name}.${out_ext}"

  # Eviter d'écraser le fichier source
  if [[ "$(realpath "$src")" == "$(realpath "$out_path")" ]]; then
    log_error "Le fichier source et de destination sont identiques : $src"
    return 1
  fi

  case "$ext_in" in
    # Fichiers audio
    mp3|wav|flac|aac|ogg)
      log_info "Conversion audio : $src → $out_path"
      case "$out_ext" in
        mp3)  cmd=(ffmpeg -nostdin -i "$src" -codec:a libmp3lame -q:a 2 "$out_path") ;;
        wav)  cmd=(ffmpeg -nostdin -i "$src" -acodec pcm_s16le "$out_path") ;;
        flac) cmd=(ffmpeg -nostdin -i "$src" -codec:a flac "$out_path") ;;
        aac)  cmd=(ffmpeg -nostdin -i "$src" -codec:a aac -b:a 192k "$out_path") ;;
        ogg)  cmd=(ffmpeg -nostdin -i "$src" -codec:a libvorbis -q:a 4 "$out_path") ;;
        *)    cmd=(ffmpeg -nostdin -i "$src" "$out_path") ;;
      esac
      ;;
    # Fichiers vidéo
    mp4|mkv|avi|mov|flv|wmv)
      log_info "Conversion vidéo : $src → $out_path"
      case "$out_ext" in
        mp4)  cmd=(ffmpeg -nostdin -i "$src" -c:v libx264 -preset medium -crf 23 -c:a aac -b:a 128k "$out_path") ;;
        mkv)  cmd=(ffmpeg -nostdin -i "$src" -c:v libx264 -preset medium -crf 23 -c:a copy "$out_path") ;;
        avi)  cmd=(ffmpeg -nostdin -i "$src" -c:v libx264 -c:a mp3 "$out_path") ;;
        *)    cmd=(ffmpeg -nostdin -i "$src" "$out_path") ;;
      esac
      ;;
    # Fichiers image
    png|jpg|jpeg|gif|bmp|tiff|webp)
      log_info "Conversion image  : $src → $out_path"
      
      # Paramètres spécifiques pour certains formats
      case "$out_ext" in
        jpg|jpeg) cmd=(convert "$src" -quality 90 "$out_path") ;;
        png)  cmd=(convert "$src" -quality 95 "$out_path") ;;
        webp) cmd=(convert "$src" -quality 85 "$out_path") ;;
        *)    cmd=(convert "$src" "$out_path") ;;
      esac
      ;;
    *)
      log_error "Type non supporté : .$ext_in (fichier $src)"
      return 1
      ;;
  esac

  # Afficher barre de progression personnalisée
  if ! show_progress "${cmd[@]}"; then
    return 1
  fi
  
  # Vérifier que le fichier a bien été créé
  if [[ ! -f "$out_path" ]]; then
    log_error "Le fichier de sortie n'a pas été créé : $out_path"
    return 1
  fi
  
  log_info "Conversion réussie : $(du -h "$out_path" | cut -f1)"
  return 0
}

convert_folder() {
  local recursive=0

  # Parse options for convert_folder
  while getopts ":r" opt; do
    case "$opt" in
      r)
        recursive=1
        ;;
      \?)
        log_error "Option invalide : -$OPTARG"
        return 1
        ;;
    esac
  done
  shift $((OPTIND - 1))
  echo $1
  local src_dir="$1"

  ensure_dir "$OUT_DIR"

  if [[ "$recursive" -eq 1 ]]; then
    # Recursive conversion: find all files under src_dir
    while IFS= read -r -d '' file; do
      echo "DEBUG: convert_file called with: '$file'"
      convert_file "$file"
    done < <(find "$src_dir" -type f -print0)
  else
    # Non-recursive: only files in the top directory
    shopt -s nullglob
    for file in "$src_dir"/*.*; do
      [[ -f "$file" ]] && convert_file "$file"
    done
    shopt -u nullglob
  fi
}


# convert_folder(){
#   local src_dir="$1"
#   local out_dir="$OUT_DIR"

#   ensure_dir "$out_dir"

#   shopt -s nullglob
#   for src in "$src_dir"/*.*; do
#     if [[ -f "$src" ]]; then
#       convert_file "$src"
#     fi
#   done
#   shopt -u nullglob
# }

#######################################
# Affiche l'aide
#######################################
show_help() {
  cat <<EOF
Convertisseur multimédia v1.1
Usage : $0 <fichier_source>

Tu peux changer le repertoire de sortie et l'extension en modifiant config.cfg

Options:
  -h, --help    Affiche cette aide

Formats supportés:
  - Audio : mp3, wav, flac, aac, ogg
  - Vidéo : mp4, mkv, avi, mov, flv, wmv
  - Image : png, jpg, jpeg, gif, bmp, tiff, webp

Exemple :
  $0 video.mkv ./output    # Convertit video.mkv en $video_ext
  $0 image.png ./output     # Convertit image.png en $image_ext
  $0 audio.ogg ./output     # Convertit audio.ogg en $audio_ext
EOF
}

#######################################
# Fonction principale
#######################################
main() {
  # Vérifier options
  if [[ $# -eq 0 || ("$1" == "-h" || "$1" == "--help") ]]; then
    show_help
    exit 0
  fi

  # Initialiser la journalisation
  init_logging

  # Vérifier dépendances
  check_command ffmpeg
  check_command convert

  # Vérifier les arguments
  if [[ $# -lt 1 ]]; then
    log_error "Arguments insuffisants"
    show_help
    exit 1
  fi

  local recursive=0
  local args=()
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -r)
        recursive=1
        shift
        ;;
      *)
        args+=("$1")
      shift
      ;;
    esac
  done

  if [[ "${#args[@]}" -eq 0 ]]; then
    echo "Erreur : pas de fichier ni de dossier spécifié" >&2
    exit 1
  fi

  local src="${args[0]}"

  if [[ -d "$src" ]]; then
    if [[ "$recursive" -eq 1 ]]; then
      convert_folder -r "$src"
    else
      convert_folder "$src"
    fi
  else
    convert_file "$src"
  fi
}

# if sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi