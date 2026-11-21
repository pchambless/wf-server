#!/bin/bash
# Refresh the system map (deployment.sys_node / sys_edge) ON the dev droplet.
# Called by deploy.sh after sync-git-commits.sh; safe to run by hand any time.
#
# Order matters: db first (other layers link to db nodes), then infra, n8n, and the wf-server scan last.
# Loads through psql on stdin, so payload size is not limited by argv. Non-zero exit on SQL error;
# deploy.sh treats a failure here as a warning, never as a failed deploy.
#
# Env: REPO_DIR (default /home/n8n/wf-server), SYNC_DB (default n8n)
set -euo pipefail
: "${REPO_DIR:=/home/n8n/wf-server}"
: "${SYNC_DB:=n8n}"

PSQL=(sudo -u postgres psql -d "$SYNC_DB" -q -t -A -v ON_ERROR_STOP=1)

"${PSQL[@]}" <<'SQL'
SET ROLE wf_admin;
SELECT 'db '    || deployment.f_sys_refresh_db()::text;
SELECT 'infra ' || deployment.f_sys_refresh_infra()::text;
SELECT 'n8n '   || deployment.f_sys_refresh_n8n()::text;
SQL

if ! command -v python3 >/dev/null; then
  echo "server: skipped (python3 not installed)"
  exit 0
fi
JSON=$(python3 "$REPO_DIR/scripts/sys-map-server-scan.py" --root "$REPO_DIR")
case "$JSON" in *'$j$'*) echo "server: payload contains \$j\$, not loaded" >&2; exit 1;; esac
{
  echo 'SET ROLE wf_admin;'
  printf "SELECT 'server ' || deployment.f_sys_load_server(\$j\$%s\$j\$::jsonb)::text;\n" "$JSON"
} | "${PSQL[@]}"
