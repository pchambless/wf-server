-- System map <-> git history (agile.git_commits / git_commit_files, filled by sync-git-commits.sh on deploy).
-- A node links to a commit when the commit touched the node's own file:
--   server module       its path (node name)                      e.g. src/routes/dmlRoutes.js
--   db function/proc    db/<schema>/functions/<proname>.sql       (deployment: scripts/deploy-lib/sql/<proname>.sql)
--   n8n workflow        n8n/{workflows,workflows-dev-only,ops-workflows}/<name>.json
-- Tables and views have no per-object file, so they have no direct commits; reach them through f_sys_impact.
-- task_id comes from the [task/N] tag in the commit message (null when untagged).
CREATE OR REPLACE VIEW deployment.vw_sys_node_commits AS
WITH paths AS (
  SELECT n.id AS node_id, p.path
    FROM deployment.sys_node n
    CROSS JOIN LATERAL (
      SELECT n.name WHERE n.layer = 'server' AND n.kind = 'module'
      UNION ALL SELECT 'db/' || n.scope || '/functions/' || (n.attrs->>'proname') || '.sql'
       WHERE n.layer = 'db' AND n.kind IN ('function','procedure')
      UNION ALL SELECT 'scripts/deploy-lib/sql/' || (n.attrs->>'proname') || '.sql'
       WHERE n.layer = 'db' AND n.kind IN ('function','procedure') AND n.scope = 'deployment'
      UNION ALL SELECT d || '/' || n.name || '.json'
        FROM unnest(ARRAY['n8n/workflows','n8n/workflows-dev-only','n8n/ops-workflows']) d
       WHERE n.layer = 'n8n' AND n.kind = 'workflow'
    ) p(path)
   WHERE n.deleted_at IS NULL
)
SELECT p.node_id, n.layer, n.kind,
       n.scope || CASE WHEN n.scope <> '' AND n.layer <> 'server' THEN '.' ELSE '' END
         || CASE WHEN n.layer = 'server' THEN '' ELSE coalesce(n.attrs->>'proname' || '()', n.name) END AS obj,
       f.file_path, f.status AS file_status, f.insertions, f.deletions,
       c.sha, c.commit_date, c.author, c.repo,
       substring(c.message, '\[task/(\d+)\]')::int AS task_id,
       split_part(c.message, E'\n', 1) AS subject
  FROM paths p
  JOIN deployment.sys_node n ON n.id = p.node_id
  JOIN agile.git_commit_files f ON f.file_path = p.path
  JOIN agile.git_commits c ON c.sha = f.sha AND c.repo = 'wf-server';

-- Latest commit per node, with how many commits and tasks have touched it.
CREATE OR REPLACE VIEW deployment.vw_sys_node_last_change AS
SELECT DISTINCT ON (c.node_id)
       c.node_id, c.layer, c.kind, c.obj, c.file_path, c.sha, c.commit_date AS last_commit, c.author,
       c.task_id AS last_task, c.subject, t.commits, t.tasks
  FROM deployment.vw_sys_node_commits c
  JOIN (SELECT node_id, count(DISTINCT sha) AS commits, count(DISTINCT task_id) AS tasks
          FROM deployment.vw_sys_node_commits GROUP BY node_id) t USING (node_id)
 ORDER BY c.node_id, c.commit_date DESC;

-- What could break if a node changes, with who last changed each dependent, when, and for which task.
CREATE OR REPLACE FUNCTION deployment.f_sys_impact_history(p_node int, p_max int DEFAULT 6)
RETURNS TABLE (depth int, layer text, kind text, obj text, last_commit timestamp, last_task int, subject text,
               commits bigint)
LANGUAGE sql STABLE AS $body$
SELECT i.depth, i.layer, i.kind, i.obj, l.last_commit, l.last_task, l.subject, l.commits
  FROM deployment.f_sys_impact(p_node, p_max) i
  LEFT JOIN deployment.vw_sys_node_last_change l ON l.node_id = i.node_id
 ORDER BY i.depth, i.layer, i.obj
$body$;
