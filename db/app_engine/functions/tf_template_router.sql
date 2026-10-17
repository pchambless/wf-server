CREATE OR REPLACE FUNCTION app_engine.tf_template_router(p_schema text, p_source text, p_template_name text DEFAULT '*'::text)
 RETURNS TABLE(id integer, template_name text, page_id integer, workflow text, platform text, title text, group_by text, hydrate text, html text, css text, has_css boolean, has_hydrate boolean, has_html boolean, description text, updated_at date, created_at date)
 LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY EXECUTE format($sql$
    SELECT
      ht.id,
      ht.name,
      app_engine.f_template_page_id(%L, ht.id),
      CASE
        WHEN ht.platform = 'css_utility' THEN 'n/a'
        WHEN ht.n8n = 'page-structure' THEN 'page-structure'
        WHEN ht.n8n = 'report' THEN 'report'
        WHEN ht.n8n = 'login' THEN 'login'
        WHEN ht.n8n = 'raw-json' THEN 'raw-json'
        WHEN ht.n8n IN ('json','static') AND %L = 'app_engine' THEN 'styled-html'
        WHEN ht.n8n IN ('json','static') THEN 'raw-json'
        ELSE 'raw-json'
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
    FROM %I.html_templates ht
    WHERE (ht.name = %L OR %L = '*' OR %L IS NULL)
  $sql$, p_schema, p_source, p_schema, p_template_name, p_template_name, p_template_name);
END;
$function$
;
