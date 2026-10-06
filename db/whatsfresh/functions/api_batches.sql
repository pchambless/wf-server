CREATE OR REPLACE FUNCTION whatsfresh.api_batches()
 RETURNS TABLE(id integer, account_id integer, account text, entity_kind text, entity_id integer, entity_type_id integer, entity_type text, entity_name text, fsma_lot_code text, batch_number text, recipe_qty integer, batch_qty numeric, batch_ratio numeric, event_date date, measure_id integer, measure text, qty_measure text, location_id integer, location text, lot_number text, unit_quantity numeric, unit_price numeric, total numeric, brand_id integer, brand text, batch_event_key text, best_by_date date, comments text, available boolean)
 LANGUAGE sql
 STABLE
AS $function$ SELECT a.batch_id, a.account_id, whatsfresh.f_account(a.account_id)::text, a.entity_kind, a.entity_id, a.entity_type_id, a.entity_type, a.entity_name, a.fsma_lot_code, a.batch_number, a.recipe_qty::int, a.batch_qty::numeric, a.batch_ratio::numeric, a.batch_date::date, a.measure_id, a.measure, concat(a.batch_qty,' ',a.measure), a.location_id, a.location, a.lot_number, a.unit_quantity, a.unit_price, a.total::numeric, a.brand_id, a.brand, a.batch_event_key, a.best_by_date, a.comments, a.available FROM whatsfresh.vw_batches_fda a WHERE account_id IN (whatsfresh.c_getval('account_id')::integer, 0) ORDER BY a.batch_date DESC $function$
;

