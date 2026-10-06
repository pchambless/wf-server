CREATE OR REPLACE FUNCTION whatsfresh.api_accounts_users()
 RETURNS TABLE(id integer, account_id integer, account text, user_id integer, user_name text, user_email text, is_owner integer, role_id integer)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT a.id,
         a.account_id,
         whatsfresh.f_account(a.account_id) as account,
         a.user_id,
         whatsfresh.f_user_name(a.user_id)::text,
         b.email::text,
         a.is_owner,
         b.role
  FROM whatsfresh.accounts_users a
  JOIN whatsfresh.users b 
  ON a.user_id = b.id
  join whatsfresh.accounts c
  on c.id = a.account_id
  WHERE  c.deleted_at is null
     and (a.deleted_at is null
    AND account_id IN (whatsfresh.c_getval('account_id')::integer, 0))
  ORDER BY id;
$function$
;

