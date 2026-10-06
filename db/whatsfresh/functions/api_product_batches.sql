CREATE OR REPLACE FUNCTION whatsfresh.api_product_batches()
 RETURNS TABLE(id integer, product_id integer, product_name text, event_date text, batch_number text, qty_measure text, location text, best_by_date date, comments text, location_id integer, measure_id integer, available boolean)
 LANGUAGE sql
 STABLE
AS $function$ SELECT b.batch_id as id, a.id as product_id, a.name as product_name, b.batch_date::text, coalesce(b.batch_number, 'No Batches') as batch_number, concat(b.batch_qty, ' ', whatsfresh.f_measure(b.measure_id)) as qty_measure, whatsfresh.f_location(b.location_id) as location, b.best_by_date, b.comments, b.location_id, b.measure_id, b.available FROM whatsfresh.api_products() a left join whatsfresh.vw_batches_fda b on a.id = b.entity_id and b.entity_kind = 'Prod' WHERE a.id = (whatsfresh.c_getval('product_id')::INTEGER) $function$
;

