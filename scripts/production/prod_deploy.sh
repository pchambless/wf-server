#!/bin/bash
################################################################################
# prod_deploy.sh - Deploy wf-server and restart services on production droplet
#
# This script:
# - Pulls latest code from main branch
# - Installs/updates dependencies
# - Restarts wf-server service
# - Restarts N8n container
# - Verifies services are running
#
# Prerequisites:
# - Already provisioned with provision.sh
# - SSH key configured for GitHub
# - .env file exists with correct secrets
# - PostgreSQL database initialized
#
# Usage:
#   bash /home/deploy/prod_deploy.sh
#   or from dev machine:
#   ssh deploy@v2.whatsfresh.app 'bash /home/deploy/prod_deploy.sh'
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
WF_SERVER_DIR="/home/deploy/wf-server"
N8N_DATA_DIR="/home/deploy/n8n_data"
LOG_FILE="/var/log/wf-server.log"

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
# 3. Stop current services
################################################################################
log_section "Stopping services"

log_info "Stopping wf-server..."
systemctl stop wf-server || true

log_info "Stopping N8n container..."
docker stop n8n || true

log_info "Services stopped"

################################################################################
# 4. Start N8n container
################################################################################
log_section "Starting N8n container"

log_info "Removing old N8n container..."
docker rm n8n || true

log_info "Starting new N8n container..."
docker run -d \
  --name n8n \
  --restart unless-stopped \
  -p 127.0.0.1:5678:5678 \
  -e NODE_ENV=production \
  -e N8N_HOST=n8n.whatsfresh.app \
  -e N8N_PROTOCOL=https \
  -e N8N_PORT=5678 \
  -e N8N_SECURE_COOKIE=true \
  -v "$N8N_DATA_DIR:/home/node/.n8n" \
  n8nio/n8n:latest

sleep 5

if docker ps | grep -q n8n; then
    log_info "N8n container started successfully"
else
    log_error "Failed to start N8n container"
    exit 1
fi

################################################################################
# 5. Start wf-server service
################################################################################
log_section "Starting wf-server"

systemctl start wf-server
sleep 3

if systemctl is-active --quiet wf-server; then
    log_info "wf-server started successfully"
else
    log_error "Failed to start wf-server"
    systemctl status wf-server
    exit 1
fi

################################################################################
# 6. Verify services are healthy
################################################################################
log_section "Verifying services"

log_info "Checking wf-server..."
if curl -f http://localhost:3001/health > /dev/null 2>&1; then
    log_info "wf-server health check: ✓"
else
    log_warn "wf-server health check failed (may still be starting)"
fi

log_info "Checking N8n..."
if curl -f http://localhost:5678 > /dev/null 2>&1; then
    log_info "N8n health check: ✓"
else
    log_warn "N8n health check failed (may still be starting)"
fi

################################################################################
# 7. Summary
################################################################################
log_section "Deployment complete!"

log_info "Services status:"
systemctl status wf-server --no-pager | grep -E "Active|Loaded" || true
docker ps | grep -E "n8n|CONTAINER" || true

log_info ""
log_info "Logs:"
log_info "  wf-server: journalctl -u wf-server -f"
log_info "  N8n: docker logs -f n8n"
log_info ""
log_info "URLs:"
log_info "  v2.whatsfresh.app: https://v2.whatsfresh.app"
log_info "  n8n.whatsfresh.app: https://n8n.whatsfresh.app"
log_info ""
