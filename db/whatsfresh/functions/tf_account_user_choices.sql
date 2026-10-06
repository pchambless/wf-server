CREATE OR REPLACE FUNCTION whatsfresh.tf_account_user_choices()
 RETURNS TABLE(user_id integer, user_name text, user_email text, account_id integer)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT u.id,
         (u.first_name || ' ' || u.last_name)::text,
         u.email::text,
         whatsfresh.c_getval('account_id')::integer
  FROM whatsfresh.users u
  WHERE u.deleted_at IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM whatsfresh.accounts_users au
      WHERE au.user_id = u.id
        AND au.account_id = whatsfresh.c_getval('account_id')::integer
        AND au.deleted_at IS NULL
    )
  ORDER BY u.first_name, u.last_name
  LIMIT 200
$function$
;

