CREATE OR REPLACE FUNCTION whatsfresh.oz_to_lbs(p_oz integer)
 RETURNS numeric
 LANGUAGE sql
AS $function$
    SELECT ROUND((p_oz / 16.0)::numeric, 4);
$function$
;

