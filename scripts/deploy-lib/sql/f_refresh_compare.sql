CREATE OR REPLACE FUNCTION deployment.f_refresh_compare(p_environment text DEFAULT 'prod'::text, p_schemas text[] DEFAULT ARRAY['studio'::text, 'whatsfresh'::text])
 RETURNS TABLE(out_env text, scanned integer, changed integer, gone integer, descoped integer, captured integer)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT p_environment, s.scanned, s.changed, s.gone, s.descoped, c.captured
      FROM deployment.f_scan(p_schemas) s
      CROSS JOIN deployment.f_capture_env_fingerprints(p_environment, p_schemas) c;
END;
$function$
;

