#!/usr/bin/env bash
# Phase 5: Stack Setup - Build and start Docker stack

# Build Docker stack using tfcdev
build_stack() {
    log_step "Building Docker stack with tfcdev"
    
    local atlas_dir="${ATLAS_DIR:-$HOME/hashicorp/atlas}"
    cd "$atlas_dir" || return 1
    
    # Source asdf to ensure tfcdev is available
    source_asdf || return 1
    
    # Check if tfcdev is available
    if ! command_exists tfcdev; then
        log_error "tfcdev command not found. Please ensure it's installed."
        return 1
    fi
    
    # Set up Artifactory token before building (function defined in phases/02-repository.sh)
    setup_artifactory_token || return 1
    
    # Run tfcdev stack build with retry
    run_cmd_retry tfcdev stack build
    
    if [ $? -eq 0 ]; then
        log_info "Docker stack built successfully"
        return 0
    else
        log_error "Failed to build Docker stack"
        return 1
    fi
}

# Start Docker stack using tfcdev
start_stack() {
    log_step "Starting Docker stack with tfcdev"
    
    local atlas_dir="${ATLAS_DIR:-$HOME/hashicorp/atlas}"
    cd "$atlas_dir" || return 1
    
    # Source asdf to ensure tfcdev is available
    source_asdf || return 1
    
    # Run tfcdev stack up with retry
    run_cmd_retry tfcdev stack up
    
    if [ $? -eq 0 ]; then
        log_info "Docker stack started successfully"
        return 0
    else
        log_error "Failed to start Docker stack"
        return 1
    fi
}

run_stack_phase() {
    execute_phase "SETTING UP TFCDEV STACK" \
        build_stack \
        start_stack
}