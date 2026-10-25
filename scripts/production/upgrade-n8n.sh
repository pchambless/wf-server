#!/usr/bin/env bash
set -euo pipefail
################################################################################
# upgrade-n8n.sh - RUNS ON THE DEV OR PROD DROPLET
#
# Re-pull and restart the n8n container on a new pinned tag, reusing the exact
# `docker run` shape from provision.sh section 8. The /data volume (workflows,
# credentials, N8N_ENCRYPTION_KEY) persists across the recreate, so nothing is
# lost - the container is cattle, the volume is the pet.
#
# Why parameterized: we pin an exact version so dev/prod/local stay identical,
# which means we only move when we choose to and the security clock keeps
# ticking. This turns each deliberate bump into one command instead of a
# hand-edited docker run. Epic 278 -> n8n Version Currency and Advisories.
#
# Usage:
#   WF_ADMIN_PASSWORD=... ./upgrade-n8n.sh 2.43.5     # explicit version
#   WF_ADMIN_PASSWORD=... ./upgrade-n8n.sh            # resolve latest from the feed
#   WF_ADMIN_PASSWORD=... CONFIRM=yes ./upgrade-n8n.sh # non-interactive (skip prompt)
#
# With no version arg, the target is read from deployment.latest_version
# (fed by the version-fetch workflow off the n8n GitHub releases API) and
# confirmed before anything is pulled - propose-and-confirm, not blind
# auto-latest. WF_ADMIN_PASSWORD must be exported (same value the box was
# provisioned with) - it is not stored here.
################################################################################

: "${WF_ADMIN_PASSWORD:?Export WF_ADMIN_PASSWORD (the n8n DB password) before running}"

# Version resolution: pass an explicit tag to override, OR omit it and the
# script reads the target from deployment.latest_version (populated by the
# version-fetch n8n workflow off version_feed -> the n8n GitHub releases API).
# This closes the loop the version-currency subsystem was built for: the DB
# already knows the latest safe version; stop hand-typing it.
#
# PROPOSE-AND-CONFIRM, not blind auto-latest: we do NOT auto-jump prod to a
# release that may be hours old (that is how you catch a fresh regression).
# The resolved version is shown and confirmed before anything is pulled.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -n "${1:-}" ]; then
    N8N_TAG="$1"
    echo "==> Target version (explicit): ${N8N_TAG}"
else
    echo "==> No version given - resolving from deployment.latest_version ..."
    source "$SCRIPT_DIR/../deploy-lib/pg-query.sh"
    RESOLVED=$(pg_query "SELECT latest_version FROM deployment.latest_version WHERE component='n8n' ORDER BY major DESC LIMIT 1" \
        | jq -r '.[0].latest_version // empty' | sed 's/^v//')
    INSTALLED=$(docker ps --filter name=n8n --format '{{.Image}}' | sed 's#.*:##')
    if [ -z "$RESOLVED" ]; then
        echo "ERROR: could not resolve latest n8n version from deployment.latest_version." >&2
        echo "       Check the version-fetch workflow / version_feed, or pass a version explicitly." >&2
        exit 1
    fi
    echo "    installed: ${INSTALLED:-unknown}"
    echo "    latest (per feed): ${RESOLVED}"
    if [ "$INSTALLED" = "$RESOLVED" ]; then
        echo "==> Already on ${RESOLVED}. Nothing to do."
        exit 0
    fi
    N8N_TAG="$RESOLVED"
    # Confirm before touching a running container (prod safety). Skip the
    # prompt with CONFIRM=yes for non-interactive/automated use.
    if [ "${CONFIRM:-}" != "yes" ]; then
        read -r -p "==> Upgrade n8n ${INSTALLED:-?} -> ${N8N_TAG}? [y/N] " ans
        case "$ans" in
            y|Y|yes) ;;
            *) echo "Aborted."; exit 0 ;;
        esac
    fi
fi

echo "==> Pulling n8nio/n8n:${N8N_TAG}"
docker pull "n8nio/n8n:${N8N_TAG}"

echo "==> Stopping and removing the current n8n container (volume /data is kept)"
docker stop n8n 2>/dev/null || true
docker rm n8n 2>/dev/null || true

echo "==> Starting n8n on ${N8N_TAG}"
docker run -d \
  --name n8n \
  --network host \
  --restart unless-stopped \
  -v /home/n8n/n8n_data:/data \
  -e DB_TYPE=postgresdb \
  -e DB_POSTGRESDB_HOST=127.0.0.1 \
  -e DB_POSTGRESDB_PORT=5432 \
  -e DB_POSTGRESDB_DATABASE=n8n \
  -e DB_POSTGRESDB_POOL_SIZE=10 \
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
  "n8nio/n8n:${N8N_TAG}"

echo "==> Done. Follow the DB migration and startup with:"
echo "    docker logs -f n8n"
echo "==> Then confirm: editor loads, active workflows still active, run a"
echo "    webhook workflow (dml / server-query) end to end."
