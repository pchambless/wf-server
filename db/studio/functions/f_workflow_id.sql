CREATE OR REPLACE FUNCTION studio.f_workflow_id(p_func_name text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT id 
  FROM studio.tf_n8n_workflow_detail(p_func_name)
  LIMIT 1;
$function$
;

