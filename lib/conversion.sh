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

init_logging > /dev/null 2>&1

#######################################
# ext_lower <filename> : renvoie l'extension en minuscules (sans le point)
#######################################
ext_lower() {
  local filename="$1"
  echo "${filename##*.}" | tr '[:upper:]' '[:lower:]'
}

#######################################
# keep state of converted_files
#######################################
log_to_convert() {
  if ! grep -Fxq "$1" "$CONVERTED_FILES_LOG"; then
    echo "$1" >> "$CONVERTED_FILES_LOG"
  fi
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

#############################################
# Convertit un fichier audio, vidéo ou image
#############################################
convert_file() {
  local src="$1"
  local out_dir base name ext_in out_path type cmd

  if [[ ! -f "$src" ]]; then
    log_error "Le fichier n'existe pas: $src"
  fi

  if [[ "$OPT_OUT_DIR" -eq 1 ]]; then
    out_dir="$CUSTOM_OUT_DIR"
  else
    out_dir="$DEFAULT_OUT_DIR"
  fi

  base="$(basename "$src")"
  name="${base%.*}"
  ext_in="$(ext_lower "$src")"

  case "$ext_in" in
    mp3|wav|flac|aac|ogg)
      type="audios"
      if [[ "$OPT_CUSTOM_AUDIO_EXT" -eq 1 ]]; then
        out_ext="$CUSTOM_AUDIO_EXT"
      else
        out_ext="$default_audio_ext"
      fi
      ;;
    mp4|mkv|avi|mov|flv|wmv)
      type="videos"
      if [[ "$OPT_CUSTOM_VIDEO_EXT" -eq 1 ]]; then
        out_ext="$CUSTOM_VIDEO_EXT"
      else
        out_ext="$default_video_ext"
      fi
      ;;
    png|jpg|jpeg|gif|bmp|tiff|webp)
      type="images"
      if [[ "$OPT_CUSTOM_IMAGE_EXT" -eq 1 ]]; then
        out_ext="$CUSTOM_IMAGE_EXT"
      else
        out_ext="$default_image_ext"
      fi
      ;;
    *)
      log_error "Type non supporté : .$ext_in (fichier $src)"
      return 1
      ;;
  esac

  ensure_dir "$out_dir/$type"
  out_path="$out_dir/$type/${name}.${out_ext}"

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
  log_to_convert "$base"
  log_info "Conversion réussie : $(du -h "$out_path" | cut -f1)"
  return 0
}

convert_folder() {
  local src_dir="$1"
  local out_dir

  if [[ "$OPT_OUT_DIR" -eq 1 ]]; then
    out_dir="$CUSTOM_OUT_DIR"
  else
    out_dir="$DEFAULT_OUT_DIR"
  fi
  
  ensure_dir "$out_dir"

  if [[ "$OPT_RECURSIVE" -eq 1 ]]; then
    #recursive conversion -r:
    while IFS= read -r -d '' file; do
      convert_file "$file"
    done < <(find "$src_dir" -type f -print0)
  else
    #non recursive conversion
    shopt -s nullglob
    for file in "$src_dir"/*.*; do
      [[ -f "$file" ]] && convert_file "$file"
    done
    shopt -u nullglob
  fi
}

#######################################
# Affiche l'aide
#######################################
show_help() {
    cat <<EOF
Convertisseur multimédia v1.1

Usage : "$0" [-h | -r] <fichier_source> [-o] <out_dir> [-v | -a | -i] <ext>

Tu peux changer le répertoire de sortie et l'extension en modifiant config.cfg

Options:
  -h, Affiche cette aide
  -o, Spécifie le répertoire de sortie
  -r, Convertit tous les fichiers dans le dossier et ses sous-dossiers
  -v, Spécifie l'extension vidéo
  -a, Spécifie l'extension audio
  -i, Spécifie l'extension image
Formats supportés:
  - Audio : mp3, wav, flac, aac, ogg
  - Vidéo : mp4, mkv, avi, mov, flv, wmv
  - Image : png, jpg, jpeg, gif, bmp, tiff, webp

Exemple :
  "$0" video.mkv ./output    # Convertit video.mkv en $default_video_ext
  "$0" image.png ./output    # Convertit image.png en $default_image_ext
  "$0" audio.ogg ./output    # Convertit audio.ogg en $default_audio_ext

EOF
}


#######################################
# Parse options
#######################################
parse_options() {
  #parse -h and -r because they come before the source
  while [[ ${1-} == -* ]]; do
    case "$1" in
        -r)
            OPT_RECURSIVE=1
            shift
            ;;
        -h)
            show_help
            exit 0
            ;;
        -*)
            log_error "Option invalide : $1"
            exit 1
            ;;
    esac
  done

  if [[ -z ${1-} ]]; then
    log_error "Erreur : pas de fichier ni de dossier spécifié"
    exit 1
  elif [[ ! -e "$1" ]]; then
    log_error "Le fichier/dossier source n'existe pas : $1"
    exit 1
  else
    SOURCE="$1"
    shift
  fi

  # if there is more options to parse
  if [[ "$#" -gt 0 ]]; then
    while getopts ":o:v:a:i:" opt; do
      case "$opt" in
        o)
          OPT_OUT_DIR=1
          CUSTOM_OUT_DIR="$OPTARG"
          ;;
        v)
          OPT_CUSTOM_VIDEO_EXT=1
          CUSTOM_VIDEO_EXT="${OPTARG#.}"
          ;;
        a)
          OPT_CUSTOM_AUDIO_EXT=1
          CUSTOM_AUDIO_EXT="${OPTARG#.}"
          ;;
        i)
          OPT_CUSTOM_IMAGE_EXT=1
          CUSTOM_IMAGE_EXT="${OPTARG#.}"
          ;;
        \?)
          log_error "Option invalide : -$OPTARG"
          show_help
          exit 1
          ;;
        :)
          log_error "Option -$OPTARG requiert un argument"
          show_help
          exit 1
          ;;
      esac
    done
  fi
  shift $((OPTIND - 1))

  if [[ $OPT_CUSTOM_VIDEO_EXT -eq 1 ]]; then
    case "$CUSTOM_VIDEO_EXT" in
      mp4|mkv|avi|mov|flv|wmv)
        ;;
      *)
        log_error "Extension vidéo invalide : $CUSTOM_VIDEO_EXT"
        log_error "Supported file extensions: mp4|mkv|avi|mov|flv|wmv"
        exit 1
        ;;
    esac
  fi

  if [[ $OPT_CUSTOM_IMAGE_EXT -eq 1 ]]; then
    case "$CUSTOM_IMAGE_EXT" in
      png|jpg|jpeg|gif|bmp|tiff|webp)
        ;;
      *)
        log_error "Extension image invalide : $CUSTOM_IMAGE_EXT"
        log_error "Supported file extensions: png|jpg|jpeg|gif|bmp|tiff|webp"
        exit 1
        ;;
    esac
  fi

  if [[ $OPT_CUSTOM_AUDIO_EXT -eq 1 ]]; then
    case "$CUSTOM_AUDIO_EXT" in
      mp3|wav|flac|aac|ogg)
        ;;
      *)
        log_error "Extension audio invalide : $CUSTOM_AUDIO_EXT"
        log_error "Supported file extensions: mp3|wav|flac|aac|ogg"
        exit 1
        ;;
    esac
  fi

  if [[ $OPT_OUT_DIR -eq 1 ]]; then
    if [[ -z "$CUSTOM_OUT_DIR" ]]; then
      log_error "Erreur : dossier de sortie non spécifié"
      show_help
      exit 1
    fi
    if ! ensure_dir "$CUSTOM_OUT_DIR"; then
      log_error "Impossible de créer le dossier de sortie : $CUSTOM_OUT_DIR"
      exit 1
    fi
  fi
  log_debug """
  SOURCE=$SOURCE
  OPT_OUT_DIR=$OPT_OUT_DIR
  CUSTOM_OUT_DIR=$CUSTOM_OUT_DIR
  OPT_CUSTOM_VIDEO_EXT=$OPT_CUSTOM_VIDEO_EXT
  CUSTOM_VIDEO_EXT=$CUSTOM_VIDEO_EXT
  OPT_CUSTOM_AUDIO_EXT=$OPT_CUSTOM_AUDIO_EXT
  CUSTOM_AUDIO_EXT=$CUSTOM_AUDIO_EXT
  OPT_CUSTOM_IMAGE_EXT=$OPT_CUSTOM_IMAGE_EXT
  CUSTOM_IMAGE_EXT=$CUSTOM_IMAGE_EXT
  """
}

#######################################
# Fonction principale
#######################################
convert_main() {
  # Vérifier args
  if [[ $# -eq 0 ]]; then
    show_help
    exit 0
  fi

  parse_options "$@"
  shift $((OPTIND - 1))

  # Vérifier dépendances
  check_command ffmpeg
  check_command convert

  if [[ -d "$SOURCE" ]]; then
    convert_folder "$SOURCE"
  elif [[ -f "$SOURCE" ]]; then
    convert_file "$SOURCE"
  else
    log_error "Le fichier/dossier source n'existe pas : $SOURCE"
    exit 1
  fi
}

main(){
  convert_main "$@"
}

# if sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi