CREATE OR REPLACE FUNCTION whatsfresh.f_row_in_use(p_table text, p_id integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  -- Is history depending on this row even though no foreign key says so? dml() deactivates such a row
  -- instead of hard-deleting it (task 622). A recipe row has no FK pointing at it: lineage ties batches to
  -- the (product, ingredient) pair, so deleting the row used to erase the recipe a product's past batches
  -- were made against. Only tables listed here are affected; every other table keeps the FK-based rule.
  SELECT CASE p_table
    WHEN 'product_recipes' THEN EXISTS (
      SELECT 1
        FROM whatsfresh.product_recipes pr
        JOIN whatsfresh.batches t ON t.entity_id = pr.product_id AND t.entity_kind = 'Prod'
        JOIN whatsfresh.lineage l ON l.target_batch_id = t.id
        JOIN whatsfresh.batches s ON s.id = l.source_batch_id
                                 AND s.entity_kind = 'Shop'
                                 AND s.entity_id = pr.ingredient_id
       WHERE pr.id = p_id)
    ELSE false
  END
$function$
;
