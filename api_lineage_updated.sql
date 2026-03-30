CREATE OR REPLACE FUNCTION whatsfresh.api_lineage(p_email character varying)
 RETURNS TABLE(id integer, account_id integer, account text, event_type text, srce_batch_id integer, srce_entity_id integer, srce_entity_name text, srce_batch_number text, srce_lot_code text, srce_qty_measure text, srce_date text, srce_location text, srce_batch_key text, srce_brand text, trgt_batch_id integer, trgt_entity_name text, trgt_batch_number text, trgt_lot_code text, trgt_qty_measure text, trgt_date text, trgt_location text, trgt_batch_key text, trgt_brand text, comments text)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT l.id,
          l.account_id,
           whatsfresh.f_account(l.account_id),
           l.event_type,
           l.source_batch_id,
           src.ingredient_id,
           concat(src.entity_type, '.', src.entity_name),
           src.batch_number,
 			src.fsma_lot_code,
           src.qty_measure::text,
           src.event_date::text,
		  src.location::text,
			src.batch_event_key::text,
			src.brand::text,
           l.target_batch_id::integer,
           concat(trgt.entity_type, '.', trgt.entity_name)::text,
           trgt.batch_number, trgt.fsma_lot_code,
           trgt.qty_measure::text,
           trgt.event_date::text, trgt.location,
			trgt.batch_event_key::text,
			trgt.brand::text,
           l.comments
    FROM whatsfresh.lineage l
    JOIN (select * from whatsfresh.api_batches(p_email)) src
    ON l.source_batch_id = src.id
    JOIN (select * from whatsfresh.api_batches(p_email)) trgt
    ON l.target_batch_id = trgt.id
    WHERE l.account_id IN (whatsfresh.c_getval(p_email, 'account_id')::integer, 0)
    ORDER BY l.id DESC;
$function$
;
