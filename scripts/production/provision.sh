#!/bin/bash
################################################################################
# provision.sh - Provision a fresh Ubuntu 20.04 droplet for v2.whatsfresh.app
#
# This script sets up a production-ready droplet with:
# - Caddy (reverse proxy)
# - Docker + containerd (for N8n)
# - Node.js 20.x (for wf-server)
# - PostgreSQL 12 (database)
# - Firewall rules
# - Systemd services
#
# Prerequisites:
# - Fresh Ubuntu 20.04 droplet
# - Root access or sudo privileges
# - SSH key for GitHub access (to be added to deploy user)
#
# Usage:
#   sudo bash provision.sh
#
################################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

################################################################################
# 1. System Updates
################################################################################
log_info "Updating system packages..."
apt-get update
apt-get upgrade -y
apt-get install -y curl wget git build-essential

################################################################################
# 2. Install Caddy
################################################################################
log_info "Installing Caddy..."
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.caddy.community/api/v1/repos/caddy/caddy/releases/download?os=linux&arch=amd64' | bash
apt-get install caddy -y
log_info "Caddy installed. Version:"
caddy version

################################################################################
# 3. Install Docker
################################################################################
log_info "Installing Docker..."
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable docker
systemctl start docker
log_info "Docker installed. Version:"
docker --version

################################################################################
# 4. Install Node.js 20.x
################################################################################
log_info "Installing Node.js 20.x..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs
log_info "Node.js installed. Version:"
node --version
npm --version

################################################################################
# 5. Install PostgreSQL 12
################################################################################
log_info "Installing PostgreSQL 12..."
apt-get install -y postgresql postgresql-contrib
systemctl enable postgresql
systemctl start postgresql
log_info "PostgreSQL installed and started"

################################################################################
# 6. Create deploy user
################################################################################
log_info "Creating deploy user..."
if id -u deploy > /dev/null 2>&1; then
    log_warn "Deploy user already exists"
else
    useradd -m -s /bin/bash -G docker deploy
    log_info "Deploy user created"
fi

################################################################################
# 7. Setup SSH for deploy user
################################################################################
log_info "Setting up SSH for deploy user..."
mkdir -p /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
log_warn "IMPORTANT: Add your GitHub SSH public key to /home/deploy/.ssh/authorized_keys"
log_warn "IMPORTANT: Add GitHub deploy key to /home/deploy/.ssh/id_rsa (for wf-server repo)"
chown -R deploy:deploy /home/deploy/.ssh

################################################################################
# 8. Configure Caddy
################################################################################
log_info "Configuring Caddy..."
cat > /etc/caddy/Caddyfile << 'EOF'
# v2.whatsfresh.app production configuration

v2.whatsfresh.app {
    reverse_proxy localhost:3001 {
        flush_interval -1
    }
}

n8n.whatsfresh.app {
    reverse_proxy localhost:5678 {
        flush_interval -1
    }
}

# Redirect www to non-www (optional)
www.v2.whatsfresh.app {
    redir https://v2.whatsfresh.app{uri}
}
EOF
systemctl reload caddy
log_info "Caddy configured"

################################################################################
# 9. Create wf-server systemd service
################################################################################
log_info "Creating wf-server systemd service..."
cat > /etc/systemd/system/wf-server.service << 'EOF'
[Unit]
Description=WF Server (v2.whatsfresh.app)
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=deploy
WorkingDirectory=/home/deploy/wf-server
Environment="NODE_ENV=production"
EnvironmentFile=/home/deploy/wf-server/.env
ExecStart=/usr/bin/node src/server.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
StandardOutput=append:/var/log/wf-server.log
StandardError=append:/var/log/wf-server.log

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
log_info "wf-server service created (not started yet)"

################################################################################
# 10. Setup N8n Docker directories
################################################################################
log_info "Creating N8n Docker setup..."
mkdir -p /home/deploy/n8n_data
mkdir -p /home/deploy/docker
chown -R deploy:deploy /home/deploy/n8n_data /home/deploy/docker
log_info "N8n directories created"

################################################################################
# 11. Configure Firewall (UFW)
################################################################################
log_info "Configuring UFW firewall..."
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
log_info "Firewall configured"

################################################################################
# 12. Create application directories
################################################################################
log_info "Creating application directories..."
mkdir -p /home/deploy/wf-server
mkdir -p /var/log
touch /var/log/wf-server.log
chown deploy:deploy /var/log/wf-server.log /home/deploy/wf-server
log_info "Application directories created"

################################################################################
# 13. Summary
################################################################################
log_info "================================"
log_info "Provisioning complete!"
log_info "================================"
log_info ""
log_info "Next steps (manual - run prod_deploy.sh):"
log_info "1. Copy SSH keys to /home/deploy/.ssh/"
log_info "2. Clone wf-server repo"
log_info "3. Create .env file"
log_info "4. Initialize PostgreSQL database"
log_info "5. Start services"
log_info ""
log_info "Run: bash /home/deploy/prod_deploy.sh"
log_info ""
log_info "Or manually:"
log_info "  - Caddy: systemctl status caddy"
log_info "  - PostgreSQL: systemctl status postgresql"
log_info "  - wf-server: systemctl status wf-server"
log_info "  - Docker/N8n: docker ps"
log_info ""
