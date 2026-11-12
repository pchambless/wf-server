CREATE OR REPLACE FUNCTION studio.f_dml_ref_table(p_table text, p_col text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT r.ref FROM (VALUES
    ('batches', 'entity_id', 'entities'),
    ('batches', 'measure_id', 'measures'),
    ('batches', 'location_id', 'locations'),
    ('batches', 'brand_id', 'brands'),
    ('entities', 'entity_type_id', 'entity_types'),
    ('entities', 'default_measure_id', 'measures'),
    ('entities', 'default_location_id', 'locations'),
    ('lineage', 'source_batch_id', 'batches'),
    ('lineage', 'target_batch_id', 'batches'),
    ('product_batch_tasks', 'batch_id', 'batches'),
    ('product_batch_tasks', 'task_id', 'tasks'),
    ('product_recipes', 'product_id', 'entities'),
    ('product_recipes', 'ingredient_id', 'entities'),
    ('product_recipes', 'measure_id', 'measures'),
    ('tasks', 'product_type_id', 'entity_types')
  ) r(tbl, col, ref)
  WHERE r.tbl = p_table AND r.col = p_col
$function$
;

