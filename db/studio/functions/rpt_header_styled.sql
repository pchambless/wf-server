CREATE OR REPLACE FUNCTION studio.rpt_header_styled(p_template_name text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
	SELECT
   	  '<style>'
      || COALESCE(theme.css, '')
      || E'\n'
      || COALESCE(string_agg(c.css, E'\n'), '')
    || '</style>'
    || E'\n'
    ||  replace(replace(replace(replace(replace(
			           (SELECT html FROM studio.html_templates WHERE name = '_rpt_header'),
			           '{{slot:header_content}}', t.html),
			           '{{_title}}', COALESCE(t.title, '')),
			           '{{_description}}', COALESCE(t.description, '')),
			           '{{_generated_date}}', TO_CHAR(NOW(), 'YYYY-MM-DD')),
			           '{{_generated_time}}', TO_CHAR(NOW(), 'HH12:MI AM'))
  FROM studio.html_templates t
  LEFT JOIN studio.css c ON c.class = ANY(COALESCE(t.css::text[], ARRAY[]::text[]))
  LEFT JOIN studio.css theme ON theme.class = 'themes'
  WHERE t.name = p_template_name
  GROUP BY t.id, t.name, t.title, t.description, t.hydrate, t.group_by, t.html, theme.css;
$function$
;

