CREATE OR REPLACE FUNCTION whatsfresh.f_can_delete(p_table text, p_id integer)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
AS $function$
-- Can this whatsfresh row really be deleted (task 703)? True only when nothing uses it: no row in any table
-- with a foreign key to it (inactive rows count too), and no history-without-a-foreign-key per f_row_in_use.
-- Derived from pg_constraint, so a child column added later is picked up with no change here. Grids show
-- a Delete button only when this is true; studio.dml still falls back to a soft delete if a row gains a
-- child in between.
DECLARE
  v_parent regclass := to_regclass(format('whatsfresh.%I', p_table));
  r record;
  v_used boolean;
BEGIN
  IF v_parent IS NULL OR p_id IS NULL THEN
    RETURN false;
  END IF;
  IF whatsfresh.f_row_in_use(p_table, p_id) THEN
    RETURN false;
  END IF;
  FOR r IN
    SELECT c.conrelid::regclass AS child, a.attname AS col, array_length(c.conkey, 1) AS ncols
      FROM pg_constraint c
      JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
     WHERE c.contype = 'f' AND c.confrelid = v_parent
  LOOP
    IF r.ncols <> 1 THEN
      RETURN false; -- a multi-column reference: not checked here, so never offer a delete
    END IF;
    EXECUTE format('SELECT EXISTS (SELECT 1 FROM %s WHERE %I = $1)', r.child, r.col) INTO v_used USING p_id;
    IF v_used THEN
      RETURN false;
    END IF;
  END LOOP;
  RETURN true;
END;
$function$
;
