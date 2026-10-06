CREATE OR REPLACE FUNCTION whatsfresh.f_best_by_days(in_id integer)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
    SELECT best_by_days FROM whatsfresh.entities WHERE id = in_id AND entity_kind = 'Prod';
$function$
;

