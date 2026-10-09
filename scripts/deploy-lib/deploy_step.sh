#!/bin/bash
# RUNS LOCALLY. The SQL-step analogue of run_step.sh (task 506, Sprint 504,
# Epic 401). Wraps ONE canonical deploy step so every step logs to
# deployment.deployment_run_steps - the gap that left 8 of 10 steps unrecorded
# and the task 437 ordering bug invisible.
#
# What it does, per call:
#   One call: deployment.f_run_step(run_id, step_key, params). The DB function
#   looks up deploy_steps.runs, substitutes the :tokens, executes, and logs
#   running/success/error through f_log_step (an error also fails the run). The
#   n8n orchestrator calls the same function, so bash and n8n cannot drift.
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
PARAMS_ESC=$(esc_sql "$PARAMS")

RESULT=$(pg_query "SELECT deployment.f_run_step($RUN_ID, '$STEP_ESC', '$PARAMS_ESC'::jsonb) AS r")
OK=$(printf '%s' "$RESULT" | jq -r '.[0].r.ok // empty')

if [ "$OK" = "true" ]; then
  printf '%s\n' "$RESULT" | jq -c '.[0].r.rows'
  exit 0
fi

ERR=$(printf '%s' "$RESULT" | jq -r '.[0].r.error // empty')
[ -z "$ERR" ] && ERR="no/invalid response from f_run_step: $RESULT"
echo "deploy_step: step '$STEP_KEY' FAILED - $ERR (see deployment.deployment_run_steps run $RUN_ID)" >&2
exit 1
