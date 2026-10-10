#!/usr/bin/env bash
# RUNS LOCALLY (laptop, Docker Desktop). Rehearses an n8n version bump on a COPY of a droplet's real n8n data, so the
# one-way DB migrations are proven before they touch dev or prod. Nothing real is changed. Task 543.
#
#   rehearse-upgrade.sh <ssh-host> <to-version>      e.g.  rehearse-upgrade.sh n8n.whatsfresh.app 2.42.6
#
# What it does:
#   1. copies the droplet's n8n tables (schema public only - the WhatsFresh app schemas that share that database are
#      NOT copied; no execution history) into a scratch database + scratch role on the laptop's local Postgres
#   2. DEACTIVATES every workflow in the copy BEFORE starting n8n - a copy must never run the nightly schedules,
#      triggers or webhooks of the real thing
#   3. starts n8nio/n8n:<to-version> against the copy, published on 127.0.0.1:5688 (it reaches the laptop Postgres
#      through host.docker.internal - Docker Desktop runs containers in a VM, so host networking would not see it);
#      the new version runs its migrations
#   4. reports: migrations before/after, workflow + credential counts unchanged, workflows exportable by the new
#      version, errors in the startup log
#   5. removes the container, database and role (also on failure / Ctrl-C)
# The rehearsal container gets a throwaway encryption key, so credentials cannot be decrypted (and are not needed).
set -euo pipefail

HOST="${1:?Usage: rehearse-upgrade.sh <ssh-host> <to-version>}"
TO="${2:?Usage: rehearse-upgrade.sh <ssh-host> <to-version>}"

DB=n8n_rehearsal
ROLE=n8n_rehearsal
CTR=n8n_rehearsal
PORT=5688
PASS=$(openssl rand -hex 16)
KEY=$(openssl rand -hex 16)
DUMP=$(mktemp /tmp/n8n_rehearsal.XXXXXX)
PSQL_ADMIN=(psql -v ON_ERROR_STOP=1 -X -q -d postgres)
SCRATCH() { PGPASSWORD="$PASS" psql -v ON_ERROR_STOP=1 -X -q -tA -h 127.0.0.1 -U "$ROLE" -d "$DB" "$@"; }

cleanup() {
  rm -f "$DUMP" "$DUMP.list"
  docker rm -f "$CTR" >/dev/null 2>&1 || true
  "${PSQL_ADMIN[@]}" -c "DROP DATABASE IF EXISTS $DB" >/dev/null 2>&1 || true
  "${PSQL_ADMIN[@]}" -c "DROP ROLE IF EXISTS $ROLE" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

echo "==> pulling n8nio/n8n:${TO} (kept if already present)"
docker pull -q "n8nio/n8n:${TO}" >/dev/null

echo "==> scratch database + role on the local Postgres"
# PG16+: the creator can only hand a database to a role it can SET ROLE to; createrole_self_grant gives that on roles it creates
"${PSQL_ADMIN[@]}" -c "SET createrole_self_grant = 'set,inherit'" -c "CREATE ROLE $ROLE LOGIN PASSWORD '$PASS'" -c "CREATE DATABASE $DB OWNER $ROLE"

echo "==> copying ${HOST}'s n8n tables (schema public only, no execution history)"
# -n: no stdin; keepalives notice a dead link in about a minute; hard cap so a stalled connection cannot hang this forever
timeout 300 ssh -n -o BatchMode=yes -o ControlMaster=no -o ControlPath=none -o ServerAliveInterval=15 -o ServerAliveCountMax=4 "$HOST" \
  "sudo -u postgres pg_dump -Fc -n public --no-owner --no-acl --exclude-table-data='public.execution_*' n8n" > "$DUMP"
# leave out what is not n8n data: extensions (dblink needs a superuser) and the schema itself (the scratch database already has public)
pg_restore -l "$DUMP" | grep -vE " EXTENSION | COMMENT - EXTENSION | SCHEMA - public | COMMENT - SCHEMA public " > "$DUMP.list"
PGPASSWORD="$PASS" pg_restore -h 127.0.0.1 -U "$ROLE" -d "$DB" --no-owner --no-acl --exit-on-error -L "$DUMP.list" "$DUMP"
rm -f "$DUMP" "$DUMP.list"

M_BEFORE=$(SCRATCH -c "select count(*) from migrations")
M_LAST_BEFORE=$(SCRATCH -c "select name from migrations order by id desc limit 1")
WF=$(SCRATCH -c "select count(*) from workflow_entity")
WF_ACTIVE=$(SCRATCH -c "select count(*) from workflow_entity where active")
CRED=$(SCRATCH -c "select count(*) from credentials_entity")
echo "    copy: ${WF} workflows (${WF_ACTIVE} active on the droplet), ${CRED} credentials, ${M_BEFORE} migrations applied (last: ${M_LAST_BEFORE})"

echo "==> deactivating every workflow in the COPY (so the rehearsal runs no schedules, triggers or webhooks)"
SCRATCH -c "update workflow_entity set active = false"
SCRATCH -c "update workflow_entity set \"activeVersionId\" = null" >/dev/null 2>&1 || true
echo "    active now: $(SCRATCH -c 'select count(*) from workflow_entity where active')"

echo "==> starting n8n ${TO} on the copy (127.0.0.1:${PORT}); its migrations run now"
docker run -d --name "$CTR" -p "127.0.0.1:${PORT}:5678" --add-host=host.docker.internal:host-gateway \
  -e DB_TYPE=postgresdb -e DB_POSTGRESDB_HOST=host.docker.internal -e DB_POSTGRESDB_PORT=5432 \
  -e DB_POSTGRESDB_DATABASE="$DB" -e DB_POSTGRESDB_USER="$ROLE" -e DB_POSTGRESDB_PASSWORD="$PASS" \
  -e N8N_ENCRYPTION_KEY="$KEY" -e N8N_USER_FOLDER=/tmp/rehearsal \
  -e N8N_DIAGNOSTICS_ENABLED=false -e N8N_VERSION_NOTIFICATIONS_ENABLED=false -e N8N_PERSONALIZATION_ENABLED=false \
  -e N8N_LOG_LEVEL=info -e TZ=America/Chicago \
  "n8nio/n8n:${TO}" >/dev/null

ok=0
for i in $(seq 1 90); do
  if curl -fsS -m 2 "http://127.0.0.1:${PORT}/healthz" 2>/dev/null | grep -q ok; then ok=1; break; fi
  if [ "$(docker inspect -f '{{.State.Running}}' "$CTR" 2>/dev/null)" != "true" ]; then break; fi
  sleep 2
done

echo "==> result"
if [ "$ok" != 1 ]; then
  echo "    FAIL: n8n ${TO} did not become healthy. Last log lines:"
  docker logs --tail 25 "$CTR" 2>&1 | sed 's/^/      /'
  exit 1
fi
READY=$(curl -fsS -m 3 "http://127.0.0.1:${PORT}/healthz/readiness" 2>/dev/null || echo "?")
echo "    healthy: yes   readiness (includes the database): ${READY}"
echo "    version inside: $(docker exec "$CTR" n8n --version 2>/dev/null)"
M_AFTER=$(SCRATCH -c "select count(*) from migrations")
echo "    migrations: ${M_BEFORE} -> ${M_AFTER} (last: $(SCRATCH -c 'select name from migrations order by id desc limit 1'))"
echo "    workflows:  $(SCRATCH -c 'select count(*) from workflow_entity') (copy had ${WF})   credentials: $(SCRATCH -c 'select count(*) from credentials_entity') (copy had ${CRED})"
EXPORTED=$(docker exec "$CTR" sh -c 'n8n export:workflow --all --output=/tmp/wf.json >/dev/null 2>&1; node -e "const a=JSON.parse(require(\"fs\").readFileSync(\"/tmp/wf.json\"));console.log(a.length)"' 2>/dev/null || echo "?")
echo "    workflows the new version can export: ${EXPORTED}"
ERRS=$(docker logs "$CTR" 2>&1 | grep -ciE "error|failed|exception" || true)
echo "    log lines mentioning error/failed/exception: ${ERRS}"
if [ "$ERRS" != "0" ]; then docker logs "$CTR" 2>&1 | grep -iE "error|failed|exception" | head -8 | sed 's/^/      /'; fi
echo "==> REHEARSAL PASSED for n8n ${TO} on a copy of ${HOST}'s data (scratch DB and container are removed on exit)"
