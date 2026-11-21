-- Deploy policy off knowledge_base.objects, SHADOW phase. Nothing here changes how deploys behave:
-- the live f_n8n_diff / f_structure_diff / vw_manifest still read knowledge_base.objects.
--
-- Model: ship by default. The map (deployment.sys_node) says what exists; deployment.object_policy
-- holds only the exceptions (structure = 'skip', notes.policy = obsolete | dev_only).
--
-- 1. Seed object_policy from knowledge_base.objects (obsolete + dev_only). Existing rows are never
--    overwritten (ON CONFLICT DO NOTHING) - a disagreement shows up in the compare views instead.
INSERT INTO deployment.object_policy (pipeline_id, schema_path, object_type, structure, data, reason, notes, created_by)
SELECT pl.id, o.schema_path, o.type, 'skip', 'never_touch',
       'Seeded from knowledge_base.objects (' || CASE WHEN o.status = 'obsolete' THEN 'obsolete' ELSE 'dev_only' END
         || ') for the map-driven manifest shadow test.',
       jsonb_build_object('policy', CASE WHEN o.status = 'obsolete' THEN 'obsolete' ELSE 'dev_only' END,
                          'source', 'knowledge_base.objects', 'kb_id', o.id),
       'claude'
  FROM knowledge_base.objects o
  JOIN deployment.pipelines pl
    ON (o.platform = 'database' AND pl.platform = 'database' AND pl.name = split_part(o.schema_path, '.', 1))
    OR (o.platform = 'n8n' AND pl.name = 'n8n')
 WHERE (o.platform = 'database' AND o.status = 'obsolete')
    OR (o.platform = 'n8n' AND (o.status = 'obsolete' OR o.notes->>'dev_only' = 'true'))
ON CONFLICT (pipeline_id, schema_path) DO NOTHING;

-- 2. Shadow of deployment.vw_manifest: same columns and ordering, but
--    database rows: status from the policy (no knowledge_base lookup), excluded when structure = 'skip';
--    n8n rows: every live workflow in the map, excluded when the policy says skip.
CREATE OR REPLACE VIEW deployment.vw_manifest_map AS
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

-- 3. Old vs new manifest, differences only. Empty for database = the two exclusion lists agree.
CREATE OR REPLACE VIEW deployment.vw_manifest_compare AS
SELECT coalesce(o.platform, n.platform) AS platform, coalesce(o.schema_path, n.schema_path) AS schema_path,
       o.status AS kb_status, n.status AS map_status,
       CASE WHEN o.schema_path IS NULL THEN 'only in map manifest'
            WHEN n.schema_path IS NULL THEN 'only in kb manifest'
            ELSE 'in both, fields differ' END AS difference
  FROM deployment.vw_manifest o
  FULL JOIN deployment.vw_manifest_map n ON n.platform = o.platform AND n.schema_path = o.schema_path
 WHERE o.schema_path IS NULL OR n.schema_path IS NULL
    OR (o.structure, o.data, o.deploy_phase, o.depth) IS DISTINCT FROM (n.structure, n.data, n.deploy_phase, n.depth);

-- 4. Review list: n8n workflows the map would ship that the kb manifest never listed, with evidence.
--    Decide each one by adding an object_policy skip row (dev_only/obsolete) or leaving it to ship.
CREATE OR REPLACE VIEW deployment.vw_policy_review AS
WITH c AS (
  SELECT schema_path FROM deployment.vw_manifest_compare
   WHERE platform = 'n8n' AND difference = 'only in map manifest'
), w AS (
  SELECT s.id, s.scope AS folder, s.name, (s.attrs->>'active')::boolean AS active
    FROM deployment.sys_node s JOIN c ON c.schema_path = 'n8n.' || s.name
   WHERE s.layer = 'n8n' AND s.kind = 'workflow' AND s.deleted_at IS NULL
)
SELECT w.folder, w.name, w.active,
       (SELECT string_agg(DISTINCT h.name, ', ') FROM deployment.sys_node h
         WHERE h.parent_id = w.id AND h.kind = 'webhook' AND h.deleted_at IS NULL) AS webhooks,
       EXISTS (SELECT 1 FROM deployment.sys_node h JOIN deployment.vw_sys_edges e ON e.to_node_id = h.id
                WHERE h.parent_id = w.id AND h.kind = 'webhook' AND e.from_layer = 'server') AS called_by_wf_server,
       (SELECT regexp_replace(l.file_path, '/[^/]+\Z', '') FROM deployment.vw_sys_node_last_change l
         WHERE l.node_id = w.id) AS git_folder,
       CASE
         WHEN (SELECT l.file_path FROM deployment.vw_sys_node_last_change l WHERE l.node_id = w.id)
              LIKE 'n8n/workflows-dev-only/%'
          AND EXISTS (SELECT 1 FROM deployment.sys_node h JOIN deployment.vw_sys_edges e ON e.to_node_id = h.id
                       WHERE h.parent_id = w.id AND h.kind = 'webhook' AND e.from_layer = 'server')
              THEN 'CONFLICT: exported dev-only, but wf-server calls it'
         WHEN (SELECT l.file_path FROM deployment.vw_sys_node_last_change l WHERE l.node_id = w.id)
              LIKE 'n8n/workflows-dev-only/%' THEN 'dev_only (exported to workflows-dev-only)'
         WHEN EXISTS (SELECT 1 FROM deployment.sys_node h JOIN deployment.vw_sys_edges e ON e.to_node_id = h.id
                       WHERE h.parent_id = w.id AND h.kind = 'webhook' AND e.from_layer = 'server')
              THEN 'ship (wf-server calls it)'
         WHEN w.folder LIKE 'personal%' THEN 'dev_only? (personal folder)'
         WHEN NOT w.active THEN 'obsolete? (inactive)'
         ELSE 'decide'
       END AS suggestion
  FROM w
 ORDER BY suggestion, w.folder, w.name;
