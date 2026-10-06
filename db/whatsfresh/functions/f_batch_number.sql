CREATE OR REPLACE FUNCTION whatsfresh.f_batch_number(in_id integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    SELECT batch_number FROM whatsfresh.batches WHERE id = in_id;
$function$
;

