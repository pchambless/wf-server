CREATE OR REPLACE FUNCTION whatsfresh.api_workers()
 RETURNS TABLE(id integer, account_id integer, account text, name text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT id,
           account_id,
           whatsfresh.f_account(account_id) as account,
           name
  FROM whatsfresh.workers
  WHERE deleted_at IS NULL
  AND account_id IN (whatsfresh.c_getval('account_id')::integer, 0)
  ORDER BY id;
$function$
;

