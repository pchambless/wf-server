-- GENERATED from scripts/deploy-lib/sql/f_n8n_diff.sql and f_structure_diff.sql (shadow phase).
-- Identical to the live functions except the knowledge_base.objects lookups:
--   f_n8n_diff_map:       manifest = n8n rows of deployment.vw_manifest_map (live map minus policy skips)
--   f_structure_diff_map: obsolete check = deployment.object_policy structure = skip
-- Both reach the target environment over dblink (read-only), like the originals.

CREATE OR REPLACE FUNCTION deployment.f_n8n_diff_map(p_environment text)
 RETURNS TABLE(workflow_name text, dev_content_hash text, target_content_hash text, needs_deploy boolean, detail text)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_env  deployment.environments%ROWTYPE;
    v_conn text := 'n8ndiffmap_conn_' || p_environment;
BEGIN
    SELECT * INTO v_env FROM deployment.environments WHERE name = p_environment;
    IF v_env.dblink_server IS NULL THEN
        RAISE EXCEPTION 'f_n8n_diff: environment % has no dblink_server configured', p_environment;
    END IF;

    BEGIN
        PERFORM dblink_disconnect(v_conn);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    PERFORM dblink_connect(v_conn, v_env.dblink_server);

    RETURN QUERY
    WITH manifest AS (
        SELECT m.name AS wf_name FROM deployment.vw_manifest_map m WHERE m.platform = 'n8n'
    ),
    dev_wf AS (
        -- active=true only: dev has dead workflows sharing a name with a live one.
        -- Content comes from workflow_history at activeVersionId, not
        -- workflow_entity.nodes directly - that column reflects the current DRAFT,
        -- which can differ from what is actually published and live (proven
        -- 2026-08-15: server-query had an unpublished autosave draft diverged
        -- from its activeVersionId content at the time this was built).
        -- credentials stripped per-node before hashing: import-n8n-workflows.sh
        -- deliberately remaps the credential id from dev's to prod's on every
        -- deploy, so that field can never match between environments even for
        -- byte-identical logic - hashing it raw made every DB-touching workflow
        -- read as permanently out of sync. jsonb round-trip (not raw ::text)
        -- also canonicalizes key order/whitespace so those don't cause false
        -- diffs either. Nodes sorted by id since array order isn't guaranteed
        -- to survive an n8n import.
        SELECT w.name::text AS wf_name,
               md5(
                 (SELECT jsonb_agg(elem - 'credentials' ORDER BY elem->>'id')
                    FROM jsonb_array_elements(h.nodes::jsonb) elem)::text
                 || h.connections::jsonb::text
               ) AS content_hash
          FROM public.workflow_entity w
          JOIN manifest m ON m.wf_name = w.name
          JOIN public.workflow_history h ON h."versionId" = w."activeVersionId"
         WHERE w.active = true
    ),
    target_wf AS (
        SELECT * FROM dblink(v_conn,
          'SELECT w.name::text,
                  md5(
                    (SELECT jsonb_agg(elem - ''credentials'' ORDER BY elem->>''id'')
                       FROM jsonb_array_elements(h.nodes::jsonb) elem)::text
                    || h.connections::jsonb::text
                  )
             FROM public.workflow_entity w
             JOIN public.workflow_history h ON h."versionId" = w."activeVersionId"
            WHERE w.active = true') AS t(wf_name text, content_hash text)
         WHERE wf_name IN (SELECT wf_name FROM manifest)
    )
    SELECT m.wf_name,
           d.content_hash,
           t.content_hash,
           CASE WHEN t.wf_name IS NULL THEN true
                WHEN d.content_hash IS DISTINCT FROM t.content_hash THEN true
                ELSE false END,
           CASE WHEN t.wf_name IS NULL THEN 'missing on target'
                WHEN d.content_hash IS DISTINCT FROM t.content_hash THEN 'content differs - needs redeploy'
                ELSE 'in sync' END
    FROM manifest m
    LEFT JOIN dev_wf d ON d.wf_name = m.wf_name
    LEFT JOIN target_wf t ON t.wf_name = m.wf_name
    ORDER BY 4 DESC, m.wf_name;

    PERFORM dblink_disconnect(v_conn);
END;
$function$
;

CREATE OR REPLACE FUNCTION deployment.f_structure_diff_map(p_environment text, p_schema text)
 RETURNS TABLE(category text, object_name text, detail text, dev_value text, target_value text)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_env deployment.environments%ROWTYPE;
    v_conn text := 'diffmap_conn_' || p_environment;
BEGIN
    SELECT * INTO v_env FROM deployment.environments WHERE name = p_environment;
    IF v_env.dblink_server IS NULL THEN
        RAISE EXCEPTION 'f_structure_diff: environment % has no dblink_server configured', p_environment;
    END IF;

    BEGIN
        PERFORM dblink_disconnect(v_conn);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    PERFORM dblink_connect(v_conn, v_env.dblink_server);

    -- TABLES
    RETURN QUERY
    WITH dev_tables AS (
        SELECT c.relname::text AS name
        FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname=p_schema AND c.relkind='r'
    ),
    target_tables AS (
        SELECT * FROM dblink(v_conn, format(
          'SELECT c.relname::text FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname=%L AND c.relkind=''r''', p_schema
        )) AS t(name text)
    )
    SELECT 'table'::text, COALESCE(d.name, t.name),
           CASE WHEN d.name IS NULL THEN 'missing on dev' WHEN t.name IS NULL THEN 'missing on target' END,
           CASE WHEN d.name IS NOT NULL THEN 'exists' END,
           CASE WHEN t.name IS NOT NULL THEN 'exists' END
    FROM dev_tables d FULL OUTER JOIN target_tables t ON t.name=d.name
    WHERE (d.name IS NULL OR t.name IS NULL)
      AND NOT EXISTS (SELECT 1 FROM deployment.object_policy ko WHERE ko.schema_path = p_schema || '.' || COALESCE(d.name, t.name) AND ko.structure = 'skip');

    -- VIEWS
    RETURN QUERY
    WITH dev_views AS (
        SELECT c.relname::text AS name
        FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname=p_schema AND c.relkind='v'
    ),
    target_views AS (
        SELECT * FROM dblink(v_conn, format(
          'SELECT c.relname::text FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname=%L AND c.relkind=''v''', p_schema
        )) AS t(name text)
    )
    SELECT 'view'::text, COALESCE(d.name, t.name),
           CASE WHEN d.name IS NULL THEN 'missing on dev' WHEN t.name IS NULL THEN 'missing on target' END,
           CASE WHEN d.name IS NOT NULL THEN 'exists' END,
           CASE WHEN t.name IS NOT NULL THEN 'exists' END
    FROM dev_views d FULL OUTER JOIN target_views t ON t.name=d.name
    WHERE (d.name IS NULL OR t.name IS NULL)
      AND NOT EXISTS (SELECT 1 FROM deployment.object_policy ko WHERE ko.schema_path = p_schema || '.' || COALESCE(d.name, t.name) AND ko.structure = 'skip');

    -- COLUMNS (tables present in both, column existence + type)
    RETURN QUERY
    WITH dev_cols AS (
        SELECT c.relname::text AS tbl, a.attname::text AS col, format_type(a.atttypid, a.atttypmod) AS typ
        FROM pg_attribute a
        JOIN pg_class c ON c.oid=a.attrelid
        JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname=p_schema AND c.relkind='r' AND a.attnum > 0 AND NOT a.attisdropped
    ),
    target_cols AS (
        SELECT * FROM dblink(v_conn, format(
          'SELECT c.relname::text, a.attname::text, format_type(a.atttypid, a.atttypmod) FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname=%L AND c.relkind=''r'' AND a.attnum > 0 AND NOT a.attisdropped', p_schema
        )) AS t(tbl text, col text, typ text)
    )
    SELECT 'column'::text, COALESCE(d.tbl,t.tbl) || '.' || COALESCE(d.col, t.col),
           CASE WHEN d.col IS NULL THEN 'missing on dev'
                WHEN t.col IS NULL THEN 'missing on target'
                WHEN d.typ != t.typ THEN 'type mismatch' END,
           d.typ, t.typ
    FROM dev_cols d FULL OUTER JOIN target_cols t ON t.tbl=d.tbl AND t.col=d.col
    WHERE (d.col IS NULL OR t.col IS NULL OR d.typ != t.typ)
      AND NOT EXISTS (SELECT 1 FROM deployment.object_policy ko WHERE ko.schema_path = p_schema || '.' || COALESCE(d.tbl, t.tbl) AND ko.structure = 'skip');

    -- CONSTRAINTS (by name + type, not DDL text - avoids PG-version cosmetic rendering differences)
    RETURN QUERY
    WITH dev_cons AS (
        SELECT con.conname::text AS name, con.contype::text AS typ, cl.relname::text AS tbl
        FROM pg_constraint con
        JOIN pg_class cl ON cl.oid = con.conrelid
        JOIN pg_namespace n ON n.oid = cl.relnamespace
        WHERE n.nspname = p_schema
    ),
    target_cons AS (
        SELECT * FROM dblink(v_conn, format(
          'SELECT con.conname::text, con.contype::text, cl.relname::text FROM pg_constraint con JOIN pg_class cl ON cl.oid=con.conrelid JOIN pg_namespace n ON n.oid=cl.relnamespace WHERE n.nspname=%L', p_schema
        )) AS t(name text, typ text, tbl text)
    )
    SELECT 'constraint'::text, COALESCE(d.tbl,t.tbl) || '.' || COALESCE(d.name, t.name),
           CASE WHEN d.name IS NULL THEN 'missing on dev' WHEN t.name IS NULL THEN 'missing on target' END,
           d.typ, t.typ
    FROM dev_cons d FULL OUTER JOIN target_cons t ON t.name=d.name AND t.tbl=d.tbl
    WHERE (d.name IS NULL OR t.name IS NULL)
      AND NOT EXISTS (SELECT 1 FROM deployment.object_policy ko WHERE ko.schema_path = p_schema || '.' || COALESCE(d.tbl, t.tbl) AND ko.structure = 'skip');

    -- FUNCTIONS/PROCEDURES (existence + literal body text diff - prosrc is stored verbatim, not reconstructed,
    -- so unlike constraints/views this comparison is reliable across PG versions)
    RETURN QUERY
    WITH dev_fns AS (
        SELECT p.proname::text AS name, pg_get_function_identity_arguments(p.oid) AS args, p.prosrc AS src
        FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname=p_schema
    ),
    target_fns AS (
        SELECT * FROM dblink(v_conn, format(
          'SELECT p.proname::text, pg_get_function_identity_arguments(p.oid), p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname=%L', p_schema
        )) AS t(name text, args text, src text)
    )
    SELECT 'function'::text, d.name || '(' || COALESCE(d.args,t.args) || ')',
           CASE WHEN d.name IS NULL THEN 'missing on dev'
                WHEN t.name IS NULL THEN 'missing on target'
                WHEN d.src != t.src THEN 'body differs' END,
           left(d.src, 80), left(t.src, 80)
    FROM dev_fns d FULL OUTER JOIN target_fns t ON t.name=d.name AND t.args=d.args
    WHERE (d.name IS NULL OR t.name IS NULL OR d.src != t.src)
      AND NOT EXISTS (SELECT 1 FROM deployment.object_policy ko WHERE ko.schema_path = p_schema || '.' || COALESCE(d.name, t.name) AND ko.structure = 'skip');

    -- INDEXES (by table + name; constraint-backed indexes are covered by CONSTRAINTS above, and
    -- the definition text is not compared for the same PG-version reason). f_table_ddl replays
    -- these on the structure leg, so a row here ships.
    RETURN QUERY
    WITH dev_idx AS (
        SELECT ic.relname::text AS name, tc.relname::text AS tbl
        FROM pg_index i
        JOIN pg_class ic ON ic.oid = i.indexrelid
        JOIN pg_class tc ON tc.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = tc.relnamespace
        WHERE n.nspname = p_schema AND tc.relkind = 'r'
          AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conindid = i.indexrelid)
    ),
    target_idx AS (
        SELECT * FROM dblink(v_conn, format(
          'SELECT ic.relname::text, tc.relname::text FROM pg_index i JOIN pg_class ic ON ic.oid=i.indexrelid JOIN pg_class tc ON tc.oid=i.indrelid JOIN pg_namespace n ON n.oid=tc.relnamespace WHERE n.nspname=%L AND tc.relkind=''r'' AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conindid=i.indexrelid)', p_schema
        )) AS t(name text, tbl text)
    )
    SELECT 'index'::text, COALESCE(d.tbl,t.tbl) || '.' || COALESCE(d.name, t.name),
           CASE WHEN d.name IS NULL THEN 'missing on dev' WHEN t.name IS NULL THEN 'missing on target' END,
           CASE WHEN d.name IS NOT NULL THEN 'exists' END,
           CASE WHEN t.name IS NOT NULL THEN 'exists' END
    FROM dev_idx d FULL OUTER JOIN target_idx t ON t.name = d.name AND t.tbl = d.tbl
    WHERE (d.name IS NULL OR t.name IS NULL)
      AND NOT EXISTS (SELECT 1 FROM deployment.object_policy ko WHERE ko.schema_path = p_schema || '.' || COALESCE(d.tbl, t.tbl) AND ko.structure = 'skip');

    -- TRIGGERS (by table + name). Triggers whose function lives in the deployment schema are dev-only
    -- tooling (that schema is not on prod) and are ignored here and by f_trigger_ddl.
    RETURN QUERY
    WITH dev_trg AS (
        SELECT tg.tgname::text AS name, tc.relname::text AS tbl
        FROM pg_trigger tg
        JOIN pg_class tc ON tc.oid = tg.tgrelid
        JOIN pg_namespace n ON n.oid = tc.relnamespace
        JOIN pg_proc fp ON fp.oid = tg.tgfoid
        JOIN pg_namespace fn ON fn.oid = fp.pronamespace
        WHERE n.nspname = p_schema AND NOT tg.tgisinternal AND fn.nspname <> 'deployment'
    ),
    target_trg AS (
        SELECT * FROM dblink(v_conn, format(
          'SELECT tg.tgname::text, tc.relname::text FROM pg_trigger tg JOIN pg_class tc ON tc.oid=tg.tgrelid JOIN pg_namespace n ON n.oid=tc.relnamespace JOIN pg_proc fp ON fp.oid=tg.tgfoid JOIN pg_namespace fn ON fn.oid=fp.pronamespace WHERE n.nspname=%L AND NOT tg.tgisinternal AND fn.nspname <> ''deployment''', p_schema
        )) AS t(name text, tbl text)
    )
    SELECT 'trigger'::text, COALESCE(d.tbl,t.tbl) || '.' || COALESCE(d.name, t.name),
           CASE WHEN d.name IS NULL THEN 'missing on dev' WHEN t.name IS NULL THEN 'missing on target' END,
           CASE WHEN d.name IS NOT NULL THEN 'exists' END,
           CASE WHEN t.name IS NOT NULL THEN 'exists' END
    FROM dev_trg d FULL OUTER JOIN target_trg t ON t.name = d.name AND t.tbl = d.tbl
    WHERE (d.name IS NULL OR t.name IS NULL)
      AND NOT EXISTS (SELECT 1 FROM deployment.object_policy ko WHERE ko.schema_path = p_schema || '.' || COALESCE(d.tbl, t.tbl) AND ko.structure = 'skip');

    PERFORM dblink_disconnect(v_conn);
END;
$function$
;
