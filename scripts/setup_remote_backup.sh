#!/bin/bash
# setup_remote_backup.sh - aide dans la configuration de rclone pour la sauvegarde automatique dans le cloud.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' 

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          Configuration de Sauvegarde Distante Mediasmith     ║"
echo "║             Configurer la Sauvegarde Cloud                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# s'assurer que rclone est installé
check_rclone() {
    if ! command -v rclone &> /dev/null; then
        echo -e "${RED}✗ rclone n'est pas installé${NC}"
        echo ""
        echo "Voulez-vous installer rclone maintenant ? (o/n)"
        read -r response
        if [[ "$response" =~ ^[OoYy]$ ]]; then
            install_rclone
        else
            echo -e "${YELLOW}⚠ Configuration de sauvegarde distante annulée. Installez rclone manuellement et relancez ce script.${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}✓ rclone est installé${NC}"
        rclone --version | head -1
    fi
}

# sinon Installer rclone
install_rclone() {
    echo -e "${YELLOW}📦 Installation de rclone...${NC}"
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y rclone
        elif command -v yum &> /dev/null; then
            sudo yum install -y rclone
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y rclone
        else
            curl https://rclone.org/install.sh | sudo bash
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            brew install rclone
        else
            curl https://rclone.org/install.sh | sudo bash
        fi
    else
        curl https://rclone.org/install.sh | sudo bash
    fi
    
    if command -v rclone &> /dev/null; then
        echo -e "${GREEN}✓ rclone installé avec succès${NC}"
    else
        echo -e "${RED}✗ Échec de l'installation de rclone${NC}"
        exit 1
    fi
}

# un menu pour choisir le fournisseur de stockage cloud
show_provider_menu() {
    echo ""
    echo -e "${BLUE}📁 Choisissez votre fournisseur de stockage cloud :${NC}"
    echo ""
    echo "1) Google Drive (15GB gratuit)"
    echo "2) Dropbox (2GB gratuit)"
    echo "3) Microsoft OneDrive (5GB gratuit)"
    echo "4) Amazon S3 (nécessite un compte AWS)"
    echo "5) Autre (configuration manuelle)"
    echo "6) Ignorer la configuration de sauvegarde distante"
    echo ""
    echo -n "Entrez votre choix (1-6) : "
}

# Configure Google Drive
setup_google_drive() {
    echo -e "${YELLOW}🔧 Configuration de Google Drive...${NC}"
    echo ""
    echo "Ceci va ouvrir votre navigateur web pour l'authentification."
    echo "Assurez-vous d'être connecté au bon compte Google."
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
    
    rclone config create gdrive drive
    
    if rclone listremotes | grep -q "gdrive:"; then
        echo -e "${GREEN}✓ Google Drive configuré avec succès${NC}"
        update_config "gdrive:backup"
        test_remote_backup "gdrive"
    else
        echo -e "${RED}✗ Échec de la configuration de Google Drive${NC}"
    fi
}

# Configure Dropbox
setup_dropbox() {
    echo -e "${YELLOW}🔧 Configuration de Dropbox...${NC}"
    echo ""
    echo "Ceci va ouvrir votre navigateur web pour l'authentification."
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
    
    rclone config create dropbox dropbox
    
    if rclone listremotes | grep -q "dropbox:"; then
        echo -e "${GREEN}✓ Dropbox configuré avec succès${NC}"
        update_config "dropbox:backup"
        test_remote_backup "dropbox"
    else
        echo -e "${RED}✗ Échec de la configuration de Dropbox${NC}"
    fi
}

# Configure OneDrive
setup_onedrive() {
    echo -e "${YELLOW}🔧 Configuration de Microsoft OneDrive...${NC}"
    echo ""
    echo "Ceci va ouvrir votre navigateur web pour l'authentification."
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
    
    rclone config create onedrive onedrive
    
    if rclone listremotes | grep -q "onedrive:"; then
        echo -e "${GREEN}✓ OneDrive configuré avec succès${NC}"
        update_config "onedrive:backup"
        test_remote_backup "onedrive"
    else
        echo -e "${RED}✗ Échec de la configuration de OneDrive${NC}"
    fi
}

# Configure Amazon S3
setup_amazon_s3() {
    echo -e "${YELLOW}🔧 Configuration d'Amazon S3...${NC}"
    echo ""
    echo "Vous aurez besoin de votre ID de clé d'accès AWS et de votre clé d'accès secrète."
    echo "Vous pouvez les trouver dans votre console AWS sous IAM > Utilisateurs."
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
    
    rclone config create s3 s3
    
    if rclone listremotes | grep -q "s3:"; then
        echo -e "${GREEN}✓ Amazon S3 configuré avec succès${NC}"
        echo "Entrez le nom de votre bucket S3 pour les sauvegardes :"
        read -r bucket_name
        update_config "s3:$bucket_name/mediasmith-backup"
        test_remote_backup "s3"
    else
        echo -e "${RED}✗ Échec de la configuration d'Amazon S3${NC}"
    fi
}

# configuration manuelle
setup_manual() {
    echo -e "${YELLOW}🔧 Configuration manuelle...${NC}"
    echo ""
    echo "Démarrage de la configuration interactive de rclone."
    echo "Suivez les instructions pour configurer votre fournisseur de stockage cloud."
    echo ""
    read -p "Appuyez sur Entrée pour continuer..."
    
    rclone config
    
    remotes=$(rclone listremotes)
    if [[ -n "$remotes" ]]; then
        echo -e "${GREEN}✓ Configuration terminée${NC}"
        echo ""
        echo "Télécommandes disponibles :"
        echo "$remotes"
        echo ""
        echo "Entrez le nom de la télécommande à utiliser pour les sauvegardes (ex: 'maremote:backup') :"
        read -r remote_path
        update_config "$remote_path"
        remote_name=$(echo "$remote_path" | cut -d':' -f1)
        test_remote_backup "$remote_name"
    else
        echo -e "${RED}✗ Aucune télécommande configurée${NC}"
    fi
}

# mis a jour du fichier de configuration
update_config() {
    local remote_path="$1"
    local config_file="$PROJECT_ROOT/config/config.cfg"
    
    echo -e "${YELLOW}📝 Mise à jour de la configuration Mediasmith...${NC}"
    
    if [[ -f "$config_file" ]]; then
        # Backup original config
        cp "$config_file" "$config_file.backup.$(date +%Y%m%d_%H%M%S)"
        
        # mise a jour REMOTE_DIR
        if grep -q "^REMOTE_DIR=" "$config_file"; then
            sed -i "s|^REMOTE_DIR=.*|REMOTE_DIR=\"$remote_path\"|" "$config_file"
        else
            echo "REMOTE_DIR=\"$remote_path\"" >> "$config_file"
        fi
        
        echo -e "${GREEN}✓ Configuration mise à jour${NC}"
        echo "  REMOTE_DIR défini sur : $remote_path"
    else
        echo -e "${RED}✗ Fichier de configuration non trouvé : $config_file${NC}"
    fi
}

# Test remote backup
test_remote_backup() {
    local remote_name="$1"
    
    echo -e "${YELLOW}🧪 Test de la sauvegarde distante...${NC}"
    
    # Create test file
    local test_file="/tmp/mediasmith_test_$(date +%s).txt"
    echo "Test de sauvegarde distante Mediasmith - $(date)" > "$test_file"
    
    # Test upload
    if rclone copy "$test_file" "$remote_name:mediasmith-test/" 2>/dev/null; then
        echo -e "${GREEN}✓ Test d'envoi réussi${NC}"
        
        # Test list
        if rclone ls "$remote_name:mediasmith-test/" | grep -q "mediasmith_test"; then
            echo -e "${GREEN}✓ Test de listage des fichiers réussi${NC}"
            
            # Cleanup
            rclone delete "$remote_name:mediasmith-test/$(basename "$test_file")" 2>/dev/null
            rclone rmdir "$remote_name:mediasmith-test/" 2>/dev/null
            echo -e "${GREEN}✓ Nettoyage réussi${NC}"
            
            echo ""
            echo -e "${GREEN}🎉 La sauvegarde distante fonctionne correctement !${NC}"
        else
            echo -e "${RED}✗ Échec du test de listage des fichiers${NC}"
        fi
    else
        echo -e "${RED}✗ Échec du test d'envoi${NC}"
        echo "Veuillez vérifier votre configuration distante et réessayer."
    fi
    
    rm -f "$test_file"
}

show_usage_examples() {
    echo ""
    echo -e "${BLUE}📖 Exemples d'Utilisation :${NC}"
    echo ""
    echo "Après la configuration, la sauvegarde distante fonctionnera automatiquement :"
    echo ""
    echo "# Traiter des fichiers avec sauvegarde automatique"
    echo "./mediasmith.sh files/sample.mp4"
    echo ""
    echo "# Vérifier le statut de sauvegarde"
    echo "tail -f logs/history.log | grep 'Sauvegarde en cours'"
    echo ""
    echo "# Vérifier manuellement la sauvegarde cloud"
    echo "rclone ls \$(grep REMOTE_DIR config/config.cfg | cut -d'\"' -f2)/"
    echo ""
    echo "# Surveiller l'utilisation du stockage cloud"
    local remote_name
    if rclone listremotes | head -1 | grep -q ":"; then
        remote_name=$(rclone listremotes | head -1 | tr -d ':')
        echo "rclone about $remote_name:"
    else
        echo "rclone about [votre-télécommande]:"
    fi
}

main() {
    echo -e "${BLUE}🔍 Vérification des prérequis système...${NC}"
    check_rclone
    
    echo ""
    echo -e "${GREEN}✓ Prérequis système satisfaits${NC}"
    
    while true; do
        show_provider_menu
        read -r choice
        
        case $choice in
            1)
                setup_google_drive
                break
                ;;
            2)
                setup_dropbox
                break
                ;;
            3)
                setup_onedrive
                break
                ;;
            4)
                setup_amazon_s3
                break
                ;;
            5)
                setup_manual
                break
                ;;
            6)
                echo -e "${YELLOW}⏭ Configuration de sauvegarde distante ignorée${NC}"
                echo "Vous pouvez relancer ce script plus tard pour configurer la sauvegarde distante."
                exit 0
                ;;
            *)
                echo -e "${RED}Choix invalide. Veuillez entrer 1-6.${NC}"
                ;;
        esac
    done
    
    show_usage_examples
    
    echo ""
    echo -e "${GREEN}🎉 Configuration de sauvegarde distante terminée !${NC}"
    echo ""
    echo "Vos fichiers seront maintenant automatiquement sauvegardés dans le cloud"
    echo "chaque fois que vous les traiterez avec Mediasmith."
}

main "$@"
