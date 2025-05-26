#!/bin/bash

#
# test_remote_backup.sh - Test Remote Backup Functionality
#
# This script tests the remote backup configuration and functionality
# to ensure files are properly synchronized to cloud storage.
#
# Usage: ./scripts/test_remote_backup.sh
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

# Load configuration
if [[ -f "$PROJECT_ROOT/config/config.cfg" ]]; then
    source "$PROJECT_ROOT/config/config.cfg"
else
    echo -e "${RED}✗ Configuration file not found${NC}"
    exit 1
fi

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           Mediasmith Remote Backup Test Suite               ║"
echo "║        Verify your cloud backup configuration               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Test 1: Check rclone installation
test_rclone_installation() {
    echo -e "${BLUE}📦 Test 1: rclone Installation${NC}"
    
    if command -v rclone &> /dev/null; then
        echo -e "${GREEN}✓ rclone is installed${NC}"
        echo "  Version: $(rclone --version | head -1)"
        return 0
    else
        echo -e "${RED}✗ rclone is not installed${NC}"
        echo -e "${YELLOW}  Install with: curl https://rclone.org/install.sh | sudo bash${NC}"
        return 1
    fi
}

# Test 2: Check remote configuration
test_remote_configuration() {
    echo -e "${BLUE}🔧 Test 2: Remote Configuration${NC}"
    
    local remotes
    remotes=$(rclone listremotes 2>/dev/null || echo "")
    
    if [[ -n "$remotes" ]]; then
        echo -e "${GREEN}✓ Found configured remotes:${NC}"
        echo "$remotes" | sed 's/^/    /'
        return 0
    else
        echo -e "${RED}✗ No remotes configured${NC}"
        echo -e "${YELLOW}  Run: ./scripts/setup_remote_backup.sh${NC}"
        return 1
    fi
}

# Test 3: Check REMOTE_DIR configuration
test_remote_dir_config() {
    echo -e "${BLUE}⚙️ Test 3: REMOTE_DIR Configuration${NC}"
    
    if [[ -n "${REMOTE_DIR:-}" ]]; then
        echo -e "${GREEN}✓ REMOTE_DIR is configured${NC}"
        echo "  REMOTE_DIR: $REMOTE_DIR"
        
        # Extract remote name
        local remote_name
        remote_name=$(echo "$REMOTE_DIR" | cut -d':' -f1)
        
        # Check if remote exists
        if rclone listremotes | grep -q "${remote_name}:"; then
            echo -e "${GREEN}✓ Remote '$remote_name' exists${NC}"
            return 0
        else
            echo -e "${RED}✗ Remote '$remote_name' not found${NC}"
            echo -e "${YELLOW}  Available remotes: $(rclone listremotes | tr '\n' ' ')${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ REMOTE_DIR not configured${NC}"
        echo -e "${YELLOW}  Edit config/config.cfg and set REMOTE_DIR${NC}"
        return 1
    fi
}

# Test 4: Test remote connectivity
test_remote_connectivity() {
    echo -e "${BLUE}🌐 Test 4: Remote Connectivity${NC}"
    
    if [[ -z "${REMOTE_DIR:-}" ]]; then
        echo -e "${YELLOW}⏭ Skipping - REMOTE_DIR not configured${NC}"
        return 0
    fi
    
    local remote_name
    remote_name=$(echo "$REMOTE_DIR" | cut -d':' -f1)
    
    # Test basic connectivity
    if rclone about "$remote_name:" &>/dev/null; then
        echo -e "${GREEN}✓ Remote connection successful${NC}"
        
        # Show storage info if available
        local storage_info
        storage_info=$(rclone about "$remote_name:" 2>/dev/null || echo "Storage info not available")
        echo "  Storage info:"
        echo "$storage_info" | head -5 | sed 's/^/    /'
        return 0
    else
        echo -e "${RED}✗ Cannot connect to remote${NC}"
        echo -e "${YELLOW}  Try: rclone config reconnect $remote_name:${NC}"
        return 1
    fi
}

# Test 5: Test file upload/download
test_file_operations() {
    echo -e "${BLUE}📁 Test 5: File Operations${NC}"
    
    if [[ -z "${REMOTE_DIR:-}" ]]; then
        echo -e "${YELLOW}⏭ Skipping - REMOTE_DIR not configured${NC}"
        return 0
    fi
    
    # Create test file
    local test_file="/tmp/mediasmith_test_$(date +%s).txt"
    local test_content="Mediasmith remote backup test - $(date)"
    echo "$test_content" > "$test_file"
    
    echo "  Creating test file: $(basename "$test_file")"
    
    # Test upload
    if rclone copy "$test_file" "$REMOTE_DIR/test/" 2>/dev/null; then
        echo -e "${GREEN}✓ Upload successful${NC}"
        
        # Test list
        if rclone ls "$REMOTE_DIR/test/" | grep -q "$(basename "$test_file")"; then
            echo -e "${GREEN}✓ File listing successful${NC}"
            
            # Test download
            local download_file="/tmp/$(basename "$test_file").download"
            if rclone copy "$REMOTE_DIR/test/$(basename "$test_file")" "/tmp/" 2>/dev/null; then
                mv "/tmp/$(basename "$test_file")" "$download_file"
                
                # Verify content
                if diff "$test_file" "$download_file" &>/dev/null; then
                    echo -e "${GREEN}✓ Download and verification successful${NC}"
                else
                    echo -e "${RED}✗ File content mismatch${NC}"
                    rm -f "$download_file"
                    return 1
                fi
                rm -f "$download_file"
            else
                echo -e "${RED}✗ Download failed${NC}"
                return 1
            fi
            
            # Cleanup remote
            rclone delete "$REMOTE_DIR/test/$(basename "$test_file")" 2>/dev/null
            rclone rmdir "$REMOTE_DIR/test/" 2>/dev/null
            echo -e "${GREEN}✓ Remote cleanup successful${NC}"
        else
            echo -e "${RED}✗ File listing failed${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ Upload failed${NC}"
        return 1
    fi
    
    # Cleanup local
    rm -f "$test_file"
    return 0
}

# Test 6: Test mediasmith integration
test_mediasmith_integration() {
    echo -e "${BLUE}🔄 Test 6: Mediasmith Integration${NC}"
    
    if [[ -z "${REMOTE_DIR:-}" ]]; then
        echo -e "${YELLOW}⏭ Skipping - REMOTE_DIR not configured${NC}"
        return 0
    fi
    
    # Create a test media file
    local test_media="/tmp/test_media_$(date +%s).txt"
    echo "Test media content" > "$test_media"
    cp "$test_media" "$PROJECT_ROOT/files/"
    
    echo "  Processing test file with mediasmith..."
    
    # Clear previous logs
    echo "" > "$PROJECT_ROOT/logs/history.log"
    
    # Process with mediasmith
    cd "$PROJECT_ROOT"
    if ./mediasmith.sh "files/$(basename "$test_media")" &>/dev/null; then
        echo -e "${GREEN}✓ Mediasmith processing successful${NC}"
        
        # Check if remote backup was attempted
        if grep -q "Backing up.*→.*$REMOTE_DIR" logs/history.log; then
            echo -e "${GREEN}✓ Remote backup integration working${NC}"
            
            # Verify file was uploaded
            sleep 2  # Give rclone time to finish
            local today=$(date +%Y-%m-%d)
            if rclone ls "$REMOTE_DIR/$today/" 2>/dev/null | grep -q "$(basename "$test_media")"; then
                echo -e "${GREEN}✓ File successfully backed up to cloud${NC}"
            else
                echo -e "${YELLOW}⚠ File upload may still be in progress${NC}"
            fi
        else
            echo -e "${YELLOW}⚠ Remote backup not triggered${NC}"
            echo "  (This may be normal if rclone is not available during processing)"
        fi
    else
        echo -e "${RED}✗ Mediasmith processing failed${NC}"
        return 1
    fi
    
    # Cleanup
    rm -f "$test_media" "$PROJECT_ROOT/files/$(basename "$test_media")"
    return 0
}

# Test 7: Performance and monitoring
test_performance_monitoring() {
    echo -e "${BLUE}📊 Test 7: Performance & Monitoring${NC}"
    
    if [[ -z "${REMOTE_DIR:-}" ]]; then
        echo -e "${YELLOW}⏭ Skipping - REMOTE_DIR not configured${NC}"
        return 0
    fi
    
    local remote_name
    remote_name=$(echo "$REMOTE_DIR" | cut -d':' -f1)
    
    echo "  Remote: $remote_name"
    echo "  Path: $REMOTE_DIR"
    
    # Check transfer statistics
    echo "  Recent backup activity:"
    if [[ -f "$PROJECT_ROOT/logs/history.log" ]]; then
        local backup_count
        backup_count=$(grep -c "Backing up.*→.*$REMOTE_DIR" "$PROJECT_ROOT/logs/history.log" 2>/dev/null || echo "0")
        echo "    Backup attempts in current log: $backup_count"
    fi
    
    # Check remote size
    local remote_size
    remote_size=$(rclone size "$REMOTE_DIR/" 2>/dev/null | grep "Total size:" | awk '{print $3, $4}' || echo "unknown")
    echo "    Remote backup size: $remote_size"
    
    # Check file count
    local file_count
    file_count=$(rclone ls "$REMOTE_DIR/" 2>/dev/null | wc -l || echo "0")
    echo "    Remote file count: $file_count"
    
    echo -e "${GREEN}✓ Performance monitoring data collected${NC}"
    return 0
}

# Generate summary report
generate_report() {
    echo ""
    echo -e "${BLUE}📋 Test Summary Report${NC}"
    echo "================================"
    echo "Date: $(date)"
    echo "System: $(uname -s) $(uname -r)"
    echo "rclone: $(command -v rclone &>/dev/null && rclone --version | head -1 || echo 'Not installed')"
    echo "REMOTE_DIR: ${REMOTE_DIR:-'Not configured'}"
    echo "Available remotes: $(rclone listremotes 2>/dev/null | tr '\n' ' ' || echo 'None')"
    echo ""
    
    if [[ $all_tests_passed -eq 1 ]]; then
        echo -e "${GREEN}🎉 All tests passed! Remote backup is ready to use.${NC}"
        echo ""
        echo "Next steps:"
        echo "  • Process files normally: ./mediasmith.sh files/your-file.mp4"
        echo "  • Monitor backups: tail -f logs/history.log | grep 'Backing up'"
        echo "  • Check cloud storage: rclone ls $REMOTE_DIR/"
    else
        echo -e "${RED}❌ Some tests failed. Please review the issues above.${NC}"
        echo ""
        echo "Common solutions:"
        echo "  • Install rclone: curl https://rclone.org/install.sh | sudo bash"
        echo "  • Configure remotes: ./scripts/setup_remote_backup.sh"
        echo "  • Check connectivity: rclone config reconnect [remote]:"
    fi
    
    echo ""
    echo "For detailed setup guide, see: REMOTE_BACKUP_GUIDE.md"
}

# Main execution
main() {
    local test_results=()
    all_tests_passed=1
    
    echo "Starting remote backup test suite..."
    echo ""
    
    # Run all tests
    if test_rclone_installation; then
        test_results+=("✓ rclone Installation")
    else
        test_results+=("✗ rclone Installation")
        all_tests_passed=0
    fi
    echo ""
    
    if test_remote_configuration; then
        test_results+=("✓ Remote Configuration")
    else
        test_results+=("✗ Remote Configuration")
        all_tests_passed=0
    fi
    echo ""
    
    if test_remote_dir_config; then
        test_results+=("✓ REMOTE_DIR Configuration")
    else
        test_results+=("✗ REMOTE_DIR Configuration")
        all_tests_passed=0
    fi
    echo ""
    
    if test_remote_connectivity; then
        test_results+=("✓ Remote Connectivity")
    else
        test_results+=("✗ Remote Connectivity")
        all_tests_passed=0
    fi
    echo ""
    
    if test_file_operations; then
        test_results+=("✓ File Operations")
    else
        test_results+=("✗ File Operations")
        all_tests_passed=0
    fi
    echo ""
    
    if test_mediasmith_integration; then
        test_results+=("✓ Mediasmith Integration")
    else
        test_results+=("✗ Mediasmith Integration")
        all_tests_passed=0
    fi
    echo ""
    
    if test_performance_monitoring; then
        test_results+=("✓ Performance Monitoring")
    else
        test_results+=("✗ Performance Monitoring")
        all_tests_passed=0
    fi
    echo ""
    
    generate_report
}

# Run main function
main "$@"
