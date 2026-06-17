#!/bin/bash
# =============================================================================
# Task Script: IMS Bank Deployment
# 
# This task script is called by pipeline-common.sh to deploy IMS Bank
# after DBB build completes.
#
# Usage: bash task-ims-deploy.sh
# =============================================================================

set -e

# =========================
# Source library scripts
# =========================
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPTS_DIR/config/setenv.sh"

# =========================
# Main Task
# =========================
main() {
    print_stage "Task: Deploy IMS Bank"
    
    # Call the IMS deployment script
    local deploy_script="$SCRIPTS_DIR/../scripts/deploy-ims-bank.sh"
    
    if [ ! -f "$deploy_script" ]; then
        print_error "IMS deployment script not found: $deploy_script"
        exit 1
    fi
    
    print_info "Executing IMS Bank deployment..."
    print_info "Script: $deploy_script"
    
    # Execute deployment script
    if bash "$deploy_script"; then
        print_success "IMS Bank deployment completed successfully"
        return 0
    else
        print_error "IMS Bank deployment failed"
        return 1
    fi
}

# Run main function
main "$@"

# Made with Bob