#!/bin/bash
# RUNS LOCALLY (or on the prod droplet, same as run_step.sh). Guard for the
# legs that join an EXISTING holistic run (--run-id): confirms the run exists,
# is still 'running', and targets the environment the leg is about to touch.
# Stops a leg from logging into a finished/failed run or one aimed at the
# wrong environment.
#
# Usage: check_run.sh <run_id> <environment>
# Exit 0 if the run is open and matches; 1 (with a message on stderr) if not.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/pg-query.sh"

RUN_ID="${1:?Usage: check_run.sh <run_id> <environment>}"
ENVIRONMENT="${2:?Usage: check_run.sh <run_id> <environment>}"

case "$RUN_ID" in ''|*[!0-9]*) echo "check_run: run_id must be an integer, got '$RUN_ID'" >&2; exit 1;; esac
ENV_ESC=$(esc_sql "$ENVIRONMENT")

ROW=$(pg_query "SELECT r.status, e.name AS env FROM deployment.deployment_runs r JOIN deployment.deployments d ON d.id = r.deployment_id JOIN deployment.environments e ON e.id = d.environment_id WHERE r.id = $RUN_ID")
STATUS=$(printf '%s' "$ROW" | jq -r '.[0].status // empty')
RUN_ENV=$(printf '%s' "$ROW" | jq -r '.[0].env // empty')

if [ -z "$STATUS" ]; then
  echo "check_run: run $RUN_ID not found" >&2; exit 1
fi
if [ "$STATUS" != "running" ]; then
  echo "check_run: run $RUN_ID is '$STATUS', not 'running' - start a new run" >&2; exit 1
fi
if [ "$RUN_ENV" != "$ENVIRONMENT" ]; then
  echo "check_run: run $RUN_ID targets '$RUN_ENV', this leg deploys to '$ENVIRONMENT'" >&2; exit 1
fi
exit 0
