CREATE OR REPLACE FUNCTION deployment.f_data_sync_apply(p_run_id integer, p_dry_run boolean DEFAULT true, p_allow_deletes boolean DEFAULT false, p_commit boolean DEFAULT true, p_policy text DEFAULT 'refresh_always'::text)
 RETURNS TABLE(out_seq integer, out_path text, rows_added bigint, rows_modified bigint, rows_deleted bigint, out_status text, out_error text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_env     deployment.environments%ROWTYPE;
  v_conn    text := 'sync_conn_' || p_run_id;
  t         record;
  v_pk      text;
  v_err     text;
  v_blocked text;
  v_pks     text;
  v_pk_val  text;
BEGIN
  SELECT e.* INTO v_env
    FROM deployment.deployment_runs r
    JOIN deployment.deployments d ON d.id = r.deployment_id
    JOIN deployment.environments e ON e.id = d.environment_id
   WHERE r.id = p_run_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'f_data_sync_apply: no such run %', p_run_id; END IF;
  IF NOT v_env.is_target THEN RAISE EXCEPTION 'f_data_sync_apply: environment % is not a deploy target', v_env.name; END IF;
  PERFORM deployment.f_assert_distinct_target(v_env.dblink_server);

  DROP TABLE IF EXISTS _sync_plan;
  CREATE TEMP TABLE _sync_plan (seq int, sp text, sch text, tbl text, pk_col text, diff_type text, pk text) ON COMMIT DROP;

  -- 1. the plan: every table's diff, computed before anything is written
  FOR t IN
    SELECT o.seq AS oseq, o.schema_path AS sp, split_part(o.schema_path, '.', 1) AS sch, split_part(o.schema_path, '.', 2) AS tbl
      FROM deployment.deployment_objects o
      JOIN deployment.object_policy op ON op.schema_path = o.schema_path AND op.object_type = 'table' AND op.data = p_policy
     WHERE o.run_id = p_run_id AND o.platform = 'database'
     ORDER BY o.seq
  LOOP
    SELECT a.attname INTO v_pk
      FROM pg_index i JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY (i.indkey)
     WHERE i.indrelid = format('%I.%I', t.sch, t.tbl)::regclass AND i.indisprimary AND i.indnkeyatts = 1;
    IF v_pk IS NULL THEN
      RAISE EXCEPTION 'f_data_sync_apply: % needs a single-column primary key', t.sp;
    END IF;

    INSERT INTO _sync_plan (seq, sp, sch, tbl, pk_col, diff_type, pk)
    SELECT t.oseq, t.sp, t.sch, t.tbl, v_pk, d.diff_type, d.pk_value
      FROM deployment.f_data_diff(v_env.name, t.sch, t.tbl) d;

    SELECT string_agg(DISTINCT p.diff_type, '; ') INTO v_err
      FROM _sync_plan p WHERE p.sp = t.sp AND (p.diff_type LIKE 'error:%' OR p.diff_type LIKE 'skipped:%');
    IF v_err IS NOT NULL THEN
      RAISE EXCEPTION 'f_data_sync_apply: % - %', t.sp, v_err;
    END IF;
  END LOOP;

  -- 2. the delete guard (before any write)
  SELECT string_agg(p.sp || ' (' || p.n || ')', ', ' ORDER BY p.sp) INTO v_blocked
    FROM (SELECT sp, count(*) AS n FROM _sync_plan WHERE diff_type = 'missing on dev' GROUP BY sp) p;
  IF v_blocked IS NOT NULL AND NOT p_allow_deletes AND NOT p_dry_run THEN
    RAISE EXCEPTION 'f_data_sync_apply: would DELETE rows on the target - %. Re-run with allow_deletes after reviewing the preview.', v_blocked;
  END IF;

  -- 3. apply (live and rehearsal only)
  IF NOT p_dry_run THEN
    BEGIN PERFORM dblink_disconnect(v_conn); EXCEPTION WHEN OTHERS THEN NULL; END;
    PERFORM dblink_connect(v_conn, v_env.dblink_server);
    PERFORM dblink_exec(v_conn, 'BEGIN');
    BEGIN
      -- Pass A: parents before children (deploy_objects seq order)
      FOR t IN
        SELECT DISTINCT p.seq, p.sp, p.sch, p.tbl, p.pk_col FROM _sync_plan p
         WHERE p.diff_type IN ('missing on target', 'content differs') ORDER BY p.seq
      LOOP
        FOR v_pk_val IN SELECT p.pk FROM _sync_plan p WHERE p.sp = t.sp AND p.diff_type IN ('missing on target', 'content differs') ORDER BY p.pk
        LOOP
          PERFORM dblink_exec(v_conn, deployment.f_row_upsert_sql(t.sch, t.tbl, t.pk_col, v_pk_val));
        END LOOP;
        PERFORM deployment.f_target_sequence_resync(v_conn, t.sch, t.tbl);
      END LOOP;

      -- Pass B: children before parents (reverse order), deletes only
      FOR t IN
        SELECT DISTINCT p.seq, p.sp, p.sch, p.tbl, p.pk_col FROM _sync_plan p
         WHERE p.diff_type = 'missing on dev' ORDER BY p.seq DESC
      LOOP
        SELECT string_agg(quote_literal(p.pk), ', ') INTO v_pks FROM _sync_plan p WHERE p.sp = t.sp AND p.diff_type = 'missing on dev';
        PERFORM dblink_exec(v_conn, format('DELETE FROM %I.%I WHERE %I::text IN (%s)', t.sch, t.tbl, t.pk_col, v_pks));
      END LOOP;

      IF p_commit THEN PERFORM dblink_exec(v_conn, 'COMMIT'); ELSE PERFORM dblink_exec(v_conn, 'ROLLBACK'); END IF;
    EXCEPTION WHEN OTHERS THEN
      v_err := SQLERRM;
      BEGIN PERFORM dblink_exec(v_conn, 'ROLLBACK'); EXCEPTION WHEN OTHERS THEN NULL; END;
      BEGIN PERFORM dblink_disconnect(v_conn); EXCEPTION WHEN OTHERS THEN NULL; END;
      RAISE EXCEPTION 'f_data_sync_apply: rolled back - %', v_err;
    END;
    PERFORM dblink_disconnect(v_conn);
  END IF;

  -- 4. report one row per table
  RETURN QUERY
  SELECT o.seq, o.schema_path,
         count(p.pk) FILTER (WHERE p.diff_type = 'missing on target'),
         count(p.pk) FILTER (WHERE p.diff_type = 'content differs'),
         count(p.pk) FILTER (WHERE p.diff_type = 'missing on dev'),
         CASE WHEN p_dry_run THEN CASE WHEN count(p.pk) FILTER (WHERE p.diff_type = 'missing on dev') > 0 AND NOT p_allow_deletes
                                       THEN 'blocked: deletes need allow_deletes' ELSE 'succeeded' END
              WHEN NOT p_commit THEN 'rehearsed' ELSE 'succeeded' END,
         NULL::text
    FROM deployment.deployment_objects o
    JOIN deployment.object_policy op ON op.schema_path = o.schema_path AND op.object_type = 'table' AND op.data = p_policy
    LEFT JOIN _sync_plan p ON p.sp = o.schema_path
   WHERE o.run_id = p_run_id AND o.platform = 'database'
   GROUP BY o.seq, o.schema_path
   ORDER BY o.seq;
END
$function$
;

