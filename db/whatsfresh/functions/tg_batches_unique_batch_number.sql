CREATE OR REPLACE FUNCTION whatsfresh.tg_batches_unique_batch_number()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'whatsfresh'
AS $function$
-- A batch number (lot code) must be unique among live batches of the same kind in an account.
-- Checked only when a number is set: INSERT, a batch_number/account/kind change, or an undelete,
-- so editing or deactivating a legacy duplicate still works (Guidance 43: no row-wide CHECK).
-- whatsfresh.copying_prod = 'on' (set by the dev mirror) skips it: prod already accepted those rows.
DECLARE
  v_key   text := upper(btrim(NEW.batch_number));
  v_other record;
BEGIN
  IF NEW.deleted_at IS NOT NULL OR coalesce(v_key, '') = '' THEN RETURN NEW; END IF;
  IF current_setting('whatsfresh.copying_prod', true) = 'on' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE'
     AND upper(btrim(OLD.batch_number)) IS NOT DISTINCT FROM v_key
     AND OLD.account_id = NEW.account_id
     AND OLD.entity_kind = NEW.entity_kind
     AND OLD.deleted_at IS NULL THEN
    RETURN NEW;
  END IF;

  -- Serialize concurrent saves of the same number in the same account and kind.
  PERFORM pg_advisory_xact_lock(hashtext('batch_number'), hashtext(NEW.account_id || '/' || NEW.entity_kind || '/' || v_key));

  SELECT b.batch_number, b.event_date, e.name INTO v_other
  FROM whatsfresh.batches b
  LEFT JOIN whatsfresh.entities e ON e.id = b.entity_id
  WHERE b.account_id = NEW.account_id
    AND b.entity_kind = NEW.entity_kind
    AND upper(btrim(b.batch_number)) = v_key
    AND b.deleted_at IS NULL
    AND b.id IS DISTINCT FROM NEW.id
  ORDER BY b.event_date DESC NULLS LAST
  LIMIT 1;

  IF FOUND THEN
    RAISE EXCEPTION 'Batch number % is already used by % (% %). Batch numbers must be unique in your account: start the number with the % code.',
      v_other.batch_number, coalesce(v_other.name, 'another batch'),
      CASE NEW.entity_kind WHEN 'Shop' THEN 'purchased' ELSE 'batch date' END,
      coalesce(to_char(v_other.event_date, 'YYYY-MM-DD'), 'no date'),
      CASE NEW.entity_kind WHEN 'Shop' THEN 'ingredient' ELSE 'product' END
      USING ERRCODE = 'P0001', HINT = 'duplicate_batch_number';
  END IF;
  RETURN NEW;
END;
$function$
;

