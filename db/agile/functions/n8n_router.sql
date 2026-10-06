CREATE OR REPLACE FUNCTION agile.n8n_router(p_template_name text DEFAULT '*'::text)
 RETURNS TABLE(id integer, template_name text, workflow text, title text, group_by text, hydrate text, html text, css text, has_css boolean, has_hydrate boolean, has_html boolean, description text, updated_at date, created_at date)
 LANGUAGE sql
AS $function$
SELECT 
  ht.id,
  ht.name,
  CASE
    WHEN ht.n8n = 'report' THEN 'agile-report'
    WHEN ht.n8n = 'json' then 'agile-json'
  END AS workflow,
  ht.title,
  ht.group_by,
  ht.hydrate,
  ht.html,
  ht.css,
  ht.css <> '{}' AND ht.css IS NOT NULL AS has_css,
  ht.hydrate IS NOT NULL AND ht.hydrate <> '' AS has_hydrate,
  ht.html IS NOT NULL AND ht.html <> '' AS has_html,
  ht.description,
  ht.updated_at::date,
  ht.created_at::date
FROM support.html_templates ht
WHERE (ht.name = p_template_name OR p_template_name = '*' OR p_template_name IS NULL);
$function$
;

