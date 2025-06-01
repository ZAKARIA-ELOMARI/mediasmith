# Makefile pour le projet mediasmith

# Compilateur et options
CC = gcc
# Utiliser -pthread pour les threads POSIX et -Wall pour tous les avertissements.
CFLAGS = -pthread -Wall -Wextra

# Chemins des sources et binaires
SRC = src/thread_converter.c
BIN = bin/thread_converter

.PHONY: all scripts-perm deps build test clean

# Cible par défaut
all: scripts-perm deps build

# Rendre tous les scripts exécutables
scripts-perm:
	chmod +x scripts/*.sh lib/*.sh

# Installer les dépendances système
deps:
	@echo "[MAKE] Vérification et installation des dépendances..."
	scripts/deps_check.sh

# Règle pour construire le binaire
build: $(BIN)

$(BIN): $(SRC)
	@echo "Compilation de l'assistant C multithread..."
	@mkdir -p bin
	$(CC) $(CFLAGS) -o $(BIN) $(SRC)
	@echo "Compilation réussie. Le binaire est à $(BIN)"

# Générer les fichiers de test
test: scripts-perm
	@echo "[MAKE] Création des fichiers de test..."
	scripts/populate_test_files.sh

# Règle pour nettoyer les artefacts de construction
clean:
	@echo "Nettoyage des artefacts de construction..."
	@rm -f $(BIN)
	@rm -rf test_files output
