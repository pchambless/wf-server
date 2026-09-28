#!/bin/bash
# Deploy wf-server: pull latest, restart server, sync git history
# Run on the droplet: bash /home/n8n/wf-server/scripts/deploy.sh

set -e

REPO_DIR="/home/n8n/wf-server"
LOG_FILE="/home/n8n/wf-server/logs/deploy.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

# Closes out the deployment_run on any exit path, success or failure. A
# captured status var, not an inline $? inside the trap command itself -
# the latter is fragile once the trap body runs more than one command.
RUN_ID=""
finish_tracking() {
  local exit_status=$?
  if [ -n "$RUN_ID" ]; then
    local final_status="failed"
    [ "$exit_status" -eq 0 ] && final_status="succeeded"
    bash "$REPO_DIR/scripts/deploy-lib/finish_run.sh" "$RUN_ID" "$final_status" >/dev/null 2>&1 || true
  fi
}
trap finish_tracking EXIT

cd "$REPO_DIR" || exit 1

log "=== Starting deploy ==="

# 1. Pull latest from main
PREV_SHA=$(git rev-parse HEAD)
log "Pulling latest from origin/main..."
git pull origin main 2>&1 | tee -a "$LOG_FILE"
NEW_SHA=$(git rev-parse HEAD)

# Record this deploy in deployment.deployments/deployment_runs (task 248) -
# dev's counterpart to prod_deploy.sh's tracking (task 288/298). Mirrors that
# script's start_run.sh call, but skips its run_step.sh/--worker wrapping -
# that exists there solely to solve prod_deploy.sh re-invoking itself as a
# subprocess after git pull, which this flat script never does. finish_tracking
# (trapped on EXIT above) closes the run out with the real exit status.
#
# Soft-fails on purpose: if this can't reach the tracking webhook, that must
# never block a real deploy. Logs a warning and continues either way.
source "$REPO_DIR/scripts/deploy-lib/pg-query.sh"
RELEASE_ID=$(pg_query "SELECT id FROM deployment.releases WHERE status='pending'" 2>/dev/null | jq -r '.[0].id // empty' 2>/dev/null || true)
if [ -n "$RELEASE_ID" ]; then
  RUN_ID=$("$REPO_DIR/scripts/deploy-lib/start_run.sh" wf-server dev "$RELEASE_ID" "$NEW_SHA" deploy.sh 2>/dev/null || true)
  if [ -n "$RUN_ID" ]; then
    log "deployment_run $RUN_ID started (sha $NEW_SHA)"
  else
    log "WARNING: could not start deployment tracking run - deploy continuing untracked"
  fi
else
  log "WARNING: no pending release found - deploy continuing untracked (see task 248)"
fi

# 2. Install any new dependencies
# Diff against the sha we were on BEFORE the pull. The old test was
# "git diff HEAD~1", which looks exactly one commit back no matter how many
# commits the pull brought, so a package.json change any further back was
# missed. That is how session-file-store (task 245) landed on the droplet
# uninstalled and left the server crash-looping on ERR_MODULE_NOT_FOUND.
if [ "$PREV_SHA" != "$NEW_SHA" ] && git diff --name-only "$PREV_SHA" "$NEW_SHA" | grep -q "package.json"; then
  log "package.json changed ($PREV_SHA -> $NEW_SHA) - running npm install..."
  npm install --production 2>&1 | tee -a "$LOG_FILE"
fi

# 3. Restart server
# pm2 OWNS this process on the dev droplet. An earlier version of this script did
# kill + nohup, which bypassed pm2 entirely: pm2 restarted whatever was killed,
# the nohup process then could not bind 3001, and the deploy still reported
# success - so dev served an Aug 14 build for two days while every deploy
# orphaned another process. Found 2026-08-16. Do not reintroduce kill/nohup here;
# whatever manages the process must be the thing this script talks to.
log "Restarting wf-server via pm2..."
if pm2 describe wf-server > /dev/null 2>&1; then
  pm2 restart wf-server --update-env 2>&1 | tee -a "$LOG_FILE"
else
  log "wf-server not registered with pm2 - starting from ecosystem.config.cjs"
  pm2 start "$REPO_DIR/ecosystem.config.cjs" 2>&1 | tee -a "$LOG_FILE"
fi
pm2 save > /dev/null 2>&1 || true

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
