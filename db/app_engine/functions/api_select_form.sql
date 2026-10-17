CREATE OR REPLACE FUNCTION app_engine.api_select_form(p_schema text, p_template_name text, p_current_value integer, p_field_name text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_template_id int;
  v_comp_name text;
  v_template_title text;
  v_hydrate text;
  v_field_name text;
  v_options_html text;
  v_select_html text;
  v_html text;
  v_rec record;
BEGIN
  EXECUTE format('SELECT ht.id, ht.title, ht.hydrate FROM %I.html_templates ht WHERE ht.name = $1', p_schema)
    INTO v_template_id, v_template_title, v_hydrate
    USING p_template_name;

  IF v_template_id IS NULL THEN
    RAISE EXCEPTION 'Template % not found in schema %', p_template_name, p_schema;
  END IF;

  EXECUTE format('SELECT pc.comp_name FROM %I.page_components pc WHERE pc.html_template_id = $1 AND pc.page_id = 0 AND pc.deleted_at IS NULL LIMIT 1', p_schema)
    INTO v_comp_name
    USING v_template_id;

  IF v_comp_name IS NULL THEN
    RAISE EXCEPTION 'Page component for template % not found in schema %', p_template_name, p_schema;
  END IF;

  v_field_name := COALESCE(p_field_name, v_comp_name);

  -- Preserve the row currently referenced by this form field even if it has since
  -- been soft-deleted, same transaction-local mechanism as studio.api_select_form.
  -- Stays whatsfresh-scoped (matches the hardcoded original) since only
  -- whatsfresh's api_X() functions consume it today - genericizing this session
  -- var per-schema is future work, not needed for this proof-of-concept.
  PERFORM set_config('whatsfresh.dd_preserve_id', COALESCE(p_current_value::text, ''), true);

  v_options_html := '';
  FOR v_rec IN EXECUTE v_hydrate
  LOOP
    v_options_html := v_options_html || '<option value="' || v_rec.value || '"';
    IF v_rec.value = p_current_value THEN
      v_options_html := v_options_html || ' selected';
    END IF;
    v_options_html := v_options_html || '>' || v_rec.label || '</option>';
  END LOOP;

  v_select_html := '<select id="' || v_comp_name || '" name="' || v_field_name || '">';
  v_select_html := v_select_html || v_options_html || '</select>';

  v_html := '<div class="dropdown-label">' || COALESCE(v_template_title, p_template_name) || '</div>' || v_select_html;

  RETURN v_html;
END;
$function$
;

