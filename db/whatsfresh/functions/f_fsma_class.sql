CREATE OR REPLACE FUNCTION whatsfresh.f_fsma_class(in_id integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    SELECT name FROM studio.fsma_classifications WHERE id = in_id;
$function$
;

