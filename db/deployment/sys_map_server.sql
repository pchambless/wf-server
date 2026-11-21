-- System map, wf-server layer: loads the JSON from wf-agents/agents/tools/investigate/sys-map-server-scan.
-- Hierarchy: system > area 'server' > folder (src dir) > module (file) > route.
-- Edges: route/module -calls-> n8n webhook (by path), route -calls-> module, module -depends_on-> module,
--        module -reads/writes/calls-> db objects named in its SQL string literals (f_sys_sql_refs);
--        infra dev.wf-server -hosts-> the server area.
CREATE OR REPLACE FUNCTION deployment.f_sys_load_server(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $body$
DECLARE v_n int; v_e int; v_root int; v_area int; v_missing jsonb;
BEGIN
  INSERT INTO deployment.sys_node AS s (layer, kind, scope, name, source)
  VALUES ('system', 'system', '', 'whatsfresh', 'sys_map'), ('server', 'area', '', 'server', 'route_scan')
  ON CONFLICT (layer, kind, scope, name) DO UPDATE SET last_seen = now(), deleted_at = NULL;
  SELECT id INTO v_root FROM deployment.sys_node WHERE layer = 'system' AND kind = 'system' AND name = 'whatsfresh';
  SELECT id INTO v_area FROM deployment.sys_node WHERE layer = 'server' AND kind = 'area' AND name = 'server';
  UPDATE deployment.sys_node SET parent_id = v_root WHERE id = v_area AND parent_id IS DISTINCT FROM v_root;

  WITH up AS (
    INSERT INTO deployment.sys_node AS s (layer, kind, scope, name, attrs, source)
    SELECT 'server', n->>'kind', n->>'scope', n->>'name', coalesce(n->'attrs', '{}'), 'route_scan'
      FROM jsonb_array_elements(p->'nodes') n
    ON CONFLICT (layer, kind, scope, name) DO UPDATE
       SET attrs = EXCLUDED.attrs, last_seen = now(), deleted_at = NULL,
           updated_at = CASE WHEN s.attrs IS DISTINCT FROM EXCLUDED.attrs OR s.deleted_at IS NOT NULL THEN now() ELSE s.updated_at END,
           updated_by = CASE WHEN s.attrs IS DISTINCT FROM EXCLUDED.attrs OR s.deleted_at IS NOT NULL THEN 'f_sys_load_server' ELSE s.updated_by END
    RETURNING 1)
  SELECT count(*) INTO v_n FROM up;

  UPDATE deployment.sys_node c SET parent_id = coalesce(pn.id, v_area)
    FROM jsonb_array_elements(p->'nodes') n
    LEFT JOIN deployment.sys_node pn ON pn.layer = 'server' AND n->'parent' <> 'null'
          AND pn.kind = n->'parent'->>'kind' AND pn.scope = n->'parent'->>'scope' AND pn.name = n->'parent'->>'name'
   WHERE c.layer = 'server' AND c.kind = n->>'kind' AND c.scope = n->>'scope' AND c.name = n->>'name'
     AND c.parent_id IS DISTINCT FROM coalesce(pn.id, v_area);

  CREATE TEMP TABLE _se ON COMMIT DROP AS
  SELECT f.id AS from_id, e->>'kind' AS kind, e->'to' AS to_key, e->>'webhook' AS webhook, e->>'sql' AS sql
    FROM jsonb_array_elements(p->'edges') e
    JOIN deployment.sys_node f ON f.layer = 'server' AND f.kind = e->'from'->>'kind'
     AND f.scope = e->'from'->>'scope' AND f.name = e->'from'->>'name';

  SELECT coalesce(jsonb_agg(DISTINCT webhook), '[]') INTO v_missing FROM _se x
   WHERE webhook IS NOT NULL AND NOT EXISTS (SELECT 1 FROM deployment.sys_node w WHERE w.layer = 'n8n'
         AND w.kind = 'webhook' AND w.name = x.webhook AND w.deleted_at IS NULL);

  CREATE TEMP TABLE _sr ON COMMIT DROP AS
  SELECT x.from_id, r.scope, r.obj, r.verb FROM _se x, deployment.f_sys_sql_refs(x.sql) r WHERE x.kind = 'sql';

  WITH db AS (
    SELECT id, kind, scope, name, attrs->>'proname' AS proname FROM deployment.sys_node
     WHERE layer = 'db' AND deleted_at IS NULL AND kind IN ('table','view','matview','function','procedure')
  ), e AS (
    SELECT x.from_id f, w.id t, 'calls' kind FROM _se x
      JOIN deployment.sys_node w ON w.layer = 'n8n' AND w.kind = 'webhook' AND w.name = x.webhook AND w.deleted_at IS NULL
    UNION
    SELECT x.from_id, m.id, x.kind FROM _se x
      JOIN deployment.sys_node m ON m.layer = 'server' AND m.kind = x.to_key->>'kind'
       AND m.scope = x.to_key->>'scope' AND m.name = x.to_key->>'name'
     WHERE x.to_key IS NOT NULL
    UNION
    SELECT r.from_id, d.id, 'writes' FROM _sr r
      JOIN db d ON d.scope = r.scope AND d.name = r.obj AND d.kind IN ('table','view','matview') WHERE r.verb = 'writes'
    UNION
    SELECT r.from_id, d.id, CASE WHEN d.kind IN ('function','procedure') THEN 'calls' ELSE 'reads' END FROM _sr r
      JOIN db d ON d.scope = r.scope AND (d.name = r.obj AND d.kind IN ('table','view','matview')
                                       OR d.proname = r.obj AND d.kind IN ('function','procedure'))
     WHERE r.verb = 'ref' AND NOT EXISTS (SELECT 1 FROM _sr w WHERE w.from_id = r.from_id AND w.verb = 'writes'
                                           AND w.scope = r.scope AND w.obj = r.obj)
    UNION
    SELECT i.id, v_area, 'hosts' FROM deployment.sys_node i
     WHERE i.layer = 'infra' AND i.kind = 'app' AND i.scope = 'dev' AND i.name = 'wf-server' AND i.deleted_at IS NULL
  ), up AS (
    INSERT INTO deployment.sys_edge AS s (from_node_id, to_node_id, kind, source)
    SELECT f, t, kind, 'route_scan' FROM e WHERE f <> t
    ON CONFLICT (from_node_id, to_node_id, kind) DO UPDATE SET last_seen = now(), deleted_at = NULL, source = EXCLUDED.source
    RETURNING 1)
  SELECT count(*) INTO v_e FROM up;

  UPDATE deployment.sys_node SET deleted_at = now(), updated_at = now(), updated_by = 'f_sys_load_server'
   WHERE layer = 'server' AND deleted_at IS NULL AND last_seen < now();
  UPDATE deployment.sys_edge e SET deleted_at = now(), updated_at = now(), updated_by = 'f_sys_load_server'
   WHERE e.deleted_at IS NULL
     AND ((e.source = 'route_scan' AND e.last_seen < now())
       OR EXISTS (SELECT 1 FROM deployment.sys_node n WHERE n.id IN (e.from_node_id, e.to_node_id) AND n.deleted_at IS NOT NULL));
  RETURN jsonb_build_object('nodes_seen', v_n, 'edges_seen', v_e, 'webhooks_not_in_n8n', v_missing,
    'nodes_retired', (SELECT count(*) FROM deployment.sys_node WHERE layer = 'server' AND deleted_at = now()));
END
$body$;
