CREATE OR REPLACE FUNCTION whatsfresh.api_assign_user_to_account(p_account_id integer, p_user_id integer, p_is_owner integer, p_created_by text)
 RETURNS TABLE(success boolean, assignment_id integer, error_message text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_id integer;
BEGIN
  INSERT INTO whatsfresh.accounts_users (account_id, user_id, is_owner, created_at, created_by)
  VALUES (p_account_id, p_user_id, p_is_owner, now(), p_created_by)
  RETURNING whatsfresh.accounts_users.id INTO v_id;

  RETURN QUERY SELECT true, v_id, NULL::text;
EXCEPTION
  WHEN unique_violation THEN
    RETURN QUERY SELECT false, NULL::integer, 'User already assigned to this account'::text;
  WHEN foreign_key_violation THEN
    RETURN QUERY SELECT false, NULL::integer, 'Account or user not found'::text;
END;
$function$
;

