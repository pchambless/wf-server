#!/bin/bash
################################################################################
# prod_deploy.sh - Deploy wf-server and restart it on the production droplet
#
# This script:
# - Pulls latest code from main branch
# - Installs/updates dependencies
# - Restarts the wf-server systemd service
# - Verifies it's running
#
# Does NOT touch n8n. n8n has its own separate lifecycle on this droplet -
# it is not part of a wf-server code deploy. An earlier version of this
# script did a docker rm/recreate of the n8n container using a data path and
# networking mode that did not match how n8n was actually provisioned here
# (host networking, no port mapping) - running it would have wiped a working
# n8n instance. Removed 2026-08-12 rather than fixed, since wf-server deploys
# and n8n's lifecycle have no reason to be coupled.
#
# Prerequisites:
# - Already provisioned with provision.sh
# - SSH key configured for GitHub
# - .env file exists with correct secrets
#
# Usage:
#   bash /root/wf-server/scripts/production/prod_deploy.sh
#   or from dev machine:
#   ssh root@<prod-ip> 'bash /root/wf-server/scripts/production/prod_deploy.sh'
#
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

# Configuration
WF_SERVER_DIR="/root/wf-server"

################################################################################
# Check prerequisites
################################################################################
log_section "Checking prerequisites"

if [ ! -d "$WF_SERVER_DIR" ]; then
    log_error "wf-server directory not found at $WF_SERVER_DIR"
    exit 1
fi

if [ ! -f "$WF_SERVER_DIR/.env" ]; then
    log_error ".env file not found at $WF_SERVER_DIR/.env"
    exit 1
fi

log_info "wf-server directory: ✓"
log_info ".env file: ✓"

################################################################################
# 1. Pull latest code
################################################################################
log_section "Pulling latest code from GitHub"

cd "$WF_SERVER_DIR"
git fetch origin
git checkout main
git pull origin main

log_info "Code updated to latest main branch"

################################################################################
# 2. Install/update dependencies
################################################################################
log_section "Installing dependencies"

npm install --production

log_info "Dependencies installed"

################################################################################
# 3. Restart wf-server
################################################################################
log_section "Restarting wf-server"

systemctl restart wf-server
sleep 3

if systemctl is-active --quiet wf-server; then
    log_info "wf-server started successfully"
else
    log_error "Failed to start wf-server"
    systemctl status wf-server
    exit 1
fi

################################################################################
# 4. Verify wf-server is healthy
################################################################################
log_section "Verifying wf-server"

if curl -f http://localhost:3001/health > /dev/null 2>&1; then
    log_info "wf-server health check: ✓"
else
    log_warn "wf-server health check failed (may still be starting)"
fi

################################################################################
# 5. Summary
################################################################################
log_section "Deployment complete!"

systemctl status wf-server --no-pager | grep -E "Active|Loaded" || true

log_info ""
log_info "Logs: journalctl -u wf-server -f"
log_info "URL:  https://v2.whatsfresh.app"
log_info ""
