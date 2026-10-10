#!/usr/bin/env bash
# RUNS LOCALLY (laptop). Upgrades n8n on the laptop, dev or prod with backup, verification and automatic rollback. Task 543.
#
#   n8n-upgrade.sh <local|dev|prod> [--to VERSION] [--apply] [--simulate-failure] [--allow-major]
#   n8n-upgrade.sh <local|dev|prod> --rollback     put back the pre-upgrade version + data
#   n8n-upgrade.sh <local|dev|prod> --finalize     accept the upgrade (rollback is refused afterwards)
#
# Without --apply this is a PREFLIGHT ONLY: every check runs, nothing is stopped or changed.
# The target is NOT typed: it is the nightly feed (deployment.latest_version) for the installed major version, and is
# refused if below that row's min_safe_version. --to overrides it (still subject to the same refusal).
# Canary order: local -> dev (soak 2-3 days) -> prod.   Workflow: see guidance entry for task 543 / Guide 28.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../deploy-lib/pg-query.sh"

ENV_NAME="${1:?Usage: n8n-upgrade.sh <local|dev|prod> [--to V] [--apply] [--simulate-failure] [--allow-major] [--rollback|--finalize]}"
shift
TO=""; APPLY=0; SIM=0; MAJOR=0; ACTION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --to) TO="$2"; shift 2;;
    --apply) APPLY=1; shift;;
    --simulate-failure) SIM=1; shift;;
    --allow-major) MAJOR=1; shift;;
    --rollback) ACTION=rollback; shift;;
    --finalize) ACTION=finalize; shift;;
    *) echo "unknown argument $1" >&2; exit 2;;
  esac
done

case "$ENV_NAME" in
  local) MODE=local;   SSH_HOST="";;
  dev)   MODE=droplet; SSH_HOST="n8n.whatsfresh.app";;
  prod)  MODE=droplet; SSH_HOST="root@142.93.113.124";;
  *) echo "environment must be local, dev or prod" >&2; exit 2;;
esac
[ "$SIM" = 0 ] || [ "$APPLY" = 1 ] || { echo "--simulate-failure only means something with --apply" >&2; exit 2; }

SSH=(ssh -n -o BatchMode=yes -o ControlMaster=no -o ControlPath=none -o ServerAliveInterval=15 -o ServerAliveCountMax=4 "$SSH_HOST")
remote() { if [ "$MODE" = local ]; then bash -c "$1"; else "${SSH[@]}" "$1"; fi; }

installed=$(remote "docker exec n8n n8n --version" 2>/dev/null | tr -d '\r' || true)
[ -n "$ACTION" ] && [ -z "$installed" ] && installed="not-running"
[ -n "$installed" ] || { echo "cannot read the installed n8n version on $ENV_NAME" >&2; exit 1; }
MAJOR_NOW="${installed%%.*}"
echo "==> $ENV_NAME: n8n $installed installed"

# --- target from the feed
if [ "$ACTION" = "" ]; then
  row=$(pg_query "select latest_version, coalesce(min_safe_version,'') as m from deployment.latest_version where component='n8n' and major='${MAJOR_NOW}'" )
  FEED=$(jq -r '.[0].latest_version // empty' <<<"$row"); MIN_SAFE=$(jq -r '.[0].m // empty' <<<"$row")
  [ -n "$FEED" ] || { echo "no n8n row for major $MAJOR_NOW in deployment.latest_version" >&2; exit 1; }
  [ -n "$TO" ] || TO="$FEED"
  echo "==> feed says latest $FEED, min safe ${MIN_SAFE:-none}; target $TO"
fi

# --- ship the host-side tools and run the action DETACHED, following its log
RUN_ARGS=("$ACTION")
if [ -z "$ACTION" ]; then
  if [ "$APPLY" = 1 ]; then RUN_ARGS=(upgrade); else RUN_ARGS=(preflight); fi
  RUN_ARGS+=(--to "$TO" --min-safe "$MIN_SAFE")
  [ "$SIM" = 1 ] && RUN_ARGS+=(--simulate-failure)
  [ "$MAJOR" = 1 ] && RUN_ARGS+=(--allow-major)
else
  RUN_ARGS+=(--to "${installed}")
fi
RUN_ARGS+=(--mode "$MODE")

if [ "$MODE" = local ]; then
  TOOLS="$HOME/.cache/n8n-upgrade-tools"; LOG="$TOOLS/last.log"
  mkdir -p "$TOOLS"; cp "$HERE/host-upgrade.sh" "$TOOLS/"; : > "$LOG"
  [ "$ACTION" = "" ] && [ "$APPLY" = 1 ] && echo "==> laptop n8n will be briefly down; compose file $HOME/Projects/local-desk/n8n/docker-compose.yml gets the new image tag (left uncommitted)"
  set -a; [ -f "$HOME/Projects/local-desk/n8n/.env" ] && source "$HOME/Projects/local-desk/n8n/.env"; set +a
  setsid nohup bash "$TOOLS/host-upgrade.sh" "${RUN_ARGS[@]}" > "$LOG" 2>&1 < /dev/null &
else
  TOOLS=/home/n8n/n8n-compose/tools; LOG=$TOOLS/last.log
  "${SSH[@]}" "mkdir -p $TOOLS"
  scp -q -o BatchMode=yes -o ControlMaster=no -o ControlPath=none "$HERE/host-upgrade.sh" "$HERE/check-compose-parity.sh" "$SSH_HOST:$TOOLS/"
  "${SSH[@]}" "cd $TOOLS && : > last.log && setsid nohup bash host-upgrade.sh ${RUN_ARGS[*]} > last.log 2>&1 < /dev/null &"
fi

# follow the log until a RESULT line (survives an ssh blip: each poll is a fresh short ssh)
seen=0; RESULT=""; idle=0
while [ -z "$RESULT" ]; do
  sleep 4
  if out=$(remote "tail -n +$((seen+1)) $LOG" 2>/dev/null); then
    if [ -n "$out" ]; then printf '%s\n' "$out"; seen=$((seen + $(printf '%s\n' "$out" | wc -l))); idle=0; else idle=$((idle+1)); fi
  else idle=$((idle+1)); fi
  RESULT=$(remote "grep -m1 'RESULT: ' $LOG" 2>/dev/null | sed 's/^\[[0-9:]*\] //' || true)
  [ "$idle" -lt 200 ] || { echo "no progress for ~13 minutes - the host script may be hung. Log: $SSH_HOST:$LOG" >&2; exit 1; }
done
sleep 1; out=$(remote "tail -n +$((seen+1)) $LOG" 2>/dev/null || true); [ -z "$out" ] || printf '%s\n' "$out"

case "$RESULT" in
  "RESULT: UPGRADED"*)
    # smoke test from OUTSIDE the host: the public path, not just the container's own healthz
    if [ "$ENV_NAME" = dev ]; then
      echo "==> smoke test: server-query webhook through n8n.whatsfresh.app"
      if ! pg_query "select 1 as ok" | grep -q '"ok":1'; then
        echo "SMOKE TEST FAILED - rolling back"; "$0" "$ENV_NAME" --rollback; exit 1
      fi
      echo "    ok"
    fi
    echo "==> accepted? run: $0 $ENV_NAME --finalize   (or --rollback to undo)"; exit 0;;
  "RESULT: PREFLIGHT OK"*|"RESULT: ROLLED BACK"*|"RESULT: FINALIZED"*|"RESULT: nothing to finalize"*) exit 0;;
  *) exit 1;;
esac
