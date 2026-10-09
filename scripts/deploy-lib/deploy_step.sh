#!/bin/bash
# RUNS LOCALLY. The SQL-step analogue of run_step.sh (task 506, Sprint 504,
# Epic 401). Wraps ONE canonical deploy step so every step logs to
# deployment.deployment_run_steps - the gap that left 8 of 10 steps unrecorded
# and the task 437 ordering bug invisible.
#
# What it does, per call:
#   1. Looks up the step's SQL from deployment.deploy_steps.runs (step_key).
#   2. Writes a 'running' row to deployment_run_steps (run_id, step_key).
#   3. Executes the step SQL via the server-query webhook, passing params for
#      :token substitution (server-query owns substitution - we do not reinvent
#      it here).
#   4. Writes 'success' or 'error' with a short detail. On error also marks the
#      parent deployment_runs row failed (same contract as run_step.sh).
#
# Contract notes carried over from run_step.sh / server-query:
#   - step_name written is the deploy_steps.step_key, so a step log ties back to
#     the canonical process definition.
#   - server-query answers HTTP 200 for BOTH success and SQL failure; a SQL
#     error comes back as an EMPTY body, a valid no-row query as [{}]. We treat
#     empty-body as failure, matching server-query's own stderr contract.
#
# Usage:
#   deploy_step <run_id> <step_key> [params_json]
#     run_id      - an existing deployment_runs.id (from start_run.sh - step 0)
#     step_key    - a deployment.deploy_steps.step_key (compare, plan, data, ...)
#     params_json - JSON object of :token values for the step's runs SQL,
#                   e.g. '{"env":"prod","run_id":66,"dry_run":true}'. Default {}.
#
# NOT for the two bash steps (deploy_code/deploy_n8n) - those keep run_step.sh,
# since their work is a shell command, not a runs SQL template. Same table,
# same step_key naming, so the trajectory is uniform across both.
#
# Exit code: 0 if the step succeeded, 1 if it failed.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/pg-query.sh"   # pg_query, esc_sql

RUN_ID="${1:?Usage: deploy_step <run_id> <step_key> [params_json]}"
STEP_KEY="${2:?Usage: deploy_step <run_id> <step_key> [params_json]}"
# Note: do NOT use ${3:-{}} - the literal braces in the default break brace
# expansion when $3 is itself a JSON object. Assign then default explicitly.
PARAMS="${3:-}"
[ -z "$PARAMS" ] && PARAMS='{}'

STEP_ESC=$(esc_sql "$STEP_KEY")

# --- resolve the step's SQL from the canonical catalog -----------------------
RUNS_JSON=$(pg_query "SELECT runs FROM deployment.deploy_steps WHERE step_key = '$STEP_ESC'")
if [ $? -ne 0 ] || [ -z "$RUNS_JSON" ]; then
  echo "deploy_step: could not read deploy_steps for step_key '$STEP_KEY'" >&2
  exit 1
fi
STEP_SQL=$(printf '%s' "$RUNS_JSON" | jq -r '.[0].runs // empty')
if [ -z "$STEP_SQL" ] || [ "$STEP_SQL" = "null" ]; then
  echo "deploy_step: step '$STEP_KEY' has no runs SQL (is it a bash step like deploy_code/deploy_n8n? use run_step.sh)" >&2
  exit 1
fi

# --- 1. mark running ---------------------------------------------------------
pg_query "SELECT deployment.f_log_step($RUN_ID, '$STEP_ESC', 'running')" > /dev/null

# --- 2. execute the step via server-query (it does :token substitution) ------
# server-query lives in wf-agents; pg-query.sh hits the same webhook but with
# params:{}. We need param substitution, so call the webhook directly here with
# the step's params. Mirrors pg-query.sh's own call shape + error contract.
PAYLOAD=$(jq -n --arg q "$STEP_SQL" --argjson p "$PARAMS" --arg s "deploy_step" \
  '{query: $q, params: $p, source: $s}')
RESPONSE=$(curl -s -w '\n%{http_code}' -X POST https://n8n.whatsfresh.app/webhook/server-query \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Secret: ${N8N_WEBHOOK_SECRET:-}" \
  -d "$PAYLOAD")
HTTP_CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"

OK=0
if [ "$HTTP_CODE" != "200" ]; then
  OK=1
elif [ -z "${BODY//[[:space:]]/}" ]; then
  # empty body on 200 = SQL failed (server-query contract)
  OK=1
fi

# --- 3. short detail (first row / error snippet), capped --------------------
if [ "$OK" -eq 0 ]; then
  DETAIL=$(printf '%s' "$BODY" | jq -c '.[0] // {}' 2>/dev/null | cut -c1-500)
  [ -z "$DETAIL" ] && DETAIL='ok'
else
  DETAIL=$(printf '%s' "$BODY" | jq -r '.error // empty' 2>/dev/null | cut -c1-500)
  [ -z "$DETAIL" ] && DETAIL="step '$STEP_KEY' failed (HTTP $HTTP_CODE, empty/err body)"
fi
DETAIL_ESC=$(esc_sql "$DETAIL")

# --- 4. mark success/error; on error fail the run ---------------------------
if [ "$OK" -eq 0 ]; then
  pg_query "SELECT deployment.f_log_step($RUN_ID, '$STEP_ESC', 'success', '$DETAIL_ESC')" > /dev/null
  printf '%s\n' "$BODY"
  exit 0
else
  # f_log_step also fails the run on error (error_stage 'execute' bucket).
  pg_query "SELECT deployment.f_log_step($RUN_ID, '$STEP_ESC', 'error', '$DETAIL_ESC')" > /dev/null
  echo "deploy_step: step '$STEP_KEY' FAILED - see deployment.deployment_run_steps run $RUN_ID" >&2
  [ -n "$BODY" ] && echo "$BODY" >&2
  exit 1
fi
