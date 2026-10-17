CREATE OR REPLACE FUNCTION app_engine.f_css(p_schema text, p_class text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_css text;
BEGIN
  EXECUTE format('SELECT css FROM %I.css WHERE class = $1', p_schema)
    INTO v_css USING p_class;

  IF v_css IS NULL THEN
    SELECT css INTO v_css FROM app_engine.css WHERE class = p_class;
  END IF;

  RETURN v_css;
END;
$function$
;

