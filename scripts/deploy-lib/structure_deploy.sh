#!/bin/bash
# RUNS LOCALLY. One command for a structure-only deploy of ONE database pipeline (whatsfresh or studio) to prod:
# the compare, the sequence check, the plan, the structure apply and the verify, every step logged under one run.
# Written for the 2026-10-28 hotfix (Release 15, Task 208) so nobody has to chain start_run / deploy_step /
# finish_run by hand in the right order. No code leg, no n8n leg, no data leg.
#
# DRY by default: a dry run previews the structure step and never counts as shipped. --live applies it, and stops
# first to show the compare and ask for the typed confirmation.
#
# Usage: structure_deploy.sh <pipeline> <release_id> <task_id> [--live] [--expect N]
#   pipeline    whatsfresh | studio
#   release_id  agile.releases.id the run belongs to (e.g. the hotfix release)
#   task_id     the agile task the run anchors to; a succeeded live run closes it Done
#   --live      apply for real (asks you to type: deploy prod)
#   --expect N  stop (and abort the run) unless the compare lists exactly N differences
#
# Any unexpected result aborts the run with finish_run.sh <run> aborted and exits non-zero. A step that fails
# inside deploy_step.sh already fails the run itself.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PIPELINE="${1:-}"; RELEASE_ID="${2:-}"; TASK_ID="${3:-}"
if [ -z "$PIPELINE" ] || [ -z "$RELEASE_ID" ] || [ -z "$TASK_ID" ]; then
  sed -n '/^# Usage:/,/^#   --expect/p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
fi
shift 3
LIVE=0; EXPECT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --live) LIVE=1 ;;
    --expect) EXPECT="${2:-}"; shift ;;
    *) echo "structure_deploy: unknown option '$1'" >&2; exit 2 ;;
  esac
  shift
done
case "$PIPELINE" in whatsfresh|studio) ;; *) echo "structure_deploy: pipeline must be whatsfresh or studio, got '$PIPELINE'" >&2; exit 2 ;; esac
case "$RELEASE_ID$TASK_ID" in *[!0-9]*) echo "structure_deploy: release_id and task_id must be numbers" >&2; exit 2 ;; esac
[ -n "$EXPECT" ] && case "$EXPECT" in *[!0-9]*) echo "structure_deploy: --expect needs a number" >&2; exit 2 ;; esac

BY="${DEPLOY_BY:-${USER:-deploy}}"
DRY_JSON=true; MODE_WORD="DRY RUN"
if [ "$LIVE" = 1 ]; then DRY_JSON=false; MODE_WORD="LIVE"; fi
COMPARE_STEP="compare_$PIPELINE"

RUN=""
abort() {
  echo "structure_deploy: STOP - $1" >&2
  if [ -n "$RUN" ]; then
    bash "$SCRIPT_DIR/finish_run.sh" "$RUN" aborted >&2 || true
    echo "structure_deploy: run $RUN aborted." >&2
  fi
  exit 1
}
step() {  # step <step_key>  -> prints the step's JSON rows on stdout; fails the script if the step fails
  bash "$SCRIPT_DIR/deploy_step.sh" "$RUN" "$1" "{\"env\":\"prod\",\"run_id\":$RUN,\"dry_run\":$DRY_JSON,\"task_id\":$TASK_ID,\"by\":\"$BY\"}" \
    || abort "step $1 failed (see deployment.deployment_run_steps, run $RUN)"
}

echo "== structure_deploy: $MODE_WORD - pipeline $PIPELINE, release $RELEASE_ID, task $TASK_ID"

if [ "$LIVE" = 1 ]; then
  RUN=$(bash "$SCRIPT_DIR/start_run.sh" "$PIPELINE" prod "$RELEASE_ID" "" "$BY" "" "$TASK_ID") || { echo "structure_deploy: could not start the run" >&2; exit 1; }
else
  RUN=$(bash "$SCRIPT_DIR/start_run.sh" "$PIPELINE" prod "$RELEASE_ID" "" "$BY" dry "$TASK_ID") || { echo "structure_deploy: could not start the run" >&2; exit 1; }
fi
[ -n "$RUN" ] || { echo "structure_deploy: no run id returned" >&2; exit 1; }
echo "== run $RUN started"

echo "== 1. compare ($COMPARE_STEP)"
ROWS=$(step "$COMPARE_STEP") || exit 1
COUNT=$(printf '%s' "$ROWS" | jq 'length')
printf '%s' "$ROWS" | jq -r '.[] | "   \(.category)\t\(.object_name)\t\(.detail)"'
echo "   $COUNT difference(s)"
if [ -n "$EXPECT" ] && [ "$COUNT" != "$EXPECT" ]; then abort "expected $EXPECT differences, the compare lists $COUNT"; fi

echo "== 2. sequence check (compare_sequences)"
SEQ=$(step compare_sequences) || exit 1
[ "$(printf '%s' "$SEQ" | jq 'length')" = "0" ] || { printf '%s\n' "$SEQ" | jq -c '.[]'; abort "sequence drift found"; }
echo "   clean"

if [ "$LIVE" = 1 ]; then
  echo
  echo "About to APPLY the structure to PROD (run $RUN). Close DBeaver / any GUI connection to prod first."
  printf "Type 'deploy prod' to continue: "
  read -r ANSWER
  [ "$ANSWER" = "deploy prod" ] || abort "not confirmed"
fi

echo "== 3. plan"
PLAN=$(step plan) || exit 1
printf '%s' "$PLAN" | jq -c '.[0]'

echo "== 4. structure ($MODE_WORD)"
STRUCT=$(step structure) || exit 1
printf '%s' "$STRUCT" | jq -r 'group_by(.object_type + " " + .status) | .[] | "   \(.[0].object_type) \(.[0].status): \(length)"'
FAILED=$(printf '%s' "$STRUCT" | jq '[.[] | select(.status == "failed")] | length')
if [ "$FAILED" != "0" ]; then
  printf '%s' "$STRUCT" | jq -r '.[] | select(.status == "failed") | "   FAILED \(.schema_path): \(.error)"'
  abort "$FAILED object(s) failed"
fi

echo "== 5. verify (re-run the compare)"
VER=$(step verify) || exit 1
LEFT=$(printf '%s' "$VER" | jq --arg s "$PIPELINE" '[.[] | select(.schema_name == $s)] | length')
printf '%s' "$VER" | jq -r --arg s "$PIPELINE" '.[] | select(.schema_name == $s) | "   \(.category)\t\(.object_name)\t\(.detail)"'
if [ "$LIVE" = 1 ] && [ "$LEFT" != "0" ]; then
  echo "structure_deploy: WARNING - $LEFT $PIPELINE difference(s) remain after the apply (listed above)." >&2
  echo "The run is left open so nothing is hidden: look, then close it with finish_run.sh $RUN aborted (or fix and finish it)." >&2
  exit 1
fi
[ "$LIVE" = 1 ] && echo "   no $PIPELINE differences left"

echo "== 6. close the run"
bash "$SCRIPT_DIR/finish_run.sh" "$RUN" || { echo "structure_deploy: finish_run refused - see its violations above; run $RUN is still open" >&2; exit 1; }
echo "== done: run $RUN ($MODE_WORD). Watch or review it at support.whatsfresh.app/deploy-monitor"
