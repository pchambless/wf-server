#!/bin/bash
# Run the prod->dev whatsfresh mirror on dev.  Usage: run-dev.sh dry|run
#   dry : pull + run inside a transaction that is rolled back (shows the counts, changes nothing)
#   run : pull + run, committed
set -euo pipefail
MODE="${1:?dry|run}"
case "$MODE" in dry) END="ROLLBACK;" ;; run) END="COMMIT;" ;; *) echo "dry|run"; exit 1 ;; esac
ssh -o ConnectTimeout=8 root@142.93.204.168 "sudo -u postgres psql -d n8n -q -v ON_ERROR_STOP=1" <<SQL
SET ROLE wf_admin;
\echo '--- pull (staged rows from prod)'
select * from mirror.pull();
\echo '--- run ($MODE)'
BEGIN;
select * from mirror.run();
$END
SQL
