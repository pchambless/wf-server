#!/bin/bash
# RUNS LOCALLY. Marks a deployment_run succeeded once every step in the
# sequence has passed. run_step.sh already marks a run failed the moment a
# step errors - this only covers the success path, since run_step.sh has no
# way to know it just wrapped the last step in the sequence. No-op if the
# run already failed (WHERE status <> 'failed'), so a late call after an
# earlier error can't paper over it.
#
# 'succeeded' is gated by deployment.f_check_run(run_id) - the single rule set
# (holistic runs need every enabled step, data before code, gates first).
# Violations leave the run 'running' and are printed; close an abandoned one
# with: finish_run.sh <run_id> aborted. Other statuses skip the check.
#
# Usage: finish_run.sh <run_id> [status]   # status defaults to 'succeeded'
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/pg-query.sh"

RUN_ID="${1:?Usage: finish_run.sh <run_id> [status]}"
STATUS="${2:-succeeded}"
STATUS_ESC=$(esc_sql "$STATUS")

# deployment.f_finish_run gates 'succeeded' on f_check_run and never overwrites
# a failed run; same function the n8n orchestrator calls.
RESULT=$(pg_query "SELECT deployment.f_finish_run($RUN_ID, '$STATUS_ESC') AS r")
OK=$(printf '%s' "$RESULT" | jq -r '.[0].r.ok // empty')
ACTUAL=$(printf '%s' "$RESULT" | jq -r '.[0].r.status // "unknown"')

if [ "$OK" != "true" ]; then
  VIOLATIONS=$(printf '%s' "$RESULT" | jq -r '.[0].r.violations // empty')
  if [ -n "$VIOLATIONS" ]; then
    echo "finish_run: run $RUN_ID fails deployment.f_check_run:" >&2
    printf '  %s\n' "$VIOLATIONS" >&2
    echo "finish_run: left 'running'. Finish the steps, or close it with: finish_run.sh $RUN_ID aborted" >&2
    exit 1
  fi
fi

# Report what actually landed, not the target status (a failed run stays failed).
echo "finish_run: run $RUN_ID -> $ACTUAL"
