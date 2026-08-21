#!/bin/bash
# Import (create/update) n8n workflows from wf-server/n8n/workflows/*.json
# onto prod, gated by deployment.f_n8n_diff so only workflows that changed
# since the last push are touched.
#
# Reads from the git-committed files, NOT a live source API - that is the
# actual portability fix task 270 exists for. The old version read straight
# from dev's live API, which meant "deployed" was whatever happened to be in
# dev's editor at that exact moment, not a reviewable, diffable artifact.
# Run export-n8n-workflows.sh and commit before running this - if dev has
# changed since the last export, this script has no way to know and will
# happily deploy the stale file. That is deliberate: git is the record, and
# staying current with dev is a separate, visible step, not something this
# script should paper over.
#
# Counterpart to export-n8n-workflows.sh.
#
# Usage: import-n8n-workflows.sh [workflow-name]
#   With no argument: imports every workflow deployment.f_n8n_diff('prod')
#   marks needs_deploy=true.
#   With a workflow name: imports just that one, regardless of diff state -
#   for testing a single workflow before running the full batch.
#   --worker is internal, not for direct use - see the deployment_run_steps
#   note below.
#
# Requires: curl, jq, git
# Requires in .env: N8N_PROD_API_KEY, N8N_PROD_BASE_URL (target/prod)
#
# Task 285/287: the actual import work runs as one deploy_n8n step under
# scripts/deploy-lib/run_step.sh, which re-invokes this same script with
# --worker to do it. That is what creates deployment.deployment_runs +
# deployment_run_steps rows - previously this script wrote only to
# deployment.deployments directly and n8n had zero run rows despite
# deploy_steps step 8 claiming coverage.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
WORKFLOWS_DIR="$REPO_DIR/n8n/workflows"
SELF="$SCRIPT_DIR/import-n8n-workflows.sh"

if [ -f "$REPO_DIR/.env" ]; then
  export $(grep -v '^#' "$REPO_DIR/.env" | grep -E '^N8N_(PROD_API_KEY|PROD_BASE_URL)=' | xargs)
fi

TGT_URL="${N8N_PROD_BASE_URL:?N8N_PROD_BASE_URL not set in .env}"
TGT_KEY="${N8N_PROD_API_KEY:?N8N_PROD_API_KEY not set in .env}"

# Dev's credential name -> prod's credential id/name. Static by design (see
# deployment.f_n8n_diff's header comment) - update this pair if prod's
# credential is ever recreated with a new id.
SRC_CRED_NAME="postgres-cred"
TGT_CRED_ID="cqQBJ3dwZJrFkefC"
TGT_CRED_NAME="Postgres Prod"

WORKER_MODE=0
if [ "$1" = "--worker" ]; then
  WORKER_MODE=1
  NEEDED="$2"
else
  ONLY_WF="$1"
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

  # Diff resolved (or single-workflow mode chosen) - hand off to a worker
  # invocation of this same script wrapped in run_step.sh, so the actual
  # import work is logged as one deploy_n8n step rather than running
  # untracked. NEEDED is passed through explicitly rather than letting the
  # worker recompute the diff, so both invocations act on the same list.
  GIT_SHA=$(git -C "$REPO_DIR" rev-parse HEAD)
  RUN_ID=$("$SCRIPT_DIR/deploy-lib/start_run.sh" n8n prod "$GIT_SHA" import-n8n-workflows.sh)
  echo "[import] deployment_run $RUN_ID started"

  set +e
  "$SCRIPT_DIR/deploy-lib/run_step.sh" "$RUN_ID" deploy_n8n -- "$SELF" --worker "$NEEDED"
  STEP_EXIT=$?
  set -e

  if [ "$STEP_EXIT" -eq 0 ]; then
    "$SCRIPT_DIR/deploy-lib/finish_run.sh" "$RUN_ID"
  else
    echo "[import] deployment_run $RUN_ID failed - see deployment.deployment_run_steps"
  fi
  exit "$STEP_EXIT"
fi

IMPORTED=0
FAILED=0

for WF_NAME in $NEEDED; do
  WF_FILE="$WORKFLOWS_DIR/${WF_NAME}.json"
  if [ ! -f "$WF_FILE" ]; then
    echo "[import] FAIL: $WF_NAME - no $WF_FILE. Run export-n8n-workflows.sh and commit first."
    FAILED=$((FAILED+1)); continue
  fi
  SRC_WF=$(cat "$WF_FILE")

  # API rejects id/createdAt/etc on create - only name/nodes/connections/settings.
  # settings is also rejected if it carries fields only valid on read (binaryMode,
  # availableInMCP, etc - discovered by a real 400 on first test), so it is
  # reduced to just executionOrder here rather than passed through verbatim.
  # Three remaps needed, all found the hard way:
  # - the postgres credential, from dev's name to target's id+name (credential ids
  #   are never portable across n8n instances)
  # - any httpRequest node whose URL is hardcoded to dev's n8n base URL - found
  #   because it silently made a "prod" login write session context into DEV's
  #   database instead. As of task 259 this remap is a NO-OP (login's L03-setvals
  #   is gone), kept deliberately as a guard against it being reintroduced.
  # - any Code node whose jsCode has the dev base URL baked into a string literal
  #   (e.g. styled-html's L03-html calling server-query directly for the
  #   {{{template:field}}} dropdown-enrichment pattern). Found 2026-08-21: this
  #   is NOT caught by f_n8n_diff, because dev's own copy is correctly
  #   self-referencing, so dev-hash == prod-hash even though prod's copy is
  #   silently calling DEV's database for every dropdown render. The httpRequest
  #   remap above only touches .parameters.url, never node source code - Code
  #   nodes need their own pass. Literal split/join, not jq gsub (regex), since
  #   "." in the URL would otherwise match any character.
  CREATE_PAYLOAD=$(echo "$SRC_WF" | jq \
    --arg tid "$TGT_CRED_ID" --arg tname "$TGT_CRED_NAME" --arg sname "$SRC_CRED_NAME" \
    --arg src_base "https://n8n.whatsfresh.app" --arg tgt_base "$TGT_URL" '
    {name, nodes: [.nodes[] |
        (if .credentials.postgres.name == $sname
           then .credentials.postgres = {id: $tid, name: $tname}
           else . end) |
        (if .parameters.url != null and (.parameters.url | startswith($src_base))
           then .parameters.url = ($tgt_base + (.parameters.url | ltrimstr($src_base)))
           else . end) |
        (if .parameters.jsCode != null and (.parameters.jsCode | contains($src_base))
           then .parameters.jsCode = (.parameters.jsCode | split($src_base) | join($tgt_base))
           else . end)],
     connections, settings: {executionOrder: (.settings.executionOrder // "v1")}}
  ')

  # Idempotent re-run: update if it already exists on target instead of erroring on create.
  # n8n's ?name= API filter is fuzzy/substring, not exact (confirmed the hard way -
  # "dml" matched "dml-batch-map") - fetch the list and filter for an exact match instead.
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

    # Verify the publish actually took - REST PUT on an active workflow moves
    # versionId and activeVersionId together (task 253 addendum 3), but check
    # rather than trust: this is exactly the class of bug (draft saved, live
    # code unchanged) that started this whole task.
    VERIFY=$(curl -s -H "X-N8N-API-KEY: $TGT_KEY" "$TGT_URL/api/v1/workflows/$TGT_ID")
    V_VER=$(echo "$VERIFY" | jq -r '.versionId // empty')
    V_ACTIVE_VER=$(echo "$VERIFY" | jq -r '.activeVersionId // empty')
    if [ -n "$V_ACTIVE_VER" ] && [ "$V_VER" != "$V_ACTIVE_VER" ]; then
      echo "[import] WARN: $WF_NAME imported but versionId != activeVersionId after publish - verify manually in the prod editor."
    fi
  fi

  echo "[import] $ACTION: $WF_NAME -> $TGT_ID (active=$SRC_ACTIVE)"
  IMPORTED=$((IMPORTED+1))
done

echo ""
echo "[import] Done. Imported: $IMPORTED, Failed: $FAILED"

# Worker mode only reaches here - the outer (non-worker) branch above always
# exits before this point. Exit status is what run_step.sh reads to decide
# success vs error for this deploy_n8n step; deployment.deployments and
# deployment_runs are already recorded by start_run.sh in the outer branch,
# nothing left to write here.
if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
