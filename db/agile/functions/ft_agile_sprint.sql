CREATE OR REPLACE FUNCTION agile.ft_agile_sprint(p_id integer, p_status text DEFAULT 'All'::text, p_priority text DEFAULT 'All'::text)
 RETURNS TABLE(id integer, level integer, ordr integer, page_type text, page_name text, title text, status text, description text, parent_id integer, path text, page text, created_at date, row_color text, priority text, done_count integer, total_count integer)
 LANGUAGE sql
 STABLE
AS $function$
-- p_id = 0 OR NULL = ALL apps. Status belongs only to Tasks; App/Epic/Sprint carry NULL status.
-- Rollup = done tasks / total tasks in subtree (how done are we), appended to the page label and returned as columns.
-- Status/priority filter keeps matching Tasks plus their ancestor headers; headers with no match drop.
WITH RECURSIVE hier AS (
  SELECT
    id, 1 as level,
    ordr, page_type, page_name, title, status, description, parent_id, created_at,
    id::text as path,
    lpad(id::text, 10, '0') as sort_path,
    priority
  FROM agile.vw_agile_cache
  WHERE ((p_id = 0 OR p_id IS NULL) AND page_type = 'App') OR id = p_id
  UNION ALL
  SELECT
    ac.id, h.level + 1,
    ac.ordr, ac.page_type, ac.page_name, ac.title, ac.status, ac.description, ac.parent_id, ac.created_at,
    h.path || '.' || ac.id::text,
    h.sort_path || '.' || lpad(ac.id::text, 10, '0'),
    ac.priority
  FROM agile.vw_agile_cache ac
  JOIN hier h ON ac.parent_id = h.id
  WHERE h.level < 10
  and ac.page_type <> 'App'
),
rollup AS (
  SELECT h.id,
    count(*) FILTER (WHERE d.page_type = 'Task')::integer AS total_count,
    count(*) FILTER (WHERE d.page_type = 'Task' AND d.status = 'Done')::integer AS done_count
  FROM hier h
  JOIN hier d ON (d.id = h.id OR d.path LIKE h.path || '.%')
  GROUP BY h.id
),
matched AS (
  SELECT h.id, h.path
  FROM hier h
  WHERE h.page_type = 'Task'
    AND (h.status = p_status OR p_status = 'All' OR p_status IS NULL)
    AND (h.priority = p_priority OR p_priority = 'All' OR p_priority IS NULL)
),
keep AS (
  SELECT DISTINCT h.id
  FROM hier h
  JOIN matched m ON m.id = h.id OR m.path LIKE h.path || '.%'
)
SELECT
  h.id, h.level, h.ordr, h.page_type, h.page_name, h.title,
  CASE WHEN h.page_type = 'Task' THEN h.status ELSE NULL END as status,
  h.description, h.parent_id, h.path,
  concat(repeat(' >', h.level - 1), h.title, ' (', r.done_count, '/', r.total_count, ')') as page,
  h.created_at,
  CASE page_type
      WHEN 'Epic' THEN '#1d4ed8'
      WHEN 'Sprint' THEN '#16a34a'
      WHEN 'Task' THEN '#cc0000'
      WHEN 'App' THEN '#dc2626'
    ELSE '#000000'
  END AS row_color,
  CASE WHEN h.page_type = 'Task' THEN h.priority ELSE NULL END as priority,
  r.done_count, r.total_count
FROM hier h
JOIN rollup r ON r.id = h.id
WHERE h.id IN (SELECT id FROM keep)
ORDER BY h.sort_path;
$function$
;

