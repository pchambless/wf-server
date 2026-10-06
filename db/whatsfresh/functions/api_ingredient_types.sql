CREATE OR REPLACE FUNCTION whatsfresh.api_ingredient_types()
 RETURNS TABLE(id integer, account_id integer, account text, name text, description text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT id, account_id,
         whatsfresh.f_account(account_id) as account,
         name, description
  FROM whatsfresh.entity_types
  WHERE entity_kind = 'Shop'
    AND (deleted_at IS NULL
         OR id = whatsfresh.c_getval('ingredient_type_id')::integer
         OR id::text = current_setting('whatsfresh.dd_preserve_id', true))
    AND account_id IN (whatsfresh.c_getval('account_id')::integer, 0)
  ORDER BY id;
$function$
;

