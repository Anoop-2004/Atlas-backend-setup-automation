#!/usr/bin/env bash
# Phase 1: Authentication - GitHub and HashiCorp SSO

# Get IBM email
get_ibm_email() {
    local email
    local force_prompt="${1:-false}"
    
    # Check if already set in environment (unless force prompt)
    if [ "$force_prompt" != "true" ] && [ -n "${IBM_EMAIL:-}" ]; then
        # Check if this is from a stale session after reset
        if ! grep -q '^export IBM_EMAIL=' ~/.zshrc 2>/dev/null; then
            log_warn "IBM_EMAIL is set in current shell but not in ~/.zshrc"
            log_warn "This may be from a previous session before reset"
            echo "" >&2
            echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}" >&2
            echo -e "${BOLD}${RED}WARNING:${RESET} Using cached email from shell: ${CYAN}${IBM_EMAIL}${RESET}" >&2
            echo "" >&2
            echo -e "If you ran ${CYAN}./setup.sh --reset${RESET}, you should:" >&2
            echo -e "  1. Close this terminal" >&2
            echo -e "  2. Open a new terminal" >&2
            echo -e "  3. Run ${CYAN}./setup.sh${RESET} again" >&2
            echo "" >&2
            echo -e "Or press Ctrl+C now to exit and restart in a new terminal." >&2
            echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}" >&2
            echo "" >&2
            prompt_user_action "Press ENTER to continue with cached email, or Ctrl+C to exit..."
        fi
        return 0
    fi
    
    # Prompt user for email
    echo "" >&2
    echo -e "${BOLD}${CYAN}Enter your email address against which u got authentication to various hashicorp portals:${RESET}" >&2
    read -r email
    
    # Basic email validation - check for @ symbol
    if [[ ! "$email" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
        log_error "Invalid email format. Please enter a valid email address."
        return 1
    fi
    
    # Export for current session and save to environment
    export IBM_EMAIL="$email"
    
    # Update or add to zshrc
    if grep -q '^export IBM_EMAIL=' ~/.zshrc 2>/dev/null; then
        # Update existing entry
        sed -i.bak "s|^export IBM_EMAIL=.*|export IBM_EMAIL=\"$email\"|" ~/.zshrc
        rm -f ~/.zshrc.bak
        log_info "Updated IBM_EMAIL in ~/.zshrc"
    else
        # Add new entry with newline to ensure it's on its own line
        echo "" >> ~/.zshrc
        echo "export IBM_EMAIL=\"$email\"" >> ~/.zshrc
        log_info "Added IBM_EMAIL to ~/.zshrc"
    fi
    
    return 0
}

# GitHub authentication
setup_github_auth() {
    log_step "Setting up GitHub authentication"
    
    # Check if already authenticated
    if gh auth status >/dev/null 2>&1; then
        log_skip "GitHub already authenticated"
    else
        log_step "Starting GitHub authentication"
        prompt_user_action "You will be redirected to GitHub for authentication.\nPlease complete the login process in your browser."
        
        gh auth login --git-protocol=ssh --hostname=github.com --web
        
        if ! gh auth status >/dev/null 2>&1; then
            log_error "GitHub authentication failed"
            return 1
        fi
        log_info "GitHub authentication successful"
    fi
    
    # Add GITHUB_TOKEN to zshrc
    if ! grep -q '^export GITHUB_TOKEN="$(gh auth token)"' ~/.zshrc 2>/dev/null; then
        echo 'export GITHUB_TOKEN="$(gh auth token)"' >> ~/.zshrc
        log_info "Added GITHUB_TOKEN to ~/.zshrc"
    fi
    
    # Export for current session
    export GITHUB_TOKEN="$(gh auth token)"
    
    return 0
}

# Setup SSH key for GitHub
setup_ssh_key() {
    log_step "Verifying SSH key for GitHub"
    
    local ssh_key="$HOME/.ssh/id_ed25519"
    
    # On macOS, use the system's default SSH agent (no need to start our own)
    # Just ensure the key is added to the keychain if it exists
    if [ -f "$ssh_key" ]; then
        # Add key to macOS keychain (uses system SSH agent)
        # The -K flag adds it to keychain, --apple-use-keychain for newer macOS
        ssh-add --apple-use-keychain "$ssh_key" 2>/dev/null || ssh-add -K "$ssh_key" 2>/dev/null || ssh-add "$ssh_key" 2>/dev/null
    fi
    
    # Test SSH connection to GitHub first
    local ssh_test
    ssh_test=$(ssh -T git@github.com 2>&1)
    if echo "$ssh_test" | grep -qi "successfully authenticated"; then
        log_info "SSH connection to GitHub already working"
        # Prompt for GitHub SSO authorization
        prompt_user_action "1. Go to GitHub -> Settings -> SSH and GPG keys\n2. Find the SSH Key\n3. Go to Configure SSO\n4. Click Authorize button near hashicorp"
        
        return 0
    fi
    
    # If SSH test failed, check if key exists locally
    if [ ! -f "$ssh_key" ]; then
        log_step "Generating SSH key"
        ssh-keygen -t ed25519 -C "$(git config user.email || echo 'github')" -f "$ssh_key" -N ""
        log_info "SSH key generated"
        
        # Add key to macOS keychain
        ssh-add --apple-use-keychain "$ssh_key" 2>/dev/null || ssh-add -K "$ssh_key" 2>/dev/null || ssh-add "$ssh_key" 2>/dev/null
    fi
    
    # Try to add key via gh CLI
    log_step "Attempting to add SSH key to GitHub via gh CLI"
    if gh ssh-key add "$ssh_key.pub" --title "$(hostname)-$(date +%Y%m%d)" 2>/dev/null; then
        sleep 2  # Wait for propagation
        
        # Verify connection
        ssh_test=$(ssh -T git@github.com 2>&1)
        if echo "$ssh_test" | grep -qi "successfully authenticated"; then
            log_info "SSH key added and verified successfully"
            prompt_user_action "1. Go to GitHub -> Settings -> SSH and GPG keys\n2. Find the SSH Key\n3. Go to Configure SSO\n4. Click Authorize button near hashicorp"
            return 0
        fi
    fi
    
    # If automatic addition failed, fall back to manual process
    log_warn "Automatic SSH key addition failed"
    echo ""
    echo "========================================="
    echo "  ⚠️  ACTION REQUIRED"
    echo "========================================="
    echo ""
    echo "Please add your SSH key to GitHub manually:"
    echo ""
    echo "1. Copy your public key:"
    echo "   cat $ssh_key.pub | pbcopy"
    echo ""
    echo "2. Go to: https://github.com/settings/ssh/new"
    echo "3. Paste the key and save"
    echo ""
    echo "Note: If you see 'key already in use', the key is already added."
    echo "      Just press ENTER to continue."
    echo ""
    prompt_user_action "Press ENTER when complete..."
    
    # Ensure key is in keychain before final verification
    ssh-add --apple-use-keychain "$ssh_key" 2>/dev/null || ssh-add -K "$ssh_key" 2>/dev/null || ssh-add "$ssh_key" 2>/dev/null
    
    # Final verification
    ssh_test=$(ssh -T git@github.com 2>&1)
    if echo "$ssh_test" | grep -qi "successfully authenticated"; then
        log_info "SSH connection to GitHub verified"
        
        # Prompt for GitHub SSO authorization
        prompt_user_action "1. Go to GitHub -> Settings -> SSH and GPG keys\n2. Find the SSH Key\n3. Go to Configure SSO\n4. Click Authorize button near hashicorp"
        
        return 0
    else
        log_error "SSH connection to GitHub failed. Please verify the key was added correctly."
        log_error "SSH output: $ssh_test"
        return 1
    fi
}

# Configure Git SSH
configure_git_ssh() {
    log_step "Configuring Git SSH"
    
    # Check if already configured
    if git config --global url.git@github.com:.insteadOf >/dev/null 2>&1; then
        log_skip "Git SSH already configured"
        return 0
    fi
    
    git config --global url.git@github.com:.insteadOf https://github.com/
    
    log_info "Git SSH configured"
    return 0
}

# Install Doormat CLI
install_doormat() {
    if command_exists doormat; then
        log_skip "Doormat already installed"
        return 0
    fi
    
    log_step "Installing Doormat CLI"
    
    # Export HOMEBREW_GITHUB_API_TOKEN for private tap access
    export HOMEBREW_GITHUB_API_TOKEN="${GITHUB_TOKEN:-$(gh auth token 2>/dev/null)}"
    
    # Add HashiCorp security tap
    if ! validate_brew_tap "hashicorp/security" 2>/dev/null; then
        run_cmd_retry brew tap hashicorp/security git@github.com:hashicorp/homebrew-security.git
    fi
    
    run_cmd_retry brew install hashicorp/security/doormat-cli
    
    if command_exists doormat; then
        log_info "Doormat installed successfully"
        return 0
    else
        log_error "Doormat installation failed"
        return 1
    fi
}

# Doormat authentication
setup_doormat_auth() {
    log_step "Setting up Doormat authentication"
    
    # Check if already authenticated
    if doormat login --validate >/dev/null 2>&1; then
        log_info "Doormat already authenticated"
        return 0
    fi
    
    log_step "Authenticating with Doormat (this may open your browser)"
    echo ""
    echo "If a browser window opens, please complete the Okta login."
    echo "The script will continue automatically once authentication succeeds."
    echo ""
    
    # Use --force to ensure fresh authentication
    # This command will block until authentication completes
    if doormat login --force; then
        log_info "Doormat authentication successful"
        return 0
    else
        log_error "Doormat authentication failed"
        return 1
    fi
}

# Install Docker credential helper
install_docker_credential_helper() {
    if command_exists docker-credential-doormat; then
        log_skip "Docker credential helper already installed"
        return 0
    fi
    
    log_step "Installing Docker credential helper"
    
    # Export HOMEBREW_GITHUB_API_TOKEN for private tap access
    export HOMEBREW_GITHUB_API_TOKEN="${GITHUB_TOKEN:-$(gh auth token 2>/dev/null)}"
    
    # Add HashiCorp internal tap
    if ! validate_brew_tap "hashicorp/internal" 2>/dev/null; then
        run_cmd_retry brew tap hashicorp/internal git@github.com:hashicorp/homebrew-internal.git
    fi
    
    run_cmd_retry brew install hashicorp/internal/docker-credential-doormat
    
    if command_exists docker-credential-doormat; then
        log_info "Docker credential helper installed successfully"
        return 0
    else
        log_error "Docker credential helper installation failed"
        return 1
    fi
}

# Docker login to HashiCorp registry
docker_login_hashicorp() {
    log_step "Logging into HashiCorp Docker registry"
    
    # Check if Docker is running
    log_step "Checking Docker status"
    if ! docker info >/dev/null 2>&1; then
        log_warn "Docker is not running"
        log_step "Starting Docker Desktop"
        
        if [ -d "/Applications/Docker.app" ]; then
            open -a Docker
            log_info "Docker Desktop is starting..."
            
            # Wait for Docker to start (max 60 seconds)
            local max_wait=60
            local waited=0
            while [ $waited -lt $max_wait ]; do
                if docker info >/dev/null 2>&1; then
                    log_info "Docker is now running"
                    break
                fi
                sleep 2
                waited=$((waited + 2))
                echo -n "."
            done
            echo ""
            
            # Final check
            if ! docker info >/dev/null 2>&1; then
                log_error "Docker failed to start within ${max_wait} seconds"
                log_error "Please start Docker Desktop manually and try again"
                return 1
            fi
        else
            log_error "Docker Desktop not found at /Applications/Docker.app"
            log_error "Please install Docker Desktop and try again"
            return 1
        fi
    else
        log_info "Docker is running"
    fi
    
    # Verify Doormat is authenticated (should be from previous step)
    if ! doormat login --validate >/dev/null 2>&1; then
        log_error "Doormat is not authenticated. Please run the authentication phase first."
        return 1
    fi
    
    # Get user email
    local user_email
    user_email="${IBM_EMAIL}"
    if [ -z "$user_email" ]; then
        log_error "Email address not set. Please ensure IBM_EMAIL is configured."
        return 1
    fi
    
    log_info "Using email for Docker login: $user_email"
    
    log_step "Getting Artifactory token from Doormat and logging into Docker registry"
    
    # Use the correct command format as specified
    local token
    token=$(doormat artifactory create-token 2>/dev/null | jq -r '.access_token' 2>/dev/null)
    
    if [ -z "$token" ] || [ "$token" = "null" ]; then
        log_error "Failed to get Doormat token"
        log_error "Please ensure Doormat is properly authenticated"
        return 1
    fi
    
    # Login to Docker registry with correct registry URL
    echo "$token" | docker login -u "$user_email" --password-stdin docker.artifactory.hashicorp.engineering
    
    if [ $? -ne 0 ]; then
        log_error "Docker login failed"
        log_error "Please verify:"
        log_error "  • Email address is correct: $user_email"
        log_error "  • You have access to Artifactory (doormat-artifactory-users group)"
        log_error "  • Doormat authentication is valid"
        return 1
    fi
    
    log_info "Docker login successful"
    return 0
}

# Configure Docker credential helpers
configure_docker_credential_helpers() {
    log_step "Configuring Docker credential helpers"
    
    local config_file="$HOME/.docker/config.json"
    
    # Ensure config file exists
    if [ ! -f "$config_file" ]; then
        mkdir -p "$HOME/.docker"
        echo '{}' > "$config_file"
    fi
    
    # Clean up legacy auths entries for HashiCorp Artifactory registries
    log_step "Removing legacy Docker auth entries"
    local legacy_registries=(
        "docker.artifactory.hashicorp.engineering"
        "cloud-services-docker-virtual.artifactory.hashicorp.engineering"
        "doormat.artifactory.hashicorp.engineering"
        "tf-cloud-local.artifactory.hashicorp.engineering"
    )
    
    for registry in "${legacy_registries[@]}"; do
        # Check if the registry exists in auths
        if jq -e --arg reg "$registry" '.auths[$reg]' "$config_file" >/dev/null 2>&1; then
            log_step "Removing legacy auth entry for $registry"
            jq --arg reg "$registry" 'del(.auths[$reg])' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
        fi
    done
    
    # Configure credential helpers for specific repositories
    local repos=(
        "docker.artifactory.hashicorp.engineering"
        "doormat.artifactory.hashicorp.engineering"
        "tf-cloud-local.artifactory.hashicorp.engineering"
    )
    
    for repo in "${repos[@]}"; do
        log_step "Configuring credential helper for $repo"
        jq --arg repo "$repo" '
          if .credHelpers then .credHelpers[$repo] = "doormat"
          else . + {credHelpers: {($repo): "doormat"}} end
        ' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
    done
    
    log_info "Docker credential helpers configured and legacy auth entries removed"
    return 0
}

# Validate authentication phase
validate_authentication() {
    log_step "Validating authentication phase"
    
    local failed=0
    
    if ! gh auth status >/dev/null 2>&1; then
        log_error "GitHub authentication not valid"
        failed=1
    else
        log_info "GitHub authentication valid"
    fi
    
    if ! command_exists doormat; then
        log_error "Doormat not installed"
        failed=1
    else
        log_info "Doormat installed"
    fi
    
    if [ $failed -eq 0 ]; then
        log_info "Authentication validation passed"
        return 0
    else
        log_error "Authentication validation failed"
        return 1
    fi
}

# Clear authentication phase checkpoint
clear_authentication_checkpoint() {
    if [ -f "$STATE_FILE" ] && command_exists jq; then
        local tmp_file="${STATE_FILE}.tmp"
        
        # Remove all authentication-related steps from completed_steps
        jq '
            .completed_steps = [.completed_steps[] | select(. | test("setup_github_auth|setup_ssh_key|configure_git_ssh|install_doormat|setup_doormat_auth|install_docker_credential_helper|docker_login_hashicorp|configure_docker_credential_helpers|validate_authentication") | not)] |
            .completed_phases = [.completed_phases[] | select(. != "AUTHENTICATION")] |
            .current_phase = null |
            .current_step = null |
            .last_updated = "'"$(date -u +"%Y-%m-%dT%H:%M:%SZ")"'"
        ' "$STATE_FILE" > "$tmp_file" && mv "$tmp_file" "$STATE_FILE"
        
        log_info "Cleared authentication phase checkpoint"
    fi
}

# Run authentication phase
run_authentication_phase() {
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        # Get and store IBM email first
        if [ $retry_count -eq 0 ]; then
            get_ibm_email || return 1
        else
            # On retry, force re-prompt for email
            log_warn "Authentication failed. Restarting from step 1."
            log_warn "Please re-enter your email address."
            
            # Clear the authentication phase checkpoint to restart from step 1
            clear_authentication_checkpoint
            
            # Clear the cached email
            unset IBM_EMAIL
            
            # Remove from zshrc
            if grep -q '^export IBM_EMAIL=' ~/.zshrc 2>/dev/null; then
                sed -i.bak '/^export IBM_EMAIL=/d' ~/.zshrc
                rm -f ~/.zshrc.bak
            fi
            
            # Force prompt for new email
            get_ibm_email true || return 1
        fi
        
        # Try authentication from step 1
        if execute_phase "AUTHENTICATION" \
            setup_github_auth \
            setup_ssh_key \
            configure_git_ssh \
            install_doormat \
            setup_doormat_auth \
            install_docker_credential_helper \
            docker_login_hashicorp \
            configure_docker_credential_helpers \
            validate_authentication; then
            # Authentication succeeded
            return 0
        fi
        
        # Authentication failed - get the failed step from checkpoint
        local failed_step=""
        if [ -f "$STATE_FILE" ] && command_exists jq; then
            failed_step=$(jq -r '.failed_steps[-1] // "unknown"' "$STATE_FILE" 2>/dev/null)
        fi
        
        retry_count=$((retry_count + 1))
        
        if [ $retry_count -lt $max_retries ]; then
            echo ""
            log_warn "Authentication attempt $retry_count of $max_retries failed"
            
            # Show which step failed
            if [ -n "$failed_step" ] && [ "$failed_step" != "unknown" ] && [ "$failed_step" != "null" ]; then
                echo ""
                echo -e "${RED}Failed at step:${RESET} ${BOLD}$failed_step${RESET}"
            fi
            
            echo ""
            echo -e "${YELLOW}Possible reasons for failure:${RESET}"
            
            # Provide specific guidance based on failed step
            case "$failed_step" in
                setup_github_auth)
                    echo -e "  • GitHub authentication not completed in browser"
                    echo -e "  • GitHub account not linked to HashiCorp organization"
                    ;;
                setup_ssh_key)
                    echo -e "  • SSH key not added to GitHub"
                    echo -e "  • SSH key already in use by another account"
                    ;;
                install_doormat|setup_doormat_auth)
                    echo -e "  • Okta authentication not completed"
                    echo -e "  • No access to HashiCorp Okta"
                    echo -e "  • Missing Doormat permissions"
                    ;;
                docker_login_hashicorp)
                    echo -e "  • Incorrect email address for Artifactory"
                    echo -e "  • No access to Artifactory (missing doormat-artifactory-users group)"
                    echo -e "  • Doormat token expired or invalid"
                    ;;
                *)
                    echo -e "  • Incorrect email address"
                    echo -e "  • Okta authentication not completed"
                    echo -e "  • Missing permissions in Doormat/Artifactory"
                    ;;
            esac
            
            echo ""
            echo -e "${CYAN}Check the log file for details:${RESET}"
            echo -e "  ${DIM}tail -50 $LOG_FILE${RESET}"
            echo ""
            prompt_user_action "Press ENTER to restart authentication from step 1 with a different email..."
        fi
    done
    
    # All retries exhausted
    log_error "Authentication failed after $max_retries attempts"
    
    # Show final failed step
    if [ -f "$STATE_FILE" ] && command_exists jq; then
        local failed_step=$(jq -r '.failed_steps[-1] // "unknown"' "$STATE_FILE" 2>/dev/null)
        if [ -n "$failed_step" ] && [ "$failed_step" != "unknown" ] && [ "$failed_step" != "null" ]; then
            echo ""
            echo -e "${RED}Last failed step:${RESET} ${BOLD}$failed_step${RESET}"
            echo -e "${CYAN}Check the log file:${RESET} $LOG_FILE"
        fi
    fi
    
    return 1
}

