CREATE OR REPLACE FUNCTION studio.api_page_slot_actions(p_page_id integer, p_slot_name text DEFAULT NULL::text)
 RETURNS TABLE(id integer, page_name text, group_order integer, group_name text, comp_order integer, component_name text, action_type text, parent_id integer, label text, icon text, actions jsonb, visible_when jsonb, group_id integer, page_id integer, slot_name text, render_as text, is_active boolean)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT
    v.id,
    v.page_name,
    v.group_order,
    v.group_name,
    v.comp_order,
    v.component_name,
    v.action_type, 
    v.parent_id,
    v.label,
    v.icon,
    v.actions,
    v.visible_when,
    v.group_id,
    v.page_id,
    v.slot_name,
    v.render_as,
    v.is_active
  FROM studio.vw_page_actions v
  WHERE v.page_id = p_page_id
    AND (p_slot_name IS NULL OR v.slot_name = p_slot_name)
  ORDER BY v.slot_name, v.group_order, v.comp_order, v.id;
$function$
;

