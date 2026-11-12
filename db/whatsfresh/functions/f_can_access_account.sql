CREATE OR REPLACE FUNCTION whatsfresh.f_can_access_account(p_email text, p_account_id integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT p_email IS NOT NULL AND p_account_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM whatsfresh.users u
     WHERE lower(u.email) = lower(p_email) AND u.deleted_at IS NULL
       AND (u.role = 1 OR EXISTS (
             SELECT 1 FROM whatsfresh.accounts_users au
              WHERE au.user_id = u.id AND au.account_id = p_account_id AND au.deleted_at IS NULL)))
$function$
;

