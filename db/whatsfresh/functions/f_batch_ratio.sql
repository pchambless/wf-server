CREATE OR REPLACE FUNCTION whatsfresh.f_batch_ratio(p_batch_id integer, OUT batch_ratio numeric, OUT recipe_qty integer, OUT batch_qty integer)
 RETURNS record
 LANGUAGE sql
 STABLE
AS $function$
  SELECT
    CASE
      WHEN b.entity_kind = 'Prod' AND a.recipe_quantity > 0
      THEN ROUND((b.quantity::numeric / a.recipe_quantity::numeric), 1)
      ELSE NULL
    END,
    CASE
      WHEN b.entity_kind = 'Prod' AND a.recipe_quantity > 0
      THEN a.recipe_quantity::int
      ELSE NULL
    END,
    b.quantity::int
  FROM whatsfresh.batches b
  LEFT JOIN whatsfresh.entities a ON b.entity_id = a.id AND a.entity_kind = 'Prod'
  WHERE b.id = p_batch_id;
$function$
;

