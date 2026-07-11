#!/usr/bin/env bash
# Phase 4: Frontend Setup - Install Node.js, pnpm, and build frontend

# Install Node.js via asdf
install_nodejs() {
    log_step "Installing Node.js via asdf"
    
    # Source asdf
    source_asdf || return 1
    
    # Add nodejs plugin if not already added
    if ! asdf plugin list | grep -q "nodejs"; then
        log_step "Adding asdf nodejs plugin"
        run_cmd_retry asdf plugin add nodejs https://github.com/asdf-vm/asdf-nodejs.git
    else
        log_skip "asdf nodejs plugin already added"
    fi
    
    local atlas_dir="${ATLAS_DIR:-$HOME/hashicorp/atlas}"
    
    if [ ! -f "$atlas_dir/.tool-versions" ]; then
        log_error ".tool-versions file not found in Atlas repository"
        return 1
    fi
    
    cd "$atlas_dir" || return 1
    
    # Install Node.js version from .tool-versions
    log_step "Installing Node.js from .tool-versions"
    run_cmd_retry asdf install nodejs
    
    # Reshim
    asdf reshim nodejs
    
    if command_exists node; then
        log_info "Node.js installed successfully: $(node --version)"
        return 0
    else
        log_error "Node.js installation failed"
        return 1
    fi
}

# Install pnpm via asdf
install_pnpm() {
    log_step "Installing pnpm via asdf"
    
    # Source asdf
    source_asdf || return 1
    
    # Add pnpm plugin if not already added
    if ! asdf plugin list | grep -q "pnpm"; then
        log_step "Adding asdf pnpm plugin"
        run_cmd_retry asdf plugin add pnpm https://github.com/jonathanmorley/asdf-pnpm.git
    else
        log_skip "asdf pnpm plugin already added"
    fi
    
    local atlas_dir="${ATLAS_DIR:-$HOME/hashicorp/atlas}"
    cd "$atlas_dir" || return 1
    
    # Install pnpm version from .tool-versions
    log_step "Installing pnpm from .tool-versions"
    run_cmd_retry asdf install pnpm
    
    # Reshim
    asdf reshim pnpm
    
    if command_exists pnpm; then
        log_info "pnpm installed successfully: $(pnpm --version)"
        return 0
    else
        log_error "pnpm installation failed"
        return 1
    fi
}

# Install frontend dependencies
install_frontend_dependencies() {
    log_step "Installing frontend dependencies"
    
    local atlas_dir="${ATLAS_DIR:-$HOME/hashicorp/atlas}"
    local frontend_dir="$atlas_dir/frontend/atlas"
    
    if [ ! -d "$frontend_dir" ]; then
        log_error "Frontend directory not found: $frontend_dir"
        return 1
    fi
    
    cd "$frontend_dir" || return 1
    
    # Source asdf to ensure pnpm is available
    source_asdf || return 1
    
    # Check if node_modules already exists
    if [ -d "node_modules" ]; then
        log_skip "Frontend dependencies already installed"
        return 0
    fi
    
    run_cmd_retry pnpm install
    
    if [ -d "node_modules" ]; then
        log_info "Frontend dependencies installed successfully"
        return 0
    else
        log_error "Failed to install frontend dependencies"
        return 1
    fi
}

# Build frontend
build_frontend() {
    log_step "Building frontend"
    
    local atlas_dir="${ATLAS_DIR:-$HOME/hashicorp/atlas}"
    local frontend_dir="$atlas_dir/frontend/atlas"
    
    cd "$frontend_dir" || return 1
    
    # Source asdf
    source_asdf || return 1
    
    # Check if already built
    if [ -d "dist" ]; then
        log_skip "Frontend already built"
        return 0
    fi
    
    pnpm build
    
    if [ -d "dist" ]; then
        log_info "Frontend built successfully"
        return 0
    else
        log_error "Frontend build failed"
        return 1
    fi
}




# Validate frontend setup
validate_frontend() {
    log_step "Validating frontend setup"
    
    # Source asdf
    source_asdf || return 1
    
    local failed=0
    
    validate_command "node" "Node.js" || failed=1
    validate_command "pnpm" "pnpm" || failed=1
    
    local atlas_dir="${ATLAS_DIR:-$HOME/hashicorp/atlas}"
    local frontend_dir="$atlas_dir/frontend/atlas"
    
    validate_directory "$frontend_dir/node_modules" "Frontend dependencies" || failed=1
    
    if [ $failed -eq 0 ]; then
        log_info "Frontend validation passed"
        return 0
    else
        log_error "Frontend validation failed"
        return 1
    fi
}

# Run frontend phase
run_frontend_phase() {
    execute_phase "FRONTEND" \
        install_nodejs \
        install_pnpm \
        install_frontend_dependencies \
        build_frontend \
        validate_frontend
}


