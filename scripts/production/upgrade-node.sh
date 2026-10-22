#!/usr/bin/env bash
# upgrade-node.sh - RUNS FROM THE LAPTOP, upgrades the host Node.js on the dev or prod droplet (NodeSource apt package).
#
# Why: the host runs Node 20.20.2 (end of life; the 2026-10-21 Node security release fixed 22.23.4, 24.22.1, 26.12.1 only).
# Both droplets are Ubuntu 24.04 with nodejs from deb.nodesource.com/node_20.x. This switches the repo line to node_22.x and
# installs an exact version, then restarts the app(s) and health-checks them. The n8n containers carry their own Node and are NOT touched.
#
#   scripts/production/upgrade-node.sh dev  run                # dev: pm2 apps wf-server, support-app, consulting-app
#   scripts/production/upgrade-node.sh prod run                # prod: systemd service wf-server (asks for confirmation)
#   scripts/production/upgrade-node.sh dev  revert             # back to the saved 20.x repo line and 20.20.2
#   NODE_VERSION=22.23.5 scripts/production/upgrade-node.sh dev run     # another exact 22.x version
#
# Run from a direct ssh session in a normal Terminal tab (never through an n8n webhook: Guide 28). Order: dev first, test, then prod,
# and not on go-live eve. A backup of the repo file, pm2 dump and previous version is kept in /root/node-upgrade-backup on the droplet.
set -euo pipefail

ENVN="${1:-}"; ACTION="${2:-}"; VER="${NODE_VERSION:-22.23.4}"
case "$ENVN" in
  dev)  HOST=142.93.204.168 ;;
  prod) HOST=142.93.113.124 ;;
  *) echo "usage: $0 dev|prod run|revert"; exit 2 ;;
esac
case "$ACTION" in run|revert) ;; *) echo "usage: $0 dev|prod run|revert"; exit 2 ;; esac
[[ "$VER" =~ ^22\.[0-9]+\.[0-9]+$ ]] || { echo "NODE_VERSION must look like 22.x.y (got $VER)"; exit 2; }

if [ "$ENVN" = prod ]; then
  echo "This changes the PRODUCTION droplet ($HOST): Node -> $VER and a restart of wf-server (about 5 seconds of downtime)."
  read -r -p "Type the word prod to continue: " ans; [ "$ans" = prod ] || { echo "aborted"; exit 1; }
fi

ssh "root@$HOST" bash -s -- "$ENVN" "$ACTION" "$VER" <<'REMOTE' 2>&1 | grep -v -E "post-quantum|store now|openssh.com|^\*\*"
set -euo pipefail
ENVN=$1; ACTION=$2; VER=$3
BK=/root/node-upgrade-backup
SRC=/etc/apt/sources.list.d/nodesource.sources
ts() { date '+%H:%M:%S'; }
step() { echo; echo "[$(ts)] === $* ==="; }

restart_apps() {
  if [ "$ENVN" = dev ]; then
    pm2 restart all --update-env >/dev/null; pm2 save >/dev/null
    sleep 6; pm2 jlist | python3 -c "import json,sys
for p in json.load(sys.stdin):
    e=p['pm2_env']; print('  ', p['name'], e['status'], 'node', e.get('node_version'), 'restarts', e.get('restart_time'))"
  else
    systemctl restart wf-server; sleep 5; systemctl is-active wf-server
  fi
}

health() {
  local bad=0
  if [ "$ENVN" = dev ]; then
    echo -n "  wf-server /health: ";    curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 http://127.0.0.1:3001/health || bad=1
    for port in 3002 3004; do echo -n "  port $port answers: "; code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://127.0.0.1:$port/" || true); echo "$code"; [ "$code" != 000 ] || bad=1; done
  else
    echo -n "  wf-server /health: "; curl -f -s -o /dev/null -w '%{http_code}\n' --max-time 10 http://127.0.0.1:3001/health || bad=1
  fi
  return $bad
}

if [ "$ACTION" = run ]; then
  step "before"; node -v; dpkg -l nodejs | tail -1 | awk '{print $2, $3}'; grep -h URIs "$SRC"; df -h / | tail -1 | awk '{print "disk free: "$4}'
  step "backup (repo file, pm2 dump, previous version)"
  mkdir -p "$BK"; [ -f "$BK/nodesource.sources.20x" ] || cp "$SRC" "$BK/nodesource.sources.20x"
  dpkg -l nodejs | tail -1 | awk '{print $3}' > "$BK/previous-nodejs-version"
  if [ "$ENVN" = dev ]; then pm2 save >/dev/null && cp /root/.pm2/dump.pm2 "$BK/dump.pm2" && echo "pm2 dump saved"; fi
  ls -l "$BK"
  step "switch NodeSource repo to node_22.x"
  sed -i -E 's#node_[0-9]+\.x#node_22.x#' "$SRC"; grep -h URIs "$SRC"
  apt-get update -qq 2>&1 | tail -3 || true
  apt-cache madison nodejs | grep -F "$VER-1nodesource1" >/dev/null || { echo "ABORT: nodejs $VER-1nodesource1 is not in the repo. Restoring the repo line."; cp "$BK/nodesource.sources.20x" "$SRC"; apt-get update -qq || true; exit 1; }
  step "install nodejs $VER"
  DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-downgrades "nodejs=$VER-1nodesource1" 2>&1 | tail -4
  [ "$(node -v)" = "v$VER" ] || { echo "ABORT: node -v is $(node -v), expected v$VER (apps NOT restarted)"; exit 1; }
  echo "node -v: $(node -v)  npm -v: $(npm -v)"
  step "restart apps"; restart_apps
  step "health"; if health; then echo; echo "UPGRADE OK: node $(node -v)"; else echo; echo "HEALTH CHECK FAILED: run 'scripts/production/upgrade-node.sh $ENVN revert' from the laptop"; exit 1; fi
else
  step "revert to Node 20.x"
  [ -f "$BK/nodesource.sources.20x" ] || { echo "no backup found in $BK"; exit 1; }
  PREV=$(cat "$BK/previous-nodejs-version")
  cp "$BK/nodesource.sources.20x" "$SRC"; apt-get update -qq 2>&1 | tail -3 || true
  DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-downgrades "nodejs=$PREV" 2>&1 | tail -3
  echo "node -v: $(node -v)"
  step "restart apps"; restart_apps
  step "health"; health && echo "REVERTED OK: node $(node -v)" || echo "HEALTH CHECK FAILED AFTER REVERT: investigate"
fi
REMOTE
