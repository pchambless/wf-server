CREATE OR REPLACE FUNCTION whatsfresh.api_products()
 RETURNS TABLE(id integer, account_id integer, account text, name text, code text, product_type_id integer, product_type text, description text, recipe_quantity integer, qty_meas text, default_measure_id integer, default_measure text, best_by_days integer, default_location_id integer, default_location text, upc_item_reference text, upc_check_digit text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT id, account_id,
         whatsfresh.f_account(account_id) as account,
         name, code, entity_type_id AS product_type_id,
         whatsfresh.f_product_type(id) as product_type,
         description, recipe_quantity,
         concat(recipe_quantity,' ',whatsfresh.f_measure(default_measure_id)::text)::text,
         default_measure_id, whatsfresh.f_measure(default_measure_id)::text,
         best_by_days,
         default_location_id, whatsfresh.f_location(default_location_id)::text,
         upc_item_reference, upc_check_digit
  FROM whatsfresh.entities
  WHERE entity_kind = 'Prod'
    AND (deleted_at IS NULL
         OR id = whatsfresh.c_getval('product_id')::int
         OR id::text = current_setting('whatsfresh.dd_preserve_id', true))
    AND account_id IN (whatsfresh.c_getval('account_id')::integer, 0)
    AND (whatsfresh.c_getval('product_type_id') IS NULL
       OR entity_type_id = whatsfresh.c_getval('product_type_id')::int)
  ORDER BY id;
$function$
;

