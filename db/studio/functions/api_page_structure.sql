CREATE OR REPLACE FUNCTION studio.api_page_structure()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
WITH page_context AS (
  SELECT whatsfresh.c_getval('page_id')::integer AS page_id
),
page_info AS (
  SELECT jsonb_build_object(
    'pageID', p.id,
    'pageName', p.page_name,
    'pageTitle', p.table_config->>'pageTitle',
    'templateID', p.template_id,
    'templateName', ht.name,
    'templateType', p.table_config->>'template_type',
    'formTemplate', p.table_config->>'form',
    'gridTemplate', p.table_config->>'grid',
    'contextKey', p.table_config->>'contextKey',
    'formHeadCol', p.table_config->>'formHeadCol'
  ) AS info
  FROM studio.pages p
  LEFT JOIN studio.html_templates ht ON p.template_id = ht.id
  WHERE p.id = (SELECT page_id FROM page_context)
),
components_list AS (
  SELECT
    pc.id AS page_comp_id,
    pc.comp_name,
    pc.html_template_id,
    ht.name AS template_name,
    ht.title AS template_title,
    ht.platform AS widget_type,
    pc.slot_name,
    pc.ordr,
    COALESCE(pc.actions, '[]'::jsonb) AS actions
  FROM studio.page_components pc
  LEFT JOIN studio.html_templates ht ON pc.html_template_id = ht.id
  WHERE pc.page_id = (SELECT page_id FROM page_context)
    AND pc.deleted_at IS NULL
)
SELECT jsonb_build_object(
  'pageInfo', (SELECT info FROM page_info),
  'components', COALESCE(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'page_comp_id', cl.page_comp_id,
          'comp_name', cl.comp_name,
          'html_template_id', cl.html_template_id,
          'template_name', cl.template_name,
          'template_title', cl.template_title,
          'widget_type', cl.widget_type,
          'slot_name', cl.slot_name,
          'order', cl.ordr,
          'actions', cl.actions
        )
        ORDER BY COALESCE(cl.slot_name, ''), cl.ordr, cl.page_comp_id
      )
      FROM components_list cl
    ),
    '[]'::jsonb
  ),
  'slotActions', COALESCE(
    studio.api_page_slot_actions_json((SELECT page_id FROM page_context)),
    '{}'::jsonb
  )
);
$function$
;

