#!/usr/bin/env bash
# make-personal-suite.sh: derive the personal-* copies of the app-engine n8n workflows on the DEV n8n (task 594).
#
#   make-personal-suite.sh            export the five originals to git, then create/update the five personal-* copies
#   make-personal-suite.sh --check    change nothing; exit 1 if a live copy no longer matches what would be generated
#
# WHY COPIES: an n8n Postgres node holds ONE fixed credential, so the app-engine workflows that serve support (credential
# "Postgres Dev2", database n8n) cannot also serve the personal database. The copies are identical except for exactly four
# things, so they are GENERATED, never edited by hand (re-run this after any change to an original):
#   1. name              app-x  ->  personal-app-x   (server-query -> personal-server-query)
#   2. webhook path      same prefix; a fresh webhookId per copy
#   3. Postgres node     credential "Postgres Dev2" -> "Postgres Personal" (database personal, role personal_admin)
#   4. sub-workflow link app-hydrate-guide's Execute Workflow node points at personal-app-styled-html
# The originals are only READ (GET). Nothing here repoints, updates or activates an original.
# An app uses the copies by setting N8N_WORKFLOW_PREFIX=personal- (task 593) for its process.
#
# Writes in the repo: n8n/workflows-dev-only/<name>.json (originals) and personal-<name>.json (copies, as generated).
# Requires: curl, jq, and N8N_DEV2_API_KEY in wf-agents/.env. Dev n8n only: personal apps are not on prod.
# The credential id is specific to this n8n instance (looked up 2026-10-18); update it if the credential is recreated.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
OUT_DIR="$REPO_DIR/n8n/workflows-dev-only"
AGENTS_ENV="$(dirname "$REPO_DIR")/wf-agents/.env"
N8N_BASE="${N8N_BASE_URL:-https://n8n.whatsfresh.app}"
PREFIX="personal-"
SRC_CRED_NAME="Postgres Dev2"
PERSONAL_CRED_ID="OiUIIselM7ZvRymj"
PERSONAL_CRED_NAME="Postgres Personal"
# Order matters: the styled-html sub-workflow is created before the one that calls it.
NAMES=(app-styled-html app-engine-actions app-page-structure app-hydrate-guide server-query)

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

KEY="$(sed -n 's/^N8N_DEV2_API_KEY=//p' "$AGENTS_ENV" | head -1 | tr -d '"')"
[ -n "$KEY" ] || { echo "make-personal-suite: N8N_DEV2_API_KEY missing from $AGENTS_ENV" >&2; exit 1; }
api() { curl -s -m 60 -H "X-N8N-API-KEY: $KEY" -H "Content-Type: application/json" "$@"; }

LIST="$(api "$N8N_BASE/api/v1/workflows?limit=250")"
id_of() { echo "$LIST" | jq -r --arg n "$1" '.data[] | select(.name == $n) | .id' | head -1; }   # exact name, not the fuzzy name= filter

# jq: the four differences, and nothing else. $map = {"app-styled-html": "<copy id>"} for the sub-workflow link.
GEN='{name: ($p + .name),
      nodes: [.nodes[]
        | (if (.type | endswith(".webhook")) then .parameters.path = ($p + .parameters.path) | .webhookId = $wid else . end)
        | (if .credentials.postgres.name == $src then .credentials.postgres = {id: $cid, name: $cname} else . end)
        | (if (.type | endswith(".executeWorkflow")) and ((.parameters.workflowId.cachedResultName // "") as $n | $map[$n] != null)
             then .parameters.workflowId = {"__rl": true, "mode": "list", "value": $map[.parameters.workflowId.cachedResultName], "cachedResultName": ($p + .parameters.workflowId.cachedResultName)}
             else . end)],
      connections, settings: {executionOrder: (.settings.executionOrder // "v1")}}'
# Comparable view of a workflow: per node name/type/parameters/credential names, sorted; ignores ids, positions, webhookId.
NORM='[.nodes[] | {name, type, parameters: (.parameters | del(.workflowId.cachedResultUrl)), cred: ([.credentials // {} | to_entries[] | .value.name] | sort)}] | sort_by(.name)'

declare -A COPY_ID=()
for n in "${NAMES[@]}"; do cid="$(id_of "$PREFIX$n")"; [ -n "$cid" ] && COPY_ID[$n]="$cid"; done
DRIFT=0

for n in "${NAMES[@]}"; do
  src_id="$(id_of "$n")"
  [ -n "$src_id" ] || { echo "make-personal-suite: original '$n' not found on $N8N_BASE" >&2; exit 1; }
  src="$(api "$N8N_BASE/api/v1/workflows/$src_id" | jq '{name, active, nodes, connections, settings}')"
  echo "$src" | jq -S . > "$OUT_DIR/$n.json"

  map="$(for k in "${!COPY_ID[@]}"; do jq -n --arg k "$k" --arg v "${COPY_ID[$k]}" '{($k): $v}'; done | jq -s 'add // {}')"
  wid="$(cat /proc/sys/kernel/random/uuid)"
  payload="$(echo "$src" | jq --arg p "$PREFIX" --arg src "$SRC_CRED_NAME" --arg cid "$PERSONAL_CRED_ID" --arg cname "$PERSONAL_CRED_NAME" --arg wid "$wid" --argjson map "$map" "$GEN")"

  copy_id="${COPY_ID[$n]:-}"
  if [ "$CHECK" = 1 ]; then
    if [ -z "$copy_id" ]; then echo "MISSING $PREFIX$n"; DRIFT=1; continue; fi
    live="$(api "$N8N_BASE/api/v1/workflows/$copy_id")"
    if [ "$(echo "$payload" | jq -S "$NORM")" = "$(echo "$live" | jq -S "$NORM")" ]; then echo "ok      $PREFIX$n ($copy_id)"; else echo "DRIFTED $PREFIX$n ($copy_id)"; DRIFT=1; fi
    continue
  fi

  if [ -n "$copy_id" ]; then
    res="$(api -X PUT "$N8N_BASE/api/v1/workflows/$copy_id" --data "$payload")"; action=updated
  else
    res="$(api -X POST "$N8N_BASE/api/v1/workflows" --data "$payload")"; action=created
  fi
  copy_id="$(echo "$res" | jq -r '.id // empty')"
  [ -n "$copy_id" ] || { echo "make-personal-suite: FAILED $PREFIX$n: $(echo "$res" | jq -c '.message // .')" >&2; exit 1; }
  COPY_ID[$n]="$copy_id"
  if [ "$(echo "$src" | jq -r .active)" = "true" ]; then api -X POST "$N8N_BASE/api/v1/workflows/$copy_id/activate" > /dev/null; fi
  api "$N8N_BASE/api/v1/workflows/$copy_id" | jq -S '{name, active, nodes, connections, settings}' > "$OUT_DIR/$PREFIX$n.json"
  echo "$action $PREFIX$n -> $copy_id (active=$(echo "$src" | jq -r .active))"
done

[ "$CHECK" = 1 ] && exit "$DRIFT"
exit 0
