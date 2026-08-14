#!/bin/bash
# Full deploy pipeline to the DEV droplet: push to GitHub, pull on droplet,
# restart, sync git history into agile.git_commits / git_commit_files.
#
# RUNS LOCALLY:  bash scripts/deploy-dev.sh
#
# Related scripts, and where each runs:
#   scripts/deploy.sh                  runs ON the dev droplet (invoked below).
#                                      Also invoked by local-desk for both
#                                      wf-server and wf-marketing - the relative
#                                      path is a cross-repo contract, do not rename.
#   scripts/sync-git-commits.sh        runs ON the dev droplet, called by deploy.sh
#   scripts/production/prod_deploy.sh  runs ON the prod droplet

set -e

DROPLET_HOST="n8n.whatsfresh.app"
REMOTE_DIR="/home/n8n/wf-server"

echo "=== Push & Deploy ==="

# 1. Push current branch to origin
BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "[local] Pushing $BRANCH to origin..."
git push origin "$BRANCH"

# 2. If not on main, merge to main and push
if [ "$BRANCH" != "main" ]; then
  echo "[local] Merging $BRANCH into main..."
  git checkout main
  git merge "$BRANCH"
  git push origin main
  git checkout "$BRANCH"
fi

# 3. SSH to droplet and run deploy
echo "[remote] Deploying on droplet..."
ssh "$DROPLET_HOST" "cd $REMOTE_DIR && git pull origin main && bash scripts/deploy.sh"

echo "=== Done ==="
