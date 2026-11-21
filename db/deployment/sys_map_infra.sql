-- System map, infra layer: copies deployment.infra_node (filled by the n8n infra-probe).
-- Hierarchy: system > area 'infra' > droplet > service (postgres/n8n/node/caddy) > database/app/route.
-- scope = the droplet name, so names only need to be unique per droplet.
-- Edges: caddy route -routes_to-> the app or n8n on the same droplet whose port matches the upstream;
--        dev's postgres database 'n8n' -hosts-> the db area (the db layer maps dev's n8n database).
CREATE OR REPLACE FUNCTION deployment.f_sys_refresh_infra() RETURNS jsonb LANGUAGE plpgsql AS $body$
DECLARE v_n int; v_e int; v_root int; v_area int;
BEGIN
  INSERT INTO deployment.sys_node AS s (layer, kind, scope, name, source)
  VALUES ('system', 'system', '', 'whatsfresh', 'sys_map'), ('infra', 'area', '', 'infra', 'infra_node')
  ON CONFLICT (layer, kind, scope, name) DO UPDATE SET last_seen = now(), deleted_at = NULL;
  SELECT id INTO v_root FROM deployment.sys_node WHERE layer = 'system' AND kind = 'system' AND name = 'whatsfresh';
  SELECT id INTO v_area FROM deployment.sys_node WHERE layer = 'infra' AND kind = 'area' AND name = 'infra';
  UPDATE deployment.sys_node SET parent_id = v_root WHERE id = v_area AND parent_id IS DISTINCT FROM v_root;

  CREATE TEMP TABLE _i ON COMMIT DROP AS
  WITH RECURSIVE t AS (
    SELECT i.id, i.id AS droplet_id, i.name AS droplet FROM deployment.infra_node i
     WHERE i.parent_id = i.id AND i.retired_at IS NULL
    UNION ALL
    SELECT i.id, t.droplet_id, t.droplet FROM deployment.infra_node i JOIN t ON i.parent_id = t.id
     WHERE i.parent_id <> i.id AND i.retired_at IS NULL
  )
  SELECT i.*, t.droplet, t.droplet_id FROM deployment.infra_node i JOIN t USING (id);

  WITH up AS (
    INSERT INTO deployment.sys_node AS s (layer, kind, scope, name, attrs, source)
    SELECT 'infra', node_type, CASE WHEN node_type = 'droplet' THEN '' ELSE droplet END, name,
           attrs || jsonb_build_object('infra_node_id', id, 'version', version, 'status', status), 'infra_node'
      FROM _i
    ON CONFLICT (layer, kind, scope, name) DO UPDATE
       SET attrs = EXCLUDED.attrs, last_seen = now(), deleted_at = NULL,
           updated_at = CASE WHEN s.attrs IS DISTINCT FROM EXCLUDED.attrs OR s.deleted_at IS NOT NULL THEN now() ELSE s.updated_at END,
           updated_by = CASE WHEN s.attrs IS DISTINCT FROM EXCLUDED.attrs OR s.deleted_at IS NOT NULL THEN 'f_sys_refresh_infra' ELSE s.updated_by END
    RETURNING 1)
  SELECT count(*) INTO v_n FROM up;

  -- parents: droplets under the area, everything else under the sys_node of its infra parent
  UPDATE deployment.sys_node c
     SET parent_id = CASE WHEN i.parent_id = i.id THEN v_area ELSE p.id END
    FROM _i i LEFT JOIN deployment.sys_node p
           ON p.layer = 'infra' AND (p.attrs->>'infra_node_id')::int = i.parent_id AND i.parent_id <> i.id
   WHERE c.layer = 'infra' AND (c.attrs->>'infra_node_id')::int = i.id
     AND c.parent_id IS DISTINCT FROM CASE WHEN i.parent_id = i.id THEN v_area ELSE p.id END;

  WITH n AS (
    SELECT s.id, s.kind, s.scope, s.name, s.attrs FROM deployment.sys_node s
     WHERE s.layer = 'infra' AND s.deleted_at IS NULL AND s.last_seen = now()
  ), e AS (
    SELECT r.id AS f, x.id AS t, 'routes_to' AS kind, jsonb_build_object('upstream', r.attrs->>'upstream') AS attrs
      FROM n r JOIN n x ON x.scope = r.scope
       AND ((x.kind = 'app' AND x.attrs->>'port' = r.attrs->>'upstream_port')
         OR (x.kind = 'n8n' AND r.attrs->>'upstream_port' = '5678'))
     WHERE r.kind = 'route'
    UNION ALL
    SELECT d.id, a.id, 'hosts', '{}'::jsonb
      FROM n d JOIN deployment.sys_node a ON a.layer = 'db' AND a.kind = 'area' AND a.name = 'db' AND a.deleted_at IS NULL
     WHERE d.kind = 'database' AND d.scope = 'dev' AND d.name = 'n8n'
  ), up AS (
    INSERT INTO deployment.sys_edge AS s (from_node_id, to_node_id, kind, attrs, source)
    SELECT f, t, kind, attrs, 'infra_node' FROM e
    ON CONFLICT (from_node_id, to_node_id, kind) DO UPDATE
       SET attrs = EXCLUDED.attrs, source = EXCLUDED.source, last_seen = now(), deleted_at = NULL
    RETURNING 1)
  SELECT count(*) INTO v_e FROM up;

  UPDATE deployment.sys_node SET deleted_at = now(), updated_at = now(), updated_by = 'f_sys_refresh_infra'
   WHERE layer = 'infra' AND deleted_at IS NULL AND last_seen < now();
  UPDATE deployment.sys_edge e SET deleted_at = now(), updated_at = now(), updated_by = 'f_sys_refresh_infra'
   WHERE e.deleted_at IS NULL
     AND ((e.source = 'infra_node' AND e.last_seen < now())
       OR EXISTS (SELECT 1 FROM deployment.sys_node n WHERE n.id IN (e.from_node_id, e.to_node_id) AND n.deleted_at IS NOT NULL));
  RETURN jsonb_build_object('nodes_seen', v_n, 'edges_seen', v_e,
    'nodes_retired', (SELECT count(*) FROM deployment.sys_node WHERE layer = 'infra' AND deleted_at = now()));
END
$body$;
