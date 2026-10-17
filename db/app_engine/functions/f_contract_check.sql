CREATE OR REPLACE FUNCTION app_engine.f_contract_check(p_schema text)
 RETURNS TABLE(object_type text, object_name text, status text, detail text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_req record;
  v_exists boolean;
  v_missing_cols text[];
BEGIN
  FOR v_req IN SELECT * FROM app_engine.app_contract WHERE deleted_at IS NULL ORDER BY id LOOP
    IF v_req.object_type IN ('table','view') THEN
      SELECT EXISTS (
        SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname = p_schema AND c.relname = v_req.object_name
          AND c.relkind = CASE v_req.object_type WHEN 'table' THEN 'r' ELSE 'v' END
      ) INTO v_exists;

      IF NOT v_exists THEN
        object_type := v_req.object_type;
        object_name := v_req.object_name;
        status := 'missing_object';
        detail := format('%s.%s not found', p_schema, v_req.object_name);
        RETURN NEXT;
        CONTINUE;
      END IF;

      IF v_req.required_columns IS NOT NULL THEN
        SELECT array_agg(col) INTO v_missing_cols
        FROM unnest(v_req.required_columns) AS col
        WHERE NOT EXISTS (
          SELECT 1 FROM information_schema.columns ic
          WHERE ic.table_schema = p_schema AND ic.table_name = v_req.object_name AND ic.column_name = col
        );

        IF v_missing_cols IS NOT NULL THEN
          object_type := v_req.object_type;
          object_name := v_req.object_name;
          status := 'missing_columns';
          detail := format('missing columns: %s', array_to_string(v_missing_cols, ', '));
          RETURN NEXT;
          CONTINUE;
        END IF;
      END IF;

      object_type := v_req.object_type;
      object_name := v_req.object_name;
      status := 'ok';
      detail := NULL;
      RETURN NEXT;

    ELSIF v_req.object_type = 'function' THEN
      SELECT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname = p_schema AND p.proname = v_req.object_name
      ) INTO v_exists;

      object_type := v_req.object_type;
      object_name := v_req.object_name;
      IF v_exists THEN
        status := 'ok';
        detail := NULL;
      ELSE
        status := 'missing_object';
        detail := format('%s.%s() not found', p_schema, v_req.object_name);
      END IF;
      RETURN NEXT;
    END IF;
  END LOOP;
END;
$function$
;

