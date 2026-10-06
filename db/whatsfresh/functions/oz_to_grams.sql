CREATE OR REPLACE FUNCTION whatsfresh.oz_to_grams(p_oz integer)
 RETURNS numeric
 LANGUAGE sql
AS $function$
    SELECT ROUND((p_oz * 28.3495)::numeric, 3);
$function$
;

