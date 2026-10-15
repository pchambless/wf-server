CREATE OR REPLACE FUNCTION deployment.f_impact_item_type(p_kind text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE p_kind WHEN 'table' THEN 'db_table' WHEN 'view' THEN 'db_view' WHEN 'function' THEN 'db_function'
                     WHEN 'row' THEN 'row' WHEN 'workflow' THEN 'n8n_workflow' WHEN 'node' THEN 'n8n_node' END
$function$
;

