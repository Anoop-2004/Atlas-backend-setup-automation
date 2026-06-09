#!/usr/bin/env bash
# Common utilities for setup automation

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# Logging functions
log_info() {
    echo -e "${GREEN}[✓]${RESET} $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" >> "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[⚠]${RESET} $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*" >> "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[✗]${RESET} $*" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >> "$LOG_FILE"
    show_recovery_options
}

# Show recovery options after error
show_recovery_options() {
    echo "" >&2
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}" >&2
    echo -e "${BOLD}${CYAN}Recovery Options:${RESET}" >&2
    echo "" >&2
    echo -e "  ${GREEN}•${RESET} To ${BOLD}resume${RESET} from where you left off:" >&2
    echo -e "    ${CYAN}./setup.sh${RESET}" >&2
    echo "" >&2
    echo -e "  ${GREEN}•${RESET} To ${BOLD}restart from scratch${RESET}:" >&2
    echo -e "    ${CYAN}./setup.sh --reset${RESET}" >&2
    echo "" >&2
    echo -e "  ${GREEN}•${RESET} To ${BOLD}check current status${RESET}:" >&2
    echo -e "    ${CYAN}./setup.sh --status${RESET}" >&2
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}" >&2
    echo "" >&2
}

log_step() {
    echo -e "${CYAN}[→]${RESET} $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] STEP: $*" >> "$LOG_FILE"
}

log_skip() {
    echo -e "${BLUE}[⊘]${RESET} $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SKIP: $*" >> "$LOG_FILE"
}

log_phase() {
    echo ""
    echo -e "${BOLD}${MAGENTA}============================================${RESET}"
    echo -e "${BOLD}${MAGENTA}  $*${RESET}"
    echo -e "${BOLD}${MAGENTA}============================================${RESET}"
    echo ""
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] PHASE: $*" >> "$LOG_FILE"
}

log_command() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] CMD: $*" >> "$LOG_FILE"
}

# User action prompt
prompt_user_action() {
    local message="$1"
    echo ""
    echo -e "${BOLD}${YELLOW}========================================${RESET}"
    echo -e "${BOLD}${YELLOW}  ⚠️  ACTION REQUIRED${RESET}"
    echo -e "${BOLD}${YELLOW}========================================${RESET}"
    echo ""
    echo -e "$message"
    echo ""
    echo -e "${YELLOW}Press ENTER when complete...${RESET}"
    read -r
}

# Execute command with logging
run_cmd() {
    local cmd="$*"
    log_command "$cmd"
    
    if eval "$cmd" >> "$LOG_FILE" 2>&1; then
        return 0
    else
        local exit_code=$?
        log_error "Command failed (exit code: $exit_code): $cmd"
        return $exit_code
    fi
}

# Execute command with retry
run_cmd_retry() {
    local max_attempts="${RETRY_COUNT:-3}"
    local delay="${RETRY_DELAY:-2}"
    local cmd="$*"
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log_command "$cmd (attempt $attempt/$max_attempts)"
        
        if eval "$cmd" 2>&1 | tee -a "$LOG_FILE"; then
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            log_warn "Attempt $attempt failed, retrying in ${delay}s..."
            sleep "$delay"
            delay=$((delay * 2))  # Exponential backoff
        fi
        
        attempt=$((attempt + 1))
    done
    
    echo -e "${RED}[✗]${RESET} Command failed after $max_attempts attempts: $cmd" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Command failed after $max_attempts attempts: $cmd" >> "$LOG_FILE"
    show_recovery_options
    return 1
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get command version
get_version() {
    local cmd="$1"
    local version_flag="${2:---version}"
    
    if command_exists "$cmd"; then
        $cmd $version_flag 2>&1 | head -n 1
    else
        echo "not installed"
    fi
}

# Check if file exists
file_exists() {
    [ -f "$1" ]
}

# Check if directory exists
dir_exists() {
    [ -d "$1" ]
}

# Ensure directory exists
ensure_dir() {
    local dir="$1"
    if ! dir_exists "$dir"; then
        mkdir -p "$dir"
    fi
}

# Die with error message
die() {
    echo -e "${RED}[✗]${RESET} $*" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >> "$LOG_FILE"
    show_recovery_options
    exit 1
}

# Handle script interruption (Ctrl+C)
handle_interrupt() {
    echo "" >&2
    echo "" >&2
    echo -e "${YELLOW}[⚠]${RESET} ${BOLD}Script interrupted by user${RESET}" >&2
    echo "" >&2
    echo -e "${GREEN}[✓]${RESET} Progress has been saved to checkpoint" >&2
    show_recovery_options
    exit 130
}

# Cleanup on exit
cleanup() {
    if [ -n "${CLEANUP_FUNC:-}" ]; then
        $CLEANUP_FUNC
    fi
}

trap cleanup EXIT
trap handle_interrupt SIGINT SIGTERM

# Initialize logging
init_logging() {
    local log_dir="${LOG_DIR:-./logs}"
    ensure_dir "$log_dir"
    export LOG_FILE="$log_dir/setup-$(date +%Y%m%d-%H%M%S).log"
    log_info "Logging initialized: $LOG_FILE"
}
