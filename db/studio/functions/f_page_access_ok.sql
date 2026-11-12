CREATE OR REPLACE FUNCTION studio.f_page_access_ok(p_email text, p_page_id integer)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_vis     text := studio.f_page_visibility(p_page_id);
  v_user_id integer;
  v_role    integer;
  v_account text;
BEGIN
  IF v_vis IS NULL THEN
    RETURN true;
  END IF;

  SELECT u.id, u.role INTO v_user_id, v_role
    FROM whatsfresh.users u
   WHERE lower(u.email) = lower(p_email) AND u.deleted_at IS NULL
   LIMIT 1;

  IF v_user_id IS NULL THEN
    RETURN false;
  ELSIF v_role = 1 THEN
    RETURN true;
  ELSIF v_vis = 'account_owner' THEN
    -- Same current account as c_getval('account_id'): the context value, else the user's default account.
    SELECT coalesce(nullif(cs.context ->> 'account_id', ''), (SELECT u.default_account_id::text FROM whatsfresh.users u WHERE u.id = v_user_id))
      INTO v_account
      FROM whatsfresh.api_context_store(p_email) cs;
    v_account := coalesce(v_account, (SELECT u.default_account_id::text FROM whatsfresh.users u WHERE u.id = v_user_id));
    RETURN v_account ~ '^[0-9]+\Z' AND EXISTS (
      SELECT 1 FROM whatsfresh.accounts_users au
       WHERE au.user_id = v_user_id AND au.account_id = v_account::integer AND au.is_owner = 1 AND au.deleted_at IS NULL);
  END IF;

  RETURN false;
END
$function$
;

