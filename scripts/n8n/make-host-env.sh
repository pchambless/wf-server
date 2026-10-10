#!/usr/bin/env bash
# RUNS ON THE DEV OR PROD DROPLET (run it with: ssh <host> 'bash -s' < make-host-env.sh).
# Creates /home/n8n/n8n.env (mode 600) - the host-specific and secret values compose.yaml reads - by COPYING them
# out of the running n8n container. Values are never printed; only the key names are. Safe to re-run (it rewrites
# the file from whatever the running container has). Task 543.
set -euo pipefail

OUT=/home/n8n/n8n.env
KEYS="N8N_HOST N8N_EDITOR_BASE_URL WEBHOOK_URL DB_POSTGRESDB_PASSWORD"

docker inspect n8n >/dev/null 2>&1 || { echo "make-host-env: no container named n8n is running here" >&2; exit 1; }

umask 077
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

for k in $KEYS; do
  v=$(docker inspect n8n --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -m1 "^${k}=" | cut -d= -f2- || true)
  [ -n "$v" ] || { echo "make-host-env: the running container has no $k" >&2; exit 1; }
  # single-quoted in the file so compose does not interpolate a $ inside a value; a ' in a value cannot be quoted that way
  case "$v" in *"'"*) echo "make-host-env: $k contains a single quote - cannot be written safely" >&2; exit 1;; esac
  printf "%s='%s'\n" "$k" "$v" >> "$tmp"
done

install -m 600 -o root -g root "$tmp" "$OUT"
echo "make-host-env: wrote $OUT (mode $(stat -c %a "$OUT"), keys: $(cut -d= -f1 "$OUT" | tr '\n' ' '))"
