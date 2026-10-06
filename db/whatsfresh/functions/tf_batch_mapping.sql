CREATE OR REPLACE FUNCTION whatsfresh.tf_batch_mapping()
 RETURNS TABLE(map_id integer, batch_id integer, batch_number text, batch_date date, brand text, mapped boolean, available boolean)
 LANGUAGE sql
 STABLE
AS $function$ SELECT lm.id, b.id, b.batch_number::text, b.event_date, whatsfresh.f_brand(b.brand_id), (lm.id IS NOT NULL), b.available FROM whatsfresh.batches b LEFT JOIN LATERAL ( SELECT l.id FROM whatsfresh.lineage l WHERE l.source_batch_id = b.id AND l.target_batch_id = whatsfresh.c_getval('target_batch_id')::integer LIMIT 1 ) lm ON true WHERE b.entity_kind = 'Shop' AND b.entity_id = whatsfresh.c_getval('ingredient_id')::integer AND b.account_id = whatsfresh.c_getval('account_id')::integer $function$
;
