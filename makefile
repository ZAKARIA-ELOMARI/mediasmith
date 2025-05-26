# Makefile for the mediasmith project
# Compiles the C language components.

# Compiler and flags
CC = gcc
# Use -pthread for POSIX threads and -Wall for all warnings.
CFLAGS = -pthread -Wall -Wextra

# Source and binary paths
SRC = src/thread_converter.c
BIN = bin/thread_converter

.PHONY: all scripts-perm deps build test clean

# Default target
all: scripts-perm deps build

# Rendre tous les scripts exécutables
scripts-perm:
	chmod +x scripts/*.sh lib/*.sh

# Installer les dépendances système
deps:
	@echo "[MAKE] Vérification et installation des dépendances..."
	scripts/deps_check.sh

# Rule to build the binary
build: $(BIN)

$(BIN): $(SRC)
	@echo "Compiling threaded C helper..."
	@mkdir -p bin
	$(CC) $(CFLAGS) -o $(BIN) $(SRC)
	@echo "Compilation successful. Binary is at $(BIN)"

# Générer les fichiers de test
test: scripts-perm
	@echo "[MAKE] Création des fichiers de test..."
	scripts/populate_test_files.sh

# Rule to clean up build artifacts
clean:
	@echo "Cleaning up build artifacts..."
	@rm -f $(BIN)
	@rm -rf test_files output
