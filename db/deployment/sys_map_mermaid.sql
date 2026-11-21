-- System map renderers. Both return Mermaid flowchart text.
--   f_sys_mermaid(parent_id)   one drill-down level: the node's children, with edges between
--                              their descendants rolled up to child level and counted by kind.
--   f_sys_mermaid_around(id)   one neighbourhood: the node plus its direct in/out edges.
CREATE OR REPLACE FUNCTION deployment.f_sys_mermaid(p_parent_id int) RETURNS text LANGUAGE sql STABLE AS $body$
WITH RECURSIVE sub AS (
  SELECT id, id AS child FROM deployment.sys_node WHERE parent_id = p_parent_id AND deleted_at IS NULL
  UNION ALL
  SELECT n.id, s.child FROM deployment.sys_node n JOIN sub s ON n.parent_id = s.id WHERE n.deleted_at IS NULL
), rolled AS (
  SELECT a.child AS f, b.child AS t, e.kind, count(*) AS n
    FROM deployment.sys_edge e JOIN sub a ON a.id = e.from_node_id JOIN sub b ON b.id = e.to_node_id
   WHERE e.deleted_at IS NULL AND a.child <> b.child
   GROUP BY 1, 2, 3
)
SELECT 'flowchart LR' || E'\n' ||
  coalesce((SELECT string_agg(format('  n%s["%s<br/><small>%s</small>"]', id,
                    replace(name, '"', '#quot;'), kind), E'\n' ORDER BY kind, name)
              FROM deployment.sys_node WHERE parent_id = p_parent_id AND deleted_at IS NULL), '') || E'\n' ||
  coalesce((SELECT string_agg(format('  n%s -->|%s%s| n%s', f, kind,
                    CASE WHEN n > 1 THEN ' ' || n ELSE '' END, t), E'\n' ORDER BY f, t, kind)
              FROM rolled), '')
$body$;

CREATE OR REPLACE FUNCTION deployment.f_sys_mermaid_around(p_node_id int) RETURNS text LANGUAGE sql STABLE AS $body$
WITH e AS (
  SELECT from_node_id f, to_node_id t, kind FROM deployment.vw_sys_edges
   WHERE p_node_id IN (from_node_id, to_node_id)
), ids AS (SELECT p_node_id AS id UNION SELECT f FROM e UNION SELECT t FROM e)
SELECT 'flowchart LR' || E'\n' ||
  (SELECT string_agg(format('  n%s["%s<br/><small>%s</small>"]', n.id,
           replace(n.scope || CASE WHEN n.scope <> '' THEN '.' ELSE '' END || coalesce(n.attrs->>'proname' || '()', n.name), '"', '#quot;'), n.kind)
           || CASE WHEN n.id = p_node_id THEN ':::focus' ELSE '' END, E'\n' ORDER BY n.kind, n.name)
     FROM deployment.sys_node n JOIN ids USING (id)) || E'\n' ||
  coalesce((SELECT string_agg(format('  n%s -->|%s| n%s', f, kind, t), E'\n' ORDER BY f, t, kind) FROM e), '') ||
  E'\n  classDef focus stroke-width:3px'
$body$;
