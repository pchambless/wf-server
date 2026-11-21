-- System map queries.
--   f_sys_path(from, to, max_depth)    shortest directed paths along edges (call direction), as node-id arrays
--   f_sys_impact(node, max_depth)      everything upstream of a node (what breaks if it changes), by depth
--   f_sys_mermaid_nodes(ids[])         Mermaid for a given node set and the live edges among them
-- 'references' (FKs) and 'hosts' are left out of path/impact by default: they are structure, not calls.
CREATE OR REPLACE FUNCTION deployment.f_sys_path(p_from int, p_to int, p_max int DEFAULT 8,
  p_kinds text[] DEFAULT '{reads,writes,calls,depends_on,fires_on,routes_to}')
RETURNS TABLE (hops int, path int[]) LANGUAGE sql STABLE AS $body$
WITH RECURSIVE w AS (
  SELECT 0 AS hops, ARRAY[p_from] AS path
  UNION ALL
  SELECT w.hops + 1, w.path || e.to_node_id
    FROM w JOIN deployment.vw_sys_edges e ON e.from_node_id = w.path[array_length(w.path, 1)]
   WHERE w.hops < p_max AND e.kind = ANY (p_kinds) AND NOT e.to_node_id = ANY (w.path)
     AND w.path[array_length(w.path, 1)] <> p_to
)
SELECT hops, path FROM w
 WHERE path[array_length(path, 1)] = p_to
   AND hops = (SELECT min(hops) FROM w WHERE path[array_length(path, 1)] = p_to)
$body$;

CREATE OR REPLACE FUNCTION deployment.f_sys_impact(p_node int, p_max int DEFAULT 6,
  p_kinds text[] DEFAULT '{reads,writes,calls,depends_on,fires_on,routes_to}')
RETURNS TABLE (depth int, node_id int, layer text, kind text, obj text) LANGUAGE sql STABLE AS $body$
WITH RECURSIVE up AS (
  SELECT 0 AS depth, p_node AS id
  UNION
  SELECT u.depth + 1, e.from_node_id FROM up u JOIN deployment.vw_sys_edges e ON e.to_node_id = u.id
   WHERE u.depth < p_max AND e.kind = ANY (p_kinds)
)
SELECT min(u.depth), n.id, n.layer, n.kind,
       n.scope || CASE WHEN n.scope <> '' THEN '.' ELSE '' END || coalesce(n.attrs->>'proname' || '()', n.name)
  FROM up u JOIN deployment.sys_node n ON n.id = u.id
 WHERE u.id <> p_node
 GROUP BY n.id, n.layer, n.kind, n.scope, n.name, n.attrs
$body$;

CREATE OR REPLACE FUNCTION deployment.f_sys_mermaid_nodes(p_ids int[]) RETURNS text LANGUAGE sql STABLE AS $body$
SELECT 'flowchart LR' || E'\n' ||
  (SELECT string_agg(format('  n%s["%s<br/><small>%s %s</small>"]', n.id,
           replace(CASE WHEN n.layer = 'server' THEN n.name
                        ELSE n.scope || CASE WHEN n.scope <> '' THEN '.' ELSE '' END || coalesce(n.attrs->>'proname' || '()', n.name)
                   END, '"', '#quot;'), n.layer, n.kind), E'\n' ORDER BY array_position(p_ids, n.id))
     FROM deployment.sys_node n WHERE n.id = ANY (p_ids)) || E'\n' ||
  coalesce((SELECT string_agg(format('  n%s -->|%s| n%s', e.from_node_id, e.kind, e.to_node_id), E'\n'
                              ORDER BY array_position(p_ids, e.from_node_id))
              FROM deployment.vw_sys_edges e
             WHERE e.from_node_id = ANY (p_ids) AND e.to_node_id = ANY (p_ids)), '')
$body$;
