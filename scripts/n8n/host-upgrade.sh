#!/usr/bin/env bash
# RUNS ON THE TARGET HOST (dev / prod droplet), or LOCALLY on the laptop in --mode local. Normally started for you by
# n8n-upgrade.sh, which ships this file, runs it DETACHED on the host (Guide 28 rule 1: an SSH drop must not kill an
# upgrade half way) and follows its log. Task 543.
#
#   host-upgrade.sh <preflight|upgrade|rollback|finalize> --mode local|droplet --to <version> --min-safe <version>
#                   [--simulate-failure] [--allow-major]
#
#   preflight  read-only: every check, nothing stopped or changed (it only pulls the new image)
#   upgrade    preflight -> backup (+ proof it restores) -> stop n8n -> compose up on the new
#              version -> verify -> automatic rollback if anything fails
#   rollback   restore the last backup and the previous version (also what the wrapper calls if its smoke test fails)
#   finalize   mark the upgrade accepted (rollback is refused afterwards)
#
# n8n DB migrations do NOT reverse, so rollback = restore the pre-upgrade dump of n8n's tables (schema public) plus the
# previous version. The last line of output is always "RESULT: ...".
set -o pipefail

ACTION="${1:?Usage: host-upgrade.sh <preflight|upgrade|rollback|finalize> --mode local|droplet --to V --min-safe V}"
shift
MODE=""; TO=""; MIN_SAFE=""; SIM=0; ALLOW_MAJOR=0
while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="$2"; shift 2;;
    --to) TO="$2"; shift 2;;
    --min-safe) MIN_SAFE="$2"; shift 2;;
    --simulate-failure) SIM=1; shift;;
    --allow-major) ALLOW_MAJOR=1; shift;;
    *) echo "host-upgrade: unknown argument $1" >&2; exit 2;;
  esac
done

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
umask 077

case "$MODE" in
  droplet)
    COMPOSE_DIR=/home/n8n/n8n-compose
    COMPOSE_FILE="$COMPOSE_DIR/compose.yaml"
    BACKUP_DIR=/home/n8n/backups
    IMAGE=n8nio/n8n
    SQL()       { sudo -u postgres psql -d "${DB:-n8n}" -tAX "$@"; }
    ADMIN_SQL() { sudo -u postgres psql -d postgres -tAX "$@"; }
    PGDUMP()    { sudo -u postgres pg_dump "$@"; }
    PGRESTORE() { sudo -u postgres pg_restore "$@"; }
    RESTORE_ROLE="--role=wf_admin"   # n8n connects as wf_admin: restored tables must belong to it
    ;;
  local)
    COMPOSE_DIR=/home/paul/Projects/local-desk/n8n
    COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"
    BACKUP_DIR="$HOME/n8n-backups"
    IMAGE=docker.n8n.io/n8nio/n8n
    SQL()       { psql -d "${DB:-n8n}" -tAX "$@"; }
    ADMIN_SQL() { psql -d postgres -tAX "$@"; }
    PGDUMP()    { pg_dump "$@"; }
    PGRESTORE() { pg_restore "$@"; }
    RESTORE_ROLE=""
    ;;
  *) echo "host-upgrade: --mode must be local or droplet" >&2; exit 2;;
esac

STATE="$BACKUP_DIR/last_upgrade.state"
COMPOSE() { docker compose --project-directory "$COMPOSE_DIR" -f "$COMPOSE_FILE" "$@"; }
log() { echo "[$(date +%H:%M:%S)] $*"; }
installed_version() { docker exec n8n n8n --version 2>/dev/null | tr -d '\r'; }
version_ge() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]; }   # $1 >= $2
counts() {  # workflows | active | credentials | registered webhooks
  SQL -c "select (select count(*) from workflow_entity)||'|'||(select count(*) from workflow_entity where active)||'|'||(select count(*) from credentials_entity)||'|'||(select count(*) from webhook_entity)"
}
wait_healthy() {  # $1 = seconds
  local i
  for i in $(seq 1 $(( $1 / 2 ))); do
    if curl -fsS -m 2 http://127.0.0.1:5678/healthz 2>/dev/null | grep -q ok; then return 0; fi
    [ "$(docker inspect -f '{{.State.Running}}' n8n 2>/dev/null)" = "true" ] || [ "$i" -lt 5 ] || return 1
    sleep 2
  done
  return 1
}

# --- the version lives in one place per mode: droplet = N8N_VERSION in .env next to compose.yaml; local = the image tag in
#     the compose file itself (so a later plain `docker compose up` can never silently downgrade it)
save_prev() {
  if [ "$MODE" = droplet ]; then cp -f "$COMPOSE_DIR/.env" "$COMPOSE_DIR/.env.prev"; else cp -f "$COMPOSE_FILE" "$COMPOSE_FILE.prev"; fi
}
set_version() {
  if [ "$MODE" = droplet ]; then printf 'N8N_VERSION=%s\n' "$1" > "$COMPOSE_DIR/.env"
  else sed -i -E "s#^([[:space:]]*image:[[:space:]]*${IMAGE}:).*#\1$1#" "$COMPOSE_FILE"; fi
}
restore_prev() {
  if [ "$MODE" = droplet ]; then cp -f "$COMPOSE_DIR/.env.prev" "$COMPOSE_DIR/.env"; else cp -f "$COMPOSE_FILE.prev" "$COMPOSE_FILE"; fi
}

# ============================================================================ preflight
preflight() {
  local fail=0 pgnum free
  chk() { if [ "$2" = 0 ]; then log "  ok    $1${3:+  ($3)}"; else log "  FAIL  $1${3:+  ($3)}"; fail=1; fi; }
  log "preflight ($MODE): $FROM -> $TO"
  [ -n "$FROM" ];                                                    chk "n8n container exists and answers" $? "installed $FROM"
  [ "$FROM" != "$TO" ];                                              chk "target differs from installed" $?
  version_ge "$TO" "$FROM";                                          chk "target is not a downgrade" $?
  { [ -z "$MIN_SAFE" ] || version_ge "$TO" "$MIN_SAFE"; };          chk "target is at least the minimum safe version" $? "min safe ${MIN_SAFE:-not given}"
  { [ "${FROM%%.*}" = "${TO%%.*}" ] || [ "$ALLOW_MAJOR" = 1 ]; };   chk "same major version (or --allow-major)" $? "${FROM%%.*} -> ${TO%%.*}"
  mkdir -p "$BACKUP_DIR" && chmod 700 "$BACKUP_DIR"
  free=$(df --output=avail -BG "$BACKUP_DIR" | tail -1 | tr -dc '0-9')
  [ "${free:-0}" -ge 6 ];                                            chk "disk space for the image and backups" $? "${free}G free, needs 6G"
  pgnum=$(SQL -c "show server_version_num" 2>/dev/null)
  [ "${pgnum:-0}" -ge 160000 ];                                      chk "Postgres 16 or newer (n8n floor)" $? "server_version_num ${pgnum:-?}"
  [ -n "$(counts 2>/dev/null)" ];                                    chk "n8n tables readable" $? "counts $(counts 2>/dev/null)"
  if [ "$MODE" = droplet ]; then
    [ "$(stat -c %u /home/n8n/n8n_data)" = 1000 ];                   chk "data dir owned by uid 1000 (Guide 28 rule 2)" $?
    bash "$SELF_DIR/check-compose-parity.sh" >/dev/null 2>&1;        chk "compose.yaml reproduces the running container" $?
  else
    grep -qE "^[[:space:]]*image:[[:space:]]*${IMAGE}:" "$COMPOSE_FILE"; chk "local compose file pins ${IMAGE}" $?
  fi
  log "  ...   pulling ${IMAGE}:${TO} (old version keeps running)"
  docker pull -q "${IMAGE}:${TO}" >/dev/null 2>&1;                   chk "target image exists and pulls" $?
  return $fail
}

# ============================================================================ backup
backup() {
  TS=$(date +%Y%m%d-%H%M%S)
  BK="$BACKUP_DIR/n8n_${TS}_from_${FROM}"
  log "backup: n8n tables (schema public) -> $BK.dump"
  PGDUMP -Fc -n public --no-owner --no-acl n8n > "$BK.dump" || return 1
  PGRESTORE -l "$BK.dump" 2>/dev/null | grep -vE " EXTENSION | COMMENT - EXTENSION | SCHEMA - public | COMMENT - SCHEMA public " > "$BK.list"
  [ "$(wc -c < "$BK.dump")" -gt 100000 ] && [ -s "$BK.list" ] || { log "backup is implausibly small"; return 1; }
  if [ "$MODE" = droplet ]; then
    tar czf "$BK.data.tgz" -C /home/n8n --exclude='n8n_data/logs' n8n_data || return 1
    chgrp postgres "$BK.dump" "$BK.list"; chmod 640 "$BK.dump" "$BK.list"; chgrp postgres "$BACKUP_DIR"; chmod 750 "$BACKUP_DIR"
  else
    docker run --rm -v n8n_n8n_local_data:/d:ro -v "$BACKUP_DIR":/b --entrypoint tar "${IMAGE}:${FROM}" czf "/b/$(basename "$BK").data.tgz" -C /d . || return 1
  fi
  log "backup: data dir/volume (holds the encryption key) -> $BK.data.tgz"

  # prove the dump actually restores, into a throwaway database, BEFORE anything is stopped
  log "restore check: loading the dump into a scratch database"
  ADMIN_SQL -c "drop database if exists n8n_restorecheck" >/dev/null 2>&1
  ADMIN_SQL -c "create database n8n_restorecheck" >/dev/null || return 1
  PGRESTORE -d n8n_restorecheck --no-owner --no-acl --exit-on-error -L "$BK.list" "$BK.dump" >/dev/null 2>&1; local rc=$?
  local live scratch
  live=$(SQL -c "select (select count(*) from workflow_entity)||'|'||(select count(*) from credentials_entity)||'|'||(select count(*) from migrations)")
  scratch=$(DB=n8n_restorecheck SQL -c "select (select count(*) from workflow_entity)||'|'||(select count(*) from credentials_entity)||'|'||(select count(*) from migrations)")
  ADMIN_SQL -c "drop database if exists n8n_restorecheck" >/dev/null 2>&1
  if [ "$rc" != 0 ] || [ "$live" != "$scratch" ]; then log "restore check FAILED (restore exit $rc; live $live, restored $scratch)"; return 1; fi
  log "restore check ok (workflows|credentials|migrations $live)"
  PRE=$(counts); PREMIG=$(SQL -c "select count(*) from migrations")
  printf "FROM='%s'\nPREMIG='%s'\nTO='%s'\nBK='%s'\nPRE='%s'\nMODE='%s'\nSTARTED='%s'\n" "$FROM" "$PREMIG" "$TO" "$BK" "$PRE" "$MODE" "$(date -Is)" > "$STATE"
}

# ============================================================================ verify
verify() {
  local post v i leak
  log "verify: waiting for ${IMAGE}:${TO} to become healthy (migrations run first, up to 4 minutes)"
  wait_healthy 240 || { log "VERIFY FAIL: n8n did not become healthy"; docker logs --tail 15 n8n 2>&1 | sed 's/^/        /'; return 1; }
  v=$(installed_version)
  [ "$v" = "$TO" ] || { log "VERIFY FAIL: running version is '$v', wanted $TO"; return 1; }
  log "  ok    healthy, version $v"
  for i in 1 2 3 4 5 6; do post=$(counts); [ "$post" = "$PRE" ] && break; sleep 10; done   # activation settles after start
  [ "$post" = "$PRE" ] || { log "VERIFY FAIL: workflows|active|credentials|webhooks was $PRE before, $post now"; return 1; }
  log "  ok    workflows|active|credentials|webhooks unchanged ($post)"
  leak=$(docker logs n8n 2>&1 | grep -E "Migration failed|QueryFailedError|error initializing DB|Mismatching encryption keys|Problem activating workflow|ECONNREFUSED" | head -5)
  [ -z "$leak" ] || { log "VERIFY FAIL: errors in the startup log:"; echo "$leak" | sed 's/^/        /'; return 1; }
  log "  ok    no migration, encryption, activation or connection errors in the startup log"
  for i in 1 2 3 4 5 6 7 8 9 10; do curl -fsS -m 3 http://127.0.0.1:5678/healthz/readiness >/dev/null 2>&1 && break; sleep 3; done
  curl -fsS -m 3 http://127.0.0.1:5678/healthz/readiness >/dev/null 2>&1 || { log "VERIFY FAIL: /healthz/readiness (the database check) never answered 200"; return 1; }
  log "  ok    readiness endpoint answers 200 (includes the database)"
  if [ "$SIM" = 1 ]; then log "VERIFY FAIL: --simulate-failure injected on purpose (exercising the rollback path)"; return 1; fi
  return 0
}

# ============================================================================ rollback
rollback() {
  local now
  log "ROLLBACK: restoring n8n $FROM and its pre-upgrade data"
  docker rm -f n8n >/dev/null 2>&1
  [ -f "$BK.dump" ] || { log "RESULT: ROLLBACK IMPOSSIBLE - backup $BK.dump not found. n8n is stopped."; return 1; }
  # the new version's migrations added tables/columns the old dump knows nothing about, so a --clean restore cannot work
  # (FKs from new tables block the drops): remove every n8n table (never extension members, e.g. dblink on dev), then restore
  SQL -c "do \$d\$ declare r record; begin for r in select c.relname from pg_class c where c.relnamespace='public'::regnamespace and c.relkind in ('r','p','v','m') and not exists (select 1 from pg_depend d where d.objid=c.oid and d.deptype='e') loop execute format('drop table if exists public.%I cascade', r.relname); end loop; for r in select p.oid::regprocedure as sig from pg_proc p where p.pronamespace='public'::regnamespace and not exists (select 1 from pg_depend d where d.objid=p.oid and d.deptype='e') loop execute 'drop function '||r.sig||' cascade'; end loop; end \$d\$;" >/dev/null \
    || { log "RESULT: ROLLBACK FAILED - could not clear n8n tables. Backup: $BK.*"; return 1; }
  PGRESTORE $RESTORE_ROLE -d n8n --no-owner --no-acl --exit-on-error -L "$BK.list" "$BK.dump" >/tmp/n8n_restore.log 2>&1 \
    || { log "RESULT: ROLLBACK FAILED - restore errors, see /tmp/n8n_restore.log. Backup: $BK.*"; return 1; }
  restore_prev
  COMPOSE up -d >/dev/null 2>&1
  if ! wait_healthy 180; then log "RESULT: ROLLBACK FAILED - n8n did not come back healthy. Backup: $BK.* ."; return 1; fi
  now=$(counts)
  if [ "$now" = "$PRE" ] && [ "$(installed_version)" = "$FROM" ] && [ "$(SQL -c 'select count(*) from migrations')" = "$PREMIG" ]; then
    log "RESULT: ROLLED BACK to $FROM - healthy, counts identical to before ($now). The failed upgrade left nothing behind."
    return 0
  fi
  log "RESULT: ROLLBACK INCOMPLETE - running $(installed_version), counts $now (expected $PRE). Backup: $BK.*"
  return 1
}

# ============================================================================ main
FROM=$(installed_version)

load_state() {
  [ -f "$STATE" ] || { log "RESULT: no $STATE - nothing to roll back or finalize"; exit 1; }
  # shellcheck disable=SC1090
  ACCEPTED=""; . "$STATE"
}

case "$ACTION" in
  preflight)
    if preflight; then log "RESULT: PREFLIGHT OK - $FROM -> $TO would proceed; nothing was changed"; exit 0
    else log "RESULT: PREFLIGHT FAILED - nothing was changed"; exit 1; fi
    ;;
  upgrade)
    preflight || { log "RESULT: ABORTED - preflight failed, nothing was changed"; exit 1; }
    backup    || { log "RESULT: ABORTED - backup or restore check failed, nothing was changed (n8n still running $FROM)"; exit 1; }
    log "upgrade: stopping n8n $FROM (downtime starts; its image stays on disk for rollback)"
    save_prev
    docker stop n8n >/dev/null || { log "RESULT: ABORTED - could not stop the container"; exit 1; }
    set_version "$TO"
    log "upgrade: compose up on $TO"
    if ! COMPOSE up -d >/tmp/n8n_compose_up.log 2>&1; then
      log "compose up failed:"; sed 's/^/        /' /tmp/n8n_compose_up.log | tail -8
      rollback; exit 1
    fi
    if verify; then
      log "RESULT: UPGRADED to $TO - verified. --rollback stays available until --finalize. Backup: $BK.*"
      exit 0
    fi
    rollback; exit 1
    ;;
  rollback)
    load_state
    FROM_SAVED="$FROM"; FROM="${FROM:-$FROM_SAVED}"
    [ -z "$ACCEPTED" ] || { log "RESULT: ROLLBACK REFUSED - upgrade was already finalized ($ACCEPTED); restore from $BK.* by hand if you really mean it"; exit 1; }
    rollback; exit $?
    ;;
  finalize)
    load_state
    [ -z "$ACCEPTED" ] || { log "RESULT: nothing to finalize (already accepted $ACCEPTED)"; exit 0; }
    echo "ACCEPTED=$(date -Is)" >> "$STATE"
    log "RESULT: FINALIZED - upgrade to $TO accepted; --rollback is now refused. Backup kept: $BK.*"
    exit 0
    ;;
  *) echo "host-upgrade: unknown action $ACTION" >&2; exit 2;;
esac
