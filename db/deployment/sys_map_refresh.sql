-- System map, DB layer, part 3: one-call refresh and a readable edge view.
-- Usage: SELECT deployment.f_sys_refresh_db();
CREATE OR REPLACE FUNCTION deployment.f_sys_refresh_db() RETURNS jsonb LANGUAGE plpgsql AS $body$
DECLARE v_nodes int; v_edges int;
BEGIN
  v_nodes := deployment.f_sys_refresh_db_nodes();
  v_edges := deployment.f_sys_refresh_db_edges();
  RETURN jsonb_build_object(
    'nodes_seen', v_nodes, 'edges_seen', v_edges,
    'nodes_new',     (SELECT count(*) FROM deployment.sys_node WHERE layer = 'db' AND first_seen = now()),
    'nodes_retired', (SELECT count(*) FROM deployment.sys_node WHERE layer = 'db' AND deleted_at = now()),
    'edges_new',     (SELECT count(*) FROM deployment.sys_edge WHERE first_seen = now()),
    'edges_retired', (SELECT count(*) FROM deployment.sys_edge WHERE deleted_at = now()));
END
$body$;

CREATE OR REPLACE VIEW deployment.vw_sys_edges AS
SELECT e.id, e.kind,
       f.layer AS from_layer, f.kind AS from_kind, f.scope || '.' || f.name AS from_obj,
       t.layer AS to_layer,   t.kind AS to_kind,   t.scope || '.' || t.name AS to_obj,
       e.source, e.attrs, e.from_node_id, e.to_node_id
  FROM deployment.sys_edge e
  JOIN deployment.sys_node f ON f.id = e.from_node_id
  JOIN deployment.sys_node t ON t.id = e.to_node_id
 WHERE e.deleted_at IS NULL AND f.deleted_at IS NULL AND t.deleted_at IS NULL;
