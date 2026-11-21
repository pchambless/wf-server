CREATE OR REPLACE FUNCTION whatsfresh.tg_shipments_check()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'whatsfresh'
AS $function$
BEGIN
  IF current_setting('whatsfresh.copying_prod', true) = 'on' THEN RETURN NEW; END IF;

  IF NOT EXISTS (SELECT 1 FROM whatsfresh.batches
                 WHERE id = NEW.batch_id AND account_id = NEW.account_id AND entity_kind = 'Prod') THEN
    RAISE EXCEPTION 'Shipment batch % is not a product batch of this account', NEW.batch_id
      USING ERRCODE = 'check_violation';
  END IF;
  -- no unit given: ship in the product batch's unit (review answer 5)
  IF NEW.measure_id IS NULL THEN
    SELECT measure_id INTO NEW.measure_id FROM whatsfresh.batches WHERE id = NEW.batch_id;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM whatsfresh.locations
                 WHERE id = NEW.location_id AND account_id = NEW.account_id) THEN
    RAISE EXCEPTION 'Shipment customer % is not a location of this account', NEW.location_id
      USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.measure_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM whatsfresh.measures
                 WHERE id = NEW.measure_id AND account_id = NEW.account_id) THEN
    RAISE EXCEPTION 'Shipment measure % is not a measure of this account', NEW.measure_id
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$function$
;
