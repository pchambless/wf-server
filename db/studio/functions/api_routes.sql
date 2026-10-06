CREATE OR REPLACE FUNCTION studio.api_routes()
 RETURNS TABLE(page_id integer, page_name text, route text, group_name text)
 LANGUAGE sql
 STABLE
AS $function$
SELECT 
  id,
  page_name,
  concat('/', page_name) as route,
  group_name
FROM studio.pages
ORDER BY page_name;
$function$
;

