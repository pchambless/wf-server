CREATE OR REPLACE FUNCTION deployment.f_table_data_copy(p_conn text, p_schema text, p_table text, p_upsert boolean DEFAULT false)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_col_list   text;
    v_row        record;
    v_values     text;
    v_insert_sql text;
    v_count      bigint := 0;
    v_seq_row    record;
    v_new_val    bigint;
    v_pk_col     text;
    v_set_list   text;
    v_conflict   text := '';
    v_keys       text := '';
BEGIN
    SELECT string_agg(quote_ident(a.attname), ', ' ORDER BY a.attnum)
      INTO v_col_list
      FROM pg_attribute a
      JOIN pg_class c ON c.oid = a.attrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = p_schema AND c.relname = p_table AND a.attnum > 0 AND NOT a.attisdropped;

    IF v_col_list IS NULL THEN
        RAISE EXCEPTION 'f_table_data_copy: no such table %.%', p_schema, p_table;
    END IF;

    -- Upsert mode (task 467): used for refresh tables that a non-truncated table
    -- still references by FK, so TRUNCATE is impossible. Rows are matched on the
    -- single-column primary key; rows no longer in the source are deleted after the
    -- copy (an FK-referenced stale row then fails loudly, which is correct).
    IF p_upsert THEN
        SELECT a.attname INTO v_pk_col
          FROM pg_index i
          JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY (i.indkey)
         WHERE i.indrelid = format('%I.%I', p_schema, p_table)::regclass AND i.indisprimary;

        IF v_pk_col IS NULL OR (SELECT count(*) FROM pg_index i
                                 WHERE i.indrelid = format('%I.%I', p_schema, p_table)::regclass
                                   AND i.indisprimary AND i.indnkeyatts > 1) > 0 THEN
            RAISE EXCEPTION 'f_table_data_copy: upsert needs a single-column primary key on %.%', p_schema, p_table;
        END IF;

        SELECT string_agg(format('%I = EXCLUDED.%I', a.attname, a.attname), ', ' ORDER BY a.attnum)
          INTO v_set_list
          FROM pg_attribute a
         WHERE a.attrelid = format('%I.%I', p_schema, p_table)::regclass
           AND a.attnum > 0 AND NOT a.attisdropped AND a.attname <> v_pk_col;

        v_conflict := format(' ON CONFLICT (%I) DO %s', v_pk_col,
                             CASE WHEN v_set_list IS NULL THEN 'NOTHING' ELSE 'UPDATE SET ' || v_set_list END);
    END IF;

    -- Round-trip every value through text + an explicit cast, rather than trying
    -- to special-case each type. This is what makes it work uniformly for jsonb,
    -- timestamps, booleans, etc: Postgres's own text I/O is round-trip safe.
    FOR v_row IN EXECUTE format('SELECT * FROM %I.%I', p_schema, p_table)
    LOOP
        -- json/jsonb columns need their OWN text form (kv.value::text), which
        -- keeps a stored JSON string's quotes intact ("always" stays "always",
        -- not always). #>>'{}' unwraps those quotes, which is correct for
        -- reconstructing a plain scalar type but produces invalid JSON syntax
        -- when re-cast to json/jsonb (bare `always` isn't valid JSON).
        SELECT string_agg(
                 CASE WHEN a.atttypid IN ('json'::regtype, 'jsonb'::regtype) THEN
                        CASE WHEN kv.value = 'null'::jsonb THEN 'NULL'
                             ELSE quote_nullable(kv.value::text) || '::' || format_type(a.atttypid, a.atttypmod)
                        END
                      WHEN (kv.value #>> '{}') IS NULL THEN 'NULL'
                      ELSE quote_nullable(kv.value #>> '{}') || '::' || format_type(a.atttypid, a.atttypmod)
                 END,
                 ', ' ORDER BY a.attnum)
          INTO v_values
          FROM jsonb_each(to_jsonb(v_row)) kv
          JOIN pg_attribute a ON a.attname = kv.key
          JOIN pg_class c ON c.oid = a.attrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = p_schema AND c.relname = p_table AND a.attnum > 0 AND NOT a.attisdropped;

        -- OVERRIDING SYSTEM VALUE is required to insert explicit values into a
        -- GENERATED ALWAYS AS IDENTITY column (we need the original ids to
        -- survive, e.g. page_components.html_template_id must still match).
        -- It's a harmless no-op on any table without one.
        v_insert_sql := format('INSERT INTO %I.%I (%s) OVERRIDING SYSTEM VALUE VALUES (%s)%s', p_schema, p_table, v_col_list, v_values, v_conflict);
        PERFORM dblink_exec(p_conn, v_insert_sql);
        IF p_upsert THEN
            v_keys := v_keys || CASE WHEN v_keys = '' THEN '' ELSE ', ' END || quote_nullable(to_jsonb(v_row) ->> v_pk_col);
        END IF;
        v_count := v_count + 1;
    END LOOP;

    -- Upsert mode: drop target rows that no longer exist in the source.
    IF p_upsert THEN
        PERFORM dblink_exec(p_conn, CASE WHEN v_keys = ''
            THEN format('DELETE FROM %I.%I', p_schema, p_table)
            ELSE format('DELETE FROM %I.%I WHERE %I NOT IN (%s)', p_schema, p_table, v_pk_col, v_keys) END);
    END IF;

    -- Resync any owned sequence so a later INSERT on the target doesn't collide
    -- with the ids we just copied in explicitly. Covers both serial ('a') and
    -- identity-column ('i') sequences, and reads the actual owning column name
    -- (refobjsubid) instead of assuming it's called id.
    FOR v_seq_row IN
        SELECT sn.nspname AS seq_schema, s.relname AS seq_name, a.attname AS col_name
          FROM pg_depend d
          JOIN pg_class s ON s.oid = d.objid AND s.relkind = 'S'
          JOIN pg_namespace sn ON sn.oid = s.relnamespace
          JOIN pg_class t ON t.oid = d.refobjid
          JOIN pg_namespace tn ON tn.oid = t.relnamespace
          JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = d.refobjsubid
         WHERE tn.nspname = p_schema AND t.relname = p_table AND d.deptype IN ('a', 'i')
    LOOP
        -- setval() returns a value, so it must go through dblink() (row-returning),
        -- not dblink_exec (which rejects any statement that returns a result).
        SELECT v INTO v_new_val
          FROM dblink(p_conn, format(
                 'SELECT setval(%L, COALESCE((SELECT MAX(%I) FROM %I.%I), 1))',
                 v_seq_row.seq_schema || '.' || v_seq_row.seq_name, v_seq_row.col_name, p_schema, p_table)) AS t(v bigint);
    END LOOP;

    RETURN v_count;
END
$function$
;

