-- System map, DB layer, part 1: nodes from pg_catalog into deployment.sys_node.
-- Upserts live objects, soft-deletes (deleted_at) db nodes not seen this run.
CREATE OR REPLACE FUNCTION deployment.f_sys_refresh_db_nodes(
  p_exclude text[] DEFAULT '{information_schema,public}'
) RETURNS int LANGUAGE plpgsql AS $body$
DECLARE v_n int;
BEGIN
  WITH ext AS (
    SELECT objid, classid FROM pg_depend WHERE deptype = 'e'
  ), objs AS (
    SELECT CASE c.relkind WHEN 'v' THEN 'view' WHEN 'm' THEN 'matview' ELSE 'table' END AS kind,
           n.nspname::text AS scope, c.relname::text AS name,
           jsonb_build_object('oid', c.oid, 'owner', pg_get_userbyid(c.relowner),
                              'est_rows', GREATEST(c.reltuples, 0)::bigint) AS attrs
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE c.relkind IN ('r','p','v','m') AND NOT c.relispartition
       AND n.nspname !~ '^pg_' AND n.nspname <> ALL (p_exclude)
       AND NOT EXISTS (SELECT 1 FROM ext WHERE ext.objid = c.oid AND ext.classid = 'pg_class'::regclass)
    UNION ALL
    SELECT CASE p.prokind WHEN 'p' THEN 'procedure' ELSE 'function' END,
           n.nspname, p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
           jsonb_build_object('oid', p.oid, 'proname', p.proname, 'lang', l.lanname,
                              'returns', pg_get_function_result(p.oid), 'src_md5', md5(coalesce(p.prosrc, '')))
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pg_language l ON l.oid = p.prolang
     WHERE p.prokind IN ('f','p')
       AND n.nspname !~ '^pg_' AND n.nspname <> ALL (p_exclude)
       AND NOT EXISTS (SELECT 1 FROM ext WHERE ext.objid = p.oid AND ext.classid = 'pg_proc'::regclass)
    UNION ALL
    SELECT 'trigger', n.nspname, c.relname || '.' || t.tgname,
           jsonb_build_object('oid', t.oid, 'enabled', t.tgenabled::text, 'def', pg_get_triggerdef(t.oid))
      FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE NOT t.tgisinternal AND n.nspname !~ '^pg_' AND n.nspname <> ALL (p_exclude)
  ), up AS (
    INSERT INTO deployment.sys_node AS s (layer, kind, scope, name, attrs, source)
    SELECT 'db', kind, scope, name, attrs, 'pg_catalog' FROM objs
    ON CONFLICT (layer, kind, scope, name) DO UPDATE
       SET attrs = EXCLUDED.attrs, last_seen = now(), deleted_at = NULL,
           updated_at = CASE WHEN s.attrs IS DISTINCT FROM EXCLUDED.attrs OR s.deleted_at IS NOT NULL
                             THEN now() ELSE s.updated_at END,
           updated_by = CASE WHEN s.attrs IS DISTINCT FROM EXCLUDED.attrs OR s.deleted_at IS NOT NULL
                             THEN 'f_sys_refresh_db' ELSE s.updated_by END
    RETURNING 1
  )
  SELECT count(*) INTO v_n FROM up;

  -- drill-down hierarchy: system 'whatsfresh' > area 'db' > schema > object (> trigger under its table)
  INSERT INTO deployment.sys_node AS s (layer, kind, scope, name, source)
  VALUES ('system', 'system', '', 'whatsfresh', 'sys_map'), ('db', 'area', '', 'db', 'pg_catalog')
  ON CONFLICT (layer, kind, scope, name) DO UPDATE SET last_seen = now(), deleted_at = NULL;

  INSERT INTO deployment.sys_node AS s (layer, kind, scope, name, source)
  SELECT DISTINCT 'db', 'schema', '', scope, 'pg_catalog'
    FROM deployment.sys_node
   WHERE layer = 'db' AND kind NOT IN ('area','schema') AND last_seen = now()
  ON CONFLICT (layer, kind, scope, name) DO UPDATE SET last_seen = now(), deleted_at = NULL;

  UPDATE deployment.sys_node SET parent_id = (SELECT id FROM deployment.sys_node
                                               WHERE layer = 'system' AND kind = 'system' AND name = 'whatsfresh')
   WHERE layer = 'db' AND kind = 'area' AND parent_id IS NULL;

  UPDATE deployment.sys_node c SET parent_id = p.id
    FROM deployment.sys_node p
   WHERE c.layer = 'db' AND c.last_seen = now() AND c.parent_id IS DISTINCT FROM p.id AND p.layer = 'db'
     AND ((c.kind = 'schema' AND p.kind = 'area' AND p.name = 'db')
       OR (c.kind IN ('table','view','matview','function','procedure') AND p.kind = 'schema' AND p.name = c.scope)
       OR (c.kind = 'trigger' AND p.kind = 'table' AND p.scope = c.scope AND p.name = split_part(c.name, '.', 1)));

  UPDATE deployment.sys_node SET deleted_at = now(), updated_at = now(), updated_by = 'f_sys_refresh_db'
   WHERE layer = 'db' AND deleted_at IS NULL AND last_seen < now();
  RETURN v_n;
END
$body$;
