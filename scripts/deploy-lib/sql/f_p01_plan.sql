CREATE OR REPLACE FUNCTION deployment.f_p01_plan(p_run_id integer, p_pipeline text DEFAULT NULL::text)
 RETURNS TABLE(deployment_id integer, run_id integer, objects_planned integer)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_dep_id   int;
    v_pipeline text;
    v_count    int;
BEGIN
    SELECT r.deployment_id INTO v_dep_id
      FROM deployment.deployment_runs r
     WHERE r.id = p_run_id;

    IF v_dep_id IS NULL THEN
        RAISE EXCEPTION 'f_p01_plan: no such run % (call start_run first)', p_run_id;
    END IF;

    IF p_pipeline IS NOT NULL THEN
        v_pipeline := p_pipeline;
    ELSE
        SELECT p.name INTO v_pipeline
          FROM deployment.deployments d
          LEFT JOIN deployment.pipelines p ON p.id = d.pipeline_id
         WHERE d.id = v_dep_id;
    END IF;

    -- Idempotent re-plan: start clean rather than double-insert objects.
    -- Qualify the column: the RETURNS TABLE OUT param is also named run_id,
    -- so a bare `run_id` here is ambiguous (caught in test, 2026-10-05).
    DELETE FROM deployment.deployment_objects
     WHERE deployment_objects.run_id = p_run_id;

    INSERT INTO deployment.deployment_objects
        (run_id, seq, pipeline_id, platform, schema_path, object_type, action, status)
    SELECT p_run_id,
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
     WHERE v_pipeline IS NULL OR m.pipeline = v_pipeline;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    UPDATE deployment.deployment_runs
       SET status = 'planned'
     WHERE id = p_run_id
       AND status NOT IN ('failed', 'succeeded');

    RETURN QUERY SELECT v_dep_id, p_run_id, v_count;
END
$function$
;

