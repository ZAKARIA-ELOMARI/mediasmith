#!/bin/bash

#
# setup_remote_backup.sh - Interactive Remote Backup Setup for Mediasmith
#
# This script helps users configure rclone for automatic cloud backup functionality.
# It provides guided setup for popular cloud storage providers.
#
# Usage: ./scripts/setup_remote_backup.sh
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║               Mediasmith Remote Backup Setup                ║"
echo "║              Configure Cloud Storage Backup                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if rclone is installed
check_rclone() {
    if ! command -v rclone &> /dev/null; then
        echo -e "${RED}✗ rclone is not installed${NC}"
        echo ""
        echo "Would you like to install rclone now? (y/n)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            install_rclone
        else
            echo -e "${YELLOW}⚠ Remote backup setup cancelled. Install rclone manually and run this script again.${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}✓ rclone is installed${NC}"
        rclone --version | head -1
    fi
}

# Install rclone
install_rclone() {
    echo -e "${YELLOW}📦 Installing rclone...${NC}"
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y rclone
        elif command -v yum &> /dev/null; then
            sudo yum install -y rclone
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y rclone
        else
            # Use the universal installer
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
        echo -e "${GREEN}✓ rclone installed successfully${NC}"
    else
        echo -e "${RED}✗ Failed to install rclone${NC}"
        exit 1
    fi
}

# Display cloud provider menu
show_provider_menu() {
    echo ""
    echo -e "${BLUE}📁 Choose your cloud storage provider:${NC}"
    echo ""
    echo "1) Google Drive (15GB free)"
    echo "2) Dropbox (2GB free)"
    echo "3) Microsoft OneDrive (5GB free)"
    echo "4) Amazon S3 (requires AWS account)"
    echo "5) Other (manual configuration)"
    echo "6) Skip remote backup setup"
    echo ""
    echo -n "Enter your choice (1-6): "
}

# Configure Google Drive
setup_google_drive() {
    echo -e "${YELLOW}🔧 Setting up Google Drive...${NC}"
    echo ""
    echo "This will open your web browser for authentication."
    echo "Make sure you're logged into the correct Google account."
    echo ""
    read -p "Press Enter to continue..."
    
    rclone config create gdrive drive
    
    if rclone listremotes | grep -q "gdrive:"; then
        echo -e "${GREEN}✓ Google Drive configured successfully${NC}"
        update_config "gdrive:backup"
        test_remote_backup "gdrive"
    else
        echo -e "${RED}✗ Google Drive configuration failed${NC}"
    fi
}

# Configure Dropbox
setup_dropbox() {
    echo -e "${YELLOW}🔧 Setting up Dropbox...${NC}"
    echo ""
    echo "This will open your web browser for authentication."
    echo ""
    read -p "Press Enter to continue..."
    
    rclone config create dropbox dropbox
    
    if rclone listremotes | grep -q "dropbox:"; then
        echo -e "${GREEN}✓ Dropbox configured successfully${NC}"
        update_config "dropbox:backup"
        test_remote_backup "dropbox"
    else
        echo -e "${RED}✗ Dropbox configuration failed${NC}"
    fi
}

# Configure OneDrive
setup_onedrive() {
    echo -e "${YELLOW}🔧 Setting up Microsoft OneDrive...${NC}"
    echo ""
    echo "This will open your web browser for authentication."
    echo ""
    read -p "Press Enter to continue..."
    
    rclone config create onedrive onedrive
    
    if rclone listremotes | grep -q "onedrive:"; then
        echo -e "${GREEN}✓ OneDrive configured successfully${NC}"
        update_config "onedrive:backup"
        test_remote_backup "onedrive"
    else
        echo -e "${RED}✗ OneDrive configuration failed${NC}"
    fi
}

# Configure Amazon S3
setup_amazon_s3() {
    echo -e "${YELLOW}🔧 Setting up Amazon S3...${NC}"
    echo ""
    echo "You'll need your AWS Access Key ID and Secret Access Key."
    echo "You can find these in your AWS console under IAM > Users."
    echo ""
    read -p "Press Enter to continue..."
    
    rclone config create s3 s3
    
    if rclone listremotes | grep -q "s3:"; then
        echo -e "${GREEN}✓ Amazon S3 configured successfully${NC}"
        echo "Enter your S3 bucket name for backups:"
        read -r bucket_name
        update_config "s3:$bucket_name/mediasmith-backup"
        test_remote_backup "s3"
    else
        echo -e "${RED}✗ Amazon S3 configuration failed${NC}"
    fi
}

# Manual configuration
setup_manual() {
    echo -e "${YELLOW}🔧 Manual configuration...${NC}"
    echo ""
    echo "Starting interactive rclone configuration."
    echo "Follow the prompts to set up your cloud storage provider."
    echo ""
    read -p "Press Enter to continue..."
    
    rclone config
    
    # List available remotes
    remotes=$(rclone listremotes)
    if [[ -n "$remotes" ]]; then
        echo -e "${GREEN}✓ Configuration completed${NC}"
        echo ""
        echo "Available remotes:"
        echo "$remotes"
        echo ""
        echo "Enter the remote name to use for backups (e.g., 'myremote:backup'):"
        read -r remote_path
        update_config "$remote_path"
        remote_name=$(echo "$remote_path" | cut -d':' -f1)
        test_remote_backup "$remote_name"
    else
        echo -e "${RED}✗ No remotes configured${NC}"
    fi
}

# Update mediasmith configuration
update_config() {
    local remote_path="$1"
    local config_file="$PROJECT_ROOT/config/config.cfg"
    
    echo -e "${YELLOW}📝 Updating Mediasmith configuration...${NC}"
    
    if [[ -f "$config_file" ]]; then
        # Backup original config
        cp "$config_file" "$config_file.backup.$(date +%Y%m%d_%H%M%S)"
        
        # Update REMOTE_DIR
        if grep -q "^REMOTE_DIR=" "$config_file"; then
            sed -i "s|^REMOTE_DIR=.*|REMOTE_DIR=\"$remote_path\"|" "$config_file"
        else
            echo "REMOTE_DIR=\"$remote_path\"" >> "$config_file"
        fi
        
        echo -e "${GREEN}✓ Configuration updated${NC}"
        echo "  REMOTE_DIR set to: $remote_path"
    else
        echo -e "${RED}✗ Configuration file not found: $config_file${NC}"
    fi
}

# Test remote backup functionality
test_remote_backup() {
    local remote_name="$1"
    
    echo -e "${YELLOW}🧪 Testing remote backup...${NC}"
    
    # Create test file
    local test_file="/tmp/mediasmith_test_$(date +%s).txt"
    echo "Mediasmith remote backup test - $(date)" > "$test_file"
    
    # Test upload
    if rclone copy "$test_file" "$remote_name:mediasmith-test/" 2>/dev/null; then
        echo -e "${GREEN}✓ Upload test successful${NC}"
        
        # Test list
        if rclone ls "$remote_name:mediasmith-test/" | grep -q "mediasmith_test"; then
            echo -e "${GREEN}✓ File listing test successful${NC}"
            
            # Cleanup
            rclone delete "$remote_name:mediasmith-test/$(basename "$test_file")" 2>/dev/null
            rclone rmdir "$remote_name:mediasmith-test/" 2>/dev/null
            echo -e "${GREEN}✓ Cleanup successful${NC}"
            
            echo ""
            echo -e "${GREEN}🎉 Remote backup is working correctly!${NC}"
        else
            echo -e "${RED}✗ File listing test failed${NC}"
        fi
    else
        echo -e "${RED}✗ Upload test failed${NC}"
        echo "Please check your remote configuration and try again."
    fi
    
    # Cleanup local test file
    rm -f "$test_file"
}

# Show usage examples
show_usage_examples() {
    echo ""
    echo -e "${BLUE}📖 Usage Examples:${NC}"
    echo ""
    echo "After setup, remote backup will work automatically:"
    echo ""
    echo "# Process files with automatic backup"
    echo "./mediasmith.sh files/sample.mp4"
    echo ""
    echo "# Check backup status"
    echo "tail -f logs/history.log | grep 'Backing up'"
    echo ""
    echo "# Manually verify cloud backup"
    echo "rclone ls \$(grep REMOTE_DIR config/config.cfg | cut -d'\"' -f2)/"
    echo ""
    echo "# Monitor cloud storage usage"
    local remote_name
    if rclone listremotes | head -1 | grep -q ":"; then
        remote_name=$(rclone listremotes | head -1 | tr -d ':')
        echo "rclone about $remote_name:"
    else
        echo "rclone about [your-remote]:"
    fi
}

# Main execution
main() {
    echo -e "${BLUE}🔍 Checking system requirements...${NC}"
    check_rclone
    
    echo ""
    echo -e "${GREEN}✓ System requirements met${NC}"
    
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
                echo -e "${YELLOW}⏭ Skipping remote backup setup${NC}"
                echo "You can run this script again later to configure remote backup."
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter 1-6.${NC}"
                ;;
        esac
    done
    
    show_usage_examples
    
    echo ""
    echo -e "${GREEN}🎉 Remote backup setup completed!${NC}"
    echo ""
    echo "Your files will now be automatically backed up to the cloud"
    echo "whenever you process them with Mediasmith."
}

# Run main function
main "$@"
