CREATE OR REPLACE FUNCTION studio.tf_n8n_workflow_detail(p_name character varying)
 RETURNS TABLE(id character varying, name character varying, nodes json, connections json, settings json, updated_at timestamp with time zone)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT
        w.id,
        w.name::varchar,
        w.nodes,
        w.connections,
        w.settings,
        w."updatedAt" AS updated_at
    FROM public.workflow_entity w
    WHERE w.name = p_name
      AND w.active = true
      AND w."isArchived" = false
    LIMIT 1;
$function$
;

