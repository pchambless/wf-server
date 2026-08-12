#!/bin/bash
################################################################################
# provision.sh - Provision the V2 production droplet (wf-v2-prod)
#
# Verified against dev (159.223.104.19, TMG-and-WF) 2026-08-09/10 by reading
# what actually runs there, not by assumption. Installs:
#   - Caddy (reverse proxy)
#   - Docker (for n8n)
#   - Node.js 20.x + PM2 (for wf-server - dev's systemd unit was never
#     actually used; PM2 is the real, proven pattern)
#   - PostgreSQL 16 via the official PGDG repo, extensions: dblink, pgcrypto
#     (mysql_fdw and git_fdw exist on dev but are dev-only tooling / an
#     abandoned experiment - not installed here)
#   - n8n via Docker, pinned to n8nio/n8n:2.30.5 (dev's actual running
#     version, not :latest - a fresh box should match what's proven, not
#     whatever's newest today)
#
# NOT installed: the @wf/custom-nodes package (WfDbQuery). It's saved at
# wf-agents/n8n/custom-nodes/n8n-nodes-whatsfresh for reference, but as of
# 2026-08-10 every n8n workflow that references it (9 of them) is inactive -
# it has zero live consumers. Not worth shipping to a fresh prod box. If a
# workflow starts depending on it again, add it back deliberately then.
#
# Domains (create DNS A records to this droplet's IP AFTER creation - the
# IP doesn't exist yet at provisioning time):
#   v2.whatsfresh.app       -> wf-server (port 3001)
#   v2-n8n.whatsfresh.app   -> n8n (port 5678)
#
# Deliberately NOT done here (see bottom-of-script summary):
#   - wf-server/.env and n8n's own secrets - created manually, never in git
#   - the dev-side dblink foreign server + user mapping pointing AT this
#     box - that's configured on dev, not here, once this box has an IP
#   - actual database/schema/table deploy - that's deployment.f_p02_structure
#     / f_p03_data, run against this box as a target once it exists
#
# Run as root via DigitalOcean user_data at droplet creation time.
################################################################################

set -e

# Unattended under cloud-init: no TTY exists to answer prompts. DEBIAN_FRONTEND
# suppresses debconf dialogs (timezone, postfix-style config, etc), but conffile
# conflicts ("keep your version or the maintainer's?") are a SEPARATE dpkg-level
# prompt that DEBIAN_FRONTEND alone does NOT suppress - dpkg will block on stdin
# forever without --force-confdef/--force-confold too. A fresh cloud image's
# first full upgrade is exactly where this bites, most often on openssh-server's
# own config, which can leave sshd itself unreachable while the script hangs.
export DEBIAN_FRONTEND=noninteractive
APT_CONF_FLAGS='-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold'

log_info()  { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_warn()  { echo -e "\033[1;33m[WARN]\033[0m $1"; }

################################################################################
# 1. System updates
################################################################################
log_info "Updating system packages..."
apt-get update
apt-get $APT_CONF_FLAGS upgrade -y
apt-get $APT_CONF_FLAGS install -y curl wget git build-essential ca-certificates gnupg lsb-release ufw

################################################################################
# 2. Caddy
# https://caddyserver.com/docs/install#debian-ubuntu-raspbian (verified 2026-08-10)
################################################################################
log_info "Installing Caddy..."
apt-get $APT_CONF_FLAGS install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
  | tee /etc/apt/sources.list.d/caddy-stable.list
chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg
chmod o+r /etc/apt/sources.list.d/caddy-stable.list
apt-get update
apt-get $APT_CONF_FLAGS install -y caddy

log_info "Writing Caddyfile (app + n8n only - no marketing routing yet)..."
cat > /etc/caddy/Caddyfile << 'EOF'
v2.whatsfresh.app {
    reverse_proxy localhost:3001 {
        flush_interval -1
    }
}

v2-n8n.whatsfresh.app {
    reverse_proxy localhost:5678 {
        flush_interval -1
    }
}
EOF
systemctl reload caddy || systemctl restart caddy
log_info "Caddy configured"

################################################################################
# 3. Docker
################################################################################
log_info "Installing Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get $APT_CONF_FLAGS install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable docker
systemctl start docker

################################################################################
# 4. Node.js 20.x + PM2
################################################################################
log_info "Installing Node.js 20.x..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get $APT_CONF_FLAGS install -y nodejs
npm install -g pm2

################################################################################
# 5. PostgreSQL 16 via PGDG
# https://www.postgresql.org/download/linux/ubuntu/ (verified 2026-08-10)
################################################################################
log_info "Installing PostgreSQL 16 via PGDG..."
apt-get $APT_CONF_FLAGS install -y postgresql-common
# yes| as a safety net: this runs unattended under cloud-init with no TTY -
# if -y isn't honored for some reason, an unanswered prompt would hang
# provisioning forever rather than fail loudly.
yes | /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y
apt-get update
apt-get $APT_CONF_FLAGS install -y postgresql-16
systemctl enable postgresql
systemctl start postgresql

log_info "Creating wf_admin role, n8n database, extensions..."
WF_ADMIN_PASSWORD=$(openssl rand -base64 24)
echo "$WF_ADMIN_PASSWORD" > /root/.wf_admin_pgpassword
chmod 600 /root/.wf_admin_pgpassword

# Built as a plain bash string, not a heredoc: a quoted heredoc can't expand
# $WF_ADMIN_PASSWORD, an unquoted one mangles the DO block's $$ delimiter
# (bash reads it as $$ = PID). \$body\$ is escaped so bash leaves it alone;
# $WF_ADMIN_PASSWORD is left unescaped so bash substitutes it before psql
# ever sees the string.
ROLE_SQL="DO \$body\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'wf_admin') THEN
        CREATE ROLE wf_admin WITH LOGIN PASSWORD '${WF_ADMIN_PASSWORD}';
    END IF;
END
\$body\$;"
echo "$ROLE_SQL" | sudo -u postgres psql

sudo -u postgres psql << 'PSQL'
SELECT 'CREATE DATABASE n8n OWNER wf_admin'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'n8n')\gexec
PSQL

sudo -u postgres psql -d n8n << 'PSQL'
CREATE EXTENSION IF NOT EXISTS dblink;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS studio AUTHORIZATION wf_admin;
CREATE SCHEMA IF NOT EXISTS whatsfresh AUTHORIZATION wf_admin;
PSQL

log_info "wf_admin password written to /root/.wf_admin_pgpassword (600, root-only, never logged)"

################################################################################
# 6. Postgres network isolation - private VPC only, never public
################################################################################
log_info "Restricting Postgres to localhost + private VPC interface..."
PRIVATE_IP=$(curl -s http://169.254.169.254/metadata/v1/interfaces/private/0/ipv4/address || true)
PG_CONF=$(sudo -u postgres psql -tAc "SHOW config_file")
PG_HBA=$(sudo -u postgres psql -tAc "SHOW hba_file")

if [ -n "$PRIVATE_IP" ]; then
    sed -i "s/^#\?listen_addresses.*/listen_addresses = 'localhost,${PRIVATE_IP}'/" "$PG_CONF"
    # dev's private IP (TMG-and-WF, same VPC) - the only host allowed to
    # reach in over the network, and only over the private interface.
    echo "host    n8n    wf_admin    10.136.0.2/32    scram-sha-256" >> "$PG_HBA"
    log_info "Postgres will listen on localhost + ${PRIVATE_IP}, accepting wf_admin only from dev's private IP"
else
    log_warn "Could not read private IP from metadata service - Postgres left on localhost only. Fix pg_hba/listen_addresses manually before the dev-side dblink foreign server will connect."
fi
systemctl restart postgresql

################################################################################
# 7. Service user + directories
################################################################################
log_info "Creating n8n service user..."
if id -u n8n > /dev/null 2>&1; then
    log_warn "n8n user already exists"
else
    useradd -m -s /bin/bash -G docker n8n
fi

mkdir -p /home/n8n/n8n_data
mkdir -p /home/n8n/wf-server
chown -R n8n:n8n /home/n8n

################################################################################
# 8. n8n via Docker (pinned version, host networking - matches dev)
################################################################################
log_info "Starting n8n container (pinned n8nio/n8n:2.30.5)..."
docker run -d \
  --name n8n \
  --network host \
  --restart unless-stopped \
  -v /home/n8n/n8n_data:/data \
  -e DB_TYPE=postgresdb \
  -e DB_POSTGRESDB_HOST=127.0.0.1 \
  -e DB_POSTGRESDB_PORT=5432 \
  -e DB_POSTGRESDB_DATABASE=n8n \
  -e DB_POSTGRESDB_USER=wf_admin \
  -e DB_POSTGRESDB_PASSWORD="$WF_ADMIN_PASSWORD" \
  -e N8N_HOST=v2-n8n.whatsfresh.app \
  -e N8N_PROTOCOL=https \
  -e N8N_PORT=5678 \
  -e WEBHOOK_URL=https://v2-n8n.whatsfresh.app/ \
  -e N8N_EDITOR_BASE_URL=https://v2-n8n.whatsfresh.app/ \
  -e N8N_TRUST_PROXY=true \
  -e N8N_PROXY_HOPS=1 \
  -e N8N_SECURE_COOKIE=false \
  -e N8N_PUSH_BACKEND=sse \
  -e N8N_ALLOWED_PUSH_ORIGINS=* \
  -e N8N_USER_FOLDER=/data \
  -e N8N_LOG_LEVEL=warn \
  -e N8N_LOG_OUTPUT=console,file \
  -e N8N_LOG_FILE_LOCATION=/data/logs/n8n.log \
  -e N8N_LOG_FILE_MAX_SIZE=10 \
  -e N8N_LOG_FILE_MAX_COUNT=3 \
  -e N8N_ENABLE_COMMANDS=true \
  -e N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true \
  -e TZ=America/Chicago \
  n8nio/n8n:2.30.5

log_info "n8n started without @wf/custom-nodes (WfDbQuery) - unused by any active workflow as of 2026-08-10."
log_info "Source is at wf-agents/n8n/custom-nodes/n8n-nodes-whatsfresh if it's ever needed again."

################################################################################
# 9. Firewall - only 22/80/443 from the public internet
################################################################################
log_info "Configuring UFW..."
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
# UFW's default-deny-incoming applies to EVERY interface, including the
# private VPC one - it is a lower, separate layer from postgresql.conf's
# listen_addresses/pg_hba. Restricting Postgres at the pg_hba level (above)
# does nothing if UFW drops the packets before they ever reach it. Proven
# by a direct nc/dblink test timing out even though pg_hba and
# listen_addresses were both already correct. Same scope as the pg_hba
# rule above: only dev's private IP, only port 5432.
ufw allow from 10.136.0.2 to any port 5432 proto tcp
# 5678 (n8n, host networking) is intentionally NOT opened - it is only
# reachable through Caddy's reverse proxy.

################################################################################
# 10. Summary
################################################################################
log_info "================================"
log_info "Provisioning complete!"
log_info "================================"
log_info ""
log_info "NOT done by this script - do these next, in order:"
log_info "1. Create DNS A records -> this droplet's public IP:"
log_info "     v2.whatsfresh.app"
log_info "     v2-n8n.whatsfresh.app"
log_info "2. On DEV's postgres: create a dblink_fdw foreign server + user"
log_info "   mapping pointing at this box's private IP, using the password"
log_info "   in /root/.wf_admin_pgpassword (fetch it, then delete the copy"
log_info "   from the transport once dev's user mapping is set)."
log_info "3. Clone wf-server, create its .env (never from a script/git),"
log_info "   and start it under PM2 as the n8n user:"
log_info "     su - n8n -c 'cd /home/n8n/wf-server && pm2 start src/server.js --name wf-server --interpreter-args=--env-file=.env'"
log_info "     pm2 startup && pm2 save"
log_info "4. Run deployment.f_p02_structure then f_p03_data against this"
log_info "   environment once deployment.environments has a row for it."
log_info ""
