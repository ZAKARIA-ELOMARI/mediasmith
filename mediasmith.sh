#!/usr/bin/env bash

#
# mediasmith - Multimedia Processing Orchestrator
#
# Main script to handle conversion, backup, and monitoring of multimedia files.
# It supports various execution modes and advanced logging.
#
# Version: 2.2
# Copyright (C) 2025 - All rights reserved.
#

set -euo pipefail

# --- Project Structure and Configuration ---
# Establishes the root directory and sources all necessary scripts and configurations.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# Source configuration and libraries. A check ensures the config file exists.
if [[ -f "$PROJECT_ROOT/config/config.cfg" ]]; then
    source "$PROJECT_ROOT/config/config.cfg"
else
    # config.cfg doesn't exist, try to create it from config.example.cfg
    if [[ -f "$PROJECT_ROOT/config/config.example.cfg" ]]; then
        cp "$PROJECT_ROOT/config/config.example.cfg" "$PROJECT_ROOT/config/config.cfg"
        source "$PROJECT_ROOT/config/config.cfg"
    else
        echo "FATAL: Neither config.cfg nor config.example.cfg found in 'config/' directory." >&2
        exit 1
    fi
fi


source "$PROJECT_ROOT/lib/logging.sh"
source "$PROJECT_ROOT/lib/utils.sh"
source "$PROJECT_ROOT/lib/conversion.sh"
source "$PROJECT_ROOT/lib/backup.sh"

# --- Constants and Default Values ---
# Defines error codes and default operational parameters.
EXEC_MODE="normal"
SOURCE_PATH=""

# Error Codes for specific failure scenarios.
readonly E_INVALID_OPTION=100
readonly E_MISSING_PARAM=101
readonly E_REQUIRES_SUDO=102
readonly E_FILE_NOT_FOUND=103
readonly E_THREAD_HELPER_NOT_FOUND=110

# --- Function Definitions ---

##
# Displays the detailed help and usage documentation for the program.
# This function is triggered by the -h or --help option.
##
show_help() {
    cat <<EOF

Multimedia Smith v2.2

A powerful and extensible script for multimedia file processing.

Usage:
  mediasmith [core options] <source> [conversion options]

Core Options:
  -h, --help              Displays this comprehensive help manual.
  -f, --fork              Executes the processing task in a separate child process (fork).
  -t, --thread            Delegates the conversion to a high-performance C program.
  -s, --subshell          Runs the processing logic within an isolated subshell.
  -l, --log DIR           Sets a custom directory for log files. (Requires sudo).
  -c, --config            Interactive configuration editor for modifying settings.
  -r, --restore           Resets the application to its factory default settings. (Requires sudo).
  --watch                 Activates the directory watcher.

Backup Management:
  --setup-backup          Interactive setup for remote cloud backup using rclone.
  --test-backup           Test remote backup configuration and connectivity.
  --backup-now            Trigger immediate backup of converted files to remote storage.

Conversion Options (Passed to the conversion engine):
  -R                      Process directory recursively.
  -o <dir>                Specify a custom output directory.
  -v <ext>                Set a custom output extension for videos (e.g., webm).
  -a <ext>                Set a custom output extension for audio (e.g., flac).
  -i <ext>                Set a custom output extension for images (e.g., webp).

Example Scenarios:
  1. Lightweight (single file):
     ./mediasmith.sh path/to/image.jpg

  2. Heavy-weight (Recursive video conversion to WEBM format with fork):
     ./mediasmith.sh -f path/to/videos/ -r -v webm

  3. Custom Output (Process audio files and place results in /tmp/converted):
     ./mediasmith.sh path/to/audio/ -o /tmp/converted

  4. Custom behavior with different execution modes:
     ./mediasmith.sh -f path/to/videos/ -r -v webm

  5. Interactive configuration management:
     ./mediasmith.sh -c

  6. Backup Management:
     ./mediasmith.sh --setup-backup     # Configure cloud backup
     ./mediasmith.sh --test-backup      # Test backup connectivity
     ./mediasmith.sh --backup-now       # Backup converted files now

    Run sudo ./mediasmith.sh -r | --restore once in the beginning to set up the default configuration and resolve any permissions issues.
EOF
}

##
# Centralized error handler. Logs the error message and displays help.
# @param $1 - The exit code for the error.
# @param $2 - The error message to display.
##
handle_error() {
    local exit_code="$1"
    local error_message="$2"

    log_error "$error_message (Exit Code: $exit_code)"
    echo -e "\n---------------------"
    show_help
    exit "$exit_code"
}

##
# Checks if the script is being run with administrator (root) privileges.
# Exits with an error if privileges are insufficient.
##
check_sudo() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        handle_error "$E_REQUIRES_SUDO" "This operation requires administrator privileges. Please use 'sudo'."
    fi
}

##
# Restores the application to its default state by copying config.example.cfg to config.cfg.
# Requires admin rights and clears logs.
##
# In mediasmith.sh

##
# Restores the application to its default state by copying config.example.cfg to config.cfg.
# Requires admin rights and clears logs.
##
restore_defaults() {
    check_sudo

    # ── Make sure /var/log/convertisseur_multimedia exists and is yours ──
    if [[ ! -d "$LOG_DIR" ]]; then
        mkdir -p "$LOG_DIR"
        chown "${SUDO_USER:-root}" "$LOG_DIR"
        chmod 755 "$LOG_DIR"
    fi

    log_warn "Default settings restoration initiated."
    
    local example_config="$PROJECT_ROOT/config/config.example.cfg"
    local current_config="$PROJECT_ROOT/config/config.cfg"
    
    # Check if example config exists
    if [[ ! -f "$example_config" ]]; then
        handle_error "$E_FILE_NOT_FOUND" "Default configuration template not found: $example_config"
    fi
    
    if ask_yes_no "This will reset all configurations to defaults and clear logs. Are you sure you want to proceed?"; then
        log_info "Restoring configuration from template..."
        
        # Backup current config if it exists
        if [[ -f "$current_config" ]]; then
            local backup_name="config.cfg.backup.$(date +%Y%m%d_%H%M%S)"
            cp "$current_config" "$PROJECT_ROOT/config/$backup_name"
            log_info "Current configuration backed up as: $backup_name"
        fi
        
        # Copy example config to current config
        cp "$example_config" "$current_config"
        
        # --- FIX STARTS HERE ---
        # Reset ownership of the new config file to the original user
        if [[ -n "${SUDO_USER-}" ]]; then
            chown "$SUDO_USER" "$current_config"
            log_info "Set ownership of config.cfg to '$SUDO_USER'."
        fi

        log_info "Configuration restored from template."
        
        # Clear logs
        if [[ -d "$LOG_DIR" ]]; then
            rm -f "$LOG_DIR"/*
            log_info "Log directory cleared."
        fi
        
        # Clear project logs
        if [[ -d "$PROJECT_ROOT/logs" ]]; then
            rm -f "$PROJECT_ROOT/logs"/*
            log_info "Project logs cleared."
        fi
        
        log_info "Restore operation completed successfully."
    else
        log_info "Restore operation cancelled by user."
    fi
}

##
# Interactive configuration editor that allows users to modify configuration variables.
# Displays current values and prompts for new ones, updating config.cfg accordingly.
##
interactive_config() {
    local config_file="$PROJECT_ROOT/config/config.cfg"
    
    # ── Make sure we have *some* log file (falls back to $PROJECT_ROOT/logs/ if needed) ──
    init_logging
    log_info "Starting interactive configuration editor..."
    
    # Check if config file exists
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    echo "=== MediaSmith Configuration Editor ==="
    echo "Current configuration values:"
    echo
    
    # Define configurable variables with descriptions
    declare -A config_vars=(
        ["LOG_LEVEL"]="Logging level (DEBUG, INFO, WARN, ERROR)"
        ["DEFAULT_OUT_DIR"]="Default output directory for converted files"
        ["WATCH_INTERVAL"]="File watcher polling interval in seconds"
        ["default_video_ext"]="Default video output extension"
        ["default_audio_ext"]="Default audio output extension"
        ["default_image_ext"]="Default image output extension"
        ["REMOTE_DIR"]="Remote backup directory path"
    )
    
    # Display current values
    local counter=1
    local var_list=()
    for var in "${!config_vars[@]}"; do
        # Get current value from config file
        local current_value=$(grep "^${var}=" "$config_file" | cut -d'=' -f2- | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
        if [[ -z "$current_value" ]]; then
            current_value="(not set)"
        fi
        
        echo "$counter. $var: $current_value"
        echo "   Description: ${config_vars[$var]}"
        echo
        var_list+=("$var")
        ((counter++))
    done
    
    echo "0. Exit configuration editor"
    echo
    
    while true; do
        read -p "Select a variable to modify (0-$((${#var_list[@]}))): " choice
        
        if [[ "$choice" == "0" ]]; then
            log_info "Configuration editor exited."
            break
        elif [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [[ "$choice" -le "${#var_list[@]}" ]]; then
            local selected_var="${var_list[$((choice-1))]}"
            local current_value=$(grep "^${selected_var}=" "$config_file" | cut -d'=' -f2- | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
            
            echo "Selected: $selected_var"
            echo "Current value: ${current_value:-"(not set)"}"
            echo "Description: ${config_vars[$selected_var]}"
            
            read -p "Enter new value (or press Enter to keep current): " new_value
            
            if [[ -n "$new_value" ]]; then
                # Update the configuration file
                if grep -q "^${selected_var}=" "$config_file"; then
                    if [[ "$(uname)" == "Darwin" ]]; then
                        sed -i '' "s|^${selected_var}=.*|${selected_var}=\"${new_value}\"|" "$config_file"
                    else
                        sed -i "s|^${selected_var}=.*|${selected_var}=\"${new_value}\"|" "$config_file"
                    fi
                else
                    echo "${selected_var}=\"${new_value}\"" >> "$config_file"
                fi

                
                log_info "Updated $selected_var to '$new_value'"
                echo "✓ Configuration updated successfully!"
            else
                echo "Value unchanged."
            fi
            echo
        else
            echo "Invalid selection. Please choose a number between 0 and ${#var_list[@]}."
        fi
    done
}

##
# Setup remote backup configuration by calling the dedicated setup script.
# This provides an interactive interface for configuring rclone and cloud storage.
##
setup_remote_backup() {
    log_info "Starting remote backup setup..."
    
    local setup_script="$PROJECT_ROOT/scripts/setup_remote_backup.sh"
    
    if [[ ! -f "$setup_script" ]]; then
        handle_error "$E_FILE_NOT_FOUND" "Remote backup setup script not found: $setup_script"
    fi
    
    if [[ ! -x "$setup_script" ]]; then
        log_info "Making setup script executable..."
        chmod +x "$setup_script"
    fi
    
    # Execute the setup script
    "$setup_script"
    
    log_info "Remote backup setup completed."
}

##
# Test remote backup configuration by calling the dedicated test script.
# This verifies rclone configuration and connectivity to cloud storage.
##
test_remote_backup() {
    log_info "Starting remote backup test..."
    
    local test_script="$PROJECT_ROOT/scripts/test_remote_backup.sh"
    
    if [[ ! -f "$test_script" ]]; then
        handle_error "$E_FILE_NOT_FOUND" "Remote backup test script not found: $test_script"
    fi
    
    if [[ ! -x "$test_script" ]]; then
        log_info "Making test script executable..."
        chmod +x "$test_script"
    fi
    
    # Execute the test script
    "$test_script"
    
    log_info "Remote backup test completed."
}

##
# Trigger immediate backup of converted files to remote storage.
# Uses the backup process from lib/backup.sh to synchronize files.
##
backup_now() {
    log_info "Starting immediate backup process..."
    
    # Check if rclone is available
    if ! command -v rclone &> /dev/null; then
        log_warn "rclone is not installed. Remote backup functionality unavailable."
        echo "To install rclone, run: curl https://rclone.org/install.sh | sudo bash"
        echo "Or use --setup-backup to configure remote backup."
        return 1
    fi
    
    # Check if we have any files to backup
    if [[ ! -f "$TO_BACKUP" ]] || [[ ! -s "$TO_BACKUP" ]]; then
        log_info "No files pending backup."
        echo "✓ No files to backup at this time."
        return 0
    fi
    
    echo "Starting backup process..."
    
    # Source and execute backup functionality
    source "$PROJECT_ROOT/lib/backup.sh"
    
    if backup_process; then
        log_info "Backup process completed successfully."
        echo "✓ Backup completed successfully!"
    else
        log_error "Backup process failed."
        echo "✗ Backup failed. Check logs for details."
        return 1
    fi
}

# --- Main Orchestration Logic ---

##
# The main function that parses options and orchestrates the script's execution flow.
# @param "$@" - All command-line arguments passed to the script.
##
main() {

    # This loop ONLY parses the CORE mediasmith options.
    # All other options will be passed down to the conversion script.
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -f|--fork)
                EXEC_MODE="fork"
                shift
                ;;
            -t|--thread)
                EXEC_MODE="thread"
                shift
                ;;
            -s|--subshell)
                EXEC_MODE="subshell"
                shift
                ;;
            -l|--log)
                check_sudo
                # Ensure the log directory argument is provided.
                if [[ -z "${2-}" ]]; then
                    handle_error "$E_MISSING_PARAM" "The '-l' option requires a directory path."
                fi
                LOG_DIR="$2"
                # Re-initialize logging with the new path.
                unset LOGGING_INITIALIZED
                init_logging
                export LOGGING_INITIALIZED=1
                log_info "Log directory has been set to '$LOG_DIR'."
                shift 2
                ;;
            -c|--config)
                interactive_config
                exit 0
                ;;
            -r|--restore)
                restore_defaults
                exit 0
                ;;
            --watch)
                init_logging > /dev/null 2>&1
                export LOGGING_INITIALIZED=1
                log_info "Starting file system watcher..."
                # The watcher script is executed directly.
                exec "$PROJECT_ROOT/lib/watcher.sh" "${@:2}"
                ;;
            --setup-backup)
                setup_remote_backup
                exit 0
                ;;
            --test-backup)
                test_remote_backup
                exit 0
                ;;
            --backup-now)
                backup_now
                exit 0
                ;;
            -*) # This is NOT an error. It could be a conversion option (e.g., -r, -o). Break the loop.
                break
                ;;
            *)  # This is the mandatory source path.
                SOURCE_PATH="$1"
                shift
                break # Break after finding the source path to preserve subsequent options.
                ;;
        esac
    done

        # Initialize the logging system to ensure output is captured correctly.
        init_logging
        export LOGGING_INITIALIZED=1

    # If SOURCE_PATH is still empty, it means it was not provided before an option like -r.
    # We need to find the source path among the remaining arguments
    if [[ -z "$SOURCE_PATH" ]]; then
        local temp_args=()
        local found_source=false
        local skip_next=false
        
        # Look through remaining arguments to find the source path
        # We need to be careful not to treat arguments to options as source paths
        while [[ $# -gt 0 ]]; do
            if [[ "$skip_next" == true ]]; then
                # This argument is a parameter to the previous option
                temp_args+=("$1")
                skip_next=false
                shift
            elif [[ "$1" == -* ]]; then
                # This is an option
                temp_args+=("$1")
                # Check if this option expects a parameter
                case "$1" in
                    -o|-v|-a|-i)
                        skip_next=true
                        ;;
                esac
                shift
            elif [[ -e "$1" ]] && [[ -z "$SOURCE_PATH" ]]; then
                # This is a non-option argument that exists - likely our source path
                SOURCE_PATH="$1"
                found_source=true
                shift
            else
                # Non-option argument that doesn't exist or we already have a source
                temp_args+=("$1")
                shift
            fi
        done
        
        # Restore the non-source arguments back to $@
        set -- "${temp_args[@]}"
        
        if [[ "$found_source" == false ]]; then
            handle_error "$E_MISSING_PARAM" "A source file or directory parameter is required."
        fi
    fi

    if [[ ! -e "$SOURCE_PATH" ]]; then
        handle_error "$E_FILE_NOT_FOUND" "The specified source does not exist: '$SOURCE_PATH'."
    fi

    log_info "Starting job with execution mode: '$EXEC_MODE'. Source: '$SOURCE_PATH'."
    # Log the remaining arguments for debugging
    if [[ $# -gt 0 ]]; then
        log_info "Conversion options being passed: $*"
    fi

    # --- Execution Mode Dispatcher ---
    # Calls the appropriate function based on the selected execution mode.
    # Need to separate -r/-h options (before source) from -o/-v/-a/-i options (after source)
    local pre_source_opts=()
    local post_source_opts=()
    
    # Separate the arguments based on conversion script's expected format
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -R|-h)
                pre_source_opts+=("$1")
                shift
                ;;
            -o|-v|-a|-i)
                post_source_opts+=("$1")
                if [[ -n "${2-}" ]]; then
                    post_source_opts+=("$2")
                    shift 2
                else
                    shift
                fi
                ;;
            *)
                post_source_opts+=("$1")
                shift
                ;;
        esac
    done
    
    case "$EXEC_MODE" in
        normal)
            log_info "Executing in normal mode."
            # Call convert_main with proper argument order: pre-source options, source, post-source options
            convert_main "${pre_source_opts[@]}" "$SOURCE_PATH" "${post_source_opts[@]}"
            ;;
        subshell)
            log_info "Executing in isolated subshell."
            (
                # export everything the subshell needs
                export PROJECT_ROOT LOG_DIR LOG_FILE LOG_LEVEL CONVERTED_FILES_LOG
                export DEFAULT_OUT_DIR OPT_RECURSIVE OPT_OUT_DIR OPT_CUSTOM_AUDIO_EXT
                export OPT_CUSTOM_VIDEO_EXT OPT_CUSTOM_IMAGE_EXT CUSTOM_OUT_DIR
                export CUSTOM_AUDIO_EXT CUSTOM_VIDEO_EXT CUSTOM_IMAGE_EXT
                export default_video_ext default_image_ext default_audio_ext

                log_info "Subshell (PID: $$) started."
                convert_main "${pre_source_opts[@]}" "$SOURCE_PATH" "${post_source_opts[@]}"
                log_info "Subshell finished."
            )
            exit 0
            ;;
        fork)
        log_info "Forking conversion into background..."
        {
            # bring in environment for the child
            export PROJECT_ROOT LOG_DIR LOG_FILE LOG_LEVEL CONVERTED_FILES_LOG
            export DEFAULT_OUT_DIR OPT_RECURSIVE OPT_OUT_DIR OPT_CUSTOM_AUDIO_EXT
            export OPT_CUSTOM_VIDEO_EXT OPT_CUSTOM_IMAGE_EXT CUSTOM_OUT_DIR
            export CUSTOM_AUDIO_EXT CUSTOM_VIDEO_EXT CUSTOM_IMAGE_EXT
            export default_video_ext default_image_ext default_audio_ext

            # ensure the child can write logs
            init_logging > /dev/null 2>&1

            log_info "Background job (PID $$) started."
            # The redirection is removed from here
            convert_main "${pre_source_opts[@]}" "$SOURCE_PATH" "${post_source_opts[@]}"
            log_info "Background job (PID $$) has completed."
        } >> "$LOG_FILE" 2>&1 & # <-- The redirection now applies to the whole block
        # detach from shell job control
        disown $!
        log_info "Dispatched background job with PID $!."
        exit 0
        ;;
        thread)
            log_info "Executing with high-performance threaded C helper."
            local thread_helper_path="$PROJECT_ROOT/bin/thread_converter"
            if [[ ! -x "$thread_helper_path" ]]; then
                handle_error "$E_THREAD_HELPER_NOT_FOUND" "Thread helper not compiled. Please run 'make' in the project root."
            fi
            # The C program is called with the source path.
            "$thread_helper_path" "$SOURCE_PATH"
            ;;
    esac

    log_info "Mediasmith job has completed."
}

# --- Script Entry Point ---
# The script's execution begins here by calling the main function.
main "$@"
