CREATE OR REPLACE FUNCTION whatsfresh.api_users()
 RETURNS TABLE(id integer, email text, password text, appsmith_pwd text, first_name text, last_name text, role integer, default_account_id integer, last_login timestamp without time zone, remember_token text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT id, email, password, appsmith_pwd, first_name, last_name,
         role, default_account_id, last_login, remember_token
  FROM whatsfresh.users
  WHERE deleted_at IS NULL
  ORDER BY id;
$function$
;

