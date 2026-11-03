#!/bin/bash
# RUNS LOCALLY. One command for a whole release deploy to prod: starts a run pinned to the release,
# runs every step in the order f_check_run requires (compares first, then capture, plan, structure,
# data, n8n, code, verify), shows a short summary after each, and stops at the first problem.
# Stopgap until the Deploy Monitor can do this from the page (task 831).
#
# Usage: run_release.sh <release_id> [--dry | --run <run_id>]
#   --dry         opens a dry run: runs the five compares only, then closes the run as aborted.
#   --run <id>    carry on with a live run you already started (start_run.sh) instead of opening a new one.
# Run it from anywhere; it cd's into wf-server. You answer y/n at each pause. Never Ctrl-C a live run:
# a stopped run is left open and the message says how to close it (finish_run.sh RUN aborted).
#
# Things it cannot do for you (it asks): close GUI database clients on prod, run any hand migrations
# (and fix function owners, see adhoc/release-7-deploy-2026-11-03/fix_owner.sql), push main.
set -uo pipefail
cd "$(dirname "$0")/../.."
LIB=scripts/deploy-lib
PROD=root@142.93.113.124
# shellcheck source=pg-query.sh
source "$LIB/pg-query.sh"

REL="${1:?usage: run_release.sh <release_id> [--dry | --run <run_id>]}"
DRY=""; RUN=""
case "${2:-}" in
  --dry) DRY="dry" ;;
  --run) RUN="${3:?--run needs a run id}"; JOINED=1 ;;
esac
JOINED="${JOINED:-}"

say()  { printf '\n== %s\n' "$*"; }
ask()  { local a; read -r -p "$1 [y/N] " a; [ "$a" = "y" ]; }
stop() {
  printf '\nSTOPPED: %s\n' "$*" >&2
  [ -n "$RUN" ] && printf 'Run %s is left open. Fix it and carry on by hand with %s/deploy_step.sh %s <step> <json>, or close it: %s/finish_run.sh %s aborted\n' "$RUN" "$LIB" "$RUN" "$LIB" "$RUN" >&2
  exit 1
}
trap '[ -n "$RUN" ] && echo "Ctrl-C: run $RUN left open. Close with: $LIB/finish_run.sh $RUN aborted"; exit 130' INT

step() {  # step <key> <params-json>  -> sets OUT
  OUT=$("$LIB/deploy_step.sh" "$RUN" "$1" "$2") || { echo "$OUT"; stop "step $1 failed"; }
}
names() { jq -r '.[] | "   - " + ((.object_name // .workflow_name // .schema_path // .name // (.|tostring)) | tostring)'; }

# 0. preflight: facts we can check, then the ones we can only ask
say "Preflight"
git fetch -q origin 2>/dev/null || echo "WARNING: could not reach GitHub; comparing with the last known origin/main"
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || stop "HEAD is not origin/main: push main (or switch branch) first"
echo "HEAD = origin/main = $(git rev-parse --short HEAD)"
if [ -z "$DRY" ]; then
  ask "DBeaver (or any GUI) connections to prod are closed?" || stop "close them first (an open transaction blocked run 4044)"
  ask "Any hand migrations for this release are run, and function owners fixed (wf_admin)?" || stop "run them first"
fi

# 1. start the run, pinned to the release
if [ -n "$JOINED" ]; then
  say "Joining run $RUN"
else
  say "Starting run (release $REL ${DRY:-live})"
  RUN=$("$LIB/start_run.sh" all prod "$REL" "$(git rev-parse HEAD)" paul $DRY) || stop "start_run failed"
  [ -n "$RUN" ] || stop "start_run printed no run id"
fi
TASK=$(pg_query "select d.task_id from deployment.deployments d join deployment.deployment_runs r on r.deployment_id = d.id where r.id = $RUN" | jq -r '.[0].task_id')
echo "run $RUN, release task $TASK"

# 2. the compares, in the order the run checker wants (all before structure/data)
say "Compares"
for s in compare_whatsfresh compare_studio compare_sequences; do
  step "$s" '{"env":"prod"}'; echo "$s: $(echo "$OUT" | jq length) difference(s)"; echo "$OUT" | names
done
step compare_n8n '{"env":"prod"}'
echo "compare_n8n: $(echo "$OUT" | jq '[.[] | select(.needs_deploy)] | length') workflow(s) to deploy"
echo "$OUT" | jq -r '.[] | select(.needs_deploy) | "   - " + .workflow_name + " (" + .detail + ")"'
step compare_data '{"env":"prod"}'
echo "compare_data:"
echo "$OUT" | jq -r '.[] | select(.status != "in sync") | "   - \(.schema_path): +\(.rows_added) added, \(.rows_modified) modified, \(.rows_deleted) deleted"'
[ "$(echo "$OUT" | jq '[.[].rows_deleted] | add')" = "0" ] || stop "compare_data would delete rows"

if [ -n "$DRY" ]; then
  "$LIB/finish_run.sh" "$RUN" aborted
  say "Dry run done and closed. Nothing was changed."; exit 0
fi
ask "Do those differences match what you expect for this release?" || stop "differences are not what you expected"

# 3. the changing steps
say "Capture impacts and plan"
step capture_impacts "{\"task_id\": $TASK, \"dry_run\": false, \"by\": \"paul\"}"; echo "capture_impacts: $(echo "$OUT" | jq length) item(s)"
step plan "{\"run_id\": $RUN}"; echo "plan: $(echo "$OUT" | jq -r '.[0].objects_planned') objects"

say "Structure"
step structure "{\"run_id\": $RUN, \"dry_run\": false}"
BAD=$(echo "$OUT" | jq '[.[] | select(.status != "succeeded" or .error != null)] | length')
echo "structure: $(echo "$OUT" | jq length) object(s), $BAD failed"
[ "$BAD" = "0" ] || { echo "$OUT" | jq -r '.[] | select(.status != "succeeded" or .error != null) | "   FAILED \(.schema_path): \(.error)"'; stop "structure has failed objects (the step label can still say success)"; }

say "Data"
step data "{\"run_id\": $RUN, \"dry_run\": false, \"force_refresh\": false, \"allow_deletes\": false}"
BAD=$(echo "$OUT" | jq '[.[] | select(.error != null)] | length')
echo "data: $(echo "$OUT" | jq '[.[] | select(.status == "succeeded")] | length') table(s) refreshed, $(echo "$OUT" | jq '[.[].rows_affected] | add') row(s), $BAD error(s)"
[ "$BAD" = "0" ] || stop "data step has errors"

say "n8n workflows"
"$LIB/../import-n8n-workflows.sh" --run-id "$RUN" || stop "n8n import failed"

say "Code (restarts wf-server)"
ssh "$PROD" "bash /root/wf-server/scripts/production/prod_deploy.sh --run-id $RUN" || stop "code deploy failed"

# 4. verify and close
say "Verify"
step verify '{"env":"prod"}'
[ "$(echo "$OUT" | jq length)" = "0" ] || { echo "$OUT" | names; stop "verify found differences"; }
echo "verify: prod matches dev"

say "Closing run $RUN"
"$LIB/finish_run.sh" "$RUN" || stop "finish_run refused to close the run"
say "Done. Run $RUN closed as succeeded. Now check the release and do the in-app checks."
