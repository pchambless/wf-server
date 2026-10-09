CREATE OR REPLACE FUNCTION deployment.f_p02_structure(p_run_id integer, p_dry_run boolean DEFAULT true)
 RETURNS TABLE(seq integer, schema_path text, object_type text, status text, error text)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_env         deployment.environments%ROWTYPE;
    v_env_id      int;
    v_row         record;
    v_ddl         text;
    v_conn        text := 'p02_conn_' || p_run_id;
    v_failed      boolean := false;
    v_fail_reason text;
    v_verify_sql  text;
    v_verify_count bigint;
BEGIN
    SELECT d.environment_id INTO v_env_id
      FROM deployment.deployment_runs r
      JOIN deployment.deployments d ON d.id = r.deployment_id
     WHERE r.id = p_run_id;

    IF v_env_id IS NULL THEN
        RAISE EXCEPTION 'f_p02_structure: no such run %', p_run_id;
    END IF;

    SELECT * INTO v_env FROM deployment.environments WHERE id = v_env_id;

    IF NOT v_env.is_target THEN
        UPDATE deployment.deployment_runs
           SET status = 'failed', error = format('environment %s is not a deploy target', v_env.name),
               error_stage = 'connect', finished_at = now()
         WHERE id = p_run_id;
        RAISE EXCEPTION 'f_p02_structure: environment % is not a deploy target', v_env.name;
    END IF;

    IF v_env.dblink_server IS NULL THEN
        UPDATE deployment.deployment_runs
           SET status = 'failed', error = format('environment %s has no dblink_server', v_env.name),
               error_stage = 'connect', finished_at = now()
         WHERE id = p_run_id;
        RAISE EXCEPTION 'f_p02_structure: environment % has no dblink_server configured', v_env.name;
    END IF;

    -- Source and target must be different clusters (task 517 incident). Runs in dry
    -- runs too: a read-only identity compare, so a misconfigured env fails early.
    BEGIN
        PERFORM deployment.f_assert_distinct_target(v_env.dblink_server);
    EXCEPTION WHEN OTHERS THEN
        UPDATE deployment.deployment_runs
           SET status = 'failed', error = left(SQLERRM, 500), error_stage = 'connect', finished_at = now()
         WHERE id = p_run_id;
        RAISE;
    END;

    -- Defensive: clear any stale connection left over from an aborted prior call
    BEGIN
        PERFORM dblink_disconnect(v_conn);
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    IF NOT p_dry_run THEN
        PERFORM dblink_connect(v_conn, v_env.dblink_server);
    END IF;

    UPDATE deployment.deployment_runs
       SET status = 'running', started_at = coalesce(started_at, now())
     WHERE id = p_run_id;

    FOR v_row IN
        SELECT o.id, o.seq, o.schema_path, o.object_type,
               split_part(o.schema_path, '.', 1) AS sch,
               split_part(o.schema_path, '.', 2) AS obj,
               op.structure AS policy_structure
          FROM deployment.deployment_objects o
          LEFT JOIN deployment.object_policy op
                 ON op.pipeline_id = o.pipeline_id AND op.schema_path = o.schema_path
         WHERE o.run_id = p_run_id
           AND o.platform = 'database'
           AND o.object_type IN ('table', 'function', 'view')
         ORDER BY o.seq
    LOOP
        EXIT WHEN v_failed;

        IF v_row.policy_structure = 'skip' THEN
            UPDATE deployment.deployment_objects
               SET status = 'skipped', started_at = now(), finished_at = now()
             WHERE id = v_row.id;

            seq := v_row.seq; schema_path := v_row.schema_path; object_type := v_row.object_type;
            status := 'skipped'; error := NULL;
            RETURN NEXT;
            CONTINUE;
        END IF;

        UPDATE deployment.deployment_objects
           SET status = 'running', started_at = now()
         WHERE id = v_row.id;

        v_ddl := NULL;

        BEGIN
            IF v_row.object_type = 'table' THEN
                v_ddl := deployment.f_table_ddl(v_row.sch, v_row.obj);
            ELSIF v_row.object_type = 'function' THEN
                SELECT pg_get_functiondef(p.oid) INTO v_ddl
                  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                 WHERE n.nspname = v_row.sch AND p.proname = v_row.obj
                 LIMIT 1;
            ELSIF v_row.object_type = 'view' THEN
                SELECT format('CREATE OR REPLACE VIEW %I.%I AS %s', v_row.sch, v_row.obj, pg_get_viewdef(c.oid))
                  INTO v_ddl
                  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                 WHERE n.nspname = v_row.sch AND c.relname = v_row.obj
                 LIMIT 1;
            END IF;

            IF v_ddl IS NULL THEN
                RAISE EXCEPTION 'could not extract DDL for %', v_row.schema_path;
            END IF;

            IF p_dry_run THEN
                UPDATE deployment.deployment_objects
                   SET status = 'succeeded', finished_at = now(),
                       notes = jsonb_build_object('dry_run', true, 'ddl_preview', left(v_ddl, 500))
                 WHERE id = v_row.id;
            ELSE
                PERFORM dblink_exec(v_conn, v_ddl);

                v_verify_sql := CASE v_row.object_type
                    WHEN 'table' THEN
                        format('SELECT count(*) FROM information_schema.tables WHERE table_schema = %L AND table_name = %L',
                               v_row.sch, v_row.obj)
                    WHEN 'function' THEN
                        format('SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = %L AND p.proname = %L',
                               v_row.sch, v_row.obj)
                    WHEN 'view' THEN
                        format('SELECT count(*) FROM information_schema.views WHERE table_schema = %L AND table_name = %L',
                               v_row.sch, v_row.obj)
                END;

                SELECT cnt INTO v_verify_count FROM dblink(v_conn, v_verify_sql) AS t(cnt bigint);

                IF coalesce(v_verify_count, 0) = 0 THEN
                    RAISE EXCEPTION 'verification failed: % % not found on target after apply (dblink_exec did not raise, but the object is not there)',
                        v_row.object_type, v_row.schema_path;
                END IF;

                UPDATE deployment.deployment_objects
                   SET status = 'succeeded', finished_at = now(),
                       notes = jsonb_build_object('verified', true)
                 WHERE id = v_row.id;
            END IF;

            seq := v_row.seq; schema_path := v_row.schema_path; object_type := v_row.object_type;
            status := 'succeeded';
            error := NULL;
            RETURN NEXT;

        EXCEPTION WHEN OTHERS THEN
            v_fail_reason := SQLERRM;

            UPDATE deployment.deployment_objects
               SET status = 'failed', error = v_fail_reason, finished_at = now(),
                   notes = CASE WHEN p_dry_run THEN jsonb_build_object('dry_run', true) ELSE notes END
             WHERE id = v_row.id;

            v_failed := true;

            seq := v_row.seq; schema_path := v_row.schema_path; object_type := v_row.object_type;
            status := 'failed';
            error := v_fail_reason;
            RETURN NEXT;
        END;
    END LOOP;

    IF NOT p_dry_run THEN
        PERFORM dblink_disconnect(v_conn);
    END IF;

    IF v_failed THEN
        UPDATE deployment.deployment_runs
           SET status = 'failed', error = v_fail_reason, error_stage = 'execute', finished_at = now()
         WHERE id = p_run_id;
    ELSE
        -- Do NOT finalize the run here: a run spans more steps than this one (n8n and code
        -- legs, verify). Closing it is f_finish_run's job, gated by f_check_run. Marking it
        -- succeeded here made the later legs refuse to join (run 406, 2026-10-09).
        UPDATE deployment.deployment_runs
           SET status = 'running', error = NULL, error_stage = NULL
         WHERE id = p_run_id;
    END IF;

    RETURN;
END
$function$
;

