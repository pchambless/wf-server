CREATE OR REPLACE FUNCTION whatsfresh.api_change_password(p_email text, p_old_password text, p_new_password text)
 RETURNS TABLE(success boolean, error_message text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_stored text;
BEGIN
  SELECT password INTO v_stored FROM whatsfresh.users WHERE email = p_email;

  IF v_stored IS NULL THEN
    RETURN QUERY SELECT false, 'User not found'::text;
    RETURN;
  END IF;

  IF crypt(p_old_password, v_stored) <> v_stored THEN
    RETURN QUERY SELECT false, 'Current password is incorrect'::text;
    RETURN;
  END IF;

  IF p_new_password IS NULL OR length(p_new_password) < 8 THEN
    RETURN QUERY SELECT false, 'New password must be at least 8 characters'::text;
    RETURN;
  END IF;

  UPDATE whatsfresh.users
  SET password = crypt(p_new_password, gen_salt('bf')),
      must_change_password = false,
      updated_at = now(),
      updated_by = p_email
  WHERE email = p_email;

  RETURN QUERY SELECT true, NULL::text;
END;
$function$
;

