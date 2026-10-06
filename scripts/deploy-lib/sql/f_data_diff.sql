CREATE OR REPLACE FUNCTION deployment.f_data_diff(p_environment text, p_schema text, p_table text)
 RETURNS TABLE(diff_type text, pk_value text)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_env deployment.environments%ROWTYPE;
    v_conn text := 'diff_conn_' || p_environment;
    v_pk_col text;
    v_cols text;
    v_remote_sql text;
    -- Audit metadata. Excluded from the comparison because it records WHEN a
    -- row was written, not WHAT it says. deleted_* is not in this list on purpose.
    v_skip_cols text[] := ARRAY['created_at','updated_at','created_by','updated_by'];
BEGIN
    SELECT * INTO v_env FROM deployment.environments WHERE name = p_environment;
    IF v_env.dblink_server IS NULL THEN
        RAISE EXCEPTION 'f_data_diff: environment % has no dblink_server configured', p_environment;
    END IF;

    SELECT a.attname INTO v_pk_col
    FROM pg_index i
    JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
    JOIN pg_class c ON c.oid = i.indrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = p_schema AND c.relname = p_table AND i.indisprimary
    LIMIT 1;

    IF v_pk_col IS NULL THEN
        -- Skip rather than raise: one table missing a PK should not blow up
        -- a caller like f_predeploy_check that batches many tables together.
        RETURN QUERY SELECT 'skipped: no primary key'::text, NULL::text;
        RETURN;
    END IF;

    -- Build the comparison column list from the LOCAL (dev) catalog and use the
    -- same list on both sides, so the two hashes are computed over the same
    -- columns in the same order regardless of physical column order.
    SELECT string_agg(quote_ident(a.attname), ', ' ORDER BY a.attnum)
      INTO v_cols
      FROM pg_attribute a
      JOIN pg_class c ON c.oid = a.attrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = p_schema
       AND c.relname = p_table
       AND a.attnum > 0
       AND NOT a.attisdropped
       AND a.attname <> ALL (v_skip_cols);

    IF v_cols IS NULL THEN
        RETURN QUERY SELECT 'skipped: no comparable columns'::text, NULL::text;
        RETURN;
    END IF;

    BEGIN
        PERFORM dblink_disconnect(v_conn);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    PERFORM dblink_connect(v_conn, v_env.dblink_server);
    PERFORM dblink_exec(v_conn, 'SET timezone = ''UTC''');

    -- Pin the local session to UTC too, scoped to this transaction only
    -- (set_config's third arg = true), so any remaining timestamptz column
    -- (deleted_at) renders identically on both sides before hashing.
    PERFORM set_config('timezone', 'UTC', true);

    v_remote_sql := format('SELECT %I::text, md5(ROW(%s)::text) FROM %I.%I',
                           v_pk_col, v_cols, p_schema, p_table);

    BEGIN
        RETURN QUERY EXECUTE format($q$
            WITH dev_rows AS (
                SELECT %1$I::text AS pk, md5(ROW(%6$s)::text) AS row_hash FROM %2$I.%3$I
            ),
            target_rows AS (
                SELECT * FROM dblink(%4$L, %5$L) AS r(pk text, row_hash text)
            )
            SELECT
                CASE WHEN d.pk IS NULL THEN 'missing on dev'
                     WHEN t.pk IS NULL THEN 'missing on target'
                     ELSE 'content differs' END,
                COALESCE(d.pk, t.pk)
            FROM dev_rows d FULL OUTER JOIN target_rows t ON t.pk = d.pk
            WHERE d.pk IS NULL OR t.pk IS NULL OR d.row_hash IS DISTINCT FROM t.row_hash
            ORDER BY 2
        $q$, v_pk_col, p_schema, p_table, v_conn, v_remote_sql, v_cols);
    EXCEPTION WHEN OTHERS THEN
        -- Report and keep going. The gate batches many tables; one unreadable
        -- target table must not take the whole check down.
        RETURN QUERY SELECT ('error: ' || SQLERRM)::text, NULL::text;
    END;

    BEGIN
        PERFORM dblink_disconnect(v_conn);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
END
$function$
;

