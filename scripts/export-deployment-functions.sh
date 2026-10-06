#!/bin/bash
# Export the deployment schema's functions from dev's database to
# wf-server/scripts/deploy-lib/sql/<function>.sql, one file per function,
# so git holds a reviewable record of the deploy machinery itself.
#
# Why this exists (task 468): f_p01_plan, f_p02_structure, f_p03_data,
# f_table_data_copy, f_predeploy_check, f_n8n_diff and the rest live ONLY in
# dev's postgres. A droplet rebuild or a bad CREATE OR REPLACE would lose them
# with no history. Same spirit as export-n8n-workflows.sh: the DB stays the
# source of truth, git is the record, and this is the (deliberate, visible)
# step that brings the record current.
#
# Usage:
#   export-deployment-functions.sh           regenerate deploy-lib/sql/*.sql
#   export-deployment-functions.sh --check   compare live DB to the committed
#                                            files, exit 1 if they differ
#                                            (nothing is written)
#
# The directory is fully regenerated on export so a dropped function does not
# leave a stale file behind - git tracks the deletion like any other change.
#
# Reads pg_get_functiondef over SSH + psql, no n8n dependency (same route as
# dev-query). Override the host with DEV_DB_SSH if the dev droplet moves.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$SCRIPT_DIR/deploy-lib/sql"
DEV_DB_SSH="${DEV_DB_SSH:-root@142.93.204.168}"
MODE="${1:-export}"

# One query, files delimited by a marker line. string_agg + the marker keeps
# it to a single round trip; trailing ";" makes each file runnable as-is.
RAW="$(ssh -o ConnectTimeout=8 "$DEV_DB_SSH" "sudo -u postgres psql -q -d n8n -t -A" <<'EOF'
SELECT string_agg(
         E'-- @@FILE ' || p.proname || E'\n' || pg_get_functiondef(p.oid) || E';\n',
         E'\n' ORDER BY p.proname, p.oid)
  FROM pg_proc p
 WHERE p.pronamespace = 'deployment'::regnamespace
   AND p.prokind = 'f';
EOF
)"

if [ -z "$RAW" ]; then
    echo "[export-deploy-sql] ERROR: no functions returned from deployment schema" >&2
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Split on the marker. A second overload of the same name would append to the
# same file, which is what we want (one file per function name).
printf '%s\n' "$RAW" | awk -v dir="$TMP" '
  /^-- @@FILE / { f = dir "/" $3 ".sql"; next }
  f { print >> f }
'

if [ "$MODE" = "--check" ]; then
    if diff -r "$OUT_DIR" "$TMP" >/dev/null 2>&1; then
        echo "[export-deploy-sql] in sync: $(ls "$TMP" | wc -l) functions match $OUT_DIR"
        exit 0
    fi
    echo "[export-deploy-sql] DRIFT between live deployment schema and $OUT_DIR:" >&2
    diff -rq "$OUT_DIR" "$TMP" >&2 || true
    exit 1
fi

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/*.sql
cp "$TMP"/*.sql "$OUT_DIR"/
echo "[export-deploy-sql] exported $(ls "$OUT_DIR" | wc -l) functions to $OUT_DIR"
