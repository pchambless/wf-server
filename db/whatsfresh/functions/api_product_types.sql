CREATE OR REPLACE FUNCTION whatsfresh.api_product_types()
 RETURNS TABLE(id integer, account_id integer, account text, name text, fsma_class_id integer, fsma_class text, fsma_class_description text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT et.id, et.account_id,
         whatsfresh.f_account(et.account_id) as account,
         et.name,
         et.fsma_class_id,
         fc.name as fsma_class,
         fc.description as fsma_class_description
  FROM whatsfresh.entity_types et
  LEFT JOIN studio.fsma_classifications fc ON fc.id = et.fsma_class_id
  WHERE et.entity_kind = 'Prod'
    AND (et.deleted_at IS NULL
         OR et.id = whatsfresh.c_getval('product_type_id')::integer
         OR et.id::text = current_setting('whatsfresh.dd_preserve_id', true))
    AND et.account_id IN (whatsfresh.c_getval('account_id')::integer, 0)
  ORDER BY et.id;
$function$
;

