CREATE OR REPLACE FUNCTION whatsfresh.api_context_store(p_email text DEFAULT NULL::text)
 RETURNS TABLE(context jsonb)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT jsonb_object_agg(param_name, param_val)
  FROM whatsfresh.context_store
  WHERE email = p_email;
$function$
;

