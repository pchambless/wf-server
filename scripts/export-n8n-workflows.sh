#!/bin/bash
# Export production-relevant n8n workflows to wf-server/n8n/workflows/
# Uses knowledge_base.objects to determine which workflows are production-needed.
# Requires: curl, jq, psql access

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$REPO_DIR/n8n/workflows"
N8N_URL="${N8N_BASE_URL:-https://n8n.whatsfresh.app}"
N8N_API_KEY="${N8N_API_KEY:-}"
DB="n8n"

mkdir -p "$OUTPUT_DIR"

# Get production workflow names from knowledge_base
echo "[export] Querying knowledge_base for production workflows..."
WORKFLOWS=$(sudo -u postgres psql -d "$DB" -t -A -c "
  SELECT DISTINCT o.name
  FROM knowledge_base.objects o
  WHERE o.platform = 'n8n' AND o.type = 'workflow'
  AND (
    o.id IN (SELECT object_id FROM knowledge_base.step_dependencies)
    OR o.id IN (SELECT target_object_id FROM knowledge_base.object_dependencies)
  )
  AND (o.notes IS NULL OR o.notes->>'tech_debt' NOT LIKE '%dead%')
  ORDER BY o.name;
")

if [ -z "$WORKFLOWS" ]; then
  echo "[export] No production workflows found in knowledge_base"
  exit 1
fi

echo "[export] Found production workflows:"
echo "$WORKFLOWS" | sed 's/^/  - /'

# Export each workflow
EXPORTED=0
FAILED=0

for WF_NAME in $WORKFLOWS; do
  # Search for workflow by name via n8n API
  RESPONSE=$(curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" \
    "$N8N_URL/api/v1/workflows?name=$WF_NAME&limit=1" 2>/dev/null)

  WF_ID=$(echo "$RESPONSE" | jq -r '.data[0].id // empty' 2>/dev/null)

  if [ -z "$WF_ID" ]; then
    echo "[export] WARN: Could not find workflow '$WF_NAME' via API"
    FAILED=$((FAILED + 1))
    continue
  fi

  # Get full workflow details
  WF_JSON=$(curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" \
    "$N8N_URL/api/v1/workflows/$WF_ID" 2>/dev/null)

  if [ -z "$WF_JSON" ]; then
    echo "[export] WARN: Could not export workflow '$WF_NAME' (id=$WF_ID)"
    FAILED=$((FAILED + 1))
    continue
  fi

  # Save to file
  echo "$WF_JSON" | jq '.' > "$OUTPUT_DIR/${WF_NAME}.json"
  echo "[export] Exported: $WF_NAME -> n8n/workflows/${WF_NAME}.json"
  EXPORTED=$((EXPORTED + 1))
done

echo ""
echo "[export] Done. Exported: $EXPORTED, Failed: $FAILED"
echo "[export] Output: $OUTPUT_DIR/"
