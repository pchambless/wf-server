#!/bin/bash
# RUNS LOCALLY. Marks a deployment_run succeeded once every step in the
# sequence has passed. run_step.sh already marks a run failed the moment a
# step errors - this only covers the success path, since run_step.sh has no
# way to know it just wrapped the last step in the sequence. No-op if the
# run already failed (WHERE status <> 'failed'), so a late call after an
# earlier error can't paper over it.
#
# Holistic runs (deployments.pipeline_id IS NULL = "all legs") must have EVERY
# enabled deploy_steps row logged 'success' before they can be marked
# succeeded - otherwise a run that only did one leg would read as a complete
# deploy (found 2026-10-09, run 79). The run is left 'running' and the missing
# steps are listed; close an abandoned one with: finish_run.sh <run_id> aborted
# Pipeline-pinned runs (a single leg on purpose) skip the check, as do
# non-succeeded statuses.
#
# Usage: finish_run.sh <run_id> [status]   # status defaults to 'succeeded'
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/pg-query.sh"

RUN_ID="${1:?Usage: finish_run.sh <run_id> [status]}"
STATUS="${2:-succeeded}"
STATUS_ESC=$(esc_sql "$STATUS")

if [ "$STATUS" = "succeeded" ]; then
  MISSING=$(pg_query "SELECT string_agg(ds.step_key, ', ' ORDER BY ds.ordr) AS m
    FROM deployment.deployment_runs r
    JOIN deployment.deployments d ON d.id = r.deployment_id
    JOIN deployment.deploy_steps ds ON ds.enabled
    WHERE r.id = $RUN_ID AND d.pipeline_id IS NULL
      AND NOT EXISTS (SELECT 1 FROM deployment.deployment_run_steps rs
                       WHERE rs.run_id = r.id AND rs.step_name = ds.step_key AND rs.status = 'success')" | jq -r '.[0].m // empty')
  if [ -n "$MISSING" ]; then
    echo "finish_run: run $RUN_ID is holistic but these steps have no success: $MISSING" >&2
    echo "finish_run: left 'running'. Finish the steps, or close it with: finish_run.sh $RUN_ID aborted" >&2
    exit 1
  fi
fi

pg_query "UPDATE deployment.deployment_runs SET status='$STATUS_ESC', finished_at=now() WHERE id=$RUN_ID AND status <> 'failed'" > /dev/null

# Report what actually landed, not the target status - the guard above can
# silently no-op (run already failed), and echoing $STATUS regardless would
# have said "succeeded" for a run that stayed failed.
ACTUAL=$(pg_query "SELECT status AS s FROM deployment.deployment_runs WHERE id=$RUN_ID" | jq -r '.[0].s // "unknown"')
echo "finish_run: run $RUN_ID -> $ACTUAL"
