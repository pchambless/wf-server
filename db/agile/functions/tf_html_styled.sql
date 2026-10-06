CREATE OR REPLACE FUNCTION agile.tf_html_styled(p_template_name text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    t support.html_templates%ROWTYPE;
    css_classes text[];
    theme_css text;
    template_css text;
    styled_html text;
BEGIN
    SELECT * INTO t
    FROM support.html_templates
    WHERE name = p_template_name;

    css_classes := COALESCE(t.css::text[], ARRAY[]::text[]);

    SELECT css INTO theme_css
    FROM studio.css
    WHERE class = 'themes';

    template_css := COALESCE((
        SELECT string_agg(css.css, E'\n')
        FROM studio.css
        WHERE class = ANY(css_classes)
    ), '');

    IF t.css IS NULL OR t.css = '{}' OR t.css = '' THEN
        styled_html := t.html;
    ELSIF 'rpt-hdr' = ANY(css_classes) THEN
        styled_html := agile.rpt_header_styled(p_template_name);
    ELSE
        styled_html :=
            '<style>' ||
            COALESCE(theme_css, '') || E'\n' ||
            template_css ||
            '</style>' || E'\n' ||
            t.html;
    END IF;

    RETURN styled_html;
END;
$function$
;

