#!/usr/bin/env bash
# populate_test_files.sh - Crée test_files/ et génère un jeu de fichiers multimédias pour les tests
# Noms uniques : sample1, sample2, …

set -euo pipefail

# Vérifier les dépendances
for cmd in ffmpeg convert; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[ERROR] '$cmd' introuvable. Veuillez lancer deps_check.sh avant." >&2
    exit 1
  fi
done

# Définir les chemins
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
TEST_DIR="$PROJECT_ROOT/files"

# (Re)création du dossier de test
if [ -d "$TEST_DIR" ]; then
  rm -rf "$TEST_DIR"
fi
mkdir -p "$TEST_DIR"

echo "[INFO] Création de fichiers de test dans : $TEST_DIR"

# 1. Vidéo MP4 de 5 s (sample1.mp4)
ffmpeg -y -f lavfi -i testsrc=duration=5:size=320x240:rate=30 \
  "$TEST_DIR/sample1.mp4"

# 2. Vidéo MKV de 5 s (sample2.mkv)
ffmpeg -y -f lavfi -i testsrc=duration=5:size=320x240:rate=30 \
  "$TEST_DIR/sample2.mkv"

# 3. Audio WAV de 3 s (sample3.wav)
ffmpeg -y -f lavfi -i sine=frequency=440:duration=3 \
  "$TEST_DIR/sample3.wav"

# 4. Audio FLAC de 3 s (sample4.flac)
ffmpeg -y -i "$TEST_DIR/sample3.wav" \
  "$TEST_DIR/sample4.flac"

# 5. Image PNG 100×100 rouge (sample5.png)
convert -size 100x100 xc:red \
  "$TEST_DIR/sample5.png"

# 6. Image JPEG 100×100 bleue (sample6.jpg)
convert -size 100x100 xc:blue \
  "$TEST_DIR/sample6.jpg"

echo "[INFO] Génération des fichiers de test terminée."
