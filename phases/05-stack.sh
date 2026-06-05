# Build Docker stack using tfcdev
build_stack() {
    log_step "Building Docker stack with tfcdev"
    
    local atlas_dir="${ATLAS_DIR:-$HOME/hashicorp/atlas}"
    cd "$atlas_dir" || return 1
    
    # Source asdf to ensure tfcdev is available
    . "$(brew --prefix asdf)/libexec/asdf.sh"
    
    # Check if tfcdev is available
    if ! command_exists tfcdev; then
        log_error "tfcdev command not found. Please ensure it's installed."
        return 1
    fi
    
    # Set up Artifactory token before building
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
    . "$(brew --prefix asdf)/libexec/asdf.sh"
    
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