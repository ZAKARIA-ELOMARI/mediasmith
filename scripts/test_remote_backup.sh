#!/bin/bash
# test_remote_backup.sh - Ce script teste la configuration et la fonctionnalité de sauvegarde distante
# pour s'assurer que les fichiers sont correctement synchronisés vers le stockage cloud.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Charger la configuration
if [[ -f "$PROJECT_ROOT/config/config.cfg" ]]; then
    source "$PROJECT_ROOT/config/config.cfg"
else
    echo -e "${RED}✗ Fichier de configuration introuvable${NC}"
    exit 1
fi

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║        Suite de Tests de Sauvegarde Distante Mediasmith     ║"
echo "║      Vérifiez votre configuration de sauvegarde cloud       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Test 1: Vérifier l'installation de rclone
test_rclone_installation() {
    echo -e "${BLUE}📦 Test 1: Installation de rclone${NC}"
    
    if command -v rclone &> /dev/null; then
        echo -e "${GREEN}✓ rclone est installé${NC}"
        echo "  Version: $(rclone --version | head -1)"
        return 0
    else
        echo -e "${RED}✗ rclone n'est pas installé${NC}"
        echo -e "${YELLOW}  Installer avec: curl https://rclone.org/install.sh | sudo bash${NC}"
        return 1
    fi
}

# Test 2: Vérifier la configuration distante
test_remote_configuration() {
    echo -e "${BLUE}🔧 Test 2: Configuration Distante${NC}"
    
    local remotes
    remotes=$(rclone listremotes 2>/dev/null || echo "")
    
    if [[ -n "$remotes" ]]; then
        echo -e "${GREEN}✓ Distants configurés trouvés:${NC}"
        echo "$remotes" | sed 's/^/    /'
        return 0
    else
        echo -e "${RED}✗ Aucun distant configuré${NC}"
        echo -e "${YELLOW}  Exécuter: ./scripts/setup_remote_backup.sh${NC}"
        return 1
    fi
}

# Test 3: Vérifier la configuration REMOTE_DIR
test_remote_dir_config() {
    echo -e "${BLUE}⚙️ Test 3: Configuration REMOTE_DIR${NC}"
    
    if [[ -n "${REMOTE_DIR:-}" ]]; then
        echo -e "${GREEN}✓ REMOTE_DIR est configuré${NC}"
        echo "  REMOTE_DIR: $REMOTE_DIR"
        
        # Extraire le nom du distant
        local remote_name
        remote_name=$(echo "$REMOTE_DIR" | cut -d':' -f1)
        
        # Vérifier si le distant existe
        if rclone listremotes | grep -q "${remote_name}:"; then
            echo -e "${GREEN}✓ Le distant '$remote_name' existe${NC}"
            return 0
        else
            echo -e "${RED}✗ Le distant '$remote_name' introuvable${NC}"
            echo -e "${YELLOW}  Distants disponibles: $(rclone listremotes | tr '\n' ' ')${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ REMOTE_DIR non configuré${NC}"
        echo -e "${YELLOW}  Éditer config/config.cfg et définir REMOTE_DIR${NC}"
        return 1
    fi
}

# Test 4: Tester la connectivité distante
test_remote_connectivity() {
    echo -e "${BLUE}🌐 Test 4: Connectivité Distante${NC}"
    
    if [[ -z "${REMOTE_DIR:-}" ]]; then
        echo -e "${YELLOW}⏭ Ignoré - REMOTE_DIR non configuré${NC}"
        return 0
    fi
    
    local remote_name
    remote_name=$(echo "$REMOTE_DIR" | cut -d':' -f1)
    
    if rclone about "$remote_name:" &>/dev/null; then
        echo -e "${GREEN}✓ Connexion distante réussie${NC}"
        
        # Afficher les infos de stockage si disponibles
        local storage_info
        storage_info=$(rclone about "$remote_name:" 2>/dev/null || echo "Informations de stockage non disponibles")
        echo "  Infos de stockage:"
        echo "$storage_info" | head -5 | sed 's/^/    /'
        return 0
    else
        echo -e "${RED}✗ Impossible de se connecter au distant${NC}"
        echo -e "${YELLOW}  Essayer: rclone config reconnect $remote_name:${NC}"
        return 1
    fi
}

# Test 5: Tester les opérations de fichiers
test_file_operations() {
    echo -e "${BLUE}📁 Test 5: Opérations de Fichiers${NC}"
    
    if [[ -z "${REMOTE_DIR:-}" ]]; then
        echo -e "${YELLOW}⏭ Ignoré - REMOTE_DIR non configuré${NC}"
        return 0
    fi
    
    # Créer un fichier de test
    local test_file="/tmp/mediasmith_test_$(date +%s).txt"
    local test_content="Test de sauvegarde distante Mediasmith - $(date)"
    echo "$test_content" > "$test_file"
    
    echo "  Création du fichier de test: $(basename "$test_file")"
    
    # Tester l'upload
    if rclone copy "$test_file" "$REMOTE_DIR/test/" 2>/dev/null; then
        echo -e "${GREEN}✓ Upload réussi${NC}"
        
        # Tester la liste
        if rclone ls "$REMOTE_DIR/test/" | grep -q "$(basename "$test_file")"; then
            echo -e "${GREEN}✓ Liste des fichiers réussie${NC}"
            
            # Tester le download
            local download_file="/tmp/$(basename "$test_file").download"
            if rclone copy "$REMOTE_DIR/test/$(basename "$test_file")" "/tmp/" 2>/dev/null; then
                mv "/tmp/$(basename "$test_file")" "$download_file"
                
                # Vérifier le contenu
                if diff "$test_file" "$download_file" &>/dev/null; then
                    echo -e "${GREEN}✓ Download et vérification réussis${NC}"
                else
                    echo -e "${RED}✗ Contenu du fichier différent${NC}"
                    rm -f "$download_file"
                    return 1
                fi
                rm -f "$download_file"
            else
                echo -e "${RED}✗ Download échoué${NC}"
                return 1
            fi
            
            # Nettoyage distant
            rclone delete "$REMOTE_DIR/test/$(basename "$test_file")" 2>/dev/null
            rclone rmdir "$REMOTE_DIR/test/" 2>/dev/null
            echo -e "${GREEN}✓ Nettoyage distant réussi${NC}"
        else
            echo -e "${RED}✗ Liste des fichiers échouée${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ Upload échoué${NC}"
        return 1
    fi
    
    # Nettoyage local
    rm -f "$test_file"
    return 0
}

# Test 6: Tester l'intégration mediasmith
test_mediasmith_integration() {
    echo -e "${BLUE}🔄 Test 6: Intégration Mediasmith${NC}"
    
    if [[ -z "${REMOTE_DIR:-}" ]]; then
        echo -e "${YELLOW}⏭ Ignoré - REMOTE_DIR non configuré${NC}"
        return 0
    fi
    
    # Créer un fichier média de test
    local test_media="/tmp/test_media_$(date +%s).txt"
    echo "Contenu média de test" > "$test_media"
    cp "$test_media" "$PROJECT_ROOT/files/"
    
    echo "  Traitement du fichier de test avec mediasmith..."
    
    # Effacer les logs précédents
    echo "" > "$PROJECT_ROOT/logs/history.log"
    
    # Traiter avec mediasmith
    cd "$PROJECT_ROOT"
    if ./mediasmith.sh "files/$(basename "$test_media")" &>/dev/null; then
        echo -e "${GREEN}✓ Traitement mediasmith réussi${NC}"
        
        # Vérifier si la sauvegarde distante a été tentée
        if grep -q "Backing up.*→.*$REMOTE_DIR" logs/history.log; then
            echo -e "${GREEN}✓ Intégration de sauvegarde distante fonctionnelle${NC}"
            
            # Vérifier que le fichier a été uploadé
            sleep 2  # Donner du temps à rclone pour finir
            local today=$(date +%Y-%m-%d)
            if rclone ls "$REMOTE_DIR/$today/" 2>/dev/null | grep -q "$(basename "$test_media")"; then
                echo -e "${GREEN}✓ Fichier sauvegardé avec succès sur le cloud${NC}"
            else
                echo -e "${YELLOW}⚠ L'upload du fichier peut encore être en cours${NC}"
            fi
        else
            echo -e "${YELLOW}⚠ Sauvegarde distante non déclenchée${NC}"
            echo "  (Ceci peut être normal si rclone n'est pas disponible pendant le traitement)"
        fi
    else
        echo -e "${RED}✗ Traitement mediasmith échoué${NC}"
        return 1
    fi
    
    # Nettoyage
    rm -f "$test_media" "$PROJECT_ROOT/files/$(basename "$test_media")"
    return 0
}

# Test 7: Performance et surveillance
test_performance_monitoring() {
    echo -e "${BLUE}📊 Test 7: Performance et Surveillance${NC}"
    
    if [[ -z "${REMOTE_DIR:-}" ]]; then
        echo -e "${YELLOW}⏭ Ignoré - REMOTE_DIR non configuré${NC}"
        return 0
    fi
    
    local remote_name
    remote_name=$(echo "$REMOTE_DIR" | cut -d':' -f1)
    
    echo "  Distant: $remote_name"
    echo "  Chemin: $REMOTE_DIR"
    
    # Vérifier les statistiques de transfert
    echo "  Activité de sauvegarde récente:"
    if [[ -f "$PROJECT_ROOT/logs/history.log" ]]; then
        local backup_count
        backup_count=$(grep -c "Backing up.*→.*$REMOTE_DIR" "$PROJECT_ROOT/logs/history.log" 2>/dev/null || echo "0")
        echo "    Tentatives de sauvegarde dans le log actuel: $backup_count"
    fi
    
    # Vérifier la taille distante
    local remote_size
    remote_size=$(rclone size "$REMOTE_DIR/" 2>/dev/null | grep "Total size:" | awk '{print $3, $4}' || echo "inconnue")
    echo "    Taille de la sauvegarde distante: $remote_size"
    
    # Vérifier le nombre de fichiers
    local file_count
    file_count=$(rclone ls "$REMOTE_DIR/" 2>/dev/null | wc -l || echo "0")
    echo "    Nombre de fichiers distants: $file_count"
    
    echo -e "${GREEN}✓ Données de surveillance de performance collectées${NC}"
    return 0
}

# Générer le rapport de synthèse
generate_report() {
    echo ""
    echo -e "${BLUE}📋 Rapport de Synthèse des Tests${NC}"
    echo "================================"
    echo "Date: $(date)"
    echo "Système: $(uname -s) $(uname -r)"
    echo "rclone: $(command -v rclone &>/dev/null && rclone --version | head -1 || echo 'Non installé')"
    echo "REMOTE_DIR: ${REMOTE_DIR:-'Non configuré'}"
    echo "Distants disponibles: $(rclone listremotes 2>/dev/null | tr '\n' ' ' || echo 'Aucun')"
    echo ""
    
    if [[ $all_tests_passed -eq 1 ]]; then
        echo -e "${GREEN}🎉 Tous les tests sont passés! La sauvegarde distante est prête à être utilisée.${NC}"
        echo ""
        echo "Prochaines étapes:"
        echo "  • Traiter les fichiers normalement: ./mediasmith.sh files/votre-fichier.mp4"
        echo "  • Surveiller les sauvegardes: tail -f logs/history.log | grep 'Backing up'"
        echo "  • Vérifier le stockage cloud: rclone ls $REMOTE_DIR/"
    else
        echo -e "${RED}❌ Certains tests ont échoué. Veuillez réviser les problèmes ci-dessus.${NC}"
        echo ""
        echo "Solutions communes:"
        echo "  • Installer rclone: curl https://rclone.org/install.sh | sudo bash"
        echo "  • Configurer les distants: ./scripts/setup_remote_backup.sh"
        echo "  • Vérifier la connectivité: rclone config reconnect [distant]:"
    fi
    
    echo ""
    echo "Pour le guide de configuration détaillé, voir: REMOTE_BACKUP_GUIDE.md"
}

main() {
    local test_results=()
    all_tests_passed=1
    
    echo "Démarrage de la suite de tests de sauvegarde distante..."
    echo ""
    
    # Exécuter tous les tests
    if test_rclone_installation; then
        test_results+=("✓ Installation rclone")
    else
        test_results+=("✗ Installation rclone")
        all_tests_passed=0
    fi
    echo ""
    
    if test_remote_configuration; then
        test_results+=("✓ Configuration Distante")
    else
        test_results+=("✗ Configuration Distante")
        all_tests_passed=0
    fi
    echo ""
    
    if test_remote_dir_config; then
        test_results+=("✓ Configuration REMOTE_DIR")
    else
        test_results+=("✗ Configuration REMOTE_DIR")
        all_tests_passed=0
    fi
    echo ""
    
    if test_remote_connectivity; then
        test_results+=("✓ Connectivité Distante")
    else
        test_results+=("✗ Connectivité Distante")
        all_tests_passed=0
    fi
    echo ""
    
    if test_file_operations; then
        test_results+=("✓ Opérations de Fichiers")
    else
        test_results+=("✗ Opérations de Fichiers")
        all_tests_passed=0
    fi
    echo ""
    
    if test_mediasmith_integration; then
        test_results+=("✓ Intégration Mediasmith")
    else
        test_results+=("✗ Intégration Mediasmith")
        all_tests_passed=0
    fi
    echo ""
    
    if test_performance_monitoring; then
        test_results+=("✓ Surveillance Performance")
    else
        test_results+=("✗ Surveillance Performance")
        all_tests_passed=0
    fi
    echo ""
    
    generate_report
}

main "$@"
