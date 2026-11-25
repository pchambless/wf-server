CREATE OR REPLACE FUNCTION whatsfresh.tg_batches_shop_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'whatsfresh'
AS $function$
-- Task 931. A Shop batch belongs to the shopping trip for its account + store (location_id) + day (event_date).
-- shop_event_id is always derived here, never trusted from the caller: the trip is found, or created if this is
-- the first lot of that store and day, so the Ingredient Batches page and the Shopping Event page agree.
-- Prod batches and Shop batches without a store or date have no trip.
-- Runs during the prod->dev mirror too (no copying_prod skip): it re-links mirrored rows to dev's trips.
DECLARE
  v_id integer;
BEGIN
  IF NEW.entity_kind IS DISTINCT FROM 'Shop' OR NEW.location_id IS NULL OR NEW.event_date IS NULL THEN
    NEW.shop_event_id := NULL;
    RETURN NEW;
  END IF;

  SELECT e.id INTO v_id
  FROM whatsfresh.shop_events e
  WHERE e.account_id = NEW.account_id
    AND e.location_id = NEW.location_id
    AND e.event_date = NEW.event_date
    AND e.deleted_at IS NULL;

  IF v_id IS NULL THEN
    INSERT INTO whatsfresh.shop_events (account_id, location_id, event_date, created_by)
    VALUES (NEW.account_id, NEW.location_id, NEW.event_date,
            coalesce(CASE WHEN TG_OP = 'UPDATE' THEN NEW.updated_by END, NEW.created_by, 'system'))
    ON CONFLICT (account_id, location_id, event_date) WHERE deleted_at IS NULL DO NOTHING
    RETURNING id INTO v_id;

    IF v_id IS NULL THEN   -- a concurrent save created it first
      SELECT e.id INTO v_id
      FROM whatsfresh.shop_events e
      WHERE e.account_id = NEW.account_id
        AND e.location_id = NEW.location_id
        AND e.event_date = NEW.event_date
        AND e.deleted_at IS NULL;
    END IF;
  END IF;

  NEW.shop_event_id := v_id;
  RETURN NEW;
END;
$function$
;
