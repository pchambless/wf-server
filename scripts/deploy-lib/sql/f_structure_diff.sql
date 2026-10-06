CREATE OR REPLACE FUNCTION deployment.f_structure_diff(p_environment text, p_schema text)
 RETURNS TABLE(category text, object_name text, detail text, dev_value text, target_value text)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_env deployment.environments%ROWTYPE;
    v_conn text := 'diff_conn_' || p_environment;
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
      AND NOT EXISTS (SELECT 1 FROM knowledge_base.objects ko
                       WHERE ko.schema_path = p_schema || '.' || COALESCE(d.name, t.name) AND ko.status = 'obsolete');

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
      AND NOT EXISTS (SELECT 1 FROM knowledge_base.objects ko
                       WHERE ko.schema_path = p_schema || '.' || COALESCE(d.name, t.name) AND ko.status = 'obsolete');

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
      AND NOT EXISTS (SELECT 1 FROM knowledge_base.objects ko
                       WHERE ko.schema_path = p_schema || '.' || COALESCE(d.tbl, t.tbl) AND ko.status = 'obsolete');

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
      AND NOT EXISTS (SELECT 1 FROM knowledge_base.objects ko
                       WHERE ko.schema_path = p_schema || '.' || COALESCE(d.tbl, t.tbl) AND ko.status = 'obsolete');

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
      AND NOT EXISTS (SELECT 1 FROM knowledge_base.objects ko
                       WHERE ko.schema_path = p_schema || '.' || COALESCE(d.name, t.name) AND ko.status = 'obsolete');

    PERFORM dblink_disconnect(v_conn);
END;
$function$
;

