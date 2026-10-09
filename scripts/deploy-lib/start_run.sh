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
# Usage: start_run.sh <pipeline> <environment> <release_id> [git_commit] [created_by]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/pg-query.sh"

PIPELINE="${1:?Usage: start_run.sh <pipeline> <environment> <release_id> [git_commit] [created_by]}"
ENVIRONMENT="${2:?Usage: start_run.sh <pipeline> <environment> <release_id> [git_commit] [created_by]}"
RELEASE_ID="${3:?Usage: start_run.sh <pipeline> <environment> <release_id> [git_commit] [created_by]}"
GIT_COMMIT="${4:-}"
CREATED_BY="${5:-deploy-lib}"

PIPELINE_ESC=$(esc_sql "$PIPELINE")
ENV_ESC=$(esc_sql "$ENVIRONMENT")
SHA_ESC=$(esc_sql "$GIT_COMMIT")
BY_ESC=$(esc_sql "$CREATED_BY")

# The run lifecycle lives in deployment.f_start_run (shared with the n8n
# orchestrator). Pipeline 'all'/empty = holistic run (pipeline_id NULL, every
# leg); a name pins one leg. RELEASE_ID is accepted for caller compatibility but
# f_start_run always attaches the pending release.
RESULT=$(pg_query "SELECT deployment.f_start_run('$PIPELINE_ESC', '$ENV_ESC', '$SHA_ESC', '$BY_ESC') AS run_id")
RUN_ID=$(printf '%s' "$RESULT" | jq -r '.[0].run_id // empty')

if [ -z "$RUN_ID" ]; then
  echo "start_run: no run_id returned - check pipeline '$PIPELINE', environment '$ENVIRONMENT' and that a pending release exists. Response: $RESULT" >&2
  exit 1
fi

echo "$RUN_ID"
