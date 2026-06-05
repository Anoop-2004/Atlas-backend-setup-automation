#!/usr/bin/env bash
# Phase 0: Bootstrap - Install foundational tools

# Install Xcode Command Line Tools
install_xcode_tools() {
    if xcode-select -p >/dev/null 2>&1; then
        log_skip "Xcode Command Line Tools already installed"
        return 0
    fi
    
    log_step "Installing Xcode Command Line Tools"
    xcode-select --install
    
    prompt_user_action "Complete the Xcode Command Line Tools installation in the popup window."
    
    if xcode-select -p >/dev/null 2>&1; then
        log_info "Xcode Command Line Tools installed successfully"
        return 0
    else
        log_error "Xcode Command Line Tools installation failed"
        return 1
    fi
}

# Install Homebrew
install_homebrew() {
    if command_exists brew; then
        log_skip "Homebrew already installed"
        return 0
    fi
    
    log_step "Installing Homebrew"
    run_cmd_retry /bin/bash -c \"\$\(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh\)\"
    
    # Add Homebrew to PATH for Apple Silicon
    if [[ $(uname -m) == "arm64" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        
        # Add to shell profile if not already there
        if ! grep -q "brew shellenv" ~/.zshrc 2>/dev/null; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc
            log_info "Added Homebrew to ~/.zshrc"
        fi
    fi
    
    if command_exists brew; then
        log_info "Homebrew installed successfully: $(brew --version | head -n1)"
        return 0
    else
        log_error "Homebrew installation failed"
        return 1
    fi
}

# Install core tools
install_core_tools() {
    log_step "Installing core tools"
    
    local tools=(
        "git"
        "curl"
        "jq"
        "gh"
        "coreutils"
        "wget"
        "openssl"
    )
    
    for tool in "${tools[@]}"; do
        if command_exists "$tool"; then
            log_skip "$tool already installed"
        else
            log_step "Installing $tool"
            run_cmd_retry brew install "$tool"
        fi
    done
    
    log_info "Core tools installation complete"
    return 0
}

# Install Docker Desktop
install_docker() {
    if command_exists docker; then
        log_skip "Docker already installed"
        return 0
    fi
    
    log_step "Installing Docker Desktop"
    run_cmd_retry brew install --cask docker
    
    prompt_user_action "Please open Docker Desktop from Applications and complete the initial setup.\nWait for Docker to start (you'll see the whale icon in the menu bar)."
    
    # Wait for Docker daemon
    local max_wait=60
    local waited=0
    while [ $waited -lt $max_wait ]; do
        if docker info >/dev/null 2>&1; then
            log_info "Docker is running"
            return 0
        fi
        sleep 5
        waited=$((waited + 5))
    done
    
    log_error "Docker daemon did not start within timeout"
    return 1
}

# Install asdf version manager
install_asdf() {
    if command_exists asdf; then
        log_skip "asdf already installed"
        return 0
    fi
    
    log_step "Installing asdf"
    run_cmd_retry brew install asdf
    
    # Add asdf to shell profile
    if ! grep -q "asdf.sh" ~/.zshrc 2>/dev/null; then
        echo -e '\n# asdf version manager' >> ~/.zshrc
        echo '. $(brew --prefix asdf)/libexec/asdf.sh' >> ~/.zshrc
        log_info "Added asdf to ~/.zshrc"
    fi
    
    # Source asdf for current session
    . "$(brew --prefix asdf)/libexec/asdf.sh"
    
    if command_exists asdf; then
        log_info "asdf installed successfully: $(asdf version)"
        return 0
    else
        log_error "asdf installation failed"
        return 1
    fi
}

# Validate bootstrap phase
validate_bootstrap() {
    log_step "Validating bootstrap phase"
    
    local failed=0
    
    validate_command "brew" "Homebrew" || failed=1
    validate_command "git" "Git" || failed=1
    validate_command "gh" "GitHub CLI" || failed=1
    validate_command "docker" "Docker" || failed=1
    validate_command "asdf" "asdf" || failed=1
    validate_command "jq" "jq" || failed=1
    
    if [ $failed -eq 0 ]; then
        log_info "Bootstrap validation passed"
        return 0
    else
        log_error "Bootstrap validation failed"
        return 1
    fi
}

# Run bootstrap phase
run_bootstrap_phase() {
    execute_phase "INSTALLING REQUIRED TOOLS" \
        install_xcode_tools \
        install_homebrew \
        install_core_tools \
        install_docker \
        install_asdf \
        validate_bootstrap
}
