#!/bin/bash
# Compare per-table content hash: prod source vs target (secret columns excluded).
set -euo pipefail
TARGET_DB="${1:?target db}"; SRC_HOST="${SRC_HOST:-root@142.93.113.124}"
bad=0
while IFS='|' read -r tbl cols; do
    q="select count(*)||':'||coalesce(md5(string_agg(md5(t::text),'|' order by md5(t::text))),'-') from (select $cols from whatsfresh.$tbl) t"
    a=$(ssh -o ConnectTimeout=8 "$SRC_HOST" "sudo -u postgres psql -d n8n -qtA" <<< "$q")
    b=$(psql -d "$TARGET_DB" -qtA -c "$q")
    if [ "$a" = "$b" ]; then echo "OK    $tbl ${a%%:*}"; else echo "DIFF  $tbl prod=${a%%:*} target=${b%%:*}"; bad=1; fi
done < <(psql -d "$TARGET_DB" -qtAF'|' -c "select tbl, cols from mirror.stage_plan()")
exit $bad
