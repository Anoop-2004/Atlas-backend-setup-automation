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
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        export HOMEBREW_GITHUB_API_TOKEN="$GITHUB_TOKEN"
    elif command_exists gh; then
        local gh_token
        gh_token=$(gh auth token 2>/dev/null || echo "")
        if [ -n "$gh_token" ]; then
            export HOMEBREW_GITHUB_API_TOKEN="$gh_token"
        fi
    fi
    
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
    brew trust hashicorp/internal
    run_cmd_retry brew install hashicorp/internal/tfcdev
    
    if command_exists tfcdev; then
        log_info "tfcdev installed successfully: $(tfcdev version)"
        
        # Run tfcdev rc to set up shell configuration
        log_step "Setting up tfcdev shell configuration"
        eval "$(tfcdev rc)"
        log_info "tfcdev shell configuration applied"
        
        return 0
    else
        log_error "tfcdev installation failed"
        return 1
    fi
}

# Setup Artifactory token for bundle
setup_artifactory_token() {
    log_step "Setting up Artifactory token for bundle"
    
    # Get email from environment variable or load from zshrc
    local email="${IBM_EMAIL:-}"
    
    if [ -z "$email" ] && [ -f ~/.zshrc ]; then
        # Load from zshrc if not in environment
        email=$(grep '^export IBM_EMAIL=' ~/.zshrc 2>/dev/null | sed 's/^export IBM_EMAIL="\(.*\)"$/\1/')
        if [ -n "$email" ]; then
            export IBM_EMAIL="$email"
            log_info "Loaded IBM_EMAIL from ~/.zshrc"
        fi
    fi
    
    if [ -z "$email" ]; then
        log_error "IBM_EMAIL not found. Please ensure authentication phase completed successfully."
        return 1
    fi
    
    log_info "Using email: $email"
    
    local token
    token=$(doormat login -f && doormat artifactory create-token | jq -r '.access_token')
    
    if [ -z "$token" ] || [ "$token" = "null" ]; then
        log_error "Failed to get Doormat token for Bundler"
        return 1
    fi
    
    # URL encode the email (replace @ with %40)
    local encoded_email="${email/@/%40}"
    export BUNDLE_ARTIFACTORY__HASHICORP__ENGINEERING="${encoded_email}:${token}"
    
    log_info "Artifactory token configured successfully"
    return 0
}

# Initialize tfcdev
initialize_tfcdev() {
    log_step "Initializing tfcdev"
    
    # Check if tfcdev is already initialized by checking for config
    if [ -f "$HOME/.tfcdev/config.yml" ] || [ -f "$HOME/.config/tfcdev/config.yml" ]; then
        log_skip "tfcdev already initialized"
        return 0
    fi
    
    # Suggest the default code folder path (parent of all HashiCorp repos)
    local code_folder="$HOME/hashicorp"
    
    echo ""
    log_info "tfcdev will prompt you for the folder containing your HashiCorp repository working copies"
    log_info "Suggested path: $code_folder"
    echo ""
    
    # Create a temporary file to capture output
    local temp_output
    temp_output=$(mktemp)
    
    # Run tfcdev init interactively, using script command to preserve TTY
    # This allows interactive input while capturing output
    script -q "$temp_output" tfcdev init
    local exit_code=$?
    
    # Read the captured output
    local init_output
    init_output=$(cat "$temp_output")
    rm -f "$temp_output"
    
    # Log the output to file
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] tfcdev init output:" >> "$LOG_FILE"
    echo "$init_output" >> "$LOG_FILE"
    
    # Check exit code first
    if [ $exit_code -ne 0 ]; then
        log_error "tfcdev initialization failed with exit code: $exit_code"
        return 1
    fi
    
    # Check if initialization completed
    if ! echo "$init_output" | grep -q "Initialization complete"; then
        log_error "tfcdev init completed but initialization message not found"
        return 1
    fi
    
    # Check for successful health report
    if echo "$init_output" | grep -q "Report completed successfully"; then
        log_info "tfcdev initialized successfully with all health checks passing"
        
        # Apply shell configuration
        log_step "Applying tfcdev shell configuration"
        eval "$(tfcdev rc)" 2>/dev/null || true
        
        return 0
    elif echo "$init_output" | grep -q "Report built with issues reported"; then
        log_warn "tfcdev initialized but health checks reported some issues"
        log_info "These may be non-critical warnings (e.g., version updates, container not running)"
        log_info "See https://go.hashi.co/troubleshoot-tfcdev-health for troubleshooting if needed"
        
        # Apply shell configuration even with warnings
        log_step "Applying tfcdev shell configuration"
        eval "$(tfcdev rc)" 2>/dev/null || true
        
        # Continue despite warnings - let user decide if they need to fix
        return 0
    else
        log_error "tfcdev health check status unclear - please review output above"
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
    
    #prompt_user_action "You will reserve a tfcdev domain.\nThis may require browser authentication.\nFollow the prompts to complete the reservation."
    
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
    execute_phase "REPOSITORY" \
        clone_atlas_repo \
        install_tfcdev \
        setup_artifactory_token \
        initialize_tfcdev \
        reserve_tfcdev_domain \
        validate_repository
}

