CREATE OR REPLACE FUNCTION whatsfresh.tg_context_store_account_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'whatsfresh'
AS $function$
-- Task 840: a stored account_id must be an account the row's user may use (a member, or role 1), whoever
-- writes it: the app (setvals, login, register), an n8n workflow, a future bug or a hand edit. Every page reads
-- c_getval('account_id') without re-checking, so this is the gate. An empty value is allowed (c_getval then
-- falls back to the user's default account, which c_getval checks the same way).
-- whatsfresh.copying_prod = 'on' (set by the dev mirror) skips it: prod already accepted those rows.
BEGIN
  IF NEW.param_name IS DISTINCT FROM 'account_id' OR coalesce(btrim(NEW.param_val), '') = '' THEN RETURN NEW; END IF;
  IF current_setting('whatsfresh.copying_prod', true) = 'on' THEN RETURN NEW; END IF;
  IF btrim(NEW.param_val) !~ '^[0-9]+\Z'
     OR NOT whatsfresh.f_can_access_account(NEW.email, btrim(NEW.param_val)::integer) THEN
    RAISE EXCEPTION 'account % is not available to %', NEW.param_val, NEW.email USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END
$function$
;

