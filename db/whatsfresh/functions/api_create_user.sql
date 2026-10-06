CREATE OR REPLACE FUNCTION whatsfresh.api_create_user(p_email text, p_password text, p_first_name text, p_last_name text, p_role integer, p_created_by text, p_must_change_password boolean DEFAULT true, p_default_account_id integer DEFAULT NULL::integer)
 RETURNS TABLE(success boolean, user_id integer, error_message text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_user_id integer;
  v_assign_success boolean;
  v_assign_error text;
BEGIN
  IF p_role NOT IN (1, 2) THEN
    RETURN QUERY SELECT false, NULL::integer, 'role must be 1 (Admin) or 2 (User)'::text;
    RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM whatsfresh.users WHERE email = p_email) THEN
    RETURN QUERY SELECT false, NULL::integer, 'Email already registered'::text;
    RETURN;
  END IF;

  INSERT INTO whatsfresh.users (email, password, first_name, last_name, role, default_account_id, must_change_password, created_at, created_by)
  VALUES (p_email, crypt(p_password, gen_salt('bf')), p_first_name, p_last_name, p_role, p_default_account_id, p_must_change_password, now(), p_created_by)
  RETURNING id INTO v_user_id;

  IF p_default_account_id IS NOT NULL THEN
    SELECT a.success, a.error_message INTO v_assign_success, v_assign_error
    FROM whatsfresh.api_assign_user_to_account(p_default_account_id, v_user_id, 0, p_created_by) a;

    IF NOT v_assign_success THEN
      RETURN QUERY SELECT false, v_user_id, format('User created but account assignment failed: %s', v_assign_error);
      RETURN;
    END IF;
  END IF;

  RETURN QUERY SELECT true, v_user_id, NULL::text;
END;
$function$
;

