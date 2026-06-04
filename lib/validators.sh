#!/usr/bin/env bash
# Validation functions for checking prerequisites

# Validate command exists
validate_command() {
    local cmd="$1"
    local name="${2:-$cmd}"
    
    if command_exists "$cmd"; then
        local version
        version=$(get_version "$cmd" 2>/dev/null || echo "unknown")
        log_info "$name is installed ($version)"
        return 0
    else
        log_error "$name is not installed"
        return 1
    fi
}

# Validate file exists
validate_file() {
    local file="$1"
    local name="${2:-$file}"
    
    if file_exists "$file"; then
        log_info "$name exists"
        return 0
    else
        log_error "$name does not exist"
        return 1
    fi
}

# Validate directory exists
validate_directory() {
    local dir="$1"
    local name="${2:-$dir}"
    
    if dir_exists "$dir"; then
        log_info "$name exists"
        return 0
    else
        log_error "$name does not exist"
        return 1
    fi
}

# Validate Docker is running
validate_docker_running() {
    if docker info >/dev/null 2>&1; then
        log_info "Docker daemon is running"
        return 0
    else
        log_error "Docker daemon is not running"
        return 1
    fi
}

# Validate Homebrew tap
validate_brew_tap() {
    local tap="$1"
    
    if brew tap | grep -q "$tap"; then
        log_info "Homebrew tap $tap is installed"
        return 0
    else
        log_error "Homebrew tap $tap is not installed"
        return 1
    fi
}

# Validate git config
validate_git_config() {
    local key="$1"
    
    if git config --global "$key" >/dev/null 2>&1; then
        local value
        value=$(git config --global "$key")
        log_info "Git config $key is set: $value"
        return 0
    else
        log_error "Git config $key is not set"
        return 1
    fi
}

# Validate environment variable
validate_env_var() {
    local var="$1"
    
    if [ -n "${!var}" ]; then
        log_info "Environment variable $var is set"
        return 0
    else
        log_error "Environment variable $var is not set"
        return 1
    fi
}

# Validate port is available
validate_port_available() {
    local port="$1"
    
    if lsof -i ":$port" >/dev/null 2>&1; then
        log_error "Port $port is already in use"
        return 1
    else
        log_info "Port $port is available"
        return 0
    fi
}

# Validate all prerequisites for a phase
validate_prerequisites() {
    local phase="$1"
    shift
    local validators=("$@")
    
    log_step "Validating prerequisites for $phase"
    
    local failed=0
    for validator in "${validators[@]}"; do
        if ! $validator; then
            failed=1
        fi
    done
    
    if [ $failed -eq 0 ]; then
        log_info "All prerequisites validated for $phase"
        return 0
    else
        log_error "Some prerequisites failed for $phase"
        return 1
    fi
}

# Made with Bob
