CREATE OR REPLACE FUNCTION deployment.f_capture_env_fingerprints(p_environment text, p_schemas text[] DEFAULT ARRAY['studio'::text, 'whatsfresh'::text])
 RETURNS TABLE(out_env text, captured integer)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_env   deployment.environments%ROWTYPE;
    v_now   timestamptz := clock_timestamp();
    v_skip  text[];
    v_rows  text[];
    v_skip_lit text;
    v_rows_lit text;
    v_sch_lit  text;
    v_remote   text;
    v_n     integer;
BEGIN
    SELECT * INTO v_env FROM deployment.environments WHERE name = p_environment;
    IF v_env.dblink_server IS NULL THEN
        RAISE EXCEPTION 'f_capture_env_fingerprints: environment % has no dblink_server configured', p_environment;
    END IF;

    -- Resolve scope from dev's policy (the remote has no deployment schema).
    SELECT array_agg(schema_path)
      INTO v_skip
      FROM deployment.object_policy
     WHERE structure = 'skip' AND split_part(schema_path,'.',1) = ANY(p_schemas);

    SELECT array_agg(schema_path)
      INTO v_rows
      FROM deployment.object_policy
     WHERE diff_data = 'compare' AND object_type = 'table'
       AND split_part(schema_path,'.',1) = ANY(p_schemas);

    v_skip := COALESCE(v_skip, ARRAY[]::text[]);
    v_rows := COALESCE(v_rows, ARRAY[]::text[]);

    -- Build the remote call. quote_literal on each array rendered as a PG array literal.
    v_sch_lit  := quote_literal(p_schemas::text);
    v_skip_lit := quote_literal(v_skip::text);
    v_rows_lit := quote_literal(v_rows::text);

    v_remote := format(
        'SELECT * FROM operations.f_fingerprints(%s::text[], %s::text[], %s::text[])',
        v_sch_lit, v_skip_lit, v_rows_lit);

    INSERT INTO deployment.env_fingerprints
        (env, kind, schema_name, object_name, component_name, fingerprint, captured_at)
    SELECT p_environment, t.kind, t.schema_name, t.object_name,
           COALESCE(t.component_name,''), t.fingerprint, v_now
      FROM dblink(v_env.dblink_server, v_remote)
        AS t(kind text, schema_name text, object_name text, component_name text, fingerprint text)
    ON CONFLICT (env, kind, schema_name, object_name, component_name)
    DO UPDATE SET fingerprint = EXCLUDED.fingerprint, captured_at = EXCLUDED.captured_at;

    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN QUERY SELECT p_environment, v_n;
END;
$function$
;

