CREATE OR REPLACE FUNCTION whatsfresh.f_user_name(in_id integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    SELECT concat(first_name,' ', last_name)  
   FROM whatsfresh.users WHERE id = in_id;
$function$
;

