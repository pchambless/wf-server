CREATE OR REPLACE FUNCTION whatsfresh.f_user_email(in_id integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    SELECT email FROM whatsfresh.users WHERE id = in_id;
$function$
;

