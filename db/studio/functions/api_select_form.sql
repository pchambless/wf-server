CREATE OR REPLACE FUNCTION studio.api_select_form(p_template_name text, p_current_value integer, p_field_name text DEFAULT NULL::text)
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
  -- Get template info
  SELECT ht.id, ht.title, ht.hydrate
  INTO v_template_id, v_template_title, v_hydrate
  FROM studio.html_templates ht
  WHERE ht.name = p_template_name;

  IF v_template_id IS NULL THEN
    RAISE EXCEPTION 'Template % not found', p_template_name;
  END IF;

  -- Get comp_name from page_components (global, page_id=0)
  SELECT pc.comp_name
  INTO v_comp_name
  FROM studio.page_components pc
  WHERE pc.html_template_id = v_template_id
    AND pc.page_id = 0
    AND pc.deleted_at IS NULL
  LIMIT 1;

  IF v_comp_name IS NULL THEN
    RAISE EXCEPTION 'Page component for template % not found', p_template_name;
  END IF;

  -- Use the field name passed from the form token (e.g., f_measure_id)
  -- Falls back to comp_name if not provided
  v_field_name := COALESCE(p_field_name, v_comp_name);

  -- Preserve the row currently referenced by this form field even if it has since
  -- been soft-deleted (deleted_at set) elsewhere. Transaction-local only (is_local
  -- = true via set_config) - never touches whatsfresh.context_store, so it cannot
  -- leak into or overwrite any other page/session state. Source api_X() functions
  -- opt in via: OR id::text = current_setting('whatsfresh.dd_preserve_id', true)
  PERFORM set_config('whatsfresh.dd_preserve_id', COALESCE(p_current_value::text, ''), true);

  -- Build options HTML by executing the hydrate query
  v_options_html := '';
  FOR v_rec IN EXECUTE v_hydrate
  LOOP
    v_options_html := v_options_html || '<option value="' || v_rec.value || '"';
    IF v_rec.value = p_current_value THEN
      v_options_html := v_options_html || ' selected';
    END IF;
    v_options_html := v_options_html || '>' || v_rec.label || '</option>';
  END LOOP;

  -- Build select element with field name for form submission
  v_select_html := '<select id="' || v_comp_name || '" name="' || v_field_name || '">';
  v_select_html := v_select_html || v_options_html || '</select>';

  -- Build final HTML: label + select
  v_html := '<div class="dropdown-label">' || COALESCE(v_template_title, p_template_name) || '</div>' || v_select_html;

  RETURN v_html;
END;
$function$
;

