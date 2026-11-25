CREATE OR REPLACE FUNCTION whatsfresh.tg_shop_events_move_batches()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'whatsfresh'
AS $function$
-- Task 931. AFTER UPDATE OF location_id, event_date on shop_events: a trip moved to another store or day
-- takes its lots with it, so batches.location_id/event_date never disagree with their trip.
-- tg_batches_shop_event then finds this same trip under its new store+day.
BEGIN
  IF current_setting('whatsfresh.copying_prod', true) = 'on' THEN RETURN NULL; END IF;
  IF NEW.location_id IS NOT DISTINCT FROM OLD.location_id
     AND NEW.event_date IS NOT DISTINCT FROM OLD.event_date THEN
    RETURN NULL;
  END IF;

  UPDATE whatsfresh.batches b
     SET location_id = NEW.location_id,
         event_date  = NEW.event_date,
         updated_at  = now(),
         updated_by  = coalesce(NEW.updated_by, b.updated_by)
   WHERE b.shop_event_id = NEW.id;
  RETURN NULL;
END;
$function$
;
