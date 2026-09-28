#!/bin/bash
# Import (create/update) n8n workflows from wf-server/n8n/workflows/*.json
# onto wf-v2-dev (the new droplet, task 427-430), same credential-remapping
# approach as import-n8n-workflows.sh (dev->prod) but targeting the new
# droplet instead.
#
# Simpler than the prod version deliberately: no deployment_run_steps
# tracking (that's specific to the formal prod deploy pipeline), no
# deployment.f_n8n_diff gating (wf-v2-dev has no prior deploy history to
# diff against yet). Re-running this is still idempotent - it updates by
# exact-name match instead of erroring on create, same as prod's version.
#
# Usage: import-n8n-workflows-dev2.sh [workflow-name]
#   With no argument: imports every *.json in n8n/workflows/
#   With a workflow name: imports just that one
#
# Requires: curl, jq
# Requires in wf-agents/.env: N8N_DEV2_API_KEY, N8N_WEBHOOK_SECRET
# Requires N8N_DEV2_BASE_URL to be reachable - wf-v2-dev's n8n is not
# publicly exposed yet (no DNS cutover, task 433), so this must be run
# through an SSH tunnel to the droplet:
#   ssh -4 -L 5679:127.0.0.1:5678 root@142.93.204.168
#   N8N_DEV2_BASE_URL=http://127.0.0.1:5679 ./import-n8n-workflows-dev2.sh
# Defaults to http://127.0.0.1:15678 (this session's own tunnel) if unset.
#
# Credential ids are specific to wf-v2-dev's n8n instance (created task 430,
# 2026-09-27) - update these if that instance's credentials are ever
# recreated with new ids:
#   Postgres Dev2:      V5lXvMgDf3cob0Bs
#   wf-webhook-secret:  Cr5FofBlVGzpKoKv

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
WORKFLOWS_DIR="$REPO_DIR/n8n/workflows"
AGENTS_ENV="$(dirname "$REPO_DIR")/wf-agents/.env"

if [ -f "$AGENTS_ENV" ]; then
  export $(grep -v '^#' "$AGENTS_ENV" | grep -E '^(N8N_DEV2_API_KEY|N8N_WEBHOOK_SECRET)=' | xargs)
fi

TGT_URL="${N8N_DEV2_BASE_URL:-http://127.0.0.1:15678}"
TGT_KEY="${N8N_DEV2_API_KEY:?N8N_DEV2_API_KEY not set in wf-agents/.env}"

SRC_CRED_NAME="postgres-cred"
TGT_CRED_ID="V5lXvMgDf3cob0Bs"
TGT_CRED_NAME="Postgres Dev2"

SRC_HEADERAUTH_CRED_NAME="wf-webhook-secret"
TGT_HEADERAUTH_CRED_ID="Cr5FofBlVGzpKoKv"
TGT_HEADERAUTH_CRED_NAME="wf-webhook-secret"

ONLY_WF="$1"
if [ -n "$ONLY_WF" ]; then
  FILES=("$WORKFLOWS_DIR/${ONLY_WF}.json")
else
  FILES=("$WORKFLOWS_DIR"/*.json)
fi

IMPORTED=0
FAILED=0

for WF_FILE in "${FILES[@]}"; do
  WF_NAME=$(basename "$WF_FILE" .json)
  if [ ! -f "$WF_FILE" ]; then
    echo "[import-dev2] FAIL: $WF_NAME - no $WF_FILE"
    FAILED=$((FAILED+1)); continue
  fi
  SRC_WF=$(cat "$WF_FILE")

  # Same three remaps as import-n8n-workflows.sh - see that script's header
  # comment for why each one exists (real incidents, not speculative).
  CREATE_PAYLOAD=$(echo "$SRC_WF" | jq \
    --arg tid "$TGT_CRED_ID" --arg tname "$TGT_CRED_NAME" --arg sname "$SRC_CRED_NAME" \
    --arg htid "$TGT_HEADERAUTH_CRED_ID" --arg htname "$TGT_HEADERAUTH_CRED_NAME" --arg hsname "$SRC_HEADERAUTH_CRED_NAME" \
    --arg src_base "https://n8n.whatsfresh.app" --arg tgt_base "$TGT_URL" '
    {name, nodes: [.nodes[] |
        (if .credentials.postgres.name == $sname
           then .credentials.postgres = {id: $tid, name: $tname}
           else . end) |
        (if .credentials.httpHeaderAuth.name == $hsname
           then .credentials.httpHeaderAuth = {id: $htid, name: $htname}
           else . end) |
        (if .parameters.url != null and (.parameters.url | startswith($src_base))
           then .parameters.url = ($tgt_base + (.parameters.url | ltrimstr($src_base)))
           else . end) |
        (if .parameters.jsCode != null and (.parameters.jsCode | contains($src_base))
           then .parameters.jsCode = (.parameters.jsCode | split($src_base) | join($tgt_base))
           else . end)],
     connections, settings: {executionOrder: (.settings.executionOrder // "v1")}}
  ')

  TGT_LOOKUP=$(curl -s -H "X-N8N-API-KEY: $TGT_KEY" "$TGT_URL/api/v1/workflows?limit=250")
  TGT_ID=$(echo "$TGT_LOOKUP" | jq -r --arg n "$WF_NAME" '.data[] | select(.name == $n) | .id' | head -1)

  if [ -n "$TGT_ID" ]; then
    RESULT=$(curl -s -X PUT -H "X-N8N-API-KEY: $TGT_KEY" -H "Content-Type: application/json" \
      "$TGT_URL/api/v1/workflows/$TGT_ID" --data "$CREATE_PAYLOAD")
    ACTION="updated"
  else
    RESULT=$(curl -s -X POST -H "X-N8N-API-KEY: $TGT_KEY" -H "Content-Type: application/json" \
      "$TGT_URL/api/v1/workflows" --data "$CREATE_PAYLOAD")
    TGT_ID=$(echo "$RESULT" | jq -r '.id // empty')
    ACTION="created"
  fi

  if [ -z "$TGT_ID" ] || [ "$TGT_ID" = "null" ]; then
    echo "[import-dev2] FAIL: $WF_NAME - $(echo "$RESULT" | jq -c '.message // .' 2>/dev/null || echo "$RESULT")"
    FAILED=$((FAILED+1)); continue
  fi

  SRC_ACTIVE=$(echo "$SRC_WF" | jq -r '.active')
  if [ "$SRC_ACTIVE" = "true" ]; then
    curl -s -X POST -H "X-N8N-API-KEY: $TGT_KEY" "$TGT_URL/api/v1/workflows/$TGT_ID/activate" > /dev/null
  fi

  echo "[import-dev2] $ACTION: $WF_NAME -> $TGT_ID (active=$SRC_ACTIVE)"
  IMPORTED=$((IMPORTED+1))
done

echo ""
echo "[import-dev2] Done. Imported: $IMPORTED, Failed: $FAILED"
if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
