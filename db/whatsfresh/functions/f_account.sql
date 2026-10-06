CREATE OR REPLACE FUNCTION whatsfresh.f_account(in_id integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    SELECT name FROM whatsfresh.accounts WHERE id = in_id;
$function$
;

