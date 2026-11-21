CREATE OR REPLACE FUNCTION whatsfresh.tg_recalls_check()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'whatsfresh'
AS $function$
BEGIN
  IF current_setting('whatsfresh.copying_prod', true) = 'on' THEN RETURN NEW; END IF;
  IF NOT EXISTS (SELECT 1 FROM whatsfresh.batches
                 WHERE id = NEW.batch_id AND account_id = NEW.account_id AND entity_kind = 'Shop') THEN
    RAISE EXCEPTION 'Recall lot % is not an ingredient batch of this account', NEW.batch_id
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$function$
;

