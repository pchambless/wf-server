CREATE OR REPLACE FUNCTION deployment.f_impact_status(p_change_type text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE p_change_type WHEN 'added' THEN 'A' WHEN 'modified' THEN 'M' WHEN 'deleted' THEN 'D' END
$function$
;

