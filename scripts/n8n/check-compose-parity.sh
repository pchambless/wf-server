#!/usr/bin/env bash
# RUNS ON THE DEV OR PROD DROPLET (ssh <host> 'bash -s' < check-compose-parity.sh).
# Proves compose.yaml (+ /home/n8n/n8n-compose/.env + /home/n8n/n8n.env) would start n8n EXACTLY as the container
# that is running now: same image, network, restart policy, mounts and environment. Read-only; nothing is started or
# changed, and no value is printed (only key names and OK/MISMATCH). Exit 1 on any difference. Task 543.
set -euo pipefail

DIR=/home/n8n/n8n-compose
[ -f "$DIR/compose.yaml" ] && [ -f "$DIR/.env" ] && [ -f /home/n8n/n8n.env ] || { echo "parity: missing compose.yaml, .env or /home/n8n/n8n.env" >&2; exit 1; }

python3 - "$DIR" <<'PY'
import json, subprocess, sys
d = sys.argv[1]
def sh(*a): return subprocess.run(a, capture_output=True, text=True, check=True).stdout

want = json.loads(sh('docker', 'compose', '--project-directory', d, '-f', d + '/compose.yaml', 'config', '--format', 'json'))['services']['n8n']
have = json.loads(sh('docker', 'inspect', 'n8n'))[0]

bad = []
def check(label, a, b):
    ok = a == b
    print(('  OK        ' if ok else '  MISMATCH  ') + label + ('' if ok else f'   compose={a!r}  running={b!r}'))
    if not ok: bad.append(label)

check('image', want['image'], have['Config']['Image'])
check('network_mode', want.get('network_mode'), have['HostConfig']['NetworkMode'])
check('restart', want.get('restart'), have['HostConfig']['RestartPolicy']['Name'])
check('container_name', want.get('container_name'), have['Name'].lstrip('/'))
wv = sorted(f"{v['source']}:{v['target']}" for v in want.get('volumes', []))
hv = sorted(f"{m['Source']}:{m['Destination']}" for m in have['Mounts'])
check('volumes', wv, hv)

run_env = dict(e.split('=', 1) for e in have['Config']['Env'])
secret = ('PASSWORD', 'KEY', 'SECRET', 'TOKEN')
wrong = []
for k, v in want['environment'].items():
    if run_env.get(k) != v: wrong.append(k)
print(('  OK        ' if not wrong else '  MISMATCH  ') + f"environment: {len(want['environment'])} keys compared" + ('' if not wrong else ' differing keys: ' + ', '.join(sorted(wrong))))
if wrong: bad.append('environment')

# keys the running container has that compose does not set (image defaults like PATH/NODE_* are expected)
baked = set(e.split('=', 1)[0] for e in json.loads(sh('docker', 'image', 'inspect', have['Config']['Image']))[0]['Config']['Env'])
extra = sorted(k for k in run_env if k not in want['environment'] and k not in baked)
print(('  OK        ' if not extra else '  MISMATCH  ') + 'no extra environment keys on the running container' + ('' if not extra else ': ' + ', '.join(extra)))
if extra: bad.append('extra env')

print('PARITY: ' + ('compose reproduces the running container' if not bad else 'DIFFERENCES FOUND - ' + ', '.join(bad)))
sys.exit(1 if bad else 0)
PY
