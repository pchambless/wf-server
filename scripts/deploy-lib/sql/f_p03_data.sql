CREATE OR REPLACE FUNCTION deployment.f_p03_data(p_run_id integer, p_dry_run boolean DEFAULT true, p_force_refresh boolean DEFAULT false)
 RETURNS TABLE(seq integer, schema_path text, action text, status text, rows_affected bigint, error text)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_env         deployment.environments%ROWTYPE;
    v_env_id      int;
    v_row         record;
    v_conn        text := 'p03_conn_' || p_run_id;
    v_failed      boolean := false;
    v_fail_reason text;
    v_target_cnt  bigint;
    v_source_cnt  bigint;
    v_copied      bigint;
    v_truncate_list text;
    v_pinned      text[];
BEGIN
    SELECT d.environment_id INTO v_env_id
      FROM deployment.deployment_runs r
      JOIN deployment.deployments d ON d.id = r.deployment_id
     WHERE r.id = p_run_id;

    IF v_env_id IS NULL THEN
        RAISE EXCEPTION 'f_p03_data: no such run %', p_run_id;
    END IF;

    SELECT * INTO v_env FROM deployment.environments WHERE id = v_env_id;

    IF NOT v_env.is_target THEN
        UPDATE deployment.deployment_runs
           SET status = 'failed', error = format('environment %s is not a deploy target', v_env.name),
               error_stage = 'connect', finished_at = now()
         WHERE id = p_run_id;
        RAISE EXCEPTION 'f_p03_data: environment % is not a deploy target', v_env.name;
    END IF;

    IF v_env.dblink_server IS NULL THEN
        UPDATE deployment.deployment_runs
           SET status = 'failed', error = format('environment %s has no dblink_server', v_env.name),
               error_stage = 'connect', finished_at = now()
         WHERE id = p_run_id;
        RAISE EXCEPTION 'f_p03_data: environment % has no dblink_server configured', v_env.name;
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

    -- p_force_refresh exists to let practice/rehearsal runs re-seed repeatedly
    -- without permanently changing object_policy.data (which must stay an honest,
    -- permanent statement of intent - not a switch someone forgets to flip back
    -- before it points at real production data).
    --
    -- Gate is environments.notes->>'cutover_status', NOT environment name. task
    -- (pre-launch whatsfresh reseed, 2026-08-21): wf-v2-prod is named 'prod' for
    -- infra reasons but is not yet the real live system - whatsfresh there is a
    -- disposable dev mirror (dev itself refreshes from the legacy droplet every
    -- Sunday) until the actual cutover. Fails SAFE: missing/cleared notes key
    -- defaults to blocked, same as the old unconditional check. To unblock,
    -- notes must explicitly carry 'cutover_status':'pre_launch' - set it back
    -- (or clear it) at the real go-live moment and this reverts to a hard block
    -- with no code change needed either direction.
    IF p_force_refresh AND v_env.name = 'prod'
       AND coalesce(v_env.notes->>'cutover_status', 'live') != 'pre_launch' THEN
        UPDATE deployment.deployment_runs
           SET status = 'failed', error = 'p_force_refresh is not allowed against prod (cutover_status is not pre_launch)',
               error_stage = 'connect', finished_at = now()
         WHERE id = p_run_id;
        RAISE EXCEPTION 'f_p03_data: p_force_refresh is not allowed against prod (cutover_status is not pre_launch)';
    END IF;

    BEGIN
        PERFORM dblink_disconnect(v_conn);
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    -- Dry run stays fully local, no dblink connection at all - same as f_p02_structure.
    IF NOT p_dry_run THEN
        PERFORM dblink_connect(v_conn, v_env.dblink_server);
    END IF;

    UPDATE deployment.deployment_runs
       SET status = 'running', started_at = coalesce(started_at, now()),
           notes = coalesce(notes, '{}'::jsonb) || jsonb_build_object('force_refresh', p_force_refresh)
     WHERE id = p_run_id;

    -- PASS 1: clear every table that's about to be reloaded, in ONE combined
    -- TRUNCATE statement. Postgres requires that: truncating a table with an
    -- incoming FK reference is blocked unless every referencing table is
    -- truncated in the SAME statement (order doesn't matter then) - truncating
    -- them one at a time in dependency order, even the right order, still fails,
    -- since the restriction is "all together" not "correct sequence."
    -- PINNED tables (task 467): a refresh table that some table OUTSIDE the
    -- truncate set references by FK (e.g. studio.fsma_classifications <- seed
    -- whatsfresh.entity_types) cannot be truncated without wiping or failing on
    -- that other table. Those are reloaded by upsert + delete-missing instead,
    -- leaving the referencing data alone. Fixpoint: pinning a table pins every
    -- refresh table it references too. Uses the local FK catalog, so dry runs
    -- report the same plan.
    WITH RECURSIVE cand AS (
        SELECT o.schema_path AS sp,
               format('%I.%I', split_part(o.schema_path, '.', 1), split_part(o.schema_path, '.', 2))::regclass AS rel
          FROM deployment.deployment_objects o
         WHERE o.run_id = p_run_id AND o.platform = 'database'
           AND (o.action = 'refresh' OR (o.action = 'seed' AND p_force_refresh))
    ),
    pinned(sp, rel) AS (
        SELECT c.sp, c.rel FROM cand c
         WHERE EXISTS (SELECT 1 FROM pg_constraint k
                        WHERE k.contype = 'f' AND k.confrelid = c.rel AND k.conrelid <> c.rel
                          AND k.conrelid NOT IN (SELECT rel FROM cand))
        UNION
        SELECT c.sp, c.rel FROM cand c
          JOIN pg_constraint k ON k.contype = 'f' AND k.confrelid = c.rel AND k.conrelid <> c.rel
          JOIN pinned p ON p.rel = k.conrelid
    )
    SELECT coalesce(array_agg(sp), ARRAY[]::text[]) INTO v_pinned FROM pinned;

    IF NOT p_dry_run THEN
        SELECT string_agg(format('%I.%I', split_part(o.schema_path, '.', 1), split_part(o.schema_path, '.', 2)), ', ')
          INTO v_truncate_list
          FROM deployment.deployment_objects o
         WHERE o.run_id = p_run_id
           AND o.platform = 'database'
           AND (o.action = 'refresh' OR (o.action = 'seed' AND p_force_refresh))
           AND o.schema_path <> ALL (v_pinned);

        IF v_truncate_list IS NOT NULL THEN
            BEGIN
                PERFORM dblink_exec(v_conn, format('TRUNCATE TABLE %s', v_truncate_list));
            EXCEPTION WHEN OTHERS THEN
                v_fail_reason := SQLERRM;
                UPDATE deployment.deployment_runs
                   SET status = 'failed', error = v_fail_reason,
                       error_stage = 'execute', finished_at = now()
                 WHERE id = p_run_id;
                PERFORM dblink_disconnect(v_conn);
                RAISE EXCEPTION 'f_p03_data: combined truncate failed: %', v_fail_reason;
            END;
        END IF;
    END IF;

    -- PASS 2: reload, forward seq order (parents before children).
    FOR v_row IN
        SELECT o.id, o.seq, o.schema_path, o.action,
               split_part(o.schema_path, '.', 1) AS sch,
               split_part(o.schema_path, '.', 2) AS obj
          FROM deployment.deployment_objects o
         WHERE o.run_id = p_run_id
           AND o.platform = 'database'
           AND o.action IN ('seed', 'refresh')
         ORDER BY o.seq
    LOOP
        EXIT WHEN v_failed;

        UPDATE deployment.deployment_objects SET status = 'running', started_at = now() WHERE id = v_row.id;

        BEGIN
            EXECUTE format('SELECT count(*) FROM %I.%I', v_row.sch, v_row.obj) INTO v_source_cnt;

            IF p_dry_run THEN
                UPDATE deployment.deployment_objects
                   SET status = 'succeeded', finished_at = now(),
                       notes = jsonb_build_object('dry_run', true, 'action', v_row.action,
                                                   'source_rows', v_source_cnt,
                                                   'upsert_pinned', v_row.schema_path = ANY (v_pinned),
                                                   'caveat', CASE WHEN v_row.action = 'seed'
                                                                  THEN 'seed only writes if target is empty - not checked in dry_run'
                                                                  ELSE NULL END)
                 WHERE id = v_row.id;

                seq := v_row.seq; schema_path := v_row.schema_path; action := v_row.action;
                status := 'succeeded'; rows_affected := v_source_cnt; error := NULL;
                RETURN NEXT;
                CONTINUE;
            END IF;

            -- Truncation (if any) already happened in pass 1. Here, seed without
            -- force_refresh still needs the "already populated?" check, since
            -- pass 1 deliberately did NOT touch plain seed tables.
            IF v_row.action = 'seed' AND NOT p_force_refresh THEN
                SELECT cnt INTO v_target_cnt
                  FROM dblink(v_conn, format('SELECT count(*) FROM %I.%I', v_row.sch, v_row.obj)) AS t(cnt bigint);

                IF v_target_cnt > 0 THEN
                    UPDATE deployment.deployment_objects
                       SET status = 'skipped', finished_at = now(),
                           notes = jsonb_build_object('reason', 'seed_once: target already has rows', 'target_rows', v_target_cnt)
                     WHERE id = v_row.id;

                    seq := v_row.seq; schema_path := v_row.schema_path; action := v_row.action;
                    status := 'skipped'; rows_affected := 0; error := NULL;
                    RETURN NEXT;
                    CONTINUE;
                END IF;
            END IF;

            v_copied := deployment.f_table_data_copy(v_conn, v_row.sch, v_row.obj, v_row.schema_path = ANY (v_pinned));

            UPDATE deployment.deployment_objects
               SET status = 'succeeded', rows_affected = v_copied, finished_at = now(),
                   notes = CASE WHEN v_row.action = 'seed' AND p_force_refresh
                                THEN jsonb_build_object('force_refresh', true,
                                       'note', 'seed_once treated as refresh for this practice run')
                                ELSE notes END
             WHERE id = v_row.id;

            seq := v_row.seq; schema_path := v_row.schema_path; action := v_row.action;
            status := 'succeeded'; rows_affected := v_copied; error := NULL;
            RETURN NEXT;

        EXCEPTION WHEN OTHERS THEN
            v_fail_reason := SQLERRM;

            UPDATE deployment.deployment_objects
               SET status = 'failed', error = v_fail_reason, finished_at = now()
             WHERE id = v_row.id;

            v_failed := true;

            seq := v_row.seq; schema_path := v_row.schema_path; action := v_row.action;
            status := 'failed'; rows_affected := 0; error := v_fail_reason;
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

