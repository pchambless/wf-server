#!/bin/bash
# Install the mirror.* functions on the dev droplet's n8n DB (as wf_admin). Idempotent.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
{ echo "SET ROLE wf_admin;"; cat "$DIR/mirror_sync.sql"; } \
  | ssh -o ConnectTimeout=8 root@142.93.204.168 "sudo -u postgres psql -d n8n -q -v ON_ERROR_STOP=1"
echo "installed; functions:"
ssh -o ConnectTimeout=8 root@142.93.204.168 "sudo -u postgres psql -d n8n -qtA -c \"select proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='mirror' order by 1\""
