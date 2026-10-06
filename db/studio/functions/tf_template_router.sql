CREATE OR REPLACE FUNCTION studio.tf_template_router(p_source text, p_template_name text DEFAULT '*'::text)
 RETURNS TABLE(id integer, template_name text, page_id integer, workflow text, platform text, title text, group_by text, hydrate text, html text, css text, has_css boolean, has_hydrate boolean, has_html boolean, description text, updated_at date, created_at date)
 LANGUAGE sql
AS $function$
SELECT 
  ht.id,
  ht.name,
  studio.f_template_page_id(ht.id), 
  CASE
    WHEN ht.platform = 'css_utility'  THEN 'n/a'
   	WHEN ht.name = 'api_page_structure' then 'page-structure'
    WHEN ht.name in ( 'api_page_actions', 'api_routes') then 'raw-json'
    WHEN ht.name in ( 'api_login') then 'login'
    WHEN ht.platform = 'report' THEN 'report'
    WHEN ht.hydrate = 'select null as data' AND p_source = 'wf-server' THEN 'styled-html'
    when   p_source <> 'wf-server' and ht.platform = 'api' then 'raw-json'
    WHEN ht.html IS NOT NULL 
		AND ht.css IS NOT NULL 
		AND ht.hydrate IS NOT NULL 
		AND p_source = 'wf-server' 
		THEN 'styled-html'
    ELSE 
		'raw-json'
  END AS workflow,
  ht.platform,
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
FROM studio.html_templates ht
WHERE (ht.name = p_template_name OR p_template_name = '*' OR p_template_name IS NULL);
$function$
;
