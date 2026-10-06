CREATE OR REPLACE FUNCTION whatsfresh.api_login_verify(p_email text, p_password text)
 RETURNS TABLE(email text, user_id integer, first_name text, last_name text, role_id integer, default_account_id integer, password_matches boolean)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT
    a.email::text,
    a.id,
    a.first_name::text,
    a.last_name::text,
    a.role,
    a.default_account_id,
   crypt(p_password, a.password) = a.password
  FROM whatsfresh.users a
  WHERE a.email::text = p_email::text
  LIMIT 1;
$function$
;

