CREATE OR REPLACE FUNCTION studio.f_page_name(p_id integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT a.page_name::text
  FROM studio.pages a
  WHERE a.id = p_id
  LIMIT 1;
$function$
;

