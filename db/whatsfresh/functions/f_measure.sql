CREATE OR REPLACE FUNCTION whatsfresh.f_measure(in_id integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
		select name
        from   whatsfresh.measures
        where id = in_id;
$function$
;

