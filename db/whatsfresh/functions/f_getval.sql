CREATE OR REPLACE FUNCTION whatsfresh.f_getval(p_param_name text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    SELECT context->>p_param_name
  	FROM whatsfresh.api_context_store();
$function$
;

