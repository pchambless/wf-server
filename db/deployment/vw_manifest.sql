-- deployment.vw_manifest: what a deploy plans (f_p01_plan) - ship by default.
-- database rows: every table/view/function in a database pipeline schema, minus object_policy structure = 'skip'.
-- n8n rows: every live workflow in the system map (deployment.sys_node), minus object_policy skips.
-- Replaced knowledge_base.objects as the registry on 2026-11-21 (shadow-tested against prod first).
CREATE OR REPLACE VIEW deployment.vw_manifest AS
WITH cat AS (
  SELECT (n.nspname || '.' || c.relname) COLLATE "default" AS schema_path,
         CASE c.relkind WHEN 'r' THEN 'table' ELSE 'view' END AS object_type
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname IN (SELECT pl.name FROM deployment.pipelines pl WHERE pl.platform = 'database')
     AND c.relkind IN ('r','v')
  UNION
  SELECT DISTINCT (n.nspname || '.' || p.proname) COLLATE "default", 'function'
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN (SELECT pl.name FROM deployment.pipelines pl WHERE pl.platform = 'database')
), base AS (
  SELECT 'database' AS platform, p.name AS pipeline, c.schema_path, split_part(c.schema_path, '.', 2) AS name,
         c.object_type, 'active' AS status, op.structure, op.data,
         CASE c.object_type WHEN 'table' THEN 1 WHEN 'function' THEN 2 WHEN 'view' THEN 2 END AS deploy_phase,
         coalesce(lo.load_level, co.code_level, 0) AS depth
    FROM cat c
    LEFT JOIN deployment.pipelines p ON p.name = split_part(c.schema_path, '.', 1)
    LEFT JOIN deployment.object_policy op ON op.schema_path = c.schema_path
    LEFT JOIN deployment.vw_load_order lo ON lo.schema_name = split_part(c.schema_path, '.', 1)
                                          AND lo.table_name = split_part(c.schema_path, '.', 2)
    LEFT JOIN deployment.vw_code_order co ON co.schema_path = c.schema_path
   WHERE coalesce(op.structure, 'deploy') <> 'skip'
  UNION ALL
  SELECT 'n8n', p.name, 'n8n.' || s.name, s.name, 'workflow',
         CASE WHEN (s.attrs->>'active')::boolean THEN 'active' ELSE 'inactive' END,
         'deploy', 'never_touch', 4, 0
    FROM deployment.sys_node s
    LEFT JOIN deployment.pipelines p ON p.name = 'n8n'
    LEFT JOIN deployment.object_policy op ON op.pipeline_id = p.id AND op.schema_path = 'n8n.' || s.name
   WHERE s.layer = 'n8n' AND s.kind = 'workflow' AND s.deleted_at IS NULL
     AND coalesce(op.structure, 'deploy') <> 'skip'
)
SELECT row_number() OVER (ORDER BY deploy_phase, depth, schema_path) AS seq,
       platform, pipeline, schema_path, name, object_type, status, structure, data, deploy_phase, depth
  FROM base;
