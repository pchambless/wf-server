#!/bin/bash
# RUNS LOCALLY. Creates a deployment + deployment_run row for legs
# deployment.f_p01_plan cannot serve - it plans objects from vw_manifest and
# raises an exception on zero objects planned, which is exactly what
# wf-server code deploys hit (no manifest rows: code isn't a DB object).
# n8n has manifest rows so f_p01_plan already works for it, but
# import-n8n-workflows.sh does its own ad hoc deployments insert and has not
# been wired onto this yet - task 285.
#
# Prints the new run_id on stdout on success, nothing else.
#
# Usage: start_run.sh <pipeline> <environment> [git_commit] [created_by]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/pg-query.sh"

PIPELINE="${1:?Usage: start_run.sh <pipeline> <environment> [git_commit] [created_by]}"
ENVIRONMENT="${2:?Usage: start_run.sh <pipeline> <environment> [git_commit] [created_by]}"
GIT_COMMIT="${3:-}"
CREATED_BY="${4:-deploy-lib}"

PIPELINE_ESC=$(esc_sql "$PIPELINE")
ENV_ESC=$(esc_sql "$ENVIRONMENT")
SHA_ESC=$(esc_sql "$GIT_COMMIT")
BY_ESC=$(esc_sql "$CREATED_BY")

SHA_SQL="NULL"
[ -n "$GIT_COMMIT" ] && SHA_SQL="'$SHA_ESC'"

SQL="WITH new_deployment AS (
  INSERT INTO deployment.deployments (environment_id, pipeline_id, git_commit, created_by)
  SELECT e.id, p.id, $SHA_SQL, '$BY_ESC'
    FROM deployment.environments e, deployment.pipelines p
   WHERE e.name = '$ENV_ESC' AND p.name = '$PIPELINE_ESC'
  RETURNING id
), new_run AS (
  INSERT INTO deployment.deployment_runs (deployment_id, attempt, status, triggered_by)
  SELECT id, 1, 'running', '$BY_ESC' FROM new_deployment
  RETURNING id
)
SELECT id AS run_id FROM new_run"

RESULT=$(pg_query "$SQL")
RUN_ID=$(printf '%s' "$RESULT" | jq -r '.[0].run_id // empty')

if [ -z "$RUN_ID" ]; then
  echo "start_run: no run_id returned - check pipeline '$PIPELINE' and environment '$ENVIRONMENT' exist. Response: $RESULT" >&2
  exit 1
fi

echo "$RUN_ID"
