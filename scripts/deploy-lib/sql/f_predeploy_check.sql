CREATE OR REPLACE FUNCTION deployment.f_predeploy_check(p_environment text DEFAULT 'prod'::text)
 RETURNS TABLE(schema_name text, category text, object_name text, detail text)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_obj record;
BEGIN
    -- 1. whatsfresh structure. Catalog/manifest driven, not policy driven - see the
    -- note on diff_structure about why structure defaults to being checked.
    RETURN QUERY
    SELECT 'whatsfresh'::text, d.category, d.object_name, d.detail
    FROM deployment.f_structure_diff(p_environment, 'whatsfresh') d;

    -- 2. studio structure
    RETURN QUERY
    SELECT 'studio'::text, d.category, d.object_name, d.detail
    FROM deployment.f_structure_diff(p_environment, 'studio') d;

    -- 3. data, for every table explicitly marked diff_data='compare'.
    FOR v_obj IN
        SELECT split_part(schema_path, '.', 1) AS sch,
               split_part(schema_path, '.', 2) AS obj
        FROM deployment.object_policy
        WHERE diff_data = 'compare' AND object_type = 'table'
        ORDER BY schema_path
    LOOP
        RETURN QUERY
        SELECT v_obj.sch::text,
               ('data: ' || v_obj.obj)::text,
               d.pk_value,
               d.diff_type
        FROM deployment.f_data_diff(p_environment, v_obj.sch, v_obj.obj) d;
    END LOOP;
END;
$function$
;

