-- Deploy policy exceptions in deployment.object_policy (structure = 'skip'), used by vw_manifest,
-- f_n8n_diff and f_structure_diff since 2026-11-21. Everything else ships by default.
-- This seed copied the old knowledge_base.objects exclusions (obsolete + dev_only). Paul's 27 n8n
-- decisions (2026-11-21) were inserted directly and carry notes.decided_by = 'paul'.
-- To ship something later (e.g. wf-api), set its row's structure to 'deploy'.
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
