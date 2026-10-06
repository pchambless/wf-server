CREATE OR REPLACE FUNCTION whatsfresh.api_locations()
 RETURNS TABLE(id integer, account_id integer, account text, name text, contact_name text, contact_phone text, contact_email text, comments text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT id, account_id,
         whatsfresh.f_account(account_id) as account,
         name, contact_name, contact_phone, contact_email, comments
  FROM whatsfresh.locations
  WHERE (deleted_at IS NULL
         OR id = whatsfresh.c_getval('location_id')::int
         OR id::text = current_setting('whatsfresh.dd_preserve_id', true))
    AND account_id IN (whatsfresh.c_getval('account_id')::integer, 0)
  ORDER BY id;
$function$
;

