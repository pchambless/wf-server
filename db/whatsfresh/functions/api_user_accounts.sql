CREATE OR REPLACE FUNCTION whatsfresh.api_user_accounts()
 RETURNS TABLE(id integer, account_id integer, account text, user_id integer, email text, is_owner boolean, global_user_type_id integer)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT au.id,
         au.account_id,
         whatsfresh.f_account(au.account_id) as account,
         au.user_id,
         u.email,
         au.is_owner::boolean,
         au.global_user_type_id
  FROM whatsfresh.accounts_users au
  JOIN whatsfresh.users u 
	ON u.id = au.user_id
  JOIN whatsfresh.accounts c
  on au.account_id = c.id
  WHERE c.deleted_at is null
    and au.deleted_at IS NULL
    AND u.email = whatsfresh.c_getval('userEmail')
  ORDER BY whatsfresh.f_account(au.account_id)
$function$
;

