CREATE OR REPLACE FUNCTION app_engine.api_page_slot_actions(p_schema text, p_page_id integer, p_slot_name text DEFAULT NULL::text)
 RETURNS TABLE(id integer, page_name text, group_order integer, group_name text, comp_order integer, component_name text, action_type text, parent_id integer, label text, icon text, actions jsonb, visible_when jsonb, group_id integer, page_id integer, slot_name text, render_as text, is_active boolean)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    RETURN QUERY EXECUTE format($q$
        SELECT v.id, v.page_name, v.group_order, v.group_name, v.comp_order,
               v.component_name, v.action_type, v.parent_id, v.label, v.icon,
               v.actions, v.visible_when, v.group_id, v.page_id, v.slot_name,
               v.render_as, v.is_active
          FROM %I.vw_page_actions v
         WHERE v.page_id = $1
           AND ($2 IS NULL OR v.slot_name = $2)
         ORDER BY v.slot_name, v.group_order, v.comp_order, v.id
    $q$, p_schema)
    USING p_page_id, p_slot_name;
END;
$function$
;

