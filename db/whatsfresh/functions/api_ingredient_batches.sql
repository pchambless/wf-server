CREATE OR REPLACE FUNCTION whatsfresh.api_ingredient_batches()
 RETURNS TABLE(id integer, event_date text, batch_number text, qty_meas text, location text, best_by_date date, ingredient_id integer, measure_id integer, location_id integer)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT b.id,
         b.event_date::text,
         case when b.batch_number is null then 'No Batches' else b.batch_number end batch_number,
         b.qty_measure,
         whatsfresh.f_location(b.location_id),
         b.best_by_date,
         b.entity_id,
         b.measure_id,
        b.location_id
  FROM whatsfresh.api_ingredients() a
  left join whatsfresh.api_batches() b
  on  a.id = b.entity_id
  and b.entity_kind = 'Shop'
  WHERE a.id = (whatsfresh.c_getval('ingredient_id')::INTEGER)
  ORDER BY 3;
$function$
;

