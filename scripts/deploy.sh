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
# $SERVER_PIDS may hold SEVERAL newline-separated pids. It was previously quoted
# as kill "$SERVER_PID", which passes them as ONE argument and fails with
# "arguments must be process or job IDs" the moment a second process exists.
# The old process kept the port, the new one died unable to bind, and the deploy
# still reported success - so dev silently served stale code, and every
# subsequent deploy orphaned another process and made it worse. Found 2026-08-16
# with dev still running an Aug 14 build. Leave $SERVER_PIDS unquoted on purpose.
log "Restarting wf-server..."
SERVER_PIDS=$(pgrep -f "node /home/n8n/wf-server/src/server.js" || true)
if [ -n "$SERVER_PIDS" ]; then
  log "Killing existing server(s): $(echo $SERVER_PIDS | tr '\n' ' ')"
  # shellcheck disable=SC2086
  kill $SERVER_PIDS 2>/dev/null || true
  sleep 2
  SURVIVORS=$(pgrep -f "node /home/n8n/wf-server/src/server.js" || true)
  if [ -n "$SURVIVORS" ]; then
    log "Force-killing survivors: $(echo $SURVIVORS | tr '\n' ' ')"
    # shellcheck disable=SC2086
    kill -9 $SURVIVORS 2>/dev/null || true
    sleep 1
  fi
fi

nohup node /home/n8n/wf-server/src/server.js >> "$LOG_FILE" 2>&1 &
NEW_PID=$!
log "Server started (PID: $NEW_PID)"

# Prove it actually came up. Binding failures are the whole reason this section
# exists, and a deploy that cannot bind must fail loudly rather than report success.
PORT_TO_CHECK="${PORT:-3001}"
for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -sf -o /dev/null "http://localhost:$PORT_TO_CHECK/health"; then
    log "Health check passed on port $PORT_TO_CHECK (attempt $i)"
    break
  fi
  if [ "$i" = "10" ]; then
    log "ERROR: server did not answer /health on port $PORT_TO_CHECK after 10 tries"
    exit 1
  fi
  sleep 1
done

# 4. Sync git commits to studio tables
log "Syncing git commits to database..."
bash "$REPO_DIR/scripts/sync-git-commits.sh" 2>&1 | tee -a "$LOG_FILE"

log "=== Deploy complete ==="
