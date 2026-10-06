CREATE OR REPLACE FUNCTION whatsfresh.api_ingredients()
 RETURNS TABLE(id integer, account_id integer, account text, name text, ingredient_type_id integer, ingredient_type text, description text, code text, grams_per_ounce integer, default_measure_id integer, default_measure text, default_location_id integer, default_location text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT id,
         account_id,
         whatsfresh.f_account(account_id) as account,
         name,
         entity_type_id AS ingredient_type_id,
         whatsfresh.f_ingredient_type(id) as ingredient_type,
         description,
         code,
         grams_per_ounce,
         default_measure_id, whatsfresh.f_measure(default_measure_id),
         default_location_id, whatsfresh.f_location(default_location_id)
  FROM whatsfresh.entities
  WHERE entity_kind = 'Shop'
    AND (deleted_at IS NULL
         OR id = whatsfresh.c_getval('ingredient_id')::int
         OR id::text = current_setting('whatsfresh.dd_preserve_id', true))
    AND account_id IN (whatsfresh.c_getval('account_id')::integer, 0)
    AND (whatsfresh.c_getval('ingredient_type_id') IS NULL
       OR entity_type_id = whatsfresh.c_getval('ingredient_type_id')::int)
  ORDER BY id;
$function$
;

