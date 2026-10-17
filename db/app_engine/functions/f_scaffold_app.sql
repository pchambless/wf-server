CREATE OR REPLACE FUNCTION app_engine.f_scaffold_app(p_source_schema text, p_target_schema text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_req record;
  v_ddl text;
  v_out text := format(E'-- Scaffold DDL: %I -> %I, generated from app_engine.app_contract\n', p_source_schema, p_target_schema);
  v_oid oid;
  v_remaining text[];
  v_order text[] := '{}';
  v_progress boolean;
  v_tbl text;
  v_unmet int;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM app_engine.vw_app_contract_status
    WHERE schema_name = p_source_schema AND compliant
  ) THEN
    RAISE EXCEPTION 'f_scaffold_app: source schema % is not contract-compliant, run app_engine.f_contract_check(%L) first', p_source_schema, p_source_schema;
  END IF;

  -- Topologically sort contracted tables by FK edges among themselves (Kahn's
  -- algorithm). Emitting them in app_contract.id order broke page_components
  -- and action_groups, both FK'd to pages, which happened to sort after them.
  -- Derived live from pg_constraint rather than a hand-picked order, per the
  -- same reasoning deployment.f_table_ddl already uses for column/constraint DDL.
  v_remaining := ARRAY(SELECT object_name FROM app_engine.app_contract WHERE object_type = 'table' AND deleted_at IS NULL ORDER BY id);

  WHILE array_length(v_remaining, 1) > 0 LOOP
    v_progress := false;
    FOREACH v_tbl IN ARRAY v_remaining LOOP
      SELECT count(*) INTO v_unmet
        FROM pg_constraint con
        JOIN pg_class c ON c.oid = con.conrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_class rc ON rc.oid = con.confrelid
       WHERE con.contype = 'f' AND n.nspname = p_source_schema AND c.relname = v_tbl
         AND rc.relname <> v_tbl
         AND rc.relname = ANY(v_remaining);

      IF v_unmet = 0 THEN
        v_order := v_order || v_tbl;
        v_remaining := array_remove(v_remaining, v_tbl);
        v_progress := true;
        EXIT;
      END IF;
    END LOOP;

    IF NOT v_progress THEN
      RAISE EXCEPTION 'f_scaffold_app: circular FK dependency among contracted tables: %', v_remaining;
    END IF;
  END LOOP;

  v_out := v_out || format(E'CREATE SCHEMA IF NOT EXISTS %I;\n\n', p_target_schema);

  -- Tables in topological order, then functions, then views: a view's referenced
  -- functions/tables ARE validated eagerly at CREATE VIEW time, but a plpgsql
  -- function body's table/view references are only checked at call time, so
  -- functions are always safe to create before the views/tables they call.
  FOR v_req IN
    SELECT ac.*,
      CASE ac.object_type
        WHEN 'table' THEN array_position(v_order, ac.object_name)
        WHEN 'function' THEN 100000 + ac.id
        WHEN 'view' THEN 200000 + ac.id
      END AS rank
    FROM app_engine.app_contract ac
    WHERE ac.deleted_at IS NULL
    ORDER BY rank
  LOOP
    IF v_req.object_type = 'table' THEN
      v_ddl := deployment.f_table_ddl(p_source_schema, v_req.object_name);

    ELSIF v_req.object_type = 'view' THEN
      SELECT c.oid INTO v_oid
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = p_source_schema AND c.relname = v_req.object_name AND c.relkind = 'v';

      IF v_oid IS NULL THEN
        RAISE EXCEPTION 'f_scaffold_app: view %.% not found', p_source_schema, v_req.object_name;
      END IF;

      v_ddl := format('CREATE OR REPLACE VIEW %I.%I AS%s', p_source_schema, v_req.object_name, pg_get_viewdef(v_oid, true)) || ';';

    ELSIF v_req.object_type = 'function' THEN
      SELECT p.oid INTO v_oid
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = p_source_schema AND p.proname = v_req.object_name;

      IF v_oid IS NULL THEN
        RAISE EXCEPTION 'f_scaffold_app: function %.% not found', p_source_schema, v_req.object_name;
      END IF;

      v_ddl := pg_get_functiondef(v_oid) || ';';
    ELSE
      CONTINUE;
    END IF;

    v_ddl := regexp_replace(v_ddl, format('\m%s\M', p_source_schema), p_target_schema, 'g');

    v_out := v_out || format(E'-- %s: %s\n', v_req.object_type, v_req.object_name) || v_ddl || E'\n\n';
  END LOOP;

  RETURN v_out;
END;
$function$
;

