#!/bin/bash
# Pull prod whatsfresh rows into the target DB's mirror_stg schema (read-only on prod).
# Usage: mirror-pull.sh <target_db>
set -euo pipefail
TARGET_DB="${1:?target db}"
SRC_HOST="${SRC_HOST:-root@142.93.113.124}"
psql -d "$TARGET_DB" -qtA -c "select mirror.prepare_staging()" >/dev/null
psql -d "$TARGET_DB" -qtAF'|' -c "select tbl, cols from mirror.stage_plan()" | while IFS='|' read -r tbl cols; do
    ssh -o ConnectTimeout=8 "$SRC_HOST" "sudo -u postgres psql -d n8n -q" \
        <<< "COPY (SELECT $cols FROM whatsfresh.$tbl) TO STDOUT WITH (FORMAT csv)" \
      | psql -d "$TARGET_DB" -q -v ON_ERROR_STOP=1 -c "COPY mirror_stg.$tbl ($cols) FROM STDIN WITH (FORMAT csv)"
    echo "staged $tbl: $(psql -d "$TARGET_DB" -qtA -c "select count(*) from mirror_stg.$tbl")"
done
