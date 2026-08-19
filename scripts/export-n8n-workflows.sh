#!/bin/bash
# Export prod-scoped n8n workflows from source (dev by default) to
# wf-server/n8n/workflows/*.json for version control.
#
# SCOPE, not just "active": which workflows are production-relevant is a
# deliberate decision, not something "active=true" can answer on its own -
# dev's n8n also hosts agent tooling (Agile, Agents folders) and unrelated
# projects (Mitch, TMG) on the same instance, all of which can be active
# without belonging in prod. The scope is n8n folder membership: a workflow
# is exported if it's active AND sits in a folder prefixed 'wf-'
# (wf-controllers, wf-hydrate, ...), via knowledge_base.tf_n8n_workflows().
# Folder assignment is a deliberate, human-made choice - same spirit as
# object_policy for database objects (task 213) - not inferred from a proxy
# signal. See task 270 discussion 2026-08-19 for how this was arrived at.
#
# This is the first leg of git-as-record deploy: export -> commit/review ->
# import-n8n-workflows.sh reads FROM these files, not from a live API. That
# makes drift structurally impossible instead of policed by memory - see
# task 270. Counterpart to import-n8n-workflows.sh.
#
# THE DRAFT/PUBLISH TRAP (task 253 addendum 2/3, reconfirmed here): a plain
# GET /api/v1/workflows/{id} returns the CURRENT DRAFT's nodes/connections,
# not what is actually live, whenever versionId != activeVersionId. Verified
# directly on this export: server-shell's draft had an extra responseBody
# param its published version does not. When they diverge, the true active
# content only exists in workflow_history keyed on activeVersionId, which
# the public REST API has no endpoint for - queried via server-query instead
# (same join f_n8n_diff already uses for its content hash).
#
# Each workflow is normalized to {name, nodes, connections, settings, active}
# before being written - dropping id/versionId/createdAt/updatedAt/tags keeps
# git diffs meaningful (only real content changes show up) instead of every
# re-export touching every file on timestamp/version churn alone.
#
# The directory is fully regenerated each run (existing *.json removed
# first) so it never accumulates a stale file for a workflow that was
# renamed or deactivated - git tracks the deletion like any other change.
#
# Requires: curl, jq
# Requires in .env: N8N_API_KEY, N8N_BASE_URL (source; defaults to dev)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$REPO_DIR/n8n/workflows"
SERVER_QUERY_URL="https://n8n.whatsfresh.app/webhook/server-query"

if [ -f "$REPO_DIR/.env" ]; then
  export $(grep -v '^#' "$REPO_DIR/.env" | grep -E '^N8N_(API_KEY|BASE_URL)=' | xargs)
fi

SRC_URL="${N8N_BASE_URL:-https://n8n.whatsfresh.app}"
SRC_KEY="${N8N_API_KEY:?N8N_API_KEY not set in .env}"

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/*.json

echo "[export] Discovering wf-* scoped workflows via knowledge_base.tf_n8n_workflows()..."
SCOPE_QUERY=$(jq -n '{query: "SELECT id, name, folder_name FROM knowledge_base.tf_n8n_workflows() WHERE folder_name LIKE '"'"'wf-%'"'"' ORDER BY folder_name, name", params: {}, source: "export-n8n-workflows"}')
SCOPE_ROWS=$(curl -s -X POST "$SERVER_QUERY_URL" -H "Content-Type: application/json" -d "$SCOPE_QUERY")
IDS=$(echo "$SCOPE_ROWS" | jq -r '.[].id // empty')

if [ -z "$IDS" ]; then
  echo "[export] No wf-* scoped workflows found - check folder assignment or knowledge_base.tf_n8n_workflows()."
  exit 1
fi

echo "$SCOPE_ROWS" | jq -r '.[] | "  - [\(.folder_name)] \(.name)"'

EXPORTED=0
FAILED=0
FROM_HISTORY=0

for WF_ID in $IDS; do
  WF_JSON=$(curl -s -H "X-N8N-API-KEY: $SRC_KEY" "$SRC_URL/api/v1/workflows/$WF_ID")
  WF_NAME=$(echo "$WF_JSON" | jq -r '.name // empty')

  if [ -z "$WF_NAME" ]; then
    echo "[export] WARN: could not fetch workflow id=$WF_ID"
    FAILED=$((FAILED + 1))
    continue
  fi

  VERSION_ID=$(echo "$WF_JSON" | jq -r '.versionId // empty')
  ACTIVE_VERSION_ID=$(echo "$WF_JSON" | jq -r '.activeVersionId // empty')

  if [ -n "$ACTIVE_VERSION_ID" ] && [ "$VERSION_ID" != "$ACTIVE_VERSION_ID" ]; then
    echo "[export] $WF_NAME has an unpublished draft - pulling true active content from workflow_history"
    HIST_QUERY=$(jq -n --arg wid "$WF_ID" --arg vid "$ACTIVE_VERSION_ID" '
      ($wid | gsub("\u0027"; "\u0027\u0027")) as $w |
      ($vid | gsub("\u0027"; "\u0027\u0027")) as $v |
      {query: ("SELECT nodes, connections FROM workflow_history WHERE \"workflowId\" = \u0027\($w)\u0027 AND \"versionId\" = \u0027\($v)\u0027"), params: {}, source: "export-n8n-workflows"}
    ')
    HIST_ROW=$(curl -s -X POST "$SERVER_QUERY_URL" -H "Content-Type: application/json" -d "$HIST_QUERY")
    HIST_NODES=$(echo "$HIST_ROW" | jq -c '.[0].nodes // empty')
    HIST_CONNECTIONS=$(echo "$HIST_ROW" | jq -c '.[0].connections // empty')

    if [ -z "$HIST_NODES" ] || [ -z "$HIST_CONNECTIONS" ]; then
      echo "[export] WARN: $WF_NAME - could not read activeVersionId $ACTIVE_VERSION_ID from workflow_history, falling back to draft (MAY BE WRONG)"
    else
      WF_JSON=$(echo "$WF_JSON" | jq --argjson n "$HIST_NODES" --argjson c "$HIST_CONNECTIONS" '.nodes = $n | .connections = $c')
      FROM_HISTORY=$((FROM_HISTORY + 1))
    fi
  fi

  echo "$WF_JSON" | jq '{name, nodes, connections, settings, active}' \
    > "$OUTPUT_DIR/${WF_NAME}.json"
  echo "[export] Exported: $WF_NAME -> n8n/workflows/${WF_NAME}.json"
  EXPORTED=$((EXPORTED + 1))
done

echo ""
echo "[export] Done. Exported: $EXPORTED (from workflow_history: $FROM_HISTORY), Failed: $FAILED"
echo "[export] Output: $OUTPUT_DIR/"
echo "[export] Review the diff, then commit - this is the record import-n8n-workflows.sh deploys from."
