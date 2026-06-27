#!/bin/bash
# Deploy wf-server: pull latest, restart server, sync git history
# Run on the droplet: bash /home/n8n/wf-server/scripts/deploy.sh

set -e

REPO_DIR="/home/n8n/wf-server"
LOG_FILE="/home/n8n/wf-server/logs/deploy.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

cd "$REPO_DIR" || exit 1

log "=== Starting deploy ==="

# 1. Pull latest from main
log "Pulling latest from origin/main..."
git pull origin main 2>&1 | tee -a "$LOG_FILE"

# 2. Install any new dependencies
if git diff HEAD~1 --name-only | grep -q "package.json"; then
  log "package.json changed — running npm install..."
  npm install --production 2>&1 | tee -a "$LOG_FILE"
fi

# 3. Restart server
log "Restarting wf-server..."
SERVER_PID=$(pgrep -f "node /home/n8n/wf-server/src/server.js" || true)
if [ -n "$SERVER_PID" ]; then
  log "Killing existing server (PID: $SERVER_PID)..."
  kill "$SERVER_PID"
  sleep 2
fi

nohup node /home/n8n/wf-server/src/server.js >> "$LOG_FILE" 2>&1 &
NEW_PID=$!
log "Server started (PID: $NEW_PID)"

# 4. Sync git commits to studio tables
log "Syncing git commits to database..."
bash "$REPO_DIR/scripts/sync-git-commits.sh" 2>&1 | tee -a "$LOG_FILE"

log "=== Deploy complete ==="
