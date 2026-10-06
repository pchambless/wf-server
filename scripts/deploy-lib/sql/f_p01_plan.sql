CREATE OR REPLACE FUNCTION deployment.f_p01_plan(p_environment text, p_release_id integer, p_pipeline text DEFAULT NULL::text, p_version text DEFAULT NULL::text, p_git_commit text DEFAULT NULL::text, p_created_by text DEFAULT 'claude'::text)
 RETURNS TABLE(deployment_id integer, run_id integer, objects_planned integer)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_env_id  int;
    v_pipe_id int;
    v_dep_id  int;
    v_run_id  int;
    v_count   int;
BEGIN
    SELECT id INTO v_env_id FROM deployment.environments WHERE name = p_environment;
    IF v_env_id IS NULL THEN
        RAISE EXCEPTION 'no such environment: %', p_environment;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM deployment.releases WHERE id = p_release_id) THEN
        RAISE EXCEPTION 'no such release: %', p_release_id;
    END IF;

    IF p_pipeline IS NOT NULL THEN
        SELECT id INTO v_pipe_id FROM deployment.pipelines WHERE name = p_pipeline;
        IF v_pipe_id IS NULL THEN
            RAISE EXCEPTION 'no such pipeline: %', p_pipeline;
        END IF;
    END IF;

    INSERT INTO deployment.deployments (environment_id, pipeline_id, release_id, version, git_commit, created_by)
    VALUES (v_env_id, v_pipe_id, p_release_id, p_version, p_git_commit, p_created_by)
    RETURNING id INTO v_dep_id;

    INSERT INTO deployment.deployment_runs (deployment_id, attempt, status, triggered_by)
    VALUES (v_dep_id, 1, 'planned', p_created_by)
    RETURNING id INTO v_run_id;

    -- Objects come from vw_manifest, which is already filtered to non-obsolete
    -- and non-skip, and already carries a validated total order in seq.
    -- Renumber seq per run so it is contiguous when planning a single pipeline.
    INSERT INTO deployment.deployment_objects
        (run_id, seq, pipeline_id, platform, schema_path, object_type, action, status)
    SELECT v_run_id,
           row_number() OVER (ORDER BY m.seq),
           p.id,
           m.platform,
           m.schema_path,
           m.object_type,
           CASE
             WHEN m.object_type <> 'table' THEN 'replace'
             WHEN m.data = 'seed_once'      THEN 'seed'
             WHEN m.data = 'refresh_always' THEN 'refresh'
             ELSE 'replace'
           END,
           'pending'
      FROM deployment.vw_manifest m
      LEFT JOIN deployment.pipelines p ON p.name = m.pipeline
     WHERE p_pipeline IS NULL OR m.pipeline = p_pipeline;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    IF v_count = 0 THEN
        UPDATE deployment.deployment_runs
           SET status = 'failed', error = 'planner produced zero objects',
               error_stage = 'plan', finished_at = now()
         WHERE id = v_run_id;
        RAISE EXCEPTION 'planner produced zero objects for pipeline %', coalesce(p_pipeline,'(all)');
    END IF;

    RETURN QUERY SELECT v_dep_id, v_run_id, v_count;
END
$function$
;

