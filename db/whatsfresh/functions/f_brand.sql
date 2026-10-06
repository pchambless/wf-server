CREATE OR REPLACE FUNCTION whatsfresh.f_brand(in_id integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    SELECT name FROM whatsfresh.brands WHERE id = in_id;
$function$
;

