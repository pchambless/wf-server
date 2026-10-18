CREATE OR REPLACE FUNCTION deployment.f_row_upsert_sql(p_schema text, p_table text, p_pk_col text, p_pk_val text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_row  jsonb;
  v_cols text;
  v_vals text;
  v_set  text;
BEGIN
  EXECUTE format('SELECT to_jsonb(t) FROM %I.%I t WHERE %I::text = $1', p_schema, p_table, p_pk_col)
     INTO v_row USING p_pk_val;
  IF v_row IS NULL THEN
    RAISE EXCEPTION 'f_row_upsert_sql: no row %.% where % = %', p_schema, p_table, p_pk_col, p_pk_val;
  END IF;

  SELECT string_agg(quote_ident(a.attname), ', ' ORDER BY a.attnum),
         string_agg(CASE WHEN a.atttypid IN ('json'::regtype, 'jsonb'::regtype) THEN
                           CASE WHEN (v_row -> a.attname) = 'null'::jsonb THEN 'NULL'
                                ELSE quote_nullable((v_row -> a.attname)::text) || '::' || format_type(a.atttypid, a.atttypmod) END
                         WHEN (v_row ->> a.attname) IS NULL THEN 'NULL'
                         ELSE quote_nullable(v_row ->> a.attname) || '::' || format_type(a.atttypid, a.atttypmod)
                    END, ', ' ORDER BY a.attnum),
         string_agg(CASE WHEN a.attname <> p_pk_col AND a.attidentity <> 'a' THEN format('%I = EXCLUDED.%I', a.attname, a.attname) END, ', ' ORDER BY a.attnum)
    INTO v_cols, v_vals, v_set
    FROM pg_attribute a
   WHERE a.attrelid = format('%I.%I', p_schema, p_table)::regclass AND a.attnum > 0 AND NOT a.attisdropped AND a.attgenerated = '';

  -- OVERRIDING SYSTEM VALUE: explicit ids must survive on GENERATED ALWAYS identity columns.
  RETURN format('INSERT INTO %I.%I (%s) OVERRIDING SYSTEM VALUE VALUES (%s) ON CONFLICT (%I) DO %s',
                p_schema, p_table, v_cols, v_vals, p_pk_col,
                CASE WHEN v_set IS NULL THEN 'NOTHING' ELSE 'UPDATE SET ' || v_set END);
END
$function$
;

