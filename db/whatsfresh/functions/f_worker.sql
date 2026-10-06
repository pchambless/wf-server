CREATE OR REPLACE FUNCTION whatsfresh.f_worker(in_id integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    SELECT name FROM whatsfresh.workers WHERE id = in_id;
$function$
;

