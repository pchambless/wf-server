CREATE OR REPLACE FUNCTION whatsfresh.api_measures()
 RETURNS TABLE(id integer, account_id integer, account text, name text, abbrev text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT id, account_id,
         whatsfresh.f_account(account_id) as account,
         name, abbrev
  FROM whatsfresh.measures
  WHERE (deleted_at IS NULL
         OR id = whatsfresh.c_getval('measure_id')::int
         OR id::text = current_setting('whatsfresh.dd_preserve_id', true))
    AND account_id IN (whatsfresh.c_getval('account_id')::integer, 0)
  ORDER BY id;
$function$
;

