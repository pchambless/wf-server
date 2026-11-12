CREATE OR REPLACE FUNCTION studio.f_page_visibility(p_page_id integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT g.data ->> 'visibility'
    FROM studio.vw_pages vp
    JOIN studio.action_components c ON c.actions ->> 'url' = vp.route_path AND c.deleted_at IS NULL
    JOIN studio.action_groups g ON g.id = c.group_id AND g.deleted_at IS NULL
   WHERE vp.page_id = p_page_id AND g.data ? 'visibility'
   ORDER BY (g.data ->> 'visibility') = 'global_staff' DESC
   LIMIT 1
$function$
;

