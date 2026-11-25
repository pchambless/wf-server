CREATE OR REPLACE FUNCTION whatsfresh.api_shop_event_lines()
 RETURNS TABLE(line_kind text, item_id integer, batch_id integer, ingredient_id integer, ingredient text,
               batch_number text, qty_price text, total numeric, was_planned boolean)
 LANGUAGE sql
 STABLE
AS $function$
-- Task 613. The lines of the selected shopping trip (context shop_event_id) for the grid on /shopping-trips:
-- 'To buy' = a list item with no live lot of that ingredient on the trip yet; 'Bought' = each live lot on the trip.
-- Buying is derived, never stored: recording a lot for a listed ingredient turns its line into a Bought line.
-- Only trips of the current account (context account_id) are returned.
  WITH trip AS (
    SELECT e.id
    FROM whatsfresh.shop_events e
    WHERE e.id = whatsfresh.c_getval('shop_event_id')::integer
      AND e.account_id = whatsfresh.c_getval('account_id')::integer
      AND e.deleted_at IS NULL
  )
  SELECT 'To buy', i.id, NULL::integer, i.ingredient_id, n.name::text,
         NULL::text, NULL::text, NULL::numeric, true
  FROM trip
  JOIN whatsfresh.shop_event_items i ON i.shop_event_id = trip.id AND i.deleted_at IS NULL
  JOIN whatsfresh.entities n ON n.id = i.ingredient_id
  WHERE NOT EXISTS (SELECT 1 FROM whatsfresh.batches x
                    WHERE x.shop_event_id = trip.id AND x.entity_id = i.ingredient_id AND x.deleted_at IS NULL)
  UNION ALL
  SELECT 'Bought', NULL::integer, b.id, b.entity_id, n.name::text,
         b.batch_number::text,
         CASE WHEN b.unit_price > 0
              THEN concat(trim_scale(b.quantity), ' @ ', chr(36),
                          CASE WHEN b.unit_price = round(b.unit_price, 2) THEN to_char(b.unit_price, 'FM999990.00')
                               ELSE trim_scale(b.unit_price)::text END,
                          ' per ', trim_scale(coalesce(b.unit_quantity, 1)), ' ', coalesce(m.name, ''))
              ELSE concat(trim_scale(b.quantity), ' ', m.name) END,
         round(coalesce(b.quantity, 0) * coalesce(b.unit_price, 0), 2),
         EXISTS (SELECT 1 FROM whatsfresh.shop_event_items i
                 WHERE i.shop_event_id = trip.id AND i.ingredient_id = b.entity_id AND i.deleted_at IS NULL)
  FROM trip
  JOIN whatsfresh.batches b ON b.shop_event_id = trip.id AND b.deleted_at IS NULL
  JOIN whatsfresh.entities n ON n.id = b.entity_id
  LEFT JOIN whatsfresh.measures m ON m.id = b.measure_id
  ORDER BY 1 DESC, 5, 6;
$function$
;
