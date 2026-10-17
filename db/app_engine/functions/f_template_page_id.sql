CREATE OR REPLACE FUNCTION app_engine.f_template_page_id(p_schema text, p_template_id integer)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_page_id int;
BEGIN
  EXECUTE format('SELECT page_id FROM %I.page_components WHERE html_template_id = $1 LIMIT 1', p_schema)
    INTO v_page_id
    USING p_template_id;
  RETURN v_page_id;
END;
$function$
;

