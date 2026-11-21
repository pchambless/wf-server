-- System map, n8n layer part 1: nodes from dev n8n's own tables (public.workflow_entity, public.folder),
-- i.e. what is actually deployed, not the exported JSON. Archived workflows are left out (so retired).
-- Hierarchy: system > area 'n8n' > folder (nested) > workflow > webhook.
CREATE OR REPLACE FUNCTION deployment.f_sys_refresh_n8n_nodes() RETURNS int LANGUAGE plpgsql AS $body$
DECLARE v_n int; v_root int; v_area int;
BEGIN
  INSERT INTO deployment.sys_node AS s (layer, kind, scope, name, source)
  VALUES ('system', 'system', '', 'whatsfresh', 'sys_map'), ('n8n', 'area', '', 'n8n', 'n8n_db')
  ON CONFLICT (layer, kind, scope, name) DO UPDATE SET last_seen = now(), deleted_at = NULL;
  SELECT id INTO v_root FROM deployment.sys_node WHERE layer = 'system' AND kind = 'system' AND name = 'whatsfresh';
  SELECT id INTO v_area FROM deployment.sys_node WHERE layer = 'n8n' AND kind = 'area' AND name = 'n8n';
  UPDATE deployment.sys_node SET parent_id = v_root WHERE id = v_area AND parent_id IS DISTINCT FROM v_root;

  CREATE TEMP TABLE _f ON COMMIT DROP AS
  WITH RECURSIVE f AS (
    SELECT id, name::text AS path FROM public.folder WHERE "parentFolderId" IS NULL
    UNION ALL
    SELECT c.id, f.path || '/' || c.name FROM public.folder c JOIN f ON c."parentFolderId" = f.id
  ) SELECT * FROM f;

  WITH objs AS (
    SELECT 'folder' AS kind, '' AS scope, path AS name, jsonb_build_object('n8n_id', id) AS attrs FROM _f
    UNION ALL
    SELECT 'workflow', coalesce(f.path, ''), w.name,
           jsonb_build_object('n8n_id', w.id, 'active', w.active, 'folder_id', w."parentFolderId",
                              'n8n_updated_at', w."updatedAt")
      FROM public.workflow_entity w LEFT JOIN _f f ON f.id = w."parentFolderId"
     WHERE NOT w."isArchived"
    UNION ALL
    SELECT 'webhook', '', n->'parameters'->>'path',
           jsonb_build_object('method', coalesce(n->'parameters'->>'httpMethod', 'GET'), 'workflow_id', w.id,
                              'auth', coalesce(n->'parameters'->>'authentication', 'none'))
      FROM public.workflow_entity w, json_array_elements(w.nodes) n
     WHERE NOT w."isArchived" AND n->>'type' = 'n8n-nodes-base.webhook' AND n->'parameters'->>'path' IS NOT NULL
  ), up AS (
    INSERT INTO deployment.sys_node AS s (layer, kind, scope, name, attrs, source)
    SELECT 'n8n', kind, scope, name, attrs, 'n8n_db' FROM objs
    ON CONFLICT (layer, kind, scope, name) DO UPDATE
       SET attrs = EXCLUDED.attrs, last_seen = now(), deleted_at = NULL,
           updated_at = CASE WHEN s.attrs IS DISTINCT FROM EXCLUDED.attrs OR s.deleted_at IS NOT NULL THEN now() ELSE s.updated_at END,
           updated_by = CASE WHEN s.attrs IS DISTINCT FROM EXCLUDED.attrs OR s.deleted_at IS NOT NULL THEN 'f_sys_refresh_n8n' ELSE s.updated_by END
    RETURNING 1)
  SELECT count(*) INTO v_n FROM up;

  -- parents: folder -> parent folder | area; workflow -> its folder | area; webhook -> its workflow
  UPDATE deployment.sys_node c SET parent_id = coalesce(p.id, v_area)
    FROM deployment.sys_node c2
    LEFT JOIN public.folder pf ON c2.kind = 'folder' AND pf.id = c2.attrs->>'n8n_id'
    LEFT JOIN deployment.sys_node p ON p.layer = 'n8n' AND p.deleted_at IS NULL AND (
            (c2.kind = 'folder'   AND p.kind = 'folder'   AND p.attrs->>'n8n_id' = pf."parentFolderId")
         OR (c2.kind = 'workflow' AND p.kind = 'folder'   AND p.attrs->>'n8n_id' = c2.attrs->>'folder_id')
         OR (c2.kind = 'webhook'  AND p.kind = 'workflow' AND p.attrs->>'n8n_id' = c2.attrs->>'workflow_id'))
   WHERE c.id = c2.id AND c.layer = 'n8n' AND c.kind IN ('folder','workflow','webhook') AND c.last_seen = now()
     AND c.parent_id IS DISTINCT FROM coalesce(p.id, v_area);

  UPDATE deployment.sys_node SET deleted_at = now(), updated_at = now(), updated_by = 'f_sys_refresh_n8n'
   WHERE layer = 'n8n' AND deleted_at IS NULL AND last_seen < now();
  RETURN v_n;
END
$body$;
