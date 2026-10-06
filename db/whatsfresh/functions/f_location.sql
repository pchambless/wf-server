CREATE OR REPLACE FUNCTION whatsfresh.f_location(in_id integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    SELECT name FROM whatsfresh.locations WHERE id = in_id;
$function$
;

