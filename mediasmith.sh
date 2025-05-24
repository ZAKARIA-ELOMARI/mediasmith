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
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$SCRIPT_DIR"

# Source configuration and libraries. A check ensures the config file exists.
if [[ -f "$PROJECT_ROOT/config/config.cfg" ]]; then
    source "$PROJECT_ROOT/config/config.cfg"
else
    echo "FATAL: Configuration file 'config.cfg' not found in 'config/' directory." >&2
    exit 1
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
  -e, --env VAR=VALUE     Sets environment variables for the current session.
  --restore               Resets the application to its factory default settings. (Requires sudo).
  --watch                 Activates the directory watcher.

Conversion Options (Passed to the conversion engine):
  -r                      Process directory recursively.
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

  4. Set environment variables for custom behavior:
     ./mediasmith.sh -e LOG_LEVEL=INFO -e DEFAULT_OUT_DIR=/tmp/output files/

  5. Multiple environment variables with different execution modes:
     ./mediasmith.sh -e LOG_LEVEL=DEBUG -e WATCH_INTERVAL=5 -f files/ -r

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
# Restores the application to its default state. Requires admin rights.
##
restore_defaults() {
    check_sudo
    log_warn "Default settings restoration initiated."
    if ask_yes_no "This will reset all configurations and clear logs. Are you sure you want to proceed?"; then
        log_info "Restoring configuration and clearing logs..."
        # Placeholder for actual restoration logic, e.g., copying a default config
        # and clearing the log directory.
        rm -f "$LOG_DIR"/*
        log_info "Restore operation completed successfully."
    else
        log_info "Restore operation cancelled by user."
    fi
}

##
# Sets an environment variable for the current session.
# @param $1 - The environment variable assignment in the format VAR=VALUE
##
set_environment_variable() {
    local env_assignment="$1"
    
    # Validate the format (should contain exactly one '=' sign)
    if [[ "$env_assignment" != *"="* ]]; then
        handle_error "$E_INVALID_OPTION" "Invalid environment variable format. Expected: VAR=VALUE"
    fi
    
    # Split the assignment into variable name and value
    local var_name="${env_assignment%%=*}"
    local var_value="${env_assignment#*=}"
    
    # Validate variable name (should not be empty and follow bash variable naming rules)
    if [[ -z "$var_name" ]] || [[ ! "$var_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        handle_error "$E_INVALID_OPTION" "Invalid variable name: '$var_name'. Variable names must start with a letter or underscore and contain only letters, numbers, and underscores."
    fi
    
    # Set the environment variable
    export "$var_name"="$var_value"
    log_info "Environment variable set: $var_name='$var_value'"
}

# --- Main Orchestration Logic ---

##
# The main function that parses options and orchestrates the script's execution flow.
# @param "$@" - All command-line arguments passed to the script.
##
main() {
    # Initialize the logging system to ensure output is captured correctly.
    init_logging

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
                init_logging
                log_info "Log directory has been set to '$LOG_DIR'."
                shift 2
                ;;
            -e|--env)
                # Ensure the environment variable assignment is provided.
                if [[ -z "${2-}" ]]; then
                    handle_error "$E_MISSING_PARAM" "The '-e' option requires an environment variable assignment (VAR=VALUE)."
                fi
                set_environment_variable "$2"
                shift 2
                ;;
            --restore)
                restore_defaults
                exit 0
                ;;
            --watch)
                log_info "Starting file system watcher..."
                # The watcher script is executed directly.
                exec "$PROJECT_ROOT/lib/watcher.sh" "${@:2}"
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
            -r|-h)
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
                log_info "Subshell (PID: $$) started."
                convert_main "${pre_source_opts[@]}" "$SOURCE_PATH" "${post_source_opts[@]}"
                log_info "Subshell finished."
            )
            ;;
        fork)
            log_info "Forking process to the background."
            # The task is defined as a function and run in the background.
            fork_task() {
                log_info "Forked process (PID: $$) is running."
                convert_main "${pre_source_opts[@]}" "$SOURCE_PATH" "${post_source_opts[@]}"
                log_info "Forked process (PID: $$) has completed."
            }
            fork_task &
            log_info "Task dispatched to background process with PID: $!."
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