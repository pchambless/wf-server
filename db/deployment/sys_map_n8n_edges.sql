-- System map, n8n layer part 2: edges.
--   webhook -calls-> its workflow
--   workflow -reads/writes/calls-> db objects named in its Postgres nodes' SQL (f_sys_sql_refs)
--   workflow -calls-> workflow (Execute Workflow with a literal id; {{ expression }} ids are dynamic, skipped)
--   infra dev.n8n -hosts-> the n8n area
CREATE OR REPLACE FUNCTION deployment.f_sys_refresh_n8n_edges() RETURNS int LANGUAGE plpgsql AS $body$
DECLARE v_n int;
BEGIN
  CREATE TEMP TABLE _wn ON COMMIT DROP AS
  SELECT s.id AS node_id, w.id AS n8n_id, n AS jnode
    FROM public.workflow_entity w
    JOIN deployment.sys_node s ON s.layer = 'n8n' AND s.kind = 'workflow' AND s.attrs->>'n8n_id' = w.id AND s.deleted_at IS NULL,
         json_array_elements(w.nodes) n
   WHERE NOT w."isArchived";

  CREATE TEMP TABLE _db ON COMMIT DROP AS
  SELECT id, kind, scope, name, attrs->>'proname' AS proname
    FROM deployment.sys_node WHERE layer = 'db' AND deleted_at IS NULL
     AND kind IN ('table','view','matview','function','procedure');

  CREATE TEMP TABLE _r ON COMMIT DROP AS
  SELECT w.node_id, w.jnode->>'name' AS step, r.scope, r.obj, r.verb
    FROM _wn w, deployment.f_sys_sql_refs(w.jnode->'parameters'->>'query') r
   WHERE w.jnode->>'type' = 'n8n-nodes-base.postgres';

  CREATE TEMP TABLE _ne (f int, t int, kind text, step text) ON COMMIT DROP;

  INSERT INTO _ne
  SELECT h.id, wf.id, 'calls', NULL
    FROM deployment.sys_node h JOIN deployment.sys_node wf ON wf.id = h.parent_id
   WHERE h.layer = 'n8n' AND h.kind = 'webhook' AND h.deleted_at IS NULL;

  INSERT INTO _ne
  SELECT r.node_id, d.id, 'writes', r.step FROM _r r
    JOIN _db d ON d.scope = r.scope AND d.name = r.obj AND d.kind IN ('table','view','matview')
   WHERE r.verb = 'writes';

  INSERT INTO _ne
  SELECT r.node_id, d.id, CASE WHEN d.kind IN ('function','procedure') THEN 'calls' ELSE 'reads' END, r.step
    FROM _r r JOIN _db d ON d.scope = r.scope
     AND (d.name = r.obj AND d.kind IN ('table','view','matview') OR d.proname = r.obj AND d.kind IN ('function','procedure'))
   WHERE r.verb = 'ref'
     AND NOT EXISTS (SELECT 1 FROM _ne x WHERE x.f = r.node_id AND x.t = d.id AND x.kind = 'writes');

  INSERT INTO _ne
  SELECT w.node_id, t.id, 'calls', w.jnode->>'name'
    FROM _wn w JOIN deployment.sys_node t ON t.layer = 'n8n' AND t.kind = 'workflow' AND t.deleted_at IS NULL
     AND t.attrs->>'n8n_id' = coalesce(w.jnode->'parameters'->'workflowId'->>'value', w.jnode->'parameters'->>'workflowId')
   WHERE w.jnode->>'type' = 'n8n-nodes-base.executeWorkflow' AND w.node_id <> t.id;

  INSERT INTO _ne
  SELECT i.id, a.id, 'hosts', NULL
    FROM deployment.sys_node i, deployment.sys_node a
   WHERE i.layer = 'infra' AND i.kind = 'n8n' AND i.scope = 'dev' AND i.deleted_at IS NULL
     AND a.layer = 'n8n' AND a.kind = 'area';

  WITH agg AS (
    SELECT f, t, kind,
           CASE WHEN count(step) > 0 THEN jsonb_build_object('steps', jsonb_agg(DISTINCT step) FILTER (WHERE step IS NOT NULL))
                ELSE '{}'::jsonb END AS attrs
      FROM _ne WHERE f <> t GROUP BY 1, 2, 3
  ), up AS (
    INSERT INTO deployment.sys_edge AS s (from_node_id, to_node_id, kind, attrs, source)
    SELECT f, t, kind, attrs, 'n8n_db' FROM agg
    ON CONFLICT (from_node_id, to_node_id, kind) DO UPDATE
       SET attrs = EXCLUDED.attrs, source = EXCLUDED.source, last_seen = now(), deleted_at = NULL,
           updated_at = CASE WHEN s.attrs IS DISTINCT FROM EXCLUDED.attrs OR s.deleted_at IS NOT NULL THEN now() ELSE s.updated_at END
    RETURNING 1)
  SELECT count(*) INTO v_n FROM up;

  UPDATE deployment.sys_edge e SET deleted_at = now(), updated_at = now(), updated_by = 'f_sys_refresh_n8n'
   WHERE e.deleted_at IS NULL
     AND ((e.source = 'n8n_db' AND e.last_seen < now())
       OR EXISTS (SELECT 1 FROM deployment.sys_node n WHERE n.id IN (e.from_node_id, e.to_node_id) AND n.deleted_at IS NOT NULL));
  RETURN v_n;
END
$body$;

CREATE OR REPLACE FUNCTION deployment.f_sys_refresh_n8n() RETURNS jsonb LANGUAGE plpgsql AS $body$
DECLARE v_nodes int; v_edges int;
BEGIN
  v_nodes := deployment.f_sys_refresh_n8n_nodes();
  v_edges := deployment.f_sys_refresh_n8n_edges();
  RETURN jsonb_build_object('nodes_seen', v_nodes, 'edges_seen', v_edges,
    'nodes_retired', (SELECT count(*) FROM deployment.sys_node WHERE layer = 'n8n' AND deleted_at = now()),
    'edges_retired', (SELECT count(*) FROM deployment.sys_edge WHERE source = 'n8n_db' AND deleted_at = now()));
END
$body$;
