CREATE OR REPLACE FUNCTION whatsfresh.api_lineage()
 RETURNS TABLE(id integer, account_id integer, account text, event_type text, batch_ratio numeric, srce_batch_id integer, srce_entity_type_id integer, srce_entity_id integer, srce_entity_name text, srce_batch_number text, srce_batch_qty numeric, srce_recipe_qty numeric, recipe_meas text, recipe_theory_qty numeric, srce_lot_code text, srce_qty_measure text, srce_date text, srce_location text, srce_batch_key text, srce_brand text, trgt_batch_id integer, trgt_entity_type_id integer, trgt_entity_id integer, trgt_entity_name text, trgt_batch_number text, trgt_batch_qty numeric, trgt_lot_code text, trgt_qty_measure text, trgt_date text, trgt_location text, trgt_batch_key text, trgt_brand text, comments text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT l.id,
		l.account_id,
		whatsfresh.f_account(l.account_id),
		l.event_type,
		trgt.batch_ratio::numeric,
         l.source_batch_id,
        src.entity_type_id,
		src.entity_id,
         concat(src.entity_type, '.', src.entity_name),
		src.batch_number,
        src.batch_qty::numeric,
		pr.quantity::numeric as srce_recipe_qty,
		whatsfresh.f_measure(pr.measure_id),
        (pr.quantity::numeric * trgt.batch_ratio::numeric)::numeric as recipe_theory_qty,
		src.fsma_lot_code,
        src.qty_measure::text,
		src.event_date::text,
		src.location::text,
		src.batch_event_key::text,
		src.brand::text,
         l.target_batch_id::integer,
        trgt.entity_type_id,
		trgt.entity_id,
         concat(trgt.entity_type, '.',trgt.entity_name)::text,
		trgt.batch_number,
        trgt.batch_qty::numeric,
		trgt.fsma_lot_code,
         trgt.qty_measure::text,
		trgt.event_date::text,
		trgt.location,
		trgt.batch_event_key::text,
		trgt.brand::text,
         l.comments
  FROM whatsfresh.lineage l
  JOIN (SELECT * FROM whatsfresh.api_batches()) src
     ON l.source_batch_id = src.id
  JOIN (SELECT * FROM whatsfresh.api_batches()) trgt
    ON l.target_batch_id = trgt.id
  LEFT JOIN whatsfresh.product_recipes pr
   ON pr.product_id = trgt.entity_id
   AND pr.ingredient_id = src.entity_id
  WHERE l.account_id IN (whatsfresh.c_getval('account_id')::integer, 0)
  and src.entity_kind = 'Shop'
  and trgt.entity_kind = 'Prod'
  and pr.deleted_at is null
  ORDER BY l.id DESC;
$function$
;

