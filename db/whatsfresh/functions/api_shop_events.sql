CREATE OR REPLACE FUNCTION whatsfresh.api_shop_events()
 RETURNS TABLE(id integer, event_date date, location_id integer, location text, planned_count integer, bought_count integer, label text)
 LANGUAGE sql
 STABLE
AS $function$
-- Task 613. Shopping trips of the current account (context account_id), newest first, for the Trip dropdown on
-- /shopping-trips. planned_count = list items not bought yet (no live lot of that ingredient on the trip);
-- bought_count = live lots on the trip.
  SELECT e.id, e.event_date, e.location_id, l.name::text,
         p.n::int, b.n::int,
         concat(to_char(e.event_date, 'Dy Mon FMDD, YYYY'), ' - ', l.name,
                CASE WHEN p.n > 0 THEN concat(' - ', p.n, ' to buy') END,
                CASE WHEN b.n > 0 THEN concat(' - ', b.n, ' bought') END)
  FROM whatsfresh.shop_events e
  JOIN whatsfresh.locations l ON l.id = e.location_id
  CROSS JOIN LATERAL (
    SELECT count(*) AS n FROM whatsfresh.batches x
    WHERE x.shop_event_id = e.id AND x.deleted_at IS NULL) b
  CROSS JOIN LATERAL (
    SELECT count(*) AS n FROM whatsfresh.shop_event_items i
    WHERE i.shop_event_id = e.id AND i.deleted_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM whatsfresh.batches x
                      WHERE x.shop_event_id = e.id AND x.entity_id = i.ingredient_id AND x.deleted_at IS NULL)) p
  WHERE e.account_id = whatsfresh.c_getval('account_id')::integer
    AND e.deleted_at IS NULL
  ORDER BY e.event_date DESC, l.name;
$function$
;
