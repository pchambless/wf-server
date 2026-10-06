CREATE OR REPLACE FUNCTION whatsfresh.api_product_batch_tasks()
 RETURNS TABLE(id integer, product_type_id integer, batch_id integer, batch_number text, task_id integer, task text, ordr integer, comments text, workers text, measure_value numeric)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT
  pbt.id,
  t.product_type_id,
  b.id as batch_id,
  b.batch_number,
  t.id as task_id,
  t.name as task,
  t.ordr,
  pbt.comments,
  pbt.workers,
  pbt.measure_value
FROM whatsfresh.batches b
JOIN whatsfresh.entities e ON e.id = b.entity_id AND e.entity_kind = b.entity_kind
JOIN whatsfresh.tasks t ON t.product_type_id = e.entity_type_id
LEFT JOIN whatsfresh.product_batch_tasks pbt
  ON pbt.task_id = t.id
  AND pbt.batch_id = b.id
  AND pbt.deleted_at IS NULL
WHERE b.id = whatsfresh.c_getval('product_batch_id')::integer
  AND b.entity_kind = 'Prod'
ORDER BY t.ordr;
$function$
;

