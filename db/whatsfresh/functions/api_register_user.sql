CREATE OR REPLACE FUNCTION whatsfresh.api_register_user(p_email text, p_password text, p_first_name text, p_last_name text, p_company_name text, p_zip_code text, p_description text DEFAULT NULL::text, p_street_address text DEFAULT NULL::text, p_city text DEFAULT NULL::text, p_state_code text DEFAULT NULL::text, p_url text DEFAULT NULL::text)
 RETURNS TABLE(success boolean, user_id integer, account_id integer, error_message text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_user_id integer;
  v_account_id integer;
BEGIN
  IF EXISTS (SELECT 1 FROM whatsfresh.users WHERE email = p_email) THEN
    RETURN QUERY SELECT false, NULL::integer, NULL::integer, 'Email already registered'::text;
    RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM whatsfresh.accounts WHERE name = p_company_name) THEN
    RETURN QUERY SELECT false, NULL::integer, NULL::integer, 'Company name already registered'::text;
    RETURN;
  END IF;

  INSERT INTO whatsfresh.accounts (name, description, street_address, city, state_code, zip_code, url, created_at, created_by)
  VALUES (p_company_name, p_description, p_street_address, p_city, p_state_code, p_zip_code, p_url, now(), p_email)
  RETURNING id INTO v_account_id;

  INSERT INTO whatsfresh.users (email, password, first_name, last_name, role, default_account_id, created_at, created_by)
  VALUES (p_email, crypt(p_password, gen_salt('bf')), p_first_name, p_last_name, 2, v_account_id, now(), p_email)
  RETURNING id INTO v_user_id;

  INSERT INTO whatsfresh.accounts_users (account_id, user_id, is_owner, created_at, created_by)
  VALUES (v_account_id, v_user_id, 1, now(), p_email);

  RETURN QUERY SELECT true, v_user_id, v_account_id, NULL::text;
END;
$function$
;

