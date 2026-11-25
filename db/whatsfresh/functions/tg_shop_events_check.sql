CREATE OR REPLACE FUNCTION whatsfresh.tg_shop_events_check()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'whatsfresh'
AS $function$
-- Task 931. BEFORE INSERT/UPDATE on shop_events.
-- - The store is one of the account's locations, or a shared one (account 0, e.g. Kitchen Hub).
-- - Moving a trip onto a store+day that already has a live trip is refused with a readable message.
-- - A trip that still has live lots cannot be deleted: the lots are the traceability record.
-- whatsfresh.copying_prod = 'on' (dev mirror) skips the checks: prod already accepted those rows.
DECLARE
  v_name text;
BEGIN
  IF current_setting('whatsfresh.copying_prod', true) = 'on' THEN RETURN NEW; END IF;

  IF NOT EXISTS (SELECT 1 FROM whatsfresh.locations l
                 WHERE l.id = NEW.location_id AND l.account_id IN (NEW.account_id, 0)) THEN
    RAISE EXCEPTION 'Store % is not a location of this account', NEW.location_id
      USING ERRCODE = 'check_violation';
  END IF;

  IF NEW.deleted_at IS NULL AND EXISTS (
       SELECT 1 FROM whatsfresh.shop_events e
       WHERE e.account_id = NEW.account_id AND e.location_id = NEW.location_id
         AND e.event_date = NEW.event_date AND e.deleted_at IS NULL
         AND e.id IS DISTINCT FROM NEW.id) THEN
    SELECT l.name INTO v_name FROM whatsfresh.locations l WHERE l.id = NEW.location_id;
    RAISE EXCEPTION 'There is already a shopping trip to % on %. Open that trip instead.',
      coalesce(v_name, 'that store'), to_char(NEW.event_date, 'YYYY-MM-DD')
      USING ERRCODE = 'unique_violation', HINT = 'duplicate_shop_event';
  END IF;

  IF TG_OP = 'UPDATE' AND NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL
     AND EXISTS (SELECT 1 FROM whatsfresh.batches b
                 WHERE b.shop_event_id = NEW.id AND b.deleted_at IS NULL) THEN
    RAISE EXCEPTION 'This shopping trip has purchased lots. Delete the lots first, then the trip.'
      USING ERRCODE = 'check_violation', HINT = 'shop_event_has_batches';
  END IF;

  RETURN NEW;
END;
$function$
;
