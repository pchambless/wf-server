CREATE OR REPLACE FUNCTION studio.f_dml_row_account(p_table text, p_id integer)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_account integer;
BEGIN
  IF p_id IS NULL THEN
    RETURN NULL;
  ELSIF p_table = 'product_recipes' THEN
    SELECT e.account_id INTO v_account FROM whatsfresh.product_recipes r JOIN whatsfresh.entities e ON e.id = r.product_id WHERE r.id = p_id;
  ELSIF p_table = 'product_batch_tasks' THEN
    SELECT b.account_id INTO v_account FROM whatsfresh.product_batch_tasks t JOIN whatsfresh.batches b ON b.id = t.batch_id WHERE t.id = p_id;
  ELSIF EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'whatsfresh' AND table_name = p_table AND column_name = 'account_id') THEN
    EXECUTE format('SELECT account_id FROM whatsfresh.%I WHERE id = $1', p_table) INTO v_account USING p_id;
  END IF;
  RETURN v_account;
END
$function$
;

