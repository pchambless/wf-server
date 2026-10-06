CREATE OR REPLACE FUNCTION whatsfresh.api_admin_reset_password(p_user_id integer, p_new_password text, p_reset_by text)
 RETURNS TABLE(success boolean, error_message text)
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF p_new_password IS NULL OR length(p_new_password) < 8 THEN
    RETURN QUERY SELECT false, 'Password must be at least 8 characters'::text;
    RETURN;
  END IF;

  UPDATE whatsfresh.users
  SET password = crypt(p_new_password, gen_salt('bf')),
      must_change_password = true,
      updated_at = now(),
      updated_by = p_reset_by
  WHERE id = p_user_id;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'User not found'::text;
    RETURN;
  END IF;

  RETURN QUERY SELECT true, NULL::text;
END;
$function$
;

