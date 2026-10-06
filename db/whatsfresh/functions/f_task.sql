CREATE OR REPLACE FUNCTION whatsfresh.f_task(in_id integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    SELECT name FROM whatsfresh.tasks WHERE id = in_id;
$function$
;

