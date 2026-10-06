CREATE OR REPLACE FUNCTION whatsfresh.api_tasks()
 RETURNS TABLE(id integer, account_id integer, account text, name text, ordr integer, product_type_id integer, product_type text, description text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT id, account_id,
         whatsfresh.f_account(account_id) as account,
         name, ordr, product_type_id,
         whatsfresh.f_product_type(product_type_id) as product_type,
         description
  FROM whatsfresh.tasks
  WHERE deleted_at IS NULL
    AND account_id IN (whatsfresh.c_getval('account_id')::integer, 0)
    AND product_type_id = whatsfresh.c_getval('product_type_id')::int
  ORDER BY ordr;
$function$
;

