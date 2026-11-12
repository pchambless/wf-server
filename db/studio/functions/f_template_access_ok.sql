CREATE OR REPLACE FUNCTION studio.f_template_access_ok(p_email text, p_template text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT NOT EXISTS (SELECT 1 FROM studio.f_template_pages(p_template))
      OR EXISTS (SELECT 1 FROM studio.f_template_pages(p_template) tp WHERE studio.f_page_access_ok(p_email, tp.page_id))
$function$
;

