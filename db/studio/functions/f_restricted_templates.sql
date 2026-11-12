CREATE OR REPLACE FUNCTION studio.f_restricted_templates()
 RETURNS TABLE(template_name text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT ht.name FROM studio.html_templates ht
   WHERE EXISTS (SELECT 1 FROM studio.f_template_pages(ht.name))
     AND NOT EXISTS (SELECT 1 FROM studio.f_template_pages(ht.name) tp WHERE studio.f_page_visibility(tp.page_id) IS NULL)
$function$
;

