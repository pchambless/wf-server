CREATE OR REPLACE FUNCTION whatsfresh.f_html_escape(p_text text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT replace(replace(replace(replace(replace(replace(coalesce(p_text, ''),
         '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;'), '''', '&#39;'), '{', '&#123;')
$function$
;

