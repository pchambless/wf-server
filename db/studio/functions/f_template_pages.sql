CREATE OR REPLACE FUNCTION studio.f_template_pages(p_template text)
 RETURNS TABLE(page_id integer)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT pc.page_id FROM studio.page_components pc JOIN studio.html_templates ht ON ht.id = pc.html_template_id
   WHERE ht.name = p_template AND pc.deleted_at IS NULL
  UNION
  SELECT vp.page_id FROM studio.vw_pages vp WHERE p_template IN (vp.form_template, vp.grid_template)
  UNION
  -- report templates opened by a button on a page (open_report actions) belong to that page
  SELECT ag.page_id FROM studio.action_components ac JOIN studio.action_groups ag ON ag.id = ac.group_id
   WHERE ac.action_type = 'open_report' AND ac.deleted_at IS NULL AND ag.deleted_at IS NULL
     AND ac.actions->'templates' ? p_template
$function$
;

