CREATE OR REPLACE FUNCTION app_engine.api_page_structure(p_schema text, p_page_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    v_page_info  jsonb;
    v_components jsonb;
    v_slots      jsonb;
BEGIN
    EXECUTE format($q$
        SELECT jsonb_build_object(
            'pageID',       p.id,
            'pageName',     p.page_name,
            'pageTitle',    p.table_config->>'pageTitle',
            'templateID',   p.template_id,
            'templateName', ht.name,
            'templateType', p.table_config->>'template_type',
            'formTemplate', p.table_config->>'form',
            'gridTemplate', p.table_config->>'grid',
            'contextKey',   p.table_config->>'contextKey',
            'formHeadCol',  p.table_config->>'formHeadCol'
        )
          FROM %I.pages p
          LEFT JOIN %I.html_templates ht ON p.template_id = ht.id
         WHERE p.id = $1
    $q$, p_schema, p_schema)
    INTO v_page_info USING p_page_id;

    EXECUTE format($q$
        SELECT COALESCE(jsonb_agg(
            jsonb_build_object(
                'page_comp_id',     pc.id,
                'comp_name',        pc.comp_name,
                'html_template_id', pc.html_template_id,
                'template_name',    ht.name,
                'template_title',   ht.title,
                'widget_type',      ht.platform,
                'slot_name',        pc.slot_name,
                'order',            pc.ordr,
                'actions',          COALESCE(pc.actions, '[]'::jsonb)
            )
            ORDER BY COALESCE(pc.slot_name, ''), pc.ordr, pc.id
        ), '[]'::jsonb)
          FROM %I.page_components pc
          LEFT JOIN %I.html_templates ht ON pc.html_template_id = ht.id
         WHERE pc.page_id = $1
           AND pc.deleted_at IS NULL
    $q$, p_schema, p_schema)
    INTO v_components USING p_page_id;

    v_slots := app_engine.api_page_slot_actions_json(p_schema, p_page_id);

    RETURN jsonb_build_object(
        'pageInfo',    v_page_info,
        'components',  v_components,
        'slotActions', COALESCE(v_slots, '{}'::jsonb)
    );
END;
$function$
;

