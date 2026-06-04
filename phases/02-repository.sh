#!/usr/bin/env bash
# Phase 2: Repository Setup - Clone Atlas and setup tfcdev

# Clone Atlas repository
clone_atlas_repo() {
    local atlas_dir="${ATLAS_DIR:-$HOME/hashicorp/atlas}"
    
    if dir_exists "$atlas_dir/.git"; then
        log_skip "Atlas repository already cloned"
        return 0
    fi
    
    log_step "Cloning Atlas repository"
    
    local parent_dir
    parent_dir=$(dirname "$atlas_dir")
    ensure_dir "$parent_dir"
    
    cd "$parent_dir" || return 1
    
    run_cmd_retry git clone git@github.com:hashicorp/atlas.git
    
    if dir_exists "$atlas_dir/.git"; then
        log_info "Atlas repository cloned successfully to $atlas_dir"
        return 0
    else
        log_error "Failed to clone Atlas repository"
        return 1
    fi
}

# Install tfcdev
install_tfcdev() {
    # Export HOMEBREW_GITHUB_API_TOKEN for private tap access
    export HOMEBREW_GITHUB_API_TOKEN="${GITHUB_TOKEN:-$(gh auth token 2>/dev/null)}"
    
    # Add HashiCorp internal tap if not already added
    if ! validate_brew_tap "hashicorp/internal" 2>/dev/null; then
        run_cmd_retry brew tap hashicorp/internal git@github.com:hashicorp/homebrew-internal.git
    fi
    
    if command_exists tfcdev; then
        log_step "Checking for tfcdev updates"
        
        # Get current version
        local current_version
        current_version=$(tfcdev version 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        
        # Update brew tap to get latest formula info
        brew update hashicorp/internal 2>/dev/null || true
        
        # Check if upgrade is available
        local upgrade_info
        upgrade_info=$(brew outdated hashicorp/internal/tfcdev 2>/dev/null)
        
        if [ -n "$upgrade_info" ]; then
            log_warn "tfcdev update available"
            log_info "Current version: $current_version"
            log_step "Upgrading tfcdev to latest version"
            
            if run_cmd_retry brew upgrade hashicorp/internal/tfcdev; then
                local new_version
                new_version=$(tfcdev version 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1)
                log_info "tfcdev upgraded successfully: $current_version → $new_version"
            else
                log_warn "tfcdev upgrade failed, continuing with current version: $current_version"
            fi
        else
            log_info "tfcdev is up to date: $current_version"
        fi
        return 0
    fi
    
    log_step "Installing tfcdev"
    run_cmd_retry brew install hashicorp/internal/tfcdev
    
    if command_exists tfcdev; then
        log_info "tfcdev installed successfully: $(tfcdev version)"
        return 0
    else
        log_error "tfcdev installation failed"
        return 1
    fi
}

# Initialize tfcdev
initialize_tfcdev() {
    log_step "Initializing tfcdev"
    
    # Check if tfcdev is already initialized by checking for config
    if [ -f "$HOME/.tfcdev/config.yml" ] || [ -f "$HOME/.config/tfcdev/config.yml" ]; then
        log_skip "tfcdev already initialized"
        return 0
    fi
    
    # Run tfcdev init and capture output
    local init_output
    init_output=$(tfcdev init 2>&1)
    local exit_code=$?
    
    # Log the output to file
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] tfcdev init output:" >> "$LOG_FILE"
    echo "$init_output" >> "$LOG_FILE"
    
    # Display the output to user
    echo "$init_output"
    
    # Check for health check issues in the output
    if echo "$init_output" | grep -q "Report built with issues reported"; then
        log_error "tfcdev initialization completed but health checks reported issues"
        log_error "Please review the health check output above and resolve any issues"
        log_info "See https://go.hashi.co/troubleshoot-tfcdev-health for troubleshooting assistance"
        return 1
    fi
    
    # Check exit code
    if [ $exit_code -eq 0 ]; then
        log_info "tfcdev initialized successfully with all health checks passing"
        return 0
    else
        log_error "tfcdev initialization failed with exit code: $exit_code"
        return 1
    fi
}

# Reserve tfcdev domain
reserve_tfcdev_domain() {
    log_step "Reserving tfcdev domain"
    
    # Check if domain already reserved
    if tfcdev domain list 2>/dev/null | grep -q "Reserved"; then
        log_skip "tfcdev domain already reserved"
        return 0
    fi
    
    prompt_user_action "You will reserve a tfcdev domain.\nThis may require browser authentication.\nFollow the prompts to complete the reservation."
    
    # Capture the output of tfcdev domain reserve
    local reserve_output
    reserve_output=$(tfcdev domain reserve 2>&1)
    local exit_code=$?
    
    # Log the output to file
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] tfcdev domain reserve output:" >> "$LOG_FILE"
    echo "$reserve_output" >> "$LOG_FILE"
    
    # Display the output to user
    echo "$reserve_output"
    
    # Check if the command succeeded based on exit code OR output content
    # The command is successful if:
    # 1. Exit code is 0, OR
    # 2. Output contains "domain=" (indicating a domain was reserved/found)
    if [ $exit_code -eq 0 ] || echo "$reserve_output" | grep -q "domain="; then
        # Extract and display domain from output if present
        if echo "$reserve_output" | grep -q "domain="; then
            local domain=$(echo "$reserve_output" | grep -o "domain=[^ ]*" | cut -d= -f2)
            log_info "tfcdev domain: $domain"
            log_info "tfcdev domain reserved successfully"
            return 0
        fi
        
        # If no domain in output but exit code was 0, verify with domain list
        if tfcdev domain list 2>/dev/null | grep -q "Reserved"; then
            log_info "tfcdev domain reserved successfully"
            return 0
        fi
    fi
    
    log_error "Failed to reserve tfcdev domain"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Exit code: $exit_code" >> "$LOG_FILE"
    return 1
}

# Validate repository phase
validate_repository() {
    log_step "Validating repository phase"
    
    local atlas_dir="${ATLAS_DIR:-$HOME/hashicorp/atlas}"
    local failed=0
    
    validate_directory "$atlas_dir" "Atlas repository" || failed=1
    validate_command "tfcdev" "tfcdev" || failed=1
    
    if [ $failed -eq 0 ]; then
        log_info "Repository validation passed"
        return 0
    else
        log_error "Repository validation failed"
        return 1
    fi
}

# Run repository phase
run_repository_phase() {
    execute_phase "repository" \
        clone_atlas_repo \
        install_tfcdev \
        initialize_tfcdev \
        reserve_tfcdev_domain \
        validate_repository
}

# Made with Bob
