#!/bin/bash
# RUNS LOCALLY. Wraps one deploy step: logs a 'running' event to
# deployment.deployment_run_steps, execs the command untouched (stdout/stderr
# still visible live, not swallowed), then logs 'success' or 'error' with the
# last output line as detail. On error also marks the parent deployment_runs
# row failed (status/error/error_stage/finished_at). The wrapped command does
# not need to know this exists - no script changes required to adopt it.
#
# step_name should be one of deployment.deploy_steps.step_key so a step log
# ties back to the canonical process definition instead of inventing a
# parallel naming scheme.
#
# Usage: run_step.sh <run_id> <step_name> -- <command...>
# Exit code is the wrapped command's exit code.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/pg-query.sh"

RUN_ID="${1:?Usage: run_step.sh <run_id> <step_name> -- <command...>}"
STEP_NAME="${2:?Usage: run_step.sh <run_id> <step_name> -- <command...>}"
shift 2
if [ "${1:-}" != "--" ]; then
  echo "run_step: expected -- before the command" >&2
  exit 1
fi
shift
if [ "$#" -eq 0 ]; then
  echo "run_step: no command given after --" >&2
  exit 1
fi

STEP_ESC=$(esc_sql "$STEP_NAME")

pg_query "INSERT INTO deployment.deployment_run_steps (run_id, step_name, status) VALUES ($RUN_ID, '$STEP_ESC', 'running')" > /dev/null

OUTPUT_FILE=$(mktemp)
trap 'rm -f "$OUTPUT_FILE"' EXIT
"$@" 2>&1 | tee "$OUTPUT_FILE"
EXIT_CODE=${PIPESTATUS[0]}

# Strip ANSI color codes before the blank-line check - prod_deploy.sh's
# colored log_info "" spacer lines are invisible but not byte-empty, so they
# survived the filter and became the "detail" instead of a real message
# (found 2026-08-21 running this for real against prod).
DETAIL=$(sed 's/\x1b\[[0-9;]*m//g' "$OUTPUT_FILE" | grep -v '^[[:space:]]*$' | tail -n1 | cut -c1-500)
DETAIL_ESC=$(esc_sql "$DETAIL")

if [ "$EXIT_CODE" -eq 0 ]; then
  pg_query "INSERT INTO deployment.deployment_run_steps (run_id, step_name, status, detail) VALUES ($RUN_ID, '$STEP_ESC', 'success', '$DETAIL_ESC')" > /dev/null
else
  pg_query "INSERT INTO deployment.deployment_run_steps (run_id, step_name, status, detail) VALUES ($RUN_ID, '$STEP_ESC', 'error', '$DETAIL_ESC')" > /dev/null
  # error_stage is constrained to connect/plan/execute/verify (deployment_runs_stage_chk) -
  # coarser than step_key. deployment_run_steps.step_name is the precise record now,
  # this just needs to land in the existing bucket every one of our steps falls under.
  pg_query "UPDATE deployment.deployment_runs SET status='failed', error='$DETAIL_ESC', error_stage='execute', finished_at=now() WHERE id=$RUN_ID" > /dev/null
fi

exit "$EXIT_CODE"
