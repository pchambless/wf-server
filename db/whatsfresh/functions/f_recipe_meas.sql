CREATE OR REPLACE FUNCTION whatsfresh.f_recipe_meas(p_id integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select concat(a.quantity, ' ', whatsfresh.f_measure(a.measure_id)) as recipe_meas
from whatsfresh.product_recipes a
where id = p_id
$function$
;

