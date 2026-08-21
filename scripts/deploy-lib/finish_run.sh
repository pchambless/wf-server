#!/bin/bash
# RUNS LOCALLY. Marks a deployment_run succeeded once every step in the
# sequence has passed. run_step.sh already marks a run failed the moment a
# step errors - this only covers the success path, since run_step.sh has no
# way to know it just wrapped the last step in the sequence. No-op if the
# run already failed (WHERE status <> 'failed'), so a late call after an
# earlier error can't paper over it.
#
# Usage: finish_run.sh <run_id> [status]   # status defaults to 'succeeded'
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/pg-query.sh"

RUN_ID="${1:?Usage: finish_run.sh <run_id> [status]}"
STATUS="${2:-succeeded}"
STATUS_ESC=$(esc_sql "$STATUS")

pg_query "UPDATE deployment.deployment_runs SET status='$STATUS_ESC', finished_at=now() WHERE id=$RUN_ID AND status <> 'failed'" > /dev/null

# Report what actually landed, not the target status - the guard above can
# silently no-op (run already failed), and echoing $STATUS regardless would
# have said "succeeded" for a run that stayed failed.
ACTUAL=$(pg_query "SELECT status AS s FROM deployment.deployment_runs WHERE id=$RUN_ID" | jq -r '.[0].s // "unknown"')
echo "finish_run: run $RUN_ID -> $ACTUAL"
