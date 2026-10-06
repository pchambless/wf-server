CREATE OR REPLACE FUNCTION whatsfresh.api_product_recipes()
 RETURNS TABLE(id integer, account_id integer, product_id integer, product text, ingredient_id integer, ingredient text, qty_meas text, measure_id integer, measure text, ingredient_order integer, quantity numeric, comments text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT a.id,
         b.account_id,
         a.product_id,
         concat(b.name,' (',whatsfresh.f_product_type(b.product_type_id),')'),
         a.ingredient_id,
         case when a.ingredient_id is null then
         		'No Ingredients'
         else
         		whatsfresh.f_ingredient(a.ingredient_id)
         end,
         concat(a.quantity, ' ', whatsfresh.f_measure(a.measure_id)),
         a.measure_id,
         whatsfresh.f_measure(a.measure_id) as measure,
         a.ingredient_order,
         a.quantity,
         a.comments
  FROM whatsfresh.api_products()  b
  left join whatsfresh.product_recipes a
  ON  b.id = a.product_id
  WHERE b.id = whatsfresh.c_getval('product_id')::integer
    AND b.account_id IN (whatsfresh.c_getval('account_id')::integer, 0)
    AND (a.deleted_at is null OR a.id = whatsfresh.c_getval('recipe_id')::int)
order by a.ingredient_order;
$function$
;

