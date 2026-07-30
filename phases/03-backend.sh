#!/usr/bin/env bash
# Phase 3: Backend Setup - Build and start Atlas backend

# Setup Bundler Artifactory authentication
setup_bundler_artifactory() {
    log_step "Setting up Bundler Artifactory authentication"
    
    # Try tfcdev env artifactory first
    local tfcdev_output
    tfcdev_output=$(tfcdev env artifactory 2>&1)
    local tfcdev_exit_code=$?
    
    if [ $tfcdev_exit_code -eq 0 ] && [ -n "$tfcdev_output" ]; then
        # Evaluate the output to set environment variables
        if eval "$tfcdev_output" 2>/dev/null; then
            log_info "Bundler Artifactory configured via tfcdev"
            return 0
        fi
    fi
    
    # Fallback to manual configuration
    log_warn "tfcdev env artifactory failed or returned empty, falling back to manual configuration"
    log_step "Configuring Bundler Artifactory manually"
    
    # Get IBM email from environment
    local email="${IBM_EMAIL:-}"
    
    # Validate email is set
    if [ -z "$email" ]; then
        log_error "IBM_EMAIL environment variable is not set"
        return 1
    fi
    
    log_info "Using email: $email"
    
    local token
    token=$(doormat login && doormat artifactory create-token | jq -r '.access_token')
    
    if [ -z "$token" ] || [ "$token" = "null" ]; then
        log_error "Failed to get Doormat token for Bundler"
        return 1
    fi
    
    # URL encode the email (replace @ with %40)
    local encoded_email="${email/@/%40}"
    export BUNDLE_ARTIFACTORY__HASHICORP__ENGINEERING="${encoded_email}:${token}"
    
    log_info "Bundler Artifactory configured"
    return 0
}

# Setup tfcdev environment
setup_tfcdev_env() {
    log_step "Setting up tfcdev environment"
    
    local atlas_dir="${ATLAS_DIR:-$HOME/hashicorp/atlas}"
    
    if [ ! -d "$atlas_dir" ]; then
        log_error "Atlas directory not found: $atlas_dir"
        return 1
    fi
    
    cd "$atlas_dir" || return 1
    
    # Source tfcdev environment
    eval "$(tfcdev env)"
    
    log_info "tfcdev environment configured"
    return 0
}

# Build Docker containers
build_docker_containers() {
    log_step "Building Docker containers"
    
    local atlas_dir="${ATLAS_DIR:-$HOME/hashicorp/atlas}"
    cd "$atlas_dir" || return 1
    
    # Check if already built
    if docker compose ps 2>/dev/null | grep -q "Up"; then
        log_skip "Docker containers already running"
        return 0
    fi
    
    eval "$(tfcdev env)"
    
    run_cmd_retry docker compose build
    
    log_info "Docker containers built successfully"
    return 0
}

# Start Docker containers
start_docker_containers() {
    log_step "Starting Docker containers"
    
    local atlas_dir="${ATLAS_DIR:-$HOME/hashicorp/atlas}"
    log_info "atlas_dir = $atlas_dir"                                  
    cd "$atlas_dir" || return 1
    
    eval "$(tfcdev env)"
    
    # Start containers and wait for them to be healthy
    run_cmd_retry docker compose up -d --wait
    
    if [ $? -eq 0 ]; then
        log_info "Docker containers started successfully"
        return 0
    else
        log_error "Failed to start Docker containers"
        
        # Show logs for debugging
        log_step "Showing container logs for debugging:"
        log_command "docker compose logs --tail=50"
        docker compose logs --tail=50 2>&1 | tee -a "$LOG_FILE"
        
        return 1
    fi
}

# Validate backend health
validate_backend_health() {
    log_step "Validating backend health"
    
    local atlas_dir="${ATLAS_DIR:-$HOME/hashicorp/atlas}"
    cd "$atlas_dir" || return 1
    
    # Give containers a moment to stabilize after docker compose up --wait
    sleep 3
    
    # Check if containers are running with more detailed output
    log_step "Checking container status"
    local container_status
    container_status=$(docker compose ps --format json 2>/dev/null)
    
    if [ -z "$container_status" ]; then
        log_error "No containers found"
        log_step "Showing docker compose ps output:"
        docker compose ps
        return 1
    fi
    
    # Count running containers
    local running_count
    running_count=$(echo "$container_status" | jq -r 'select(.State == "running") | .Name' 2>/dev/null | wc -l | tr -d ' ')
    
    if [ "$running_count" -eq 0 ]; then
        log_error "No containers are in running state"
        log_step "Container status:"
        docker compose ps
        log_step "Recent container logs:"
        docker compose logs --tail=50
        return 1
    fi
    
    log_info "Found $running_count running container(s)"
    
    # Check if API is accessible
    local max_attempts=30
    local attempt=1
    
    log_step "Waiting for backend API to become accessible"
    while [ $attempt -le $max_attempts ]; do
        if curl -sf http://localhost:21080/api/v2/ping >/dev/null 2>&1; then
            log_info "Backend API is accessible at http://localhost:21080"
            return 0
        fi
        
        # Check if containers are still running
        local current_running
        current_running=$(docker compose ps --format json 2>/dev/null | jq -r 'select(.State == "running") | .Name' 2>/dev/null | wc -l | tr -d ' ')
        
        if [ "$current_running" -eq 0 ]; then
            log_error "Containers stopped running during health check"
            log_step "Container status:"
            docker compose ps
            log_step "Recent container logs:"
            docker compose logs --tail=100
            return 1
        fi
        
        echo -n "."
        sleep 2
        attempt=$((attempt + 1))
    done
    echo ""
    
    log_error "Backend API did not become accessible after $max_attempts attempts"
    log_step "Final container status:"
    docker compose ps
    log_step "Recent container logs:"
    docker compose logs --tail=100
    return 1
}

# Show backend status
show_backend_status() {
    log_step "Backend status"
    
    local atlas_dir="${ATLAS_DIR:-$HOME/hashicorp/atlas}"
    cd "$atlas_dir" || return 1
    
    echo ""
    docker compose ps
    echo ""
    
    log_info "Backend is running at http://localhost:21080"
    return 0
}

# Run backend phase
run_backend_phase() {
    execute_phase "BACKEND" \
        setup_bundler_artifactory \
        setup_tfcdev_env \
        build_docker_containers \
        start_docker_containers \
        validate_backend_health \
        show_backend_status
}

