CREATE OR REPLACE FUNCTION deployment.f_sequence_drift(p_environment text DEFAULT 'prod'::text, p_schemas text[] DEFAULT ARRAY['studio'::text, 'whatsfresh'::text])
 RETURNS TABLE(environment text, tbl text, col text, seq text, last_value bigint, max_id bigint)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    v_found  boolean;
    v_server text;
    v_probe  text;
    v_outer  text;
BEGIN
    SELECT true, e.dblink_server
      INTO v_found, v_server
      FROM deployment.environments e
     WHERE e.name = p_environment;

    IF NOT COALESCE(v_found, false) THEN
        RAISE EXCEPTION 'f_sequence_drift: unknown environment %, expected one of %',
            p_environment,
            (SELECT string_agg(e.name, ', ' ORDER BY e.ordr) FROM deployment.environments e);
    END IF;

    -- Catalog probe, run against whichever side we are inspecting.
    -- deptype 'a' = serial, 'i' = GENERATED AS IDENTITY. Both must be covered.
    -- The owning column comes from refobjsubid rather than a hardcoded 'id'.
    -- query_to_xml is what lets one static query read max(<col>) per table.
    -- Every column is cast explicitly here (attname/relname are `name`, not text)
    -- so the local and dblink paths below return identical types.
    v_probe := format($q$
        SELECT (tn.nspname || '.' || t.relname)::text,
               a.attname::text,
               s.relname::text,
               pg_sequence_last_value(s.oid)::bigint,
               (xpath('/row/m/text()',
                      query_to_xml(format('select max(%%I) as m from %%I.%%I',
                                          a.attname, tn.nspname, t.relname),
                                   false, true, '')))[1]::text::bigint
          FROM pg_class s
          JOIN pg_depend d   ON d.objid = s.oid
                            AND d.classid = 'pg_class'::regclass
                            AND d.deptype IN ('a','i')
          JOIN pg_class t    ON t.oid = d.refobjid
          JOIN pg_namespace tn ON tn.oid = t.relnamespace
          JOIN pg_attribute a  ON a.attrelid = t.oid AND a.attnum = d.refobjsubid
         WHERE s.relkind = 'S' AND tn.nspname = ANY(%L)
    $q$, p_schemas);

    -- A sequence that has never been called reports last_value NULL, which is
    -- drift whenever the table already holds rows - so COALESCE, don't compare
    -- NULL. Empty tables (max_id NULL) are not drift.
    -- Note the two alias forms are NOT interchangeable: a column alias list may
    -- carry types only for a function call such as dblink(). On a plain
    -- subquery it is a syntax error, so the local path takes bare names and
    -- relies on the casts in the probe above.
    IF v_server IS NULL THEN
        v_outer := format(
            'SELECT %L::text, x.* FROM (%s) AS x(tbl, col, seq, last_value, max_id)',
            p_environment, v_probe);
    ELSE
        v_outer := format(
            'SELECT %L::text, x.* FROM dblink(%L, %L) AS x(tbl text, col text, seq text, last_value bigint, max_id bigint)',
            p_environment, v_server, v_probe);
    END IF;

    RETURN QUERY EXECUTE v_outer || ' WHERE x.max_id IS NOT NULL AND COALESCE(x.last_value, 0) < x.max_id';
END
$function$
;

