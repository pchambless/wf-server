#!/usr/bin/env python3
# System map, wf-server layer: scan wf-server/src and emit JSON for deployment.f_sys_load_server(jsonb).
# Read-only on the repo; prints the JSON. Loaders: scripts/sys-map-refresh.sh (on the droplet, psql)
# and wf-agents/agents/tools/investigate/sys-map-server-scan (from the laptop, server-query).
#
# Nodes:  folder (src dir) > module (file) > route ('POST /api/hydrate').
# Edges:  route  -calls-> webhook     callWorkflow('literal') inside the handler body
#         route  -calls-> module      imported identifiers used in the handler body
#         module -calls-> webhook     callWorkflow('literal') anywhere in the file
#         module -depends_on-> module relative imports
#         module -> db objects        string literals with schema.name (resolved in SQL by f_sys_sql_refs)
# Not seen: callWorkflow(variable) - flagged as attrs.dynamic_calls on the module/route.
#
# Usage: sys-map-server-scan [--root DIR]   (default: the repo this script lives in)
import json, os, re, subprocess, sys

args = sys.argv[1:]
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if '--root' in args:
    i = args.index('--root'); root = args[i + 1]; del args[i:i + 2]
os.chdir(root)

files = sorted(os.path.join(d, f) for d, _, fs in os.walk('src') for f in fs if f.endswith('.js'))
src = {f: open(f).read() for f in files}

IMPORT = re.compile(r"import\s+(?:([\w{},\s*]+?)\s+from\s+)?['\"](\.[^'\"]+)['\"]")
CALL = re.compile(r"callWorkflow\(\s*(['\"`])([\w-]+)\1")
DYN = re.compile(r"callWorkflow\(\s*[A-Za-z_]")
ROUTE = re.compile(r"\b(app|router)\.(get|post|put|patch|delete|all)\(\s*['\"`]([^'\"`]+)['\"`]")
MOUNT = re.compile(r"\b(?:app|router)\.use\(\s*(?:['\"`]([^'\"`]+)['\"`]\s*,\s*)?([A-Za-z_]\w*)\s*\)")
STR = re.compile(r"'(?:[^'\\\n]|\\.)*'|\"(?:[^\"\\\n]|\\.)*\"|`(?:[^`\\]|\\.)*`", re.S)
SQLISH = re.compile(r"\b[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*\b", re.I)
FRAG = re.compile(r"(?:(?:insert\s+into|update|delete\s+from|merge\s+into|truncate)\s+(?:only\s+)?)?"
                  r"\"?[a-z_][a-z0-9_]*\"?\.\"?[a-z_][a-z0-9_]*", re.I)
SQLWORD = re.compile(r"\b(select|insert|update|delete|from|call)\b", re.I)

def imports(f):
    out = {}
    for m in IMPORT.finditer(src[f]):
        p = os.path.normpath(os.path.join(os.path.dirname(f), m.group(2)))
        if p in src:
            for ident in re.findall(r"[A-Za-z_]\w*", m.group(1) or ''):
                if ident not in ('as', 'from'):
                    out[ident] = p
            out.setdefault('__file__' + p, p)
    return out

imp = {f: imports(f) for f in files}

# mount prefixes: app.use('/api', apiRoutes) and router.use(childRoutes) inherit the parent's prefix
prefix = {}
def mounts(f, base):
    for m in MOUNT.finditer(src[f]):
        child = imp[f].get(m.group(2))
        if child and child not in prefix:
            prefix[child] = base + (m.group(1) or '')
            mounts(child, prefix[child])
for f in files:
    if f in ('src/server.js', 'src/app.js', 'src/auth-server.js'):
        prefix.setdefault(f, '')
        mounts(f, '')

def key(kind, scope, name):
    return {'kind': kind, 'scope': scope, 'name': name}

nodes, edges = [], []
for d in sorted({os.path.dirname(f) for f in files}):
    nodes.append(dict(key('folder', '', d), parent=None, attrs={}))
for f in files:
    s = src[f]
    mod = key('module', os.path.dirname(f), f)
    # keep only '[write verb] schema.name' fragments: enough for f_sys_sql_refs, small enough for argv
    sql = sorted({m.group(0) for t in STR.findall(s) if SQLISH.search(t) and SQLWORD.search(t)
                  for m in FRAG.finditer(t)})
    nodes.append(dict(mod, parent=key('folder', '', os.path.dirname(f)),
                      attrs={'lines': s.count('\n') + 1, 'dynamic_calls': bool(DYN.search(s))}))
    for w in sorted({m.group(2) for m in CALL.finditer(s)}):
        edges.append({'from': mod, 'kind': 'calls', 'webhook': w})
    for p in sorted(set(imp[f].values())):
        edges.append({'from': mod, 'kind': 'depends_on', 'to': key('module', os.path.dirname(p), p)})
    if sql:
        edges.append({'from': mod, 'kind': 'sql', 'sql': '\n;\n'.join(sql)})
    rs = list(ROUTE.finditer(s))
    for i, m in enumerate(rs):
        nxt = re.compile(r"\b(?:app|router)\.(?:get|post|put|patch|delete|all|use)\(").search(s, m.end())
        body = s[m.end(): nxt.start() if nxt else len(s)]
        name = m.group(2).upper() + ' ' + prefix.get(f, '') + m.group(3)
        route = key('route', f, name)
        nodes.append(dict(route, parent=mod, attrs={'line': s[:m.start()].count('\n') + 1,
                                                    'dynamic_calls': bool(DYN.search(body))}))
        for w in sorted({c.group(2) for c in CALL.finditer(body)}):
            edges.append({'from': route, 'kind': 'calls', 'webhook': w})
        for ident, p in imp[f].items():
            if not ident.startswith('__file__') and re.search(r"\b%s\b" % re.escape(ident), body):
                edges.append({'from': route, 'kind': 'calls', 'to': key('module', os.path.dirname(p), p)})

print(json.dumps({'nodes': nodes, 'edges': edges}))
