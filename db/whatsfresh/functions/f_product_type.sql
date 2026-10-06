CREATE OR REPLACE FUNCTION whatsfresh.f_product_type(in_id integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    SELECT et.name::text
	FROM whatsfresh.entity_types et
	JOIN whatsfresh.entities e
	ON et.id = e.entity_type_id AND et.entity_kind = e.entity_kind
	WHERE e.id::int = in_id::int AND e.entity_kind = 'Prod';
$function$
;

