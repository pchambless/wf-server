CREATE OR REPLACE FUNCTION whatsfresh.f_ingredient(in_id integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    SELECT name FROM whatsfresh.entities WHERE id = in_id AND entity_kind = 'Shop';
$function$
;

