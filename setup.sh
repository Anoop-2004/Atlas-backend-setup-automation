#!/usr/bin/env bash
# HashiCorp Atlas Development Environment Setup
# Automated, resumable setup for macOS

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
export ATLAS_DIR="${ATLAS_DIR:-$HOME/hashicorp/atlas}"
export LOG_DIR="$SCRIPT_DIR/logs"
export STATE_FILE="$SCRIPT_DIR/state/checkpoint.json"
export RETRY_COUNT=3
export RETRY_DELAY=2

# Source libraries
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/checkpoint.sh"
source "$SCRIPT_DIR/lib/validators.sh"

# Source phase scripts
source "$SCRIPT_DIR/phases/00-bootstrap.sh"
source "$SCRIPT_DIR/phases/01-authentication.sh"
source "$SCRIPT_DIR/phases/02-repository.sh"
source "$SCRIPT_DIR/phases/03-backend.sh"
source "$SCRIPT_DIR/phases/04-frontend.sh"
source "$SCRIPT_DIR/phases/05-stack.sh"

# Print banner
print_banner() {
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   HashiCorp Atlas Development Environment Setup          ║
║   Automated Setup for macOS                              ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo ""
}

# Print usage
print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    --reset         Reset checkpoint and start from beginning
    --status        Show current setup status
    --help          Show this help message

Environment Variables:
    ATLAS_DIR       Atlas repository directory (default: ~/hashicorp/atlas)
    LOG_DIR         Log directory (default: ./logs)
    STATE_FILE      Checkpoint file (default: ./state/checkpoint.json)

Examples:
    # Start or resume setup
    ./setup.sh

    # Reset and start from beginning
    ./setup.sh --reset

    # Check current status
    ./setup.sh --status

EOF
}

# Parse arguments
RESET_CHECKPOINT=false
SHOW_STATUS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --reset)
            RESET_CHECKPOINT=true
            shift
            ;;
        --status)
            SHOW_STATUS=true
            shift
            ;;
        --help)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Initialize
init_logging
init_checkpoint

# Handle reset
if [ "$RESET_CHECKPOINT" = true ]; then
    log_warn "Resetting checkpoint..."
    reset_checkpoint
    
    # Clear IBM_EMAIL from environment to force re-prompt
    if [ -n "${IBM_EMAIL:-}" ]; then
        unset IBM_EMAIL
        log_info "Cleared IBM_EMAIL from current session"
    fi
    
    # Remove IBM_EMAIL from zshrc
    if grep -q '^export IBM_EMAIL=' ~/.zshrc 2>/dev/null; then
        sed -i.bak '/^export IBM_EMAIL=/d' ~/.zshrc
        rm -f ~/.zshrc.bak
        log_info "Removed IBM_EMAIL from ~/.zshrc"
    fi
    
    log_info "Checkpoint reset complete"
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}${CYAN}IMPORTANT:${RESET} To ensure a clean reset, please:"
    echo ""
    echo -e "  1. ${BOLD}Close this terminal${RESET} and open a new one"
    echo -e "     ${DIM}(This ensures IBM_EMAIL is not cached in your shell)${RESET}"
    echo ""
    echo -e "  2. Run the setup again:"
    echo -e "     ${CYAN}./setup.sh${RESET}"
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
    exit 0
fi

# Handle status
if [ "$SHOW_STATUS" = true ]; then
    show_checkpoint_summary
    exit 0
fi

# Main setup function
main() {
    print_banner
    
    log_info "Starting HashiCorp Atlas development environment setup"
    log_info "Atlas directory: $ATLAS_DIR"
    log_info "Log file: $LOG_FILE"
    log_info "Checkpoint file: $STATE_FILE"
    echo ""
    
    # Show current status
    show_checkpoint_summary
    
    # Display prerequisites
    prompt_user_action "PREREQUISITES:\n\n  • User should have an Okta account. This can be obtained by \n requesting access to 'Hashicorp Okta' and 'Hashicorp Okta Certificate' in IBM Access Hub.\n\n  • Request pull access to artifactory-users group which will also add\n    the Artifactory tile to Okta:\n    https://doormat.hashicorp.services/applications/access/artifactory/role/doormat-artifactory-users/options\n\n  • User should have a Github account and have access to the\n    HashiCorp organization\n\n${BOLD}Please ensure all prerequisites are met before continuing.\n Note: Please wait for 2-3 hours once all prerequisites are completed and rerun the script. ${RESET}"
    
    # Phase 0: Bootstrap
    run_bootstrap_phase || die "Bootstrap phase failed"
    
    # Phase 1: Authentication
    run_authentication_phase || die "Authentication phase failed"
    
    # Phase 2: Repository
    
    run_repository_phase || die "Repository phase failed"
    
    # Phase 3: Backend
    run_backend_phase || die "Backend phase failed"
    
    # Phase 4: Frontend
    run_frontend_phase || die "Frontend phase failed"

    # Phase 5: Stack
    run_stack_phase || die "Stack phase failed"
    
    # Setup complete
    log_phase "SETUP COMPLETE"
    
    # Get the reserved tfcdev domain
    local backend_url="http://localhost:21080"
    if command_exists tfcdev; then
        local domain_output
        # Run tfcdev domain reserve to get the domain (it will return existing if already reserved)
        domain_output=$(tfcdev domain reserve 2>&1 | grep -o "domain=[^ ]*" | cut -d= -f2 || true)
        if [ -n "$domain_output" ] && [ "$domain_output" != "" ]; then
            backend_url="https://$domain_output"
        fi
    fi
    
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}║                                                           ║${RESET}"
    echo -e "${GREEN}║   ✓ Setup Complete!                                      ║${RESET}"
    echo -e "${GREEN}║                                                           ║${RESET}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    open "$backend_url"
    echo -e "${BOLD}Next Steps:${RESET}"
    echo ""
    echo -e "1. Backend is running at: ${CYAN}${backend_url}${RESET}\n Login using the following:\n Username: admin \n Password: password123"
    echo ""
    echo -e "2. To stop the backend:"
    echo -e "   ${CYAN}cd $ATLAS_DIR${RESET}"
    echo -e "   ${CYAN}tfcdev stack down${RESET}"
    echo ""
    echo -e "3. To view logs:"
    echo -e "   ${CYAN}cd $ATLAS_DIR${RESET}"
    echo -e "   ${CYAN}docker compose logs -f${RESET}"
    echo ""
    echo -e "4. (OPTIONAL)For RubyMine setup, do the following:"
    echo ""
    echo -e "   ${BOLD}RSpec Configuration:${RESET}"
    echo -e "   • Open Run/Debug Configurations and remove existing runs"
    echo -e "   • Open 'Edit configuration templates…'"
    echo -e "   • Navigate to RSpec and add these environment variables:"
    echo ""
    echo -e "     DATABASE_URL=postgres://hashicorp:hashicorp@localhost:25432/hashicorp"
    echo -e "     REDIS_URL=redis://localhost:26379"
    echo -e "     TEST_DATABASE_URL=postgres://hashicorp:hashicorp@localhost:25432/hashicorp_test"
    echo -e "     PGPORT=25432"
    echo -e "     TEST_REDIS_URL=redis://localhost:26379"
    echo -e "     VAULT_ADDR=http://127.0.0.1:28200"
    echo -e "     VAULT_APP=atlas_development"
    echo -e "     VAULT_TOKEN=atlas"
    echo ""
    echo -e "${BOLD}Useful Commands:${RESET}"
    echo ""
    echo -e "  • Check setup status:     ${CYAN}./setup.sh --status${RESET}"
    echo -e "  • View logs:              ${CYAN}cat $LOG_FILE${RESET}"
    echo -e "  • Reset and restart:      ${CYAN}./setup.sh --reset${RESET}"
    echo ""
    echo -e "${GREEN}Happy coding! 🚀${RESET}"
    echo ""
}

# Run main function
main

exit 0

# Made with Bob
