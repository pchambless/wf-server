#!/bin/bash
# Export one application schema's functions from dev's database to
# wf-server/db/<schema>/functions/<function>.sql, one file per function name,
# so git records the application's DB logic (studio, whatsfresh, agile).
#
# SEPARATE from export-deployment-functions.sh on purpose (task 470): the
# deployment schema is deploy machinery and lives in scripts/deploy-lib/sql/;
# these are application functions the renderer and n8n call at runtime and
# live under db/. Each run regenerates ONLY the requested schema's folder, so
# one export can never touch another schema's files or the deployment ones.
#
# Usage:
#   export-db-functions.sh <schema>            regenerate db/<schema>/functions/
#   export-db-functions.sh <schema> --check    compare live DB to committed files,
#                                              exit 1 on drift (nothing written)
#   Allowed schemas: studio, whatsfresh, agile
#
# The DB stays the source of truth; git is the record. Re-run and commit after
# any CREATE OR REPLACE on one of these functions. Reads pg_get_functiondef
# over SSH + psql (same route as dev-query). Override the host with DEV_DB_SSH.

set -euo pipefail

SCHEMA="${1:-}"
MODE="${2:-export}"
case "$SCHEMA" in
    studio|whatsfresh|agile) ;;
    *) echo "Usage: export-db-functions.sh <studio|whatsfresh|agile> [--check]" >&2; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$(dirname "$SCRIPT_DIR")/db/$SCHEMA/functions"
DEV_DB_SSH="${DEV_DB_SSH:-root@142.93.204.168}"

# Single round trip; marker lines delimit files. prokind='f' skips aggregates
# and procedures. Overloads of one name append to the same file.
RAW="$(ssh -o ConnectTimeout=8 "$DEV_DB_SSH" "sudo -u postgres psql -q -d n8n -t -A" <<EOF2
SELECT string_agg(
         E'-- @@FILE ' || p.proname || E'\n' || pg_get_functiondef(p.oid) || E';\n',
         E'\n' ORDER BY p.proname, p.oid)
  FROM pg_proc p
 WHERE p.pronamespace = '$SCHEMA'::regnamespace
   AND p.prokind = 'f';
EOF2
)"

if [ -z "$RAW" ]; then
    echo "[export-db-functions] ERROR: no functions returned for schema $SCHEMA" >&2
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

printf '%s\n' "$RAW" | awk -v dir="$TMP" '
  /^-- @@FILE / { f = dir "/" $3 ".sql"; next }
  f { print >> f }
'

if [ "$MODE" = "--check" ]; then
    if diff -r "$OUT_DIR" "$TMP" >/dev/null 2>&1; then
        echo "[export-db-functions] $SCHEMA in sync: $(ls "$TMP" | wc -l) functions match $OUT_DIR"
        exit 0
    fi
    echo "[export-db-functions] DRIFT between live $SCHEMA schema and $OUT_DIR:" >&2
    diff -rq "$OUT_DIR" "$TMP" >&2 || true
    exit 1
fi

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/*.sql
cp "$TMP"/*.sql "$OUT_DIR"/
echo "[export-db-functions] exported $(ls "$OUT_DIR" | wc -l) $SCHEMA functions to $OUT_DIR"
