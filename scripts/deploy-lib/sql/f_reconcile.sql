CREATE OR REPLACE FUNCTION deployment.f_reconcile(p_by text DEFAULT 'claude'::text)
 RETURNS TABLE(rebaselined integer, purged integer, valued integer)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_tbl    record;
    v_base   int;
    v_purged int;
    v_valued int := 0;
    v_n      int;
BEGIN
    -- Scan first so the baseline is advanced to CURRENT reality, not to whatever
    -- the last scan happened to see.
    PERFORM deployment.f_scan();

    -- Capture the actual row content, not just its hash, for watched rows.
    -- This is the only prior-generation record studio config will ever have: unlike
    -- repo files, these rows are not in git, so once a row is overwritten and the
    -- baseline moves the previous content exists nowhere else. ~170 kB for all of it,
    -- and it is what makes a real from/to diff derivable later.
    FOR v_tbl IN
        SELECT split_part(op.schema_path,'.',1) AS sch, split_part(op.schema_path,'.',2) AS tbl
          FROM deployment.object_policy op
         WHERE op.diff_data = 'compare' AND op.object_type = 'table'
         ORDER BY op.schema_path
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                        WHERE n.nspname = v_tbl.sch AND c.relname = v_tbl.tbl AND c.relkind = 'r') THEN
            CONTINUE;
        END IF;

        EXECUTE format(
            'UPDATE deployment.object_state s
                SET baseline_value = to_jsonb(t)
               FROM %I.%I t
              WHERE s.kind = ''row'' AND s.status = ''live''
                AND s.schema_name = %L AND s.object_name = %L
                AND s.component_name = t.id::text',
            v_tbl.sch, v_tbl.tbl, v_tbl.sch, v_tbl.tbl);
        GET DIAGNOSTICS v_n = ROW_COUNT;
        v_valued := v_valued + v_n;
    END LOOP;

    -- Advance the baseline for everything we are actually watching. out_of_scope rows
    -- are deliberately left alone: we stopped watching them, so their old baseline
    -- stays valid and drift resumes correctly if they are ever re-scoped.
    UPDATE deployment.object_state
       SET baseline_fingerprint = fingerprint
     WHERE status = 'live';
    GET DIAGNOSTICS v_base = ROW_COUNT;

    -- A deleted object has now been accounted for. Drop it so object_state means
    -- exactly "what exists", and the deletion lives on in agile_impacts where it
    -- can actually be queried.
    DELETE FROM deployment.object_state WHERE status = 'deleted';
    GET DIAGNOSTICS v_purged = ROW_COUNT;

    RETURN QUERY SELECT v_base, v_purged, v_valued;
END;
$function$
;

