CREATE OR REPLACE FUNCTION deployment.f_scan(p_schemas text[] DEFAULT ARRAY['studio'::text, 'whatsfresh'::text])
 RETURNS TABLE(scanned integer, changed integer, gone integer, descoped integer)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_now  timestamptz := clock_timestamp();
    v_tbl  record;
    v_pk   text;
BEGIN
    -- FUNCTIONS. object_name carries the identity args, so an overload is its own object.
    INSERT INTO deployment.object_state
           (kind, schema_name, object_name, component_name, fingerprint, status, last_scanned, last_changed)
    SELECT 'function', n.nspname,
           p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', '',
           md5(pg_get_functiondef(p.oid)), 'live', v_now, v_now
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = ANY(p_schemas) AND p.prokind = 'f'
       AND NOT EXISTS (SELECT 1 FROM deployment.object_policy op
                        WHERE op.schema_path = n.nspname || '.' || p.proname
                          AND op.structure = 'skip')
    ON CONFLICT (kind, schema_name, object_name, component_name) DO UPDATE
       SET fingerprint  = EXCLUDED.fingerprint,
           status       = 'live',
           last_scanned = v_now,
           last_changed = CASE WHEN object_state.fingerprint IS DISTINCT FROM EXCLUDED.fingerprint
                               THEN v_now ELSE object_state.last_changed END;

    -- VIEWS. pg_get_viewdef re-renders from the parse tree, so reformatting is invisible.
    INSERT INTO deployment.object_state
           (kind, schema_name, object_name, component_name, fingerprint, status, last_scanned, last_changed)
    SELECT 'view', n.nspname, c.relname, '', md5(pg_get_viewdef(c.oid, true)), 'live', v_now, v_now
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = ANY(p_schemas) AND c.relkind = 'v'
       AND NOT EXISTS (SELECT 1 FROM deployment.object_policy op
                        WHERE op.schema_path = n.nspname || '.' || c.relname
                          AND op.structure = 'skip')
    ON CONFLICT (kind, schema_name, object_name, component_name) DO UPDATE
       SET fingerprint  = EXCLUDED.fingerprint,
           status       = 'live',
           last_scanned = v_now,
           last_changed = CASE WHEN object_state.fingerprint IS DISTINCT FROM EXCLUDED.fingerprint
                               THEN v_now ELSE object_state.last_changed END;

    -- TABLES. Columns and constraints, both ordered by name: catalog scan order is not
    -- guaranteed and unordered aggregation would manufacture false drift.
    -- NOTE: indexes and triggers are NOT covered - they are not pg_constraint entries.
    INSERT INTO deployment.object_state
           (kind, schema_name, object_name, component_name, fingerprint, status, last_scanned, last_changed)
    SELECT 'table', n.nspname, c.relname, '',
           md5(COALESCE(cols.def,'') || '|' || COALESCE(cons.def,'')), 'live', v_now, v_now
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      LEFT JOIN LATERAL (
            SELECT string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod)
                              || ':' || a.attnotnull::text
                              || ':' || COALESCE(pg_get_expr(d.adbin, d.adrelid), '')
                              || ':' || COALESCE(a.attidentity, ''), ',' ORDER BY a.attname) AS def
              FROM pg_attribute a
              LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
             WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped) cols ON true
      LEFT JOIN LATERAL (
            SELECT string_agg(con.conname || ':' || pg_get_constraintdef(con.oid), ',' ORDER BY con.conname) AS def
              FROM pg_constraint con WHERE con.conrelid = c.oid) cons ON true
     WHERE n.nspname = ANY(p_schemas) AND c.relkind = 'r'
       AND NOT EXISTS (SELECT 1 FROM deployment.object_policy op
                        WHERE op.schema_path = n.nspname || '.' || c.relname
                          AND op.structure = 'skip')
    ON CONFLICT (kind, schema_name, object_name, component_name) DO UPDATE
       SET fingerprint  = EXCLUDED.fingerprint,
           status       = 'live',
           last_scanned = v_now,
           last_changed = CASE WHEN object_state.fingerprint IS DISTINCT FROM EXCLUDED.fingerprint
                               THEN v_now ELSE object_state.last_changed END;

    -- ROWS, only for tables explicitly opted in via diff_data='compare'.
    FOR v_tbl IN
        SELECT split_part(op.schema_path,'.',1) AS sch, split_part(op.schema_path,'.',2) AS tbl
          FROM deployment.object_policy op
         WHERE op.diff_data = 'compare' AND op.object_type = 'table'
           AND split_part(op.schema_path,'.',1) = ANY(p_schemas)
         ORDER BY op.schema_path
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                        WHERE n.nspname = v_tbl.sch AND c.relname = v_tbl.tbl AND c.relkind = 'r') THEN
            CONTINUE;
        END IF;

        SELECT a.attname INTO v_pk
          FROM pg_attribute a
          JOIN pg_class c     ON c.oid = a.attrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = v_tbl.sch AND c.relname = v_tbl.tbl
           AND a.attname = 'id' AND a.attnum > 0 AND NOT a.attisdropped;

        IF v_pk IS NULL THEN
            INSERT INTO deployment.object_state
                   (kind, schema_name, object_name, component_name, fingerprint, status, last_scanned, last_changed)
            VALUES ('row', v_tbl.sch, v_tbl.tbl, '(no id column)', 'unwatchable', 'live', v_now, v_now)
            ON CONFLICT (kind, schema_name, object_name, component_name) DO UPDATE
               SET last_scanned = v_now, status = 'live';
            CONTINUE;
        END IF;

        EXECUTE format(
            'INSERT INTO deployment.object_state
                    (kind, schema_name, object_name, component_name, fingerprint, status, last_scanned, last_changed)
             SELECT ''row'', %L, %L, t.%I::text, md5((to_jsonb(t) - ARRAY[''created_at'',''created_by'',''updated_at'',''updated_by'',''deleted_by''])::text), ''live'', %L, %L FROM %I.%I t
             ON CONFLICT (kind, schema_name, object_name, component_name) DO UPDATE
                SET fingerprint  = EXCLUDED.fingerprint,
                    status       = ''live'',
                    last_scanned = %L,
                    last_changed = CASE WHEN object_state.fingerprint IS DISTINCT FROM EXCLUDED.fingerprint
                                        THEN %L ELSE object_state.last_changed END',
            v_tbl.sch, v_tbl.tbl, v_pk, v_now, v_now, v_tbl.sch, v_tbl.tbl, v_now, v_now);
    END LOOP;

    -- N8N WORKFLOWS, scoped to folders prefixed 'wf-' - same production-relevant scope
    -- export-n8n-workflows.sh uses (task 270), not every workflow on the instance.
    -- Unconditional on p_schemas - folder scope is a different axis than Postgres schema
    -- scope, so narrowing p_schemas to one DB schema should not silently stop watching n8n.
    -- Fingerprint is TOPOLOGY only (connections, settings, active, sorted node names) -
    -- mirrors TABLE (structure) vs ROW (content): editing one node's content should flag
    -- that node via kind='node' below, not also flag the whole workflow as changed.
    INSERT INTO deployment.object_state
           (kind, schema_name, object_name, component_name, fingerprint, status, last_scanned, last_changed)
    SELECT 'workflow', 'n8n', w.name, '',
           md5(w.connections::text || '|' || w.settings::text || '|' || w.active::text || '|' ||
               COALESCE((SELECT string_agg(n->>'name', ',' ORDER BY n->>'name')
                           FROM json_array_elements(w.nodes) n), '')),
           'live', v_now, v_now
      FROM public.workflow_entity w
      JOIN public.folder f ON f.id = w."parentFolderId"
     WHERE f.name LIKE 'wf-%' AND w.active = true AND w."isArchived" = false
    ON CONFLICT (kind, schema_name, object_name, component_name) DO UPDATE
       SET fingerprint  = EXCLUDED.fingerprint,
           status       = 'live',
           last_scanned = v_now,
           last_changed = CASE WHEN object_state.fingerprint IS DISTINCT FROM EXCLUDED.fingerprint
                               THEN v_now ELSE object_state.last_changed END;

    -- N8N NODES, one row per node in each wf-* scoped workflow. component_name = node name.
    -- Fingerprint drops 'position' only (canvas coordinates are cosmetic - dragging a node
    -- would otherwise manufacture false drift on every rearrange). Everything else, INCLUDING
    -- credentials, stays in the hash: unlike f_n8n_diff's cross-environment deploy diff (which
    -- strips credentials because dev/prod are EXPECTED to reference different credential ids
    -- for the same logical connection), this watches ONE environment for real edits - rewiring
    -- a node to a different credential on dev is genuine content drift, not noise to hide.
    INSERT INTO deployment.object_state
           (kind, schema_name, object_name, component_name, fingerprint, status, last_scanned, last_changed)
    SELECT 'node', 'n8n', w.name, n->>'name',
           md5((n::jsonb - 'position')::text),
           'live', v_now, v_now
      FROM public.workflow_entity w
      JOIN public.folder f ON f.id = w."parentFolderId"
      CROSS JOIN LATERAL json_array_elements(w.nodes) n
     WHERE f.name LIKE 'wf-%' AND w.active = true AND w."isArchived" = false
    ON CONFLICT (kind, schema_name, object_name, component_name) DO UPDATE
       SET fingerprint  = EXCLUDED.fingerprint,
           status       = 'live',
           last_scanned = v_now,
           last_changed = CASE WHEN object_state.fingerprint IS DISTINCT FROM EXCLUDED.fingerprint
                               THEN v_now ELSE object_state.last_changed END;

    -- Anything not touched by this scan is either GONE or merely OUT OF SCOPE.
    -- Absence has more than one cause: a policy flipped to skip, or a narrowed
    -- p_schemas, both leave an object unscanned while it still exists. Reading
    -- either as a deletion would report every row of a de-scoped table as deleted.
    -- CATALOG EXISTENCE decides first, policy only after. Learned by fault injection
    -- 2026-08-18: when whatsfresh.fsma_classifications was dropped its object_policy
    -- row moved to studio with it, so "no compare policy" matched the dropped table
    -- and its 6 rows were filed as out_of_scope - the deletion silently lost them.
    -- If the object is gone from pg_catalog it is DELETED, whatever policy now says.
    -- Only an object that still exists can be merely out of scope. Same rule applied
    -- to n8n below: gone from workflow_entity is deleted, still there but out of the
    -- wf-* folder or deactivated is merely out_of_scope.
    UPDATE deployment.object_state s
       SET status = CASE
            WHEN s.kind = 'row' THEN
                CASE WHEN NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                                       WHERE n.nspname = s.schema_name AND c.relname = s.object_name
                                         AND c.relkind = 'r')                       THEN 'deleted'
                     WHEN NOT (s.schema_name = ANY(p_schemas))                       THEN 'out_of_scope'
                     WHEN NOT EXISTS (SELECT 1 FROM deployment.object_policy op
                                       WHERE op.schema_path = s.schema_name || '.' || s.object_name
                                         AND op.object_type = 'table'
                                         AND op.diff_data = 'compare')               THEN 'out_of_scope'
                     ELSE 'deleted' END
            WHEN s.kind = 'function' THEN
                CASE WHEN NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                                       WHERE n.nspname = s.schema_name
                                         AND p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')'
                                             = s.object_name)                        THEN 'deleted'
                     WHEN NOT (s.schema_name = ANY(p_schemas))                       THEN 'out_of_scope'
                     WHEN EXISTS (SELECT 1 FROM deployment.object_policy op
                                   WHERE op.schema_path = s.schema_name || '.' || split_part(s.object_name,'(',1)
                                     AND op.structure = 'skip')                 THEN 'out_of_scope'
                     ELSE 'deleted' END
            WHEN s.kind = 'workflow' THEN
                CASE WHEN NOT EXISTS (SELECT 1 FROM public.workflow_entity w WHERE w.name = s.object_name)
                                                                                      THEN 'deleted'
                     WHEN NOT EXISTS (SELECT 1 FROM public.workflow_entity w
                                        JOIN public.folder f ON f.id = w."parentFolderId"
                                       WHERE w.name = s.object_name AND f.name LIKE 'wf-%'
                                         AND w.active = true AND w."isArchived" = false)
                                                                                      THEN 'out_of_scope'
                     ELSE 'deleted' END
            WHEN s.kind = 'node' THEN
                CASE WHEN NOT EXISTS (SELECT 1 FROM public.workflow_entity w WHERE w.name = s.object_name)
                                                                                      THEN 'deleted'
                     WHEN NOT EXISTS (SELECT 1 FROM public.workflow_entity w
                                        JOIN public.folder f ON f.id = w."parentFolderId"
                                       WHERE w.name = s.object_name AND f.name LIKE 'wf-%'
                                         AND w.active = true AND w."isArchived" = false)
                                                                                      THEN 'out_of_scope'
                     WHEN NOT EXISTS (SELECT 1 FROM public.workflow_entity w
                                       CROSS JOIN LATERAL json_array_elements(w.nodes) n
                                      WHERE w.name = s.object_name AND n->>'name' = s.component_name)
                                                                                      THEN 'deleted'
                     ELSE 'deleted' END
            ELSE
                CASE WHEN NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                                       WHERE n.nspname = s.schema_name AND c.relname = s.object_name
                                         AND c.relkind = CASE s.kind WHEN 'view' THEN 'v' ELSE 'r' END)
                                                                                     THEN 'deleted'
                     WHEN NOT (s.schema_name = ANY(p_schemas))                       THEN 'out_of_scope'
                     WHEN EXISTS (SELECT 1 FROM deployment.object_policy op
                                   WHERE op.schema_path = s.schema_name || '.' || s.object_name
                                     AND op.structure = 'skip')                 THEN 'out_of_scope'
                     ELSE 'deleted' END
            END
     WHERE s.last_scanned IS DISTINCT FROM v_now;

    RETURN QUERY
    SELECT count(*) FILTER (WHERE last_scanned = v_now)::int,
           count(*) FILTER (WHERE last_changed = v_now)::int,
           count(*) FILTER (WHERE status = 'deleted')::int,
           count(*) FILTER (WHERE status = 'out_of_scope')::int
      FROM deployment.object_state;
END;
$function$
;

