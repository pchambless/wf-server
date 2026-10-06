CREATE OR REPLACE FUNCTION whatsfresh.tf_accounts_users_set_default_account()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  UPDATE whatsfresh.users
  SET default_account_id = NEW.account_id, updated_at = now(), updated_by = NEW.created_by
  WHERE id = NEW.user_id AND default_account_id IS NULL;
  RETURN NEW;
END;
$function$
;

