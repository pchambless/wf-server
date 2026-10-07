CREATE OR REPLACE FUNCTION support.tf_nav_menu_html()
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_nav_bar text := '<div class="nav-bar">';
  v_current_group text := '';
  v_dropdown_open boolean := false;
  r record;
BEGIN
  FOR r IN
    SELECT group_name, item_label, item_url, css_class, item_actions
    FROM support.vw_nav_menus
    WHERE item_label IS NOT NULL
    ORDER BY group_order,  item_order
  LOOP
    IF r.group_name != v_current_group THEN
      IF v_dropdown_open THEN
        v_nav_bar := v_nav_bar || E'\n      </div>' || E'\n    </div>';
        v_dropdown_open := false;
      END IF;

      v_current_group := r.group_name;
      v_nav_bar := v_nav_bar || E'\n    <div class="nav-item">' ||
                   E'\n      <button class="dropdown-toggle" data-dropdown="menu-' ||
                   LOWER(REPLACE(REPLACE(r.group_name, ' ', '-'), '_', '-')) ||
                   '">' || r.group_name || '</button>' ||
                   E'\n      <div class="dropdown-menu" id="menu-' ||
                   LOWER(REPLACE(REPLACE(r.group_name, ' ', '-'), '_', '-')) || '">';
      v_dropdown_open := true;
    END IF;

    IF r.item_actions IS NOT NULL THEN
      v_nav_bar := v_nav_bar || E'\n        <a href="javascript:void(0)" class="' ||
                   COALESCE(r.css_class, '') || '" data-actions=''' ||
                   jsonb_build_object('click', r.item_actions)::text ||
                   '''>' || r.item_label || '</a>';
    ELSE
      v_nav_bar := v_nav_bar || E'\n        <a href="' || r.item_url || '" class="' ||
                   COALESCE(r.css_class, '') || '">' || r.item_label || '</a>';
    END IF;
  END LOOP;

  IF v_dropdown_open THEN
    v_nav_bar := v_nav_bar || E'\n      </div>' || E'\n    </div>';
  END IF;

  v_nav_bar := v_nav_bar || E'\n  </div>';

  RETURN v_nav_bar;
END;
$function$
;
