CREATE OR REPLACE FUNCTION deployment.f_data_sync_preview(p_env text DEFAULT 'prod'::text)
 RETURNS TABLE(schema_path text, dev_rows bigint, rows_added bigint, rows_modified bigint, rows_deleted bigint, status text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_env   deployment.environments%ROWTYPE;
  v_pol   record;
  v_sch   text;
  v_tbl   text;
  v_add   bigint;
  v_mod   bigint;
  v_del   bigint;
  v_msg   text;
BEGIN
  -- READ-ONLY preview of the diff-based data sync (task 531, Sprint 530): for every
  -- refresh_always config table, how many rows a sync would INSERT on the target
  -- (dev has them, target does not), UPDATE (content differs) and DELETE (target
  -- has them, dev does not). Built on f_data_diff (PK + row hash, audit columns
  -- excluded), so the preview and the future apply cannot disagree. Writes nothing.
  SELECT * INTO v_env FROM deployment.environments WHERE name = p_env;
  IF NOT FOUND THEN RAISE EXCEPTION 'f_data_sync_preview: unknown environment %', p_env; END IF;
  IF NOT v_env.is_target THEN RAISE EXCEPTION 'f_data_sync_preview: environment % is not a deploy target', p_env; END IF;
  PERFORM deployment.f_assert_distinct_target(v_env.dblink_server);

  FOR v_pol IN
    SELECT o.schema_path AS sp FROM deployment.object_policy o
     WHERE o.object_type = 'table' AND o.data = 'refresh_always' AND o.structure = 'deploy'
     ORDER BY o.schema_path
  LOOP
    v_sch := split_part(v_pol.sp, '.', 1);
    v_tbl := split_part(v_pol.sp, '.', 2);

    SELECT count(*) FILTER (WHERE d.diff_type = 'missing on target'),
           count(*) FILTER (WHERE d.diff_type = 'content differs'),
           count(*) FILTER (WHERE d.diff_type = 'missing on dev'),
           string_agg(DISTINCT d.diff_type, '; ') FILTER (WHERE d.diff_type LIKE 'skipped:%' OR d.diff_type LIKE 'error:%')
      INTO v_add, v_mod, v_del, v_msg
      FROM deployment.f_data_diff(p_env, v_sch, v_tbl) d;

    schema_path := v_pol.sp;
    EXECUTE format('SELECT count(*) FROM %I.%I', v_sch, v_tbl) INTO dev_rows;
    rows_added := v_add; rows_modified := v_mod; rows_deleted := v_del;
    status := CASE WHEN v_msg IS NOT NULL THEN v_msg
                   WHEN v_add + v_mod + v_del = 0 THEN 'in sync'
                   ELSE 'will change' END;
    RETURN NEXT;
  END LOOP;
END
$function$
;

