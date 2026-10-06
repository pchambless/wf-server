CREATE OR REPLACE FUNCTION studio.api_page_slot_actions_json(p_page_id integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
WITH rows AS (
  SELECT *
  FROM studio.api_page_slot_actions(p_page_id, NULL)
),
slots AS (
  SELECT
    r.slot_name,
    jsonb_agg(
      jsonb_build_object(
        'id', r.id,
        'group_id', r.group_id,
        'group_name', r.group_name,
        'group_order', r.group_order,
        'component_name', r.component_name,
        'action_type', r.action_type, 
        'parent_id', r.parent_id,
        'label', r.label,
        'icon', r.icon,
        'actions', COALESCE(r.actions, '{}'::jsonb),
        'visible_when', COALESCE(r.visible_when, '{}'::jsonb),
        'comp_order', r.comp_order,
        'render_as', r.render_as
      )
      ORDER BY r.group_order, r.comp_order, r.id
    ) AS items
  FROM rows r
  GROUP BY r.slot_name
)
SELECT COALESCE(jsonb_object_agg(slot_name, items), '{}'::jsonb)
FROM slots;
$function$
;

