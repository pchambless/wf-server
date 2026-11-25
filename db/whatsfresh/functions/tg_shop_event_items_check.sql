CREATE OR REPLACE FUNCTION whatsfresh.tg_shop_event_items_check()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'whatsfresh'
AS $function$
-- Task 931. BEFORE INSERT/UPDATE on shop_event_items (the trip plan):
-- the trip and the ingredient both belong to the item's account, and the ingredient is an ingredient (Shop entity).
-- Errors use P0001 so studio.dml shows the message itself (it rewrites unique_violation to a generic one).
-- whatsfresh.copying_prod = 'on' (dev mirror) skips the checks: prod already accepted those rows.
BEGIN
  IF current_setting('whatsfresh.copying_prod', true) = 'on' THEN RETURN NEW; END IF;

  IF NOT EXISTS (SELECT 1 FROM whatsfresh.shop_events e
                 WHERE e.id = NEW.shop_event_id AND e.account_id = NEW.account_id) THEN
    RAISE EXCEPTION 'Shopping trip % is not a trip of this account', NEW.shop_event_id
      USING ERRCODE = 'check_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM whatsfresh.entities i
                 WHERE i.id = NEW.ingredient_id AND i.account_id = NEW.account_id AND i.entity_kind = 'Shop') THEN
    RAISE EXCEPTION 'Ingredient % is not an ingredient of this account', NEW.ingredient_id
      USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.deleted_at IS NULL AND EXISTS (
       SELECT 1 FROM whatsfresh.shop_event_items x
       WHERE x.shop_event_id = NEW.shop_event_id AND x.ingredient_id = NEW.ingredient_id
         AND x.deleted_at IS NULL AND x.id IS DISTINCT FROM NEW.id) THEN
    RAISE EXCEPTION 'That ingredient is already on this trip''s list'
      USING ERRCODE = 'P0001', HINT = 'duplicate_shop_event_item';
  END IF;
  RETURN NEW;
END;
$function$
;
