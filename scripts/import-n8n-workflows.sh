#!/bin/bash
# Import (create/update) n8n workflows from dev onto prod, gated by
# deployment.f_n8n_diff so only workflows that changed since the last push
# are touched. Counterpart to export-n8n-workflows.sh.
#
# Remaps the one credential these workflows use (a Postgres connection) from
# dev's name to prod's id, since credential ids are never portable across
# n8n instances. See deployment.f_n8n_diff's header comment for why a
# name/id remap is proportionate here instead of a real content diff.
#
# Usage: import-n8n-workflows.sh [workflow-name]
#   With no argument: imports every workflow deployment.f_n8n_diff('prod')
#   marks needs_deploy=true.
#   With a workflow name: imports just that one, regardless of diff state -
#   for testing a single workflow before running the full batch.
#
# Requires: curl, jq
# Requires in .env: N8N_API_KEY, N8N_BASE_URL (source/dev),
#                   N8N_PROD_API_KEY, N8N_PROD_BASE_URL (target/prod)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
ONLY_WF="$1"

if [ -f "$REPO_DIR/.env" ]; then
  export $(grep -v '^#' "$REPO_DIR/.env" | grep -E '^N8N_(API_KEY|BASE_URL|PROD_API_KEY|PROD_BASE_URL)=' | xargs)
fi

SRC_URL="${N8N_BASE_URL:-https://n8n.whatsfresh.app}"
SRC_KEY="${N8N_API_KEY:?N8N_API_KEY not set in .env}"
TGT_URL="${N8N_PROD_BASE_URL:?N8N_PROD_BASE_URL not set in .env}"
TGT_KEY="${N8N_PROD_API_KEY:?N8N_PROD_API_KEY not set in .env}"

# Dev's credential name -> prod's credential id/name. Static by design (see
# deployment.f_n8n_diff's header comment) - update this pair if prod's
# credential is ever recreated with a new id.
SRC_CRED_NAME="postgres-cred"
TGT_CRED_ID="cqQBJ3dwZJrFkefC"
TGT_CRED_NAME="Postgres Prod"

if [ -n "$ONLY_WF" ]; then
  NEEDED="$ONLY_WF"
  echo "[import] Single-workflow mode: $ONLY_WF"
else
  echo "[import] Checking deployment.f_n8n_diff('prod') for workflows needing deploy..."
  DIFF_PAYLOAD=$(jq -n --arg q "SELECT workflow_name FROM deployment.f_n8n_diff('prod') WHERE needs_deploy = true" \
    '{query: $q, params: {}, source: "direct"}')
  NEEDED=$(curl -s -X POST https://n8n.whatsfresh.app/webhook/server-query \
    -H "Content-Type: application/json" -d "$DIFF_PAYLOAD" | jq -r '.[].workflow_name')

  if [ -z "$NEEDED" ]; then
    echo "[import] Nothing to do - prod already in sync."
    exit 0
  fi
  echo "[import] Workflows needing deploy:"
  echo "$NEEDED" | sed 's/^/  - /'
fi

IMPORTED=0
FAILED=0

for WF_NAME in $NEEDED; do
  # n8n's ?name= API filter is a fuzzy/substring match, not exact - confirmed
  # the hard way: querying "dml" matched "dml-batch-map" instead, and "report"
  # matched "agile-report" instead, silently importing the wrong workflow
  # under the right name. Fetch the active list and filter for an EXACT name
  # match in jq instead of trusting the API's own filter.
  SRC_RESPONSE=$(curl -s -H "X-N8N-API-KEY: $SRC_KEY" "$SRC_URL/api/v1/workflows?active=true&limit=250")
  SRC_ID=$(echo "$SRC_RESPONSE" | jq -r --arg n "$WF_NAME" '.data[] | select(.name == $n) | .id' | head -1)
  if [ -z "$SRC_ID" ]; then
    echo "[import] WARN: could not find exact match for '$WF_NAME' on source"; FAILED=$((FAILED+1)); continue
  fi
  SRC_WF=$(curl -s -H "X-N8N-API-KEY: $SRC_KEY" "$SRC_URL/api/v1/workflows/$SRC_ID")

  # API rejects id/createdAt/etc on create - only name/nodes/connections/settings.
  # settings is also rejected if it carries fields only valid on read (binaryMode,
  # availableInMCP, etc - discovered by a real 400 on first test) - so settings is
  # a fixed minimal object here, not passed through from source verbatim.
  # Two remaps needed, both found the hard way:
  # - the postgres credential, from dev's name to target's id+name (credential ids
  #   are never portable across n8n instances)
  # - any httpRequest node whose URL is hardcoded to the source n8n base URL (e.g.
  #   login's L03-setvals node calling https://n8n.whatsfresh.app/webhook/setvals
  #   directly instead of via a portable reference) - found because it silently
  #   made a "prod" login write session context into DEV's database instead.
  CREATE_PAYLOAD=$(echo "$SRC_WF" | jq \
    --arg tid "$TGT_CRED_ID" --arg tname "$TGT_CRED_NAME" --arg sname "$SRC_CRED_NAME" \
    --arg src_base "$SRC_URL" --arg tgt_base "$TGT_URL" '
    {name, nodes: [.nodes[] |
        (if .credentials.postgres.name == $sname
           then .credentials.postgres = {id: $tid, name: $tname}
           else . end) |
        (if .parameters.url != null and (.parameters.url | startswith($src_base))
           then .parameters.url = ($tgt_base + (.parameters.url | ltrimstr($src_base)))
           else . end)],
     connections, settings: {executionOrder: "v1"}}
  ')

  # Idempotent re-run: update if it already exists on target instead of erroring on create.
  # Same exact-match requirement as the source lookup above.
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
    echo "[import] FAIL: $WF_NAME - $(echo "$RESULT" | jq -c '.message // .' 2>/dev/null || echo "$RESULT")"
    FAILED=$((FAILED+1)); continue
  fi

  SRC_ACTIVE=$(echo "$SRC_WF" | jq -r '.active')
  if [ "$SRC_ACTIVE" = "true" ]; then
    curl -s -X POST -H "X-N8N-API-KEY: $TGT_KEY" "$TGT_URL/api/v1/workflows/$TGT_ID/activate" > /dev/null
  fi

  echo "[import] $ACTION: $WF_NAME -> $TGT_ID (active=$SRC_ACTIVE)"
  IMPORTED=$((IMPORTED+1))
done

echo ""
echo "[import] Done. Imported: $IMPORTED, Failed: $FAILED"
