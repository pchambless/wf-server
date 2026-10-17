CREATE OR REPLACE FUNCTION app_engine.f_html_styled(p_schema text, p_template_name text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_html text;
  v_css text;
  v_css_classes text[];
  v_theme_css text;
  v_template_css text;
BEGIN
  EXECUTE format('SELECT html, css FROM %I.html_templates WHERE name = $1', p_schema)
    INTO v_html, v_css USING p_template_name;

  IF v_html IS NULL THEN
    RETURN NULL;
  END IF;

  v_css_classes := CASE
    WHEN v_css IS NULL OR v_css = '{}' OR v_css = '' THEN ARRAY[]::text[]
    ELSE v_css::text[]
  END;

  IF array_length(v_css_classes, 1) IS NULL THEN
    RETURN v_html;
  END IF;

  v_theme_css := app_engine.f_css(p_schema, 'themes');
  SELECT string_agg(app_engine.f_css(p_schema, cls), E'\n')
    INTO v_template_css
    FROM unnest(v_css_classes) cls;

  RETURN '<style>' || COALESCE(v_theme_css, '') || E'\n' || COALESCE(v_template_css, '') || '</style>' || E'\n' || v_html;
END;
$function$
;

