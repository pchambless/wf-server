CREATE OR REPLACE FUNCTION studio.f_template_page_id(template_id integer)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
  SELECT page_id
  FROM studio.page_components a
  WHERE html_template_id = template_id
  LIMIT 1;
$function$
;

